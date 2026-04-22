// markov_generator.cpp — C++ Markov kernel implementation.
// Algorithmically equivalent to PriceEngine.generate_stock_m1_cache() (GDScript Phase 1).
// Switching to this path invalidates Phase 1 cache (handled by CACHE_VERSION bump in M1CacheManager).
// See: docs/architecture/024-price-engine-gdextension.md

#include "markov_generator.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/array.hpp>

#include <cmath>
#include <cstring>
#include <algorithm>

// M_PI is non-standard; define if missing (e.g. MSVC without _USE_MATH_DEFINES).
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace godot {

// ── PCG32 ────────────────────────────────────────────────────────────────────
// Standard PCG32 (permuted congruential generator).
// Deterministic but NOT identical to Godot's RandomNumberGenerator —
// Phase 1→3 cache invalidation (CACHE_VERSION bump) handles the transition.

struct Pcg32 {
    uint64_t state = 0;
    uint64_t inc   = 1;

    void seed(uint64_t s) noexcept {
        state = 0;
        inc   = (s << 1u) | 1u;  // must be odd
        next();
        state += s;
        next();
    }

    uint32_t next() noexcept {
        uint64_t old = state;
        state = old * 6364136223846793005ULL + inc;
        uint32_t xorshifted = static_cast<uint32_t>(((old >> 18u) ^ old) >> 27u);
        uint32_t rot        = static_cast<uint32_t>(old >> 59u);
        return (xorshifted >> rot) | (xorshifted << ((~rot + 1u) & 31u));
    }

    // [0.0, 1.0)  — 24-bit float precision (matches Godot randf() mantissa width)
    float randf() noexcept {
        return static_cast<float>(next() >> 8u) * (1.0f / 16777216.0f);
    }

    float randf_range(float lo, float hi) noexcept {
        return lo + (hi - lo) * randf();
    }
};

// ── Box-Muller ───────────────────────────────────────────────────────────────
// Returns the cosine component of a Box-Muller pair (matching GDScript usage).
// u1 must be > 0; u2 in [0,1).
static inline double box_muller_cos(double u1, double u2) noexcept {
    return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * M_PI * u2);
}

// ── MarkovGenerator ───────────────────────────────────────────────────────────

MarkovGenerator::MarkovGenerator() {
    _copy_defaults();
}

void MarkovGenerator::_copy_defaults() {
    std::memcpy(_sp,  DEFAULT_SP,  sizeof(_sp));
    std::memcpy(_tm,  DEFAULT_TM,  sizeof(_tm));
    std::memcpy(_vss, DEFAULT_VSS, sizeof(_vss));
    std::memcpy(_vbs, DEFAULT_VBS, sizeof(_vbs));
    std::memcpy(_vps, DEFAULT_VPS, sizeof(_vps));
    std::memcpy(_bvr_min, DEFAULT_BVR_MIN, sizeof(_bvr_min));
    std::memcpy(_bvr_max, DEFAULT_BVR_MAX, sizeof(_bvr_max));
    std::memcpy(_svm, DEFAULT_SVM, sizeof(_svm));
}

// ── set_config ───────────────────────────────────────────────────────────────

void MarkovGenerator::set_config(Dictionary cfg) {
    _copy_defaults(); // start from defaults; override only present keys

    // stateParams: Array of 7 entries, each [bias, mag_min, mag_max, noise_std, min_dur_min]
    if (cfg.has("stateParams")) {
        Array sp = cfg["stateParams"];
        for (int i = 0; i < 7 && i < sp.size(); ++i) {
            Array row = sp[i];
            for (int j = 0; j < 5 && j < row.size(); ++j) {
                _sp[i][j] = static_cast<double>(row[j]);
            }
        }
    }

    // transitionMatrix: Array[7] of Array[7]
    if (cfg.has("transitionMatrix")) {
        Array tm = cfg["transitionMatrix"];
        for (int i = 0; i < 7 && i < tm.size(); ++i) {
            Array row = tm[i];
            for (int j = 0; j < 7 && j < row.size(); ++j) {
                _tm[i][j] = static_cast<double>(row[j]);
            }
        }
    }

    // volSelfScale, volBreakoutScale, volPatternScale: Array[4]
    auto _load4 = [&](const char *key, double dst[4]) {
        if (cfg.has(key)) {
            Array a = cfg[key];
            for (int i = 0; i < 4 && i < a.size(); ++i)
                dst[i] = static_cast<double>(a[i]);
        }
    };
    _load4("volSelfScale",    _vss);
    _load4("volBreakoutScale", _vbs);
    _load4("volPatternScale",  _vps);

    // baseVolumeRange: Array[4] of Array[2] [min, max]
    if (cfg.has("baseVolumeRange")) {
        Array bvr = cfg["baseVolumeRange"];
        for (int i = 0; i < 4 && i < bvr.size(); ++i) {
            Array pair = bvr[i];
            if (pair.size() >= 2) {
                _bvr_min[i] = static_cast<double>(pair[0]);
                _bvr_max[i] = static_cast<double>(pair[1]);
            }
        }
    }

    // stateVolumeMult: Array[7]
    if (cfg.has("stateVolumeMult")) {
        Array svm = cfg["stateVolumeMult"];
        for (int i = 0; i < 7 && i < svm.size(); ++i)
            _svm[i] = static_cast<double>(svm[i]);
    }

    _cfg_loaded = true;
}

// ── _build_scaled_matrix ─────────────────────────────────────────────────────
// Mirrors _build_transition_matrix(vol_profile, SeasonBias.NEUTRAL) in GDScript.
// With NEUTRAL bias, up_bonus and down_penalty are both 0.0 — season step is a no-op.
// Steps: (1) scale self-transition, (2) scale breakout transitions, (3) redistribute.

void MarkovGenerator::_build_scaled_matrix(int vp, double out_m[7][7]) const {
    double self_scale    = _vss[vp];
    double breakout_scale= _vbs[vp];

    for (int i = 0; i < 7; ++i) {
        // Copy base row
        double row[7];
        for (int j = 0; j < 7; ++j) row[j] = _tm[i][j];

        // Step 1: scale self-transition
        double adj_self = std::min(row[i] * self_scale, 0.98);

        // Step 2: scale breakout transitions (indices 5 and 6, excluding self)
        int bi_list[2];
        int bi_count = 0;
        for (int bi : { 5, 6 }) {
            if (bi != i) bi_list[bi_count++] = bi;
        }

        double bo_orig = 0.0;
        for (int k = 0; k < bi_count; ++k) bo_orig += row[bi_list[k]];

        double remaining  = 1.0 - adj_self;
        double bo_adj     = std::min(bo_orig * breakout_scale, remaining * 0.5);

        if (bi_count == 2 && bo_orig > 0.0) {
            double ratio = row[5] / bo_orig;
            row[5] = bo_adj * ratio;
            row[6] = bo_adj * (1.0 - ratio);
        } else if (bi_count == 1) {
            row[bi_list[0]] = bo_adj;
        }

        // Step 3: redistribute remainder to non-self, non-breakout transitions
        double nsb = remaining - bo_adj;
        double others_sum = 0.0;
        for (int j = 0; j < 7; ++j)
            if (j != i && j != 5 && j != 6)
                others_sum += row[j];

        if (others_sum > 0.0) {
            for (int j = 0; j < 7; ++j)
                if (j != i && j != 5 && j != 6)
                    row[j] = row[j] / others_sum * nsb;
        }

        row[i] = adj_self;

        // Renormalize (clamp negatives, ensure row sums to 1)
        double total = 0.0;
        for (int j = 0; j < 7; ++j) { row[j] = std::max(0.0, row[j]); total += row[j]; }
        if (total > 0.0) for (int j = 0; j < 7; ++j) row[j] /= total;

        for (int j = 0; j < 7; ++j) out_m[i][j] = row[j];
    }
}

// ── generate_stock_m1 ─────────────────────────────────────────────────────────
// Algorithm mirrors PriceEngine.generate_stock_m1_cache() line-for-line.

Dictionary MarkovGenerator::generate_stock_m1(
        int vol_profile, int base_price, int n_days,
        int m1_capacity, int d1_capacity, int64_t seed) const
{
    const int VP    = std::max(0, std::min(vol_profile, 3));
    const double BP = static_cast<double>(base_price);
    const double NT = static_cast<double>(TICKS_PER_MINUTE);  // 4.0

    // Build vol-scaled transition matrix (NEUTRAL season bias — identity op)
    double matrix[7][7];
    _build_scaled_matrix(VP, matrix);

    // Initialise PCG32
    Pcg32 rng;
    rng.seed(static_cast<uint64_t>(seed));

    // Allocate circular ring buffers
    PackedInt32Array   m1_ohlc; m1_ohlc.resize(m1_capacity * 4);
    PackedFloat32Array m1_vol;  m1_vol.resize(m1_capacity);
    PackedInt32Array   d1_ohlc; d1_ohlc.resize(d1_capacity * 4);
    PackedFloat32Array d1_vol;  d1_vol.resize(d1_capacity);

    // Raw pointers for performance inside the hot loop
    int32_t  *m1_ohlc_ptr = m1_ohlc.ptrw();
    float    *m1_vol_ptr  = m1_vol.ptrw();
    int32_t  *d1_ohlc_ptr = d1_ohlc.ptrw();
    float    *d1_vol_ptr  = d1_vol.ptrw();

    double current_price  = BP;
    int    markov_state   = 2;  // SIDEWAYS
    int    state_minutes  = 0;
    int    m1_total       = 0;
    int    d1_total       = 0;

    // Price clamp bounds
    const double clamp_lo = std::max(BP * HARD_CLAMP_MIN_RATIO, HARD_CLAMP_ABS_MIN);
    const double clamp_hi = BP * HARD_CLAMP_MAX_RATIO;

    for (int _day = 0; _day < n_days; ++_day) {
        int    day_open   = static_cast<int>(std::lround(current_price));
        double day_high   = current_price;
        double day_low    = current_price;
        double day_volume = 0.0;
        bool   first_min  = true;

        for (int _min = 0; _min < MINUTES_PER_DAY; ++_min) {
            // ── State transition ─────────────────────────────────────────
            int min_dur = static_cast<int>(_sp[markov_state][4]);
            if (state_minutes >= min_dur) {
                double roll       = static_cast<double>(rng.randf());
                double cumulative = 0.0;
                for (int j = 0; j < 7; ++j) {
                    cumulative += matrix[markov_state][j];
                    if (roll <= cumulative) {
                        if (j != markov_state) {
                            markov_state  = j;
                            state_minutes = 0;
                        }
                        break;
                    }
                }
            }
            ++state_minutes;

            // ── Pattern delta (per-minute, scaled from per-tick params) ──
            const double bias   = _sp[markov_state][0] * NT;
            const double mag    = static_cast<double>(rng.randf_range(
                                      static_cast<float>(_sp[markov_state][1]),
                                      static_cast<float>(_sp[markov_state][2]))) * NT;

            // Box-Muller gaussian (cos component)
            double u1 = std::max(static_cast<double>(rng.randf()), 1e-10);
            double u2 = static_cast<double>(rng.randf());
            double noise = box_muller_cos(u1, u2) * _sp[markov_state][3] * std::sqrt(NT);

            double pattern_delta = (bias + mag + noise) * _vps[VP];

            // ── Drift (mean reversion) ───────────────────────────────────
            double dev = (current_price - BP) / BP;
            double r   = std::abs(dev);
            double intensity;
            if (r < THRESHOLD_SOFT) {
                intensity = 1.0;
            } else if (r < THRESHOLD_HARD) {
                intensity = 1.0 + (r - THRESHOLD_SOFT) * 4.0;
            } else {
                intensity = 1.0 + (THRESHOLD_HARD - THRESHOLD_SOFT) * 4.0
                                + (r - THRESHOLD_HARD) * 16.0;
            }
            double drift = -K_DRIFT * dev * intensity * NT;

            // ── Price update ─────────────────────────────────────────────
            double next_price = std::max(current_price * (1.0 + pattern_delta + drift), 100.0);
            next_price = std::clamp(next_price, clamp_lo, clamp_hi);

            // ── M1 OHLC with proportional wick ──────────────────────────
            int m1_open  = static_cast<int>(std::lround(current_price));
            int m1_close = static_cast<int>(std::lround(next_price));
            double swing = std::abs(next_price - current_price)
                         * static_cast<double>(rng.randf_range(0.2f, 0.6f));
            int m1_high  = static_cast<int>(std::lround(std::max(current_price, next_price) + swing));
            int m1_low   = static_cast<int>(std::lround(std::min(current_price, next_price) - swing));

            // ── M1 volume ────────────────────────────────────────────────
            float m1_volume = rng.randf_range(
                static_cast<float>(_bvr_min[VP]),
                static_cast<float>(_bvr_max[VP])
            ) * static_cast<float>(_svm[markov_state]);

            // ── Write M1 to ring buffer ──────────────────────────────────
            int m1_pos  = m1_total % m1_capacity;
            int m1_base = m1_pos * 4;
            m1_ohlc_ptr[m1_base]     = m1_open;
            m1_ohlc_ptr[m1_base + 1] = m1_high;
            m1_ohlc_ptr[m1_base + 2] = m1_low;
            m1_ohlc_ptr[m1_base + 3] = m1_close;
            m1_vol_ptr[m1_pos] = m1_volume;
            ++m1_total;

            // ── Accumulate D1 ────────────────────────────────────────────
            if (first_min) {
                day_open  = m1_open;
                first_min = false;
            }
            day_high   = std::max(day_high,   static_cast<double>(m1_high));
            day_low    = std::min(day_low,    static_cast<double>(m1_low));
            day_volume += static_cast<double>(m1_volume);
            current_price = next_price;
        }

        // Snap last M1 close for cross-day continuity
        if (m1_total > 0) {
            int last_pos = (m1_total - 1) % m1_capacity;
            m1_ohlc_ptr[last_pos * 4 + 3] = static_cast<int>(std::lround(current_price));
        }

        // ── Write D1 bar ─────────────────────────────────────────────────
        int d1_pos  = d1_total % d1_capacity;
        int d1_base = d1_pos * 4;
        d1_ohlc_ptr[d1_base]     = day_open;
        d1_ohlc_ptr[d1_base + 1] = static_cast<int>(std::lround(day_high));
        d1_ohlc_ptr[d1_base + 2] = static_cast<int>(std::lround(std::max(day_low, 100.0)));
        d1_ohlc_ptr[d1_base + 3] = static_cast<int>(std::lround(current_price));
        d1_vol_ptr[d1_pos] = static_cast<float>(day_volume);
        ++d1_total;
    }

    // ── Reorder circular buffers → chronological PackedArrays ────────────────

    int m1_count = std::min(m1_total, m1_capacity);
    int m1_start = (m1_total > m1_capacity) ? (m1_total % m1_capacity) : 0;
    PackedInt32Array   m1_ohlc_out; m1_ohlc_out.resize(m1_count * 4);
    PackedFloat32Array m1_vol_out;  m1_vol_out.resize(m1_count);
    int32_t *mo = m1_ohlc_out.ptrw();
    float   *mv = m1_vol_out.ptrw();
    for (int i = 0; i < m1_count; ++i) {
        int src = ((m1_start + i) % m1_capacity) * 4;
        int dst = i * 4;
        mo[dst]   = m1_ohlc_ptr[src];
        mo[dst+1] = m1_ohlc_ptr[src+1];
        mo[dst+2] = m1_ohlc_ptr[src+2];
        mo[dst+3] = m1_ohlc_ptr[src+3];
        mv[i] = m1_vol_ptr[(m1_start + i) % m1_capacity];
    }

    int d1_count = std::min(d1_total, d1_capacity);
    int d1_start = (d1_total > d1_capacity) ? (d1_total % d1_capacity) : 0;
    PackedInt32Array   d1_ohlc_out; d1_ohlc_out.resize(d1_count * 4);
    PackedFloat32Array d1_vol_out;  d1_vol_out.resize(d1_count);
    int32_t *dop = d1_ohlc_out.ptrw();
    float   *dvp = d1_vol_out.ptrw();
    for (int i = 0; i < d1_count; ++i) {
        int src = ((d1_start + i) % d1_capacity) * 4;
        int dst = i * 4;
        dop[dst]   = d1_ohlc_ptr[src];
        dop[dst+1] = d1_ohlc_ptr[src+1];
        dop[dst+2] = d1_ohlc_ptr[src+2];
        dop[dst+3] = d1_ohlc_ptr[src+3];
        dvp[i] = d1_vol_ptr[(d1_start + i) % d1_capacity];
    }

    Dictionary result;
    result["m1_ohlc"]  = m1_ohlc_out;
    result["m1_vol"]   = m1_vol_out;
    result["d1_ohlc"]  = d1_ohlc_out;
    result["d1_vol"]   = d1_vol_out;
    result["m1_count"] = m1_count;
    result["d1_count"] = d1_count;
    return result;
}

// ── GDExtension binding ───────────────────────────────────────────────────────

void MarkovGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_config", "cfg"),
                         &MarkovGenerator::set_config);
    ClassDB::bind_method(
        D_METHOD("generate_stock_m1", "vol_profile", "base_price", "n_days",
                 "m1_capacity", "d1_capacity", "seed"),
        &MarkovGenerator::generate_stock_m1);
}

} // namespace godot
