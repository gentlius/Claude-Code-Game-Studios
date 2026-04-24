// price_kernel.h — Stateful GDExtension class for live per-tick price computation.
// Replaces GDScript's per-stock tick loop (ADR-027, Phase A).
// Phase A covers: Markov + drift + VI + events + rumor + player_pressure.
// ETF management, EventEngine, and A3 updates are Phase B/C/D.
// See: docs/architecture/027-price-kernel-gdextension.md (to be written)
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>

namespace godot {

// ── PriceKernel ──────────────────────────────────────────────────────────────
// Stateful RefCounted. GDScript PriceEngine holds one instance. Lifecycle:
//   set_config(cfg)               — once per load
//   init_stock(id, data)          — once per stock
//   start_season(n, theme)        — once per season
//   start_day(day_number)         — once per game day
//   process_all_ticks(tick)       — once per tick (live loop)
//   inject_event(entry)           — anytime, queued for next process_all_ticks
//   add_player_pressure(id, d)    — on player order fill
//   set_rumor(id, delta, ticks)   — on rumor activation

class PriceKernel : public RefCounted {
    GDCLASS(PriceKernel, RefCounted)

    // ── Compiled-in defaults ─────────────────────────────────────────────────
    // Mirrors MarkovGenerator's defaults for shared parameters.

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

    static constexpr double DEFAULT_VSS[4]     = { 1.15, 1.00, 0.90, 0.75 };
    static constexpr double DEFAULT_VBS[4]     = { 0.30, 1.00, 2.00, 4.00 };
    static constexpr double DEFAULT_VPS[4]     = { 0.60, 1.00, 1.30, 1.80 };
    static constexpr double DEFAULT_BVR_MIN[4] = { 100.0, 200.0,  400.0,  800.0 };
    static constexpr double DEFAULT_BVR_MAX[4] = { 300.0, 600.0, 1200.0, 3000.0 };
    static constexpr double DEFAULT_SVM[7]     = { 1.3, 1.1, 0.7, 1.1, 1.3, 2.0, 2.0 };

    // PriceKernel-specific defaults
    static constexpr float  DEFAULT_VOL_AMPLIFIER[4] = { 0.60f, 1.00f, 1.40f, 2.00f };
    static constexpr float  DEFAULT_ENERGY_THRESHOLD  = 0.01f;
    static constexpr float  DEFAULT_ENERGY_MAX_BOOST  = 4.0f;
    static constexpr float  DEFAULT_LIMIT_DAMPEN_START= 0.7f;
    static constexpr float  DEFAULT_LIMIT_DAMPEN_MIN  = 0.15f;
    static constexpr float  DEFAULT_TOD_OPEN_MULT     = 2.5f;
    static constexpr float  DEFAULT_TOD_CLOSE_MULT    = 2.0f;
    static constexpr int    DEFAULT_TOD_WINDOW_TICKS  = 40;
    static constexpr double DEFAULT_HARD_CLAMP_MIN    = 0.15;
    static constexpr double DEFAULT_HARD_CLAMP_MAX    = 3.0;
    static constexpr double DEFAULT_HARD_CLAMP_ABS_MIN= 1000.0;
    static constexpr double DEFAULT_DAILY_LIMIT_PCT   = 0.30;
    static constexpr double DEFAULT_K_DRIFT           = 0.001;
    static constexpr double DEFAULT_THRESHOLD_SOFT    = 0.20;
    static constexpr double DEFAULT_THRESHOLD_HARD    = 0.50;
    static constexpr float  DEFAULT_MAX_SINGLE_IMPACT = 0.15f;
    static constexpr float  DEFAULT_BREAKOUT_FORCE_THRESHOLD = 0.05f;
    static constexpr float  DEFAULT_VI_THRESHOLD      = 0.15f;
    static constexpr int    DEFAULT_VI_HALT_TICKS     = 8;
    static constexpr int    DEFAULT_VI_MAX_PER_DAY    = 1;
    static constexpr int    DEFAULT_VI_COOLDOWN_TICKS = 20;
    static constexpr int    DEFAULT_TICKS_PER_DAY     = 1560;

    static constexpr double DEFAULT_MACRO_TM[3][3] = {
        { 0.96, 0.03, 0.01 },  // TREND_UP
        { 0.02, 0.96, 0.02 },  // FLAT
        { 0.01, 0.03, 0.96 },  // TREND_DOWN
    };
    static constexpr double DEFAULT_MACRO_VM[3][2] = {
        { 1.15, 1.45 },  // TREND_UP
        { 0.75, 1.05 },  // FLAT
        { 1.05, 1.35 },  // TREND_DOWN
    };
    static constexpr double DEFAULT_MACRO_BIAS = 3.0;
    static constexpr double DEFAULT_MACRO_DS[3] = { 0.2, 1.0, 0.2 };

    static constexpr int MAX_TICK_ENTRIES = 16;

    // ── Live config fields ───────────────────────────────────────────────────

    // Shared with MarkovGenerator schema
    double _sp[7][5]    = {};
    double _tm[7][7]    = {};
    double _vss[4]      = {};
    double _vbs[4]      = {};
    double _vps[4]      = {};
    double _bvr_min[4]  = {};
    double _bvr_max[4]  = {};
    double _svm[7]      = {};

    // PriceKernel-only config
    float  _vol_amplifier[4] = {};
    float  _energy_threshold  = 0.0f;
    float  _energy_max_boost  = 0.0f;
    float  _limit_dampen_start= 0.0f;
    float  _limit_dampen_min  = 0.0f;
    float  _tod_open_mult     = 0.0f;
    float  _tod_close_mult    = 0.0f;
    int    _tod_window_ticks  = 0;
    double _hard_clamp_min    = 0.0;
    double _hard_clamp_max    = 0.0;
    double _hard_clamp_abs_min= 0.0;
    double _daily_limit_pct   = 0.0;
    double _k_drift           = 0.0;
    double _threshold_soft    = 0.0;
    double _threshold_hard    = 0.0;
    float  _max_single_impact = 0.0f;
    float  _breakout_force_threshold = 0.0f;
    float  _vi_threshold      = 0.0f;
    int    _vi_halt_ticks     = 0;
    int    _vi_max_per_day    = 0;
    int    _vi_cooldown_ticks = 0;
    int    _ticks_per_day     = 0;

    // Macro trend
    double _macro_tm[3][3]       = {};
    double _macro_vm[3][2]       = {};
    double _macro_bias           = DEFAULT_MACRO_BIAS;
    double _macro_drift_scale[3] = {};

    // Per-archetype matrices
    struct ArchMatrix      { double tm[7][7]; };
    struct MacroArchMatrix { double tm[3][3]; };
    std::unordered_map<std::string, ArchMatrix>      _archetype_matrices;
    std::unordered_map<std::string, MacroArchMatrix> _macro_arch_matrices;

    // Tick-size table
    struct TickEntry { int threshold; int tick_size; };
    static constexpr TickEntry DEFAULT_TICK_TABLE[7] = {
        {    1000,    1 },
        {    5000,    5 },
        {   10000,   10 },
        {   50000,   50 },
        {  100000,  100 },
        {  500000,  500 },
        { 2147483647, 1000 },
    };
    TickEntry _tick_table[MAX_TICK_ENTRIES] = {};
    int       _tick_table_size = 0;

    bool _cfg_loaded = false;

    // ── Internal helpers ─────────────────────────────────────────────────────

    int _get_tick_size(int price) const noexcept;
    int _round_to_tick(double raw) const noexcept;
    void _copy_defaults();
    void _build_scaled_matrix(int vol_profile, double out_m[7][7],
                               const double (*base_tm)[7] = nullptr) const;
    void _apply_macro_bias(const double in_m[7][7], double out_m[7][7], int macro_state) const;

    static void _bind_methods();

    // ── Per-stock internal state ─────────────────────────────────────────────

    struct GradualEvent {
        float actual_impact;
        int   remaining_ticks;
        int   total_ticks;
        int   decay_curve;   // 0=LINEAR 1=EXPONENTIAL
        float decay_rate;    // precomputed; 0 for LINEAR
    };

    struct IncomingEvent {
        int   scope;         // 0=MACRO 1=SECTOR 2=INDIVIDUAL
        float base_impact;
        int   direction;
        int   event_type;    // 0=INSTANT 1=GRADUAL
        int   decay_ticks;
        int   decay_curve;
    };

    // PCG32 — copy of struct from markov_generator.cpp's anonymous namespace.
    // Duplicated here (anonymous namespace) to avoid cross-TU linkage dependency.
    struct Pcg32 {
        uint64_t state = 0;
        uint64_t inc   = 1;

        void seed(uint64_t s) noexcept {
            state = 0;
            inc   = (s << 1u) | 1u;
            next();
            state += s;
            next();
        }

        uint32_t next() noexcept {
            uint64_t old = state;
            state = old * 6364136223846793005ULL + inc;
            uint32_t xs  = static_cast<uint32_t>(((old >> 18u) ^ old) >> 27u);
            uint32_t rot = static_cast<uint32_t>(old >> 59u);
            return (xs >> rot) | (xs << ((~rot + 1u) & 31u));
        }

        float randf() noexcept {
            return static_cast<float>(next() >> 8u) * (1.0f / 16777216.0f);
        }

        float randf_range(float lo, float hi) noexcept {
            return lo + (hi - lo) * randf();
        }
    };

    struct StockState {
        // identity
        std::string stock_id;
        std::string sector;
        std::string archetype;
        bool        is_etf = false;
        // price
        int    base_price     = 0;
        int    current_price  = 0;
        int    prev_day_close = 0;
        // markov micro-state
        int    markov_state   = 2;   // start SIDEWAYS
        int    state_duration = 0;   // ticks in current state
        // macro state
        int    macro_state    = 1;   // start FLAT
        double macro_vol_mult = 1.0;
        double day_matrix[7][7] = {};  // macro-biased matrix, rebuilt in start_day
        // sensitivity
        int   vol_profile          = 1;   // 0=LOW..3=EXTREME
        float macro_sensitivity    = 1.0f;
        float sector_sensitivity   = 1.0f;
        // events
        std::vector<IncomingEvent> incoming_events;
        std::vector<GradualEvent>  gradual_events;
        // player / rumor
        float  player_pressure        = 0.0f;
        float  rumor_delta_per_tick   = 0.0f;
        int    rumor_ticks_remaining  = 0;
        // VI
        int    vi_halt_remaining = 0;
        int    vi_cooldown       = 0;
        int    vi_count_today    = 0;
        // per-stock RNG
        Pcg32  rng;
    };

    // All registered stocks, in insertion order (for consistent iteration).
    std::vector<StockState>                    _stocks;
    std::unordered_map<std::string, size_t>    _stock_index;  // stock_id → index in _stocks

    // Current season number (stored; season_theme fields unused in Phase A)
    int _season_number = 0;

    // ── Per-tick helpers ─────────────────────────────────────────────────────

    // Returns event_delta and sets forced_breakout (BREAKOUT_UP=5, BREAKOUT_DOWN=6, -1=none).
    float _consume_events(StockState &s, int &out_forced_breakout) noexcept;

    // Pattern delta for one tick (mirrors MarkovGenerator's per-tick hot path).
    float _pattern_delta(StockState &s) noexcept;

    // Drift delta toward base_price for one tick.
    double _drift_delta(const StockState &s) const noexcept;

public:
    PriceKernel();

    // ── GDScript-visible API ─────────────────────────────────────────────────

    void      set_config(Dictionary cfg);
    void      init_stock(String stock_id, Dictionary stock_data);
    void      reset();

    void      start_season(int season_number, Dictionary season_theme);
    void      start_day(int day_number);

    Dictionary process_all_ticks(int tick_in_day);
    void       add_player_pressure(String stock_id, float delta);
    void       set_rumor(String stock_id, float delta_per_tick, int ticks_remaining);
    void       inject_event(Dictionary event_entry);
};

} // namespace godot
