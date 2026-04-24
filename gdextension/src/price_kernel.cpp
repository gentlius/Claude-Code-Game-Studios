// price_kernel.cpp — Stateful GDExtension live tick engine (ADR-027, Phase A).
// Implements Markov + drift + VI + events + rumor + player_pressure per tick.
// ETF prices (Phase C), EventEngine (Phase B), and A3 updates (Phase D) are stubs.
// See: docs/architecture/027-price-kernel-gdextension.md

#include "price_kernel.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cmath>
#include <cstring>
#include <algorithm>

// M_PI guard (MSVC without _USE_MATH_DEFINES)
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace godot {

// ── Helpers (anonymous namespace — not linked to MarkovGenerator) ─────────────

namespace {

inline double box_muller_cos(double u1, double u2) noexcept {
    return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * M_PI * u2);
}

} // anonymous namespace

// ── PriceKernel ───────────────────────────────────────────────────────────────

PriceKernel::PriceKernel() {
    _copy_defaults();
}

// ── _copy_defaults ────────────────────────────────────────────────────────────

void PriceKernel::_copy_defaults() {
    std::memcpy(_sp,      DEFAULT_SP,      sizeof(_sp));
    std::memcpy(_tm,      DEFAULT_TM,      sizeof(_tm));
    std::memcpy(_vss,     DEFAULT_VSS,     sizeof(_vss));
    std::memcpy(_vbs,     DEFAULT_VBS,     sizeof(_vbs));
    std::memcpy(_vps,     DEFAULT_VPS,     sizeof(_vps));
    std::memcpy(_bvr_min, DEFAULT_BVR_MIN, sizeof(_bvr_min));
    std::memcpy(_bvr_max, DEFAULT_BVR_MAX, sizeof(_bvr_max));
    std::memcpy(_svm,     DEFAULT_SVM,     sizeof(_svm));

    for (int i = 0; i < 4; ++i) _vol_amplifier[i] = DEFAULT_VOL_AMPLIFIER[i];

    _energy_threshold   = DEFAULT_ENERGY_THRESHOLD;
    _energy_max_boost   = DEFAULT_ENERGY_MAX_BOOST;
    _limit_dampen_start = DEFAULT_LIMIT_DAMPEN_START;
    _limit_dampen_min   = DEFAULT_LIMIT_DAMPEN_MIN;
    _tod_open_mult      = DEFAULT_TOD_OPEN_MULT;
    _tod_close_mult     = DEFAULT_TOD_CLOSE_MULT;
    _tod_window_ticks   = DEFAULT_TOD_WINDOW_TICKS;
    _hard_clamp_min     = DEFAULT_HARD_CLAMP_MIN;
    _hard_clamp_max     = DEFAULT_HARD_CLAMP_MAX;
    _hard_clamp_abs_min = DEFAULT_HARD_CLAMP_ABS_MIN;
    _daily_limit_pct    = DEFAULT_DAILY_LIMIT_PCT;
    _k_drift            = DEFAULT_K_DRIFT;
    _threshold_soft     = DEFAULT_THRESHOLD_SOFT;
    _threshold_hard     = DEFAULT_THRESHOLD_HARD;
    _max_single_impact  = DEFAULT_MAX_SINGLE_IMPACT;
    _breakout_force_threshold = DEFAULT_BREAKOUT_FORCE_THRESHOLD;
    _vi_threshold       = DEFAULT_VI_THRESHOLD;
    _vi_halt_ticks      = DEFAULT_VI_HALT_TICKS;
    _vi_max_per_day     = DEFAULT_VI_MAX_PER_DAY;
    _vi_cooldown_ticks  = DEFAULT_VI_COOLDOWN_TICKS;
    _ticks_per_day      = DEFAULT_TICKS_PER_DAY;

    std::memcpy(_macro_tm,          DEFAULT_MACRO_TM, sizeof(_macro_tm));
    std::memcpy(_macro_vm,          DEFAULT_MACRO_VM, sizeof(_macro_vm));
    std::memcpy(_macro_drift_scale, DEFAULT_MACRO_DS, sizeof(_macro_drift_scale));
    _macro_bias = DEFAULT_MACRO_BIAS;

    constexpr int N = static_cast<int>(sizeof(DEFAULT_TICK_TABLE) / sizeof(DEFAULT_TICK_TABLE[0]));
    static_assert(N <= MAX_TICK_ENTRIES, "DEFAULT_TICK_TABLE exceeds MAX_TICK_ENTRIES");
    std::memcpy(_tick_table, DEFAULT_TICK_TABLE, sizeof(TickEntry) * N);
    _tick_table_size = N;
}

// ── Tick-size helpers ─────────────────────────────────────────────────────────

int PriceKernel::_get_tick_size(int price) const noexcept {
    for (int i = 0; i < _tick_table_size; ++i) {
        if (price < _tick_table[i].threshold)
            return _tick_table[i].tick_size;
    }
    return _tick_table_size > 0 ? _tick_table[_tick_table_size - 1].tick_size : 1;
}

int PriceKernel::_round_to_tick(double raw) const noexcept {
    int r  = static_cast<int>(std::lround(raw));
    int ts = _get_tick_size(r);
    return static_cast<int>(std::lround(raw / static_cast<double>(ts))) * ts;
}

// ── _build_scaled_matrix ──────────────────────────────────────────────────────
// Same algorithm as MarkovGenerator::_build_scaled_matrix.

void PriceKernel::_build_scaled_matrix(int vp, double out_m[7][7],
                                        const double (*base_tm)[7]) const {
    double self_scale     = _vss[vp];
    double breakout_scale = _vbs[vp];
    const double (*src)[7] = (base_tm != nullptr) ? base_tm : _tm;

    for (int i = 0; i < 7; ++i) {
        double row[7];
        for (int j = 0; j < 7; ++j) row[j] = src[i][j];

        double adj_self = std::min(row[i] * self_scale, 0.98);

        int bi_list[2];
        int bi_count = 0;
        for (int bi : { 5, 6 }) {
            if (bi != i) bi_list[bi_count++] = bi;
        }

        double bo_orig = 0.0;
        for (int k = 0; k < bi_count; ++k) bo_orig += row[bi_list[k]];

        double remaining = 1.0 - adj_self;
        double bo_adj    = std::min(bo_orig * breakout_scale, remaining * 0.5);

        if (bi_count == 2 && bo_orig > 0.0) {
            double ratio = row[5] / bo_orig;
            row[5] = bo_adj * ratio;
            row[6] = bo_adj * (1.0 - ratio);
        } else if (bi_count == 1) {
            row[bi_list[0]] = bo_adj;
        }

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

        double total = 0.0;
        for (int j = 0; j < 7; ++j) { row[j] = std::max(0.0, row[j]); total += row[j]; }
        if (total > 0.0) for (int j = 0; j < 7; ++j) row[j] /= total;

        for (int j = 0; j < 7; ++j) out_m[i][j] = row[j];
    }
}

// ── _apply_macro_bias ─────────────────────────────────────────────────────────
// Same algorithm as MarkovGenerator::_apply_macro_bias.

void PriceKernel::_apply_macro_bias(const double in_m[7][7], double out_m[7][7],
                                     int macro_state) const {
    if (macro_state == 1) {
        std::memcpy(out_m, in_m, sizeof(double) * 49);
        return;
    }
    int boost[2];
    if (macro_state == 0) { boost[0] = 0; boost[1] = 1; }
    else                  { boost[0] = 3; boost[1] = 4; }

    for (int i = 0; i < 7; ++i) {
        double row[7];
        for (int j = 0; j < 7; ++j) row[j] = in_m[i][j];
        row[boost[0]] *= _macro_bias;
        row[boost[1]] *= _macro_bias;
        double total = 0.0;
        for (int j = 0; j < 7; ++j) total += row[j];
        if (total > 0.0)
            for (int j = 0; j < 7; ++j) out_m[i][j] = row[j] / total;
        else
            for (int j = 0; j < 7; ++j) out_m[i][j] = in_m[i][j];
    }
}

// ── set_config ────────────────────────────────────────────────────────────────

void PriceKernel::set_config(Dictionary cfg) {
    _copy_defaults();

    // ── Shared schema (same as MarkovGenerator) ──────────────────────────────

    if (cfg.has("stateParams")) {
        Array sp = cfg["stateParams"];
        for (int i = 0; i < 7 && i < sp.size(); ++i) {
            Array row = sp[i];
            for (int j = 0; j < 5 && j < row.size(); ++j)
                _sp[i][j] = static_cast<double>(row[j]);
        }
    }

    if (cfg.has("transitionMatrix")) {
        Array tm = cfg["transitionMatrix"];
        for (int i = 0; i < 7 && i < tm.size(); ++i) {
            Array row = tm[i];
            for (int j = 0; j < 7 && j < row.size(); ++j)
                _tm[i][j] = static_cast<double>(row[j]);
        }
    }

    auto _load4d = [&](const char *key, double dst[4]) {
        if (cfg.has(key)) {
            Array a = cfg[key];
            for (int i = 0; i < 4 && i < a.size(); ++i)
                dst[i] = static_cast<double>(a[i]);
        }
    };
    _load4d("volSelfScale",    _vss);
    _load4d("volBreakoutScale", _vbs);
    _load4d("volPatternScale",  _vps);

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

    if (cfg.has("stateVolumeMult")) {
        Array svm = cfg["stateVolumeMult"];
        for (int i = 0; i < 7 && i < svm.size(); ++i)
            _svm[i] = static_cast<double>(svm[i]);
    }

    // archetypeMatrices
    _archetype_matrices.clear();
    if (cfg.has("archetypeMatrices")) {
        Dictionary arch_dict = cfg["archetypeMatrices"];
        Array keys = arch_dict.keys();
        for (int k = 0; k < keys.size(); ++k) {
            String key = keys[k];
            std::string ks = key.utf8().get_data();
            if (ks.empty() || ks[0] == '_') continue;
            Variant entry_v = arch_dict[key];
            if (entry_v.get_type() != Variant::DICTIONARY) continue;
            Dictionary arch_entry = entry_v;
            if (!arch_entry.has("transitionMatrix")) continue;
            Array tm = arch_entry["transitionMatrix"];
            ArchMatrix am;
            for (int i = 0; i < 7; ++i)
                for (int j = 0; j < 7; ++j)
                    am.tm[i][j] = DEFAULT_TM[i][j];
            for (int i = 0; i < 7 && i < tm.size(); ++i) {
                Array row = tm[i];
                for (int j = 0; j < 7 && j < row.size(); ++j)
                    am.tm[i][j] = static_cast<double>(row[j]);
            }
            _archetype_matrices[ks] = am;
        }
    }

    // macroTrend
    _macro_arch_matrices.clear();
    if (cfg.has("macroTrend")) {
        Dictionary mt = cfg["macroTrend"];

        if (mt.has("transitionMatrix")) {
            Array rows = mt["transitionMatrix"];
            for (int i = 0; i < 3 && i < rows.size(); ++i) {
                Array row = rows[i];
                for (int j = 0; j < 3 && j < row.size(); ++j)
                    _macro_tm[i][j] = static_cast<double>(row[j]);
            }
        }
        if (mt.has("biasFactor"))
            _macro_bias = static_cast<double>(mt["biasFactor"]);
        if (mt.has("driftScale")) {
            Array ds = mt["driftScale"];
            for (int i = 0; i < 3 && i < ds.size(); ++i)
                _macro_drift_scale[i] = static_cast<double>(ds[i]);
        }
        if (mt.has("volMultiplier")) {
            Array vm = mt["volMultiplier"];
            for (int i = 0; i < 3 && i < vm.size(); ++i) {
                Array pair = vm[i];
                if (pair.size() >= 2) {
                    _macro_vm[i][0] = static_cast<double>(pair[0]);
                    _macro_vm[i][1] = static_cast<double>(pair[1]);
                }
            }
        }
        if (mt.has("archetypeMacroMatrices")) {
            Dictionary amd = mt["archetypeMacroMatrices"];
            Array akeys = amd.keys();
            for (int k = 0; k < akeys.size(); ++k) {
                String akey = akeys[k];
                std::string aks = akey.utf8().get_data();
                if (aks.empty() || aks[0] == '_') continue;
                Variant entry_v = amd[akey];
                if (entry_v.get_type() != Variant::ARRAY) continue;
                Array rows3 = entry_v;
                MacroArchMatrix mam;
                std::memcpy(mam.tm, DEFAULT_MACRO_TM, sizeof(mam.tm));
                for (int i = 0; i < 3 && i < rows3.size(); ++i) {
                    Array row3 = rows3[i];
                    for (int j = 0; j < 3 && j < row3.size(); ++j)
                        mam.tm[i][j] = static_cast<double>(row3[j]);
                }
                _macro_arch_matrices[aks] = mam;
            }
        }
    }

    // tickTable
    if (cfg.has("tickTable")) {
        Array tt = cfg["tickTable"];
        int count = 0;
        for (int i = 0; i < tt.size() && count < MAX_TICK_ENTRIES; ++i) {
            Variant v = tt[i];
            if (v.get_type() != Variant::ARRAY) continue;
            Array pair = v;
            if (pair.size() < 2) continue;
            _tick_table[count++] = { static_cast<int>(pair[0]), static_cast<int>(pair[1]) };
        }
        if (count > 0) _tick_table_size = count;
    }

    // ── PriceKernel-specific keys ────────────────────────────────────────────

    auto _load4f = [&](const char *key, float dst[4]) {
        if (cfg.has(key)) {
            Array a = cfg[key];
            for (int i = 0; i < 4 && i < a.size(); ++i)
                dst[i] = static_cast<float>(a[i]);
        }
    };
    _load4f("volAmplifier", _vol_amplifier);

    auto _loadf = [&](const char *key, float &dst) {
        if (cfg.has(key)) dst = static_cast<float>(cfg[key]);
    };
    auto _loadd = [&](const char *key, double &dst) {
        if (cfg.has(key)) dst = static_cast<double>(cfg[key]);
    };
    auto _loadi = [&](const char *key, int &dst) {
        if (cfg.has(key)) dst = static_cast<int>(cfg[key]);
    };

    _loadf("energyThreshold",         _energy_threshold);
    _loadf("energyMaxBoost",          _energy_max_boost);
    _loadf("limitDampenStart",        _limit_dampen_start);
    _loadf("limitDampenMin",          _limit_dampen_min);
    _loadf("todOpenMult",             _tod_open_mult);
    _loadf("todCloseMult",            _tod_close_mult);
    _loadi("todWindowTicks",          _tod_window_ticks);
    _loadd("hardClampMinRatio",       _hard_clamp_min);
    _loadd("hardClampMaxRatio",       _hard_clamp_max);
    _loadd("hardClampAbsMin",         _hard_clamp_abs_min);
    _loadd("dailyLimitPct",           _daily_limit_pct);
    _loadd("kDrift",                  _k_drift);
    _loadd("thresholdSoft",           _threshold_soft);
    _loadd("thresholdHard",           _threshold_hard);
    _loadf("maxSingleImpact",         _max_single_impact);
    _loadf("breakoutForceThreshold",  _breakout_force_threshold);
    _loadf("viThreshold",             _vi_threshold);
    _loadi("viHaltTicks",             _vi_halt_ticks);
    _loadi("viMaxPerDay",             _vi_max_per_day);
    _loadi("viCooldownTicks",         _vi_cooldown_ticks);
    _loadi("ticksPerDay",             _ticks_per_day);

    _cfg_loaded = true;
}

// ── init_stock ────────────────────────────────────────────────────────────────

void PriceKernel::init_stock(String stock_id, Dictionary stock_data) {
    std::string id = stock_id.utf8().get_data();

    StockState s;
    s.stock_id = id;

    if (stock_data.has("base_price"))
        s.base_price = static_cast<int>(stock_data["base_price"]);
    if (stock_data.has("current_price"))
        s.current_price = static_cast<int>(stock_data["current_price"]);
    else
        s.current_price = s.base_price;
    if (stock_data.has("prev_day_close"))
        s.prev_day_close = static_cast<int>(stock_data["prev_day_close"]);
    else
        s.prev_day_close = s.base_price;

    if (stock_data.has("vol_profile"))
        s.vol_profile = std::max(0, std::min(3, static_cast<int>(stock_data["vol_profile"])));
    if (stock_data.has("sector"))
        s.sector = static_cast<String>(stock_data["sector"]).utf8().get_data();
    if (stock_data.has("archetype"))
        s.archetype = static_cast<String>(stock_data["archetype"]).utf8().get_data();
    if (stock_data.has("macro_sensitivity"))
        s.macro_sensitivity = static_cast<float>(stock_data["macro_sensitivity"]);
    if (stock_data.has("sector_sensitivity"))
        s.sector_sensitivity = static_cast<float>(stock_data["sector_sensitivity"]);
    if (stock_data.has("is_etf"))
        s.is_etf = static_cast<bool>(stock_data["is_etf"]);
    if (stock_data.has("macro_state"))
        s.macro_state = std::max(0, std::min(2, static_cast<int>(stock_data["macro_state"])));

    // Seed per-stock RNG from stock_id hash
    uint64_t seed_val = 0;
    for (unsigned char c : id) seed_val = seed_val * 31u + c;
    seed_val ^= static_cast<uint64_t>(0xDEADBEEF);
    s.rng.seed(seed_val);

    // Build initial day_matrix (FLAT macro state)
    const double (*base_tm)[7] = nullptr;
    auto it = _archetype_matrices.find(s.archetype);
    if (it != _archetype_matrices.end()) base_tm = it->second.tm;

    double scaled[7][7];
    _build_scaled_matrix(s.vol_profile, scaled, base_tm);
    _apply_macro_bias(scaled, s.day_matrix, s.macro_state);

    // Replace existing entry if already registered
    auto idx_it = _stock_index.find(id);
    if (idx_it != _stock_index.end()) {
        _stocks[idx_it->second] = std::move(s);
    } else {
        _stock_index[id] = _stocks.size();
        _stocks.push_back(std::move(s));
    }
}

// ── reset ─────────────────────────────────────────────────────────────────────

void PriceKernel::reset() {
    _stocks.clear();
    _stock_index.clear();
    _season_number = 0;
}

// ── start_season ──────────────────────────────────────────────────────────────

void PriceKernel::start_season(int season_number, Dictionary /*season_theme*/) {
    // Phase A: store season, reset per-stock VI counters.
    // season_theme fields (sector_bias, active_season_tags, weight scales) are Phase B.
    _season_number = season_number;
    for (auto &s : _stocks) {
        s.vi_count_today = 0;
    }
}

// ── start_day ─────────────────────────────────────────────────────────────────

void PriceKernel::start_day(int /*day_number*/) {
    for (auto &s : _stocks) {
        s.prev_day_close = s.current_price;

        // Roll macro_state using per-archetype macro matrix if available
        const double (*macro_src)[3] = _macro_tm;
        auto it = _macro_arch_matrices.find(s.archetype);
        if (it != _macro_arch_matrices.end()) macro_src = it->second.tm;

        double roll = static_cast<double>(s.rng.randf());
        double cum  = 0.0;
        for (int j = 0; j < 3; ++j) {
            cum += macro_src[s.macro_state][j];
            if (roll <= cum) { s.macro_state = j; break; }
        }

        // Draw daily volume multiplier
        s.macro_vol_mult = static_cast<double>(s.rng.randf_range(
            static_cast<float>(_macro_vm[s.macro_state][0]),
            static_cast<float>(_macro_vm[s.macro_state][1])
        ));

        // Rebuild day_matrix with new macro_state
        const double (*base_tm)[7] = nullptr;
        auto atm_it = _archetype_matrices.find(s.archetype);
        if (atm_it != _archetype_matrices.end()) base_tm = atm_it->second.tm;
        double scaled[7][7];
        _build_scaled_matrix(s.vol_profile, scaled, base_tm);
        _apply_macro_bias(scaled, s.day_matrix, s.macro_state);

        // Reset daily state
        s.player_pressure    = 0.0f;
        s.vi_halt_remaining  = 0;
        s.vi_cooldown        = 0;
        s.vi_count_today     = 0;
    }
}

// ── inject_event ──────────────────────────────────────────────────────────────

void PriceKernel::inject_event(Dictionary event_entry) {
    if (!event_entry.has("stock_id")) return;
    std::string id = static_cast<String>(event_entry["stock_id"]).utf8().get_data();
    auto idx_it = _stock_index.find(id);
    if (idx_it == _stock_index.end()) return;

    IncomingEvent ev;
    ev.scope       = event_entry.has("scope")       ? static_cast<int>(event_entry["scope"])        : 2;
    ev.base_impact = event_entry.has("base_impact") ? static_cast<float>(event_entry["base_impact"]): 0.0f;
    ev.direction   = event_entry.has("direction")   ? static_cast<int>(event_entry["direction"])    : 0;
    ev.event_type  = event_entry.has("event_type")  ? static_cast<int>(event_entry["event_type"])  : 0;
    ev.decay_ticks = event_entry.has("decay_ticks") ? static_cast<int>(event_entry["decay_ticks"]) : 0;
    ev.decay_curve = event_entry.has("decay_curve") ? static_cast<int>(event_entry["decay_curve"]) : 0;

    _stocks[idx_it->second].incoming_events.push_back(ev);
}

// ── add_player_pressure ───────────────────────────────────────────────────────

void PriceKernel::add_player_pressure(String stock_id, float delta) {
    std::string id = stock_id.utf8().get_data();
    auto it = _stock_index.find(id);
    if (it != _stock_index.end())
        _stocks[it->second].player_pressure += delta;
}

// ── set_rumor ─────────────────────────────────────────────────────────────────

void PriceKernel::set_rumor(String stock_id, float delta_per_tick, int ticks_remaining) {
    std::string id = stock_id.utf8().get_data();
    auto it = _stock_index.find(id);
    if (it != _stock_index.end()) {
        auto &s = _stocks[it->second];
        s.rumor_delta_per_tick  = delta_per_tick;
        s.rumor_ticks_remaining = ticks_remaining;
    }
}

// ── _consume_events ───────────────────────────────────────────────────────────
// Processes all incoming events and existing gradual events for one stock.
// Returns event_delta and sets out_forced_breakout (5=UP, 6=DOWN, -1=none).

float PriceKernel::_consume_events(StockState &s, int &out_forced_breakout) noexcept {
    float event_delta     = 0.0f;
    out_forced_breakout   = -1;

    // Process new incoming events
    for (const auto &ev : s.incoming_events) {
        float sens = (ev.scope == 0) ? s.macro_sensitivity
                   : (ev.scope == 1) ? s.sector_sensitivity
                   : 1.0f;
        float raw    = ev.base_impact * static_cast<float>(ev.direction)
                     * sens * _vol_amplifier[s.vol_profile];
        float actual = std::max(-_max_single_impact, std::min(_max_single_impact, raw));

        if (ev.event_type == 0) {
            // INSTANT_SHOCK
            event_delta += actual;
            if (std::abs(actual) >= _breakout_force_threshold) {
                out_forced_breakout = (actual > 0.0f) ? 5 : 6;
            }
        } else {
            // GRADUAL_SHIFT
            float rate = 0.0f;
            if (ev.decay_curve == 1 && ev.decay_ticks > 0) {
                // EXPONENTIAL: rate = 1 - exp(log(0.01) / decay_ticks)
                rate = 1.0f - static_cast<float>(
                    std::exp(std::log(0.01) / static_cast<double>(ev.decay_ticks)));
            }

            // First tick contribution
            float first_contrib;
            if (ev.decay_curve == 0) {
                // LINEAR
                first_contrib = (ev.decay_ticks > 0)
                    ? actual / static_cast<float>(ev.decay_ticks)
                    : actual;
            } else {
                // EXPONENTIAL: elapsed=0 → actual * pow(1-rate, 0) * rate = actual * rate
                first_contrib = actual * rate;
            }
            event_delta += first_contrib;

            // Push gradual event for remaining ticks
            if (ev.decay_ticks > 1) {
                GradualEvent ge;
                ge.actual_impact    = actual;
                ge.remaining_ticks  = ev.decay_ticks - 1;
                ge.total_ticks      = ev.decay_ticks;
                ge.decay_curve      = ev.decay_curve;
                ge.decay_rate       = rate;
                s.gradual_events.push_back(ge);
            }
        }
    }
    s.incoming_events.clear();

    // Advance existing gradual events
    for (auto &ge : s.gradual_events) {
        if (ge.remaining_ticks <= 0) continue;
        int elapsed = ge.total_ticks - ge.remaining_ticks;
        float contrib;
        if (ge.decay_curve == 0) {
            // LINEAR
            contrib = (ge.total_ticks > 0)
                ? ge.actual_impact / static_cast<float>(ge.total_ticks)
                : 0.0f;
        } else {
            // EXPONENTIAL
            contrib = ge.actual_impact
                * static_cast<float>(std::pow(1.0 - static_cast<double>(ge.decay_rate),
                                               static_cast<double>(elapsed)))
                * ge.decay_rate;
        }
        event_delta += contrib;
        ge.remaining_ticks -= 1;
    }

    // Prune exhausted gradual events
    s.gradual_events.erase(
        std::remove_if(s.gradual_events.begin(), s.gradual_events.end(),
                       [](const GradualEvent &ge) { return ge.remaining_ticks <= 0; }),
        s.gradual_events.end()
    );

    return event_delta;
}

// ── _pattern_delta ────────────────────────────────────────────────────────────
// Per-tick Markov pattern delta (mirrors MarkovGenerator's hot path).

float PriceKernel::_pattern_delta(StockState &s) noexcept {
    int state = s.markov_state;
    float bias  = static_cast<float>(_sp[state][0]);
    float mag   = s.rng.randf_range(
        static_cast<float>(_sp[state][1]),
        static_cast<float>(_sp[state][2]));
    double u1   = static_cast<double>(std::max(s.rng.randf(), 1e-7f));
    double u2   = static_cast<double>(s.rng.randf());
    float noise = static_cast<float>(
        box_muller_cos(u1, u2) * _sp[state][3]);

    return (bias + mag + noise) * static_cast<float>(_vps[s.vol_profile]);
}

// ── _drift_delta ──────────────────────────────────────────────────────────────

double PriceKernel::_drift_delta(const StockState &s) const noexcept {
    double deviation = (static_cast<double>(s.current_price)
                        - static_cast<double>(s.base_price))
                     / static_cast<double>(s.base_price);
    double r = std::abs(deviation);
    double intensity;
    if (r < _threshold_soft) {
        intensity = 1.0;
    } else if (r < _threshold_hard) {
        intensity = 1.0 + (r - _threshold_soft) * 4.0;
    } else {
        intensity = 1.0 + (_threshold_hard - _threshold_soft) * 4.0
                        + (r - _threshold_hard) * 16.0;
    }
    return -_k_drift * _macro_drift_scale[s.macro_state] * deviation * intensity;
}

// ── process_all_ticks ─────────────────────────────────────────────────────────

Dictionary PriceKernel::process_all_ticks(int tick_in_day) {
    Dictionary prices;
    Dictionary volumes;
    Array      vi_hits;

    for (auto &s : _stocks) {
        String sid(s.stock_id.c_str());

        // Skip ETFs in Phase A (EtfManager handles them separately)
        if (s.is_etf) {
            prices[sid] = s.current_price;
            volumes[sid] = 0.0f;
            continue;
        }

        // ── VI halt check ────────────────────────────────────────────────────
        if (s.vi_halt_remaining > 0) {
            s.vi_halt_remaining -= 1;
            prices[sid]  = s.current_price;
            volumes[sid] = 0.0f;
            continue;
        }
        if (s.vi_cooldown > 0) {
            s.vi_cooldown -= 1;
        }

        // ── Step 1: Consume events ───────────────────────────────────────────
        int   forced_breakout = -1;
        float event_delta = _consume_events(s, forced_breakout);

        // ── Step 2: Pattern delta ────────────────────────────────────────────
        float pattern_delta = _pattern_delta(s);

        // ── Step 3: Drift delta ──────────────────────────────────────────────
        double drift_delta = _drift_delta(s);

        // ── Step 4: Player + rumor delta ─────────────────────────────────────
        float player_delta = s.player_pressure;
        s.player_pressure  = 0.0f;

        float rumor_delta = 0.0f;
        if (s.rumor_ticks_remaining > 0) {
            rumor_delta = s.rumor_delta_per_tick;
            s.rumor_ticks_remaining -= 1;
        }

        // ── Step 5: Price update ─────────────────────────────────────────────
        double total_delta = static_cast<double>(pattern_delta)
                           + drift_delta
                           + static_cast<double>(event_delta)
                           + static_cast<double>(player_delta)
                           + static_cast<double>(rumor_delta);

        double raw_price = static_cast<double>(s.current_price) * (1.0 + total_delta);

        // Hard clamp (lifetime bounds)
        double min_p = std::max(static_cast<double>(s.base_price) * _hard_clamp_min,
                                _hard_clamp_abs_min);
        double max_p = static_cast<double>(s.base_price) * _hard_clamp_max;
        double clamped = std::clamp(raw_price, min_p, max_p);

        // Daily ±30% limit
        double upper = static_cast<double>(s.prev_day_close) * (1.0 + _daily_limit_pct);
        double lower = static_cast<double>(s.prev_day_close) * (1.0 - _daily_limit_pct);
        clamped = std::clamp(clamped, lower, upper);

        int final_price = _round_to_tick(clamped);
        s.current_price = final_price;
        prices[sid] = final_price;

        // ── Step 6: Markov state transition ──────────────────────────────────
        {
            int state = s.markov_state;
            // min_dur_ticks = min_dur_minutes * TICKS_PER_MINUTE (4)
            int min_dur = static_cast<int>(_sp[state][4] * 4.0);
            if (s.state_duration >= min_dur) {
                double roll = static_cast<double>(s.rng.randf());
                double cum  = 0.0;
                for (int j = 0; j < 7; ++j) {
                    cum += s.day_matrix[state][j];
                    if (roll <= cum) {
                        if (j != state) {
                            s.markov_state  = j;
                            s.state_duration = 0;
                        } else {
                            s.state_duration += 1;
                        }
                        break;
                    }
                }
            } else {
                s.state_duration += 1;
            }

            // Forced breakout overrides state transition
            if (forced_breakout >= 0) {
                s.markov_state   = forced_breakout;
                s.state_duration = 0;
            }
        }

        // ── Step 7: Volume ────────────────────────────────────────────────────
        float base_vol = s.rng.randf_range(
            static_cast<float>(_bvr_min[s.vol_profile]),
            static_cast<float>(_bvr_max[s.vol_profile]));

        float tick_energy = std::abs(pattern_delta)
                          + std::abs(event_delta)
                          + std::abs(rumor_delta);
        float energy_mult = 1.0f + std::clamp(
            tick_energy / _energy_threshold, 0.0f, _energy_max_boost);

        float state_mult = static_cast<float>(_svm[s.markov_state]);

        // Limit proximity dampening
        float prev_f = static_cast<float>(s.prev_day_close);
        float proximity = (prev_f > 0.0f)
            ? std::abs(static_cast<float>(s.current_price) - prev_f)
              / (prev_f * static_cast<float>(_daily_limit_pct))
            : 0.0f;
        float limit_dampen = 1.0f;
        if (proximity >= _limit_dampen_start) {
            float t = std::clamp(
                (proximity - _limit_dampen_start) / (1.0f - _limit_dampen_start),
                0.0f, 1.0f);
            limit_dampen = _limit_dampen_min + (1.0f - t) * (1.0f - _limit_dampen_min);
        }

        // Time-of-day multiplier
        float tod_mult = (tick_in_day < _tod_window_ticks)              ? _tod_open_mult
                       : (tick_in_day >= _ticks_per_day - _tod_window_ticks) ? _tod_close_mult
                       : 1.0f;

        float volume = base_vol * state_mult * energy_mult * limit_dampen * tod_mult
                     * static_cast<float>(s.macro_vol_mult);
        volumes[sid] = volume;

        // ── Step 8: VI check ──────────────────────────────────────────────────
        if (tick_in_day > 0
                && s.vi_halt_remaining == 0
                && s.vi_count_today < _vi_max_per_day
                && s.vi_cooldown == 0) {

            float change_pct = (prev_f > 0.0f)
                ? std::abs(static_cast<float>(s.current_price) - prev_f) / prev_f
                : 0.0f;

            if (change_pct >= _vi_threshold) {
                bool is_upper = (s.current_price > s.prev_day_close);
                s.vi_halt_remaining = _vi_halt_ticks;
                s.vi_cooldown       = _vi_cooldown_ticks;
                s.vi_count_today   += 1;

                Dictionary hit;
                hit["stock_id"] = sid;
                hit["is_upper"] = is_upper;
                vi_hits.push_back(hit);
            }
        }
    }

    Dictionary result;
    result["prices"]     = prices;
    result["volumes"]    = volumes;
    result["vi_hits"]    = vi_hits;
    result["ui_events"]  = Array();  // Phase B
    result["a3_updates"] = Array();  // Phase D
    result["etf_prices"] = Dictionary();  // Phase C
    return result;
}

// ── GDExtension binding ───────────────────────────────────────────────────────

void PriceKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_config", "cfg"),
                         &PriceKernel::set_config);
    ClassDB::bind_method(D_METHOD("init_stock", "stock_id", "stock_data"),
                         &PriceKernel::init_stock);
    ClassDB::bind_method(D_METHOD("reset"),
                         &PriceKernel::reset);
    ClassDB::bind_method(D_METHOD("start_season", "season_number", "season_theme"),
                         &PriceKernel::start_season);
    ClassDB::bind_method(D_METHOD("start_day", "day_number"),
                         &PriceKernel::start_day);
    ClassDB::bind_method(D_METHOD("process_all_ticks", "tick_in_day"),
                         &PriceKernel::process_all_ticks);
    ClassDB::bind_method(D_METHOD("add_player_pressure", "stock_id", "delta"),
                         &PriceKernel::add_player_pressure);
    ClassDB::bind_method(D_METHOD("set_rumor", "stock_id", "delta_per_tick", "ticks_remaining"),
                         &PriceKernel::set_rumor);
    ClassDB::bind_method(D_METHOD("inject_event", "event_entry"),
                         &PriceKernel::inject_event);
}

} // namespace godot
