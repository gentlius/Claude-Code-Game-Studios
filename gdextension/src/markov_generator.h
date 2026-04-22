// markov_generator.h — C++ GDExtension: stateless Markov kernel for M1 price generation.
// Ported from PriceEngine.generate_stock_m1_cache() (GDScript, Phase 1 reference).
// See: design/gdd/price-engine.md, docs/architecture/024-price-engine-gdextension.md
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cstdint>

namespace godot {

// ── MarkovGenerator ─────────────────────────────────────────────────────────
// Stateless RefCounted node.  GDScript PriceEngine holds one instance, calls:
//   set_config(cfg_dict)   — once per load (or after JSON reload)
//   generate_stock_m1(…)   — per stock in the batch thread
//
// Output dictionary matches PriceEngine.generate_stock_m1_cache() exactly:
//   { m1_ohlc: PackedInt32Array, m1_vol: PackedFloat32Array,
//     d1_ohlc: PackedInt32Array, d1_vol: PackedFloat32Array,
//     m1_count: int,             d1_count: int }

class MarkovGenerator : public RefCounted {
    GDCLASS(MarkovGenerator, RefCounted)

    // ── Compiled-in defaults (mirrors GDScript const / @export defaults) ──
    // Used when set_config() has not been called or JSON is missing a field.

    static constexpr double DEFAULT_SP[7][5] = {
        //  bias        mag_min     mag_max     noise_std   min_dur(min)
        { +0.00030,  +0.000075, +0.00050,  0.0004,  5.0 }, // STRONG_UP
        { +0.000125, +0.000025, +0.00025,  0.0003,  8.0 }, // UPTREND
        {  0.0,      -0.000125, +0.000125, 0.0002, 10.0 }, // SIDEWAYS
        { -0.000125, -0.00025,  -0.000025, 0.0003,  8.0 }, // DOWNTREND
        { -0.00030,  -0.00050,  -0.000075, 0.0004,  5.0 }, // STRONG_DOWN
        { +0.00075,  +0.00025,  +0.00125,  0.00075, 1.0 }, // BREAKOUT_UP
        { -0.00075,  -0.00125,  -0.00025,  0.00075, 1.0 }, // BREAKOUT_DOWN
    };

    static constexpr double DEFAULT_TM[7][7] = {
        { 0.980, 0.010, 0.003, 0.001, 0.000, 0.005, 0.001 }, // STRONG_UP
        { 0.005, 0.985, 0.005, 0.001, 0.000, 0.003, 0.001 }, // UPTREND
        { 0.003, 0.008, 0.975, 0.008, 0.003, 0.002, 0.001 }, // SIDEWAYS
        { 0.000, 0.001, 0.005, 0.985, 0.005, 0.001, 0.003 }, // DOWNTREND
        { 0.000, 0.001, 0.003, 0.010, 0.980, 0.001, 0.005 }, // STRONG_DOWN
        { 0.075, 0.250, 0.125, 0.040, 0.000, 0.500, 0.010 }, // BREAKOUT_UP
        { 0.000, 0.040, 0.125, 0.250, 0.075, 0.010, 0.500 }, // BREAKOUT_DOWN
    };

    // VOL_SELF_SCALE and VOL_BREAKOUT_SCALE (LOW..EXTREME)
    static constexpr double DEFAULT_VSS[4]  = { 1.15, 1.00, 0.90, 0.75 };
    static constexpr double DEFAULT_VBS[4]  = { 0.30, 1.00, 2.00, 4.00 };
    static constexpr double DEFAULT_VPS[4]  = { 0.60, 1.00, 1.30, 1.80 };
    static constexpr double DEFAULT_BVR_MIN[4] = { 100.0, 200.0,  400.0,  800.0 };
    static constexpr double DEFAULT_BVR_MAX[4] = { 300.0, 600.0, 1200.0, 3000.0 };
    static constexpr double DEFAULT_SVM[7]  = { 1.3, 1.1, 0.7, 1.1, 1.3, 2.0, 2.0 };

    // Drift / clamp constants (matches GDScript @export defaults; not in JSON yet)
    static constexpr double K_DRIFT               = 0.001;
    static constexpr double THRESHOLD_SOFT        = 0.20;
    static constexpr double THRESHOLD_HARD        = 0.50;
    static constexpr double HARD_CLAMP_MIN_RATIO  = 0.15;
    static constexpr double HARD_CLAMP_MAX_RATIO  = 3.0;
    static constexpr double HARD_CLAMP_ABS_MIN    = 1000.0;
    static constexpr int    TICKS_PER_MINUTE      = 4;
    static constexpr int    MINUTES_PER_DAY       = 390;

    // ── Live config (populated by set_config) ──
    double _sp[7][5]  = {};
    double _tm[7][7]  = {};    // base transition matrix (MEDIUM baseline)
    double _vss[4]    = {};    // vol_self_scale
    double _vbs[4]    = {};    // vol_breakout_scale
    double _vps[4]    = {};    // vol_pattern_scale
    double _bvr_min[4]= {};
    double _bvr_max[4]= {};
    double _svm[7]    = {};
    bool   _cfg_loaded = false;

    // ── Internal helpers ──
    void _copy_defaults();
    void _build_scaled_matrix(int vol_profile, double out_m[7][7]) const;

    static void _bind_methods();

public:
    MarkovGenerator();

    // Load Markov config from a Dictionary matching price_engine_config.json schema.
    // Call once before first generate_stock_m1(); safe to call again after JSON reload.
    void set_config(Dictionary cfg);

    // Generate M1 + D1 rolling cache for one stock.
    // vol_profile : 0=LOW, 1=MEDIUM, 2=HIGH, 3=EXTREME
    // base_price  : stock base price (KRW integer)
    // n_days      : total simulation days (history_seasons * DAYS_PER_SEASON)
    // m1_capacity : M1 ring-buffer size in bars (M1CacheManager.M1_CACHE_BARS)
    // d1_capacity : D1 ring-buffer size in bars (M1CacheManager.D1_CACHE_BARS)
    // seed        : (history_seed ^ hash(stock_id)) & 0x7FFFFFFF  (pre-computed by caller)
    //
    // Returns the same Dictionary shape as PriceEngine.generate_stock_m1_cache():
    //   m1_ohlc(PackedInt32Array), m1_vol(PackedFloat32Array),
    //   d1_ohlc(PackedInt32Array), d1_vol(PackedFloat32Array),
    //   m1_count(int), d1_count(int)
    Dictionary generate_stock_m1(int vol_profile, int base_price, int n_days,
                                  int m1_capacity, int d1_capacity, int64_t seed) const;
};

} // namespace godot
