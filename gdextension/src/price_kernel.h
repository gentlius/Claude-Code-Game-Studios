// price_kernel.h — Stateful GDExtension class for live per-tick price computation.
// ADR-027 Phase A–D: Markov + EventEngine + EtfEngine + ReportEngine in C++.
// Phase E (run_historical_simulation) is next.
// See: docs/architecture/027-price-kernel-unification.md
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

    // ── EventEngine: compile-time slot config ────────────────────────────────
    // Mirrors NewsEventSystem.SLOT_CONFIG_MINUTES. Minutes × TICKS_PER_MINUTE(4).

    struct SlotCfg { int tick_min; int tick_max; float probability; };
    static constexpr SlotCfg EE_SLOTS[4] = {
        {   4,  400, 0.70f },  // opening  (1–100 min × 4)
        { 404,  760, 0.55f },  // midday_1 (101–190 min × 4)
        { 764, 1120, 0.55f },  // midday_2 (191–280 min × 4)
        {1124, 1560, 0.60f },  // closing  (281–390 min × 4)
    };
    static constexpr int   EE_DAILY_HARD_CAP        = 5;
    static constexpr float EE_INDIVIDUAL_W           = 0.55f;
    static constexpr float EE_SECTOR_W               = 0.35f;
    static constexpr float EE_MACRO_W                = 0.10f;
    static constexpr float EE_IMPACT_W[4]            = {0.35f, 0.40f, 0.20f, 0.05f}; // S/M/L/MEGA
    static constexpr float EE_VOL_W[4]               = {0.7f, 1.0f, 1.2f, 1.5f};     // LOW..EXTREME
    static constexpr int   EE_INDIVIDUAL_COOLDOWN_MIN = 22;
    static constexpr float EE_CLUSTER_PENALTY         = 0.5f;

    // ── EventEngine: template and slot structs ───────────────────────────────

    struct EventTemplate {
        std::string              template_id;
        int                      scope;          // 0=INDIVIDUAL 1=SECTOR 2=MACRO
        int                      impact_tier;    // 0=SMALL 1=MEDIUM 2=LARGE 3=MEGA
        int                      event_type;     // 0=INSTANT_SHOCK 1=GRADUAL_SHIFT
        int                      direction;      // +1 / -1 / 0=VARIABLE
        float                    impact_min;
        float                    impact_max;
        int                      decay_minutes;
        int                      decay_curve;    // 0=LINEAR 1=EXPONENTIAL
        float                    weight_base;
        int                      cooldown_minutes;
        std::string              target_sector;
        std::string              mutex_group;    // may contain {stock_id}
        bool                     exclude_same_scope = false;
        std::vector<std::string> season_tags;
        std::vector<std::string> event_tags;    // for INDIVIDUAL targeting
    };

    struct DailySlot {
        int  tick;
        int  scope;    // 0=INDIVIDUAL 1=SECTOR 2=MACRO
        int  impact;   // 0=SMALL 1=MEDIUM 2=LARGE 3=MEGA
        bool fired = false;
    };

    // ── Internal helpers ─────────────────────────────────────────────────────

    int _get_tick_size(int price) const noexcept;
    int _round_to_tick(double raw) const noexcept;
    void _copy_defaults();
    void _build_scaled_matrix(int vol_profile, double out_m[7][7],
                               const double (*base_tm)[7] = nullptr) const;
    void _apply_macro_bias(const double in_m[7][7], double out_m[7][7], int macro_state) const;

    // ── EventEngine helpers ──────────────────────────────────────────────────
    void _ee_generate_daily_schedule();
    void _ee_check_slots(int tick_in_day, Array &out_ui_events);
    bool _ee_fire_event(int scope, int impact_tier, int tick, Array &out_ui_events);
    int  _ee_pick_scope()  noexcept;
    int  _ee_pick_impact() noexcept;
    const EventTemplate* _ee_pick_template(int scope, int impact_tier, int abs_tick);
    std::string _ee_select_individual_stock(const EventTemplate &tmpl, int abs_tick);
    bool _ee_season_tag_ok(const EventTemplate &tmpl) const noexcept;
    bool _ee_cooldown_ok(const EventTemplate &tmpl, int abs_tick) const;
    bool _ee_mutex_blocked(const std::string &mx_group, const std::string &stock_id) const;
    void _ee_register_mutex(const std::string &mx_group, const std::string &stock_id);

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
        std::vector<std::string> event_tags;  // for INDIVIDUAL event targeting
        float listed_shares = 1000000.0f;     // for ETF market-cap weighting
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
        // Fundamentals — ReportEngine 소유 (ADR-027 Phase D)
        float  roe = 0.08f;   // fraction (0.08 = 8%)
        float  per = 12.0f;
        float  pbr = 1.0f;
        // per-stock RNG
        Pcg32  rng;
    };

    // ── EventEngine: runtime state ───────────────────────────────────────────

    std::vector<EventTemplate>                    _event_pool;
    DailySlot                                     _daily_slots[EE_DAILY_HARD_CAP + 1] = {};
    int                                           _daily_slot_count  = 0;
    int                                           _daily_event_count = 0;
    bool                                          _daily_mega_fired  = false;
    int                                           _last_slot_scope   = -1;  // -1=none
    std::unordered_map<std::string, int>          _ee_cooldown;   // key → abs_tick
    std::unordered_map<std::string, int>          _ee_individual_cd; // stock_id → abs_tick
    std::unordered_map<std::string, std::string>  _ee_mutex;      // key → template_id
    Pcg32                                         _event_rng;
    int                                           _ee_day = 0;    // current day (abs)

    // Season-level EventEngine state (set by start_season())
    std::vector<std::string>                    _ee_season_tags;
    std::unordered_map<std::string, float>      _ee_sector_bias;
    float _ee_macro_weight_scale      = 1.0f;
    float _ee_sector_weight_scale     = 1.0f;
    float _ee_individual_weight_scale = 1.0f;

    // ── EtfEngine: structs ───────────────────────────────────────────────────

    struct EtfEntry {
        std::string etf_id;
        std::string sector;
        float current_price = 0.0f;
        float open_price    = 0.0f;
    };

    struct SectorFlowState {
        float flow          = 0.0f;
        float prev_flow     = 0.0f;
        int   cooldown      = 0;
        std::vector<float> return_history;
    };

    // ── EtfEngine: config ────────────────────────────────────────────────────

    float _etf_base_price = 50000.0f;
    std::unordered_map<std::string, std::string>              _etf_to_sector;
    std::unordered_map<std::string, std::string>              _sector_to_etf;
    std::unordered_map<std::string, std::string>              _sector_archetype;
    std::unordered_map<std::string, std::vector<std::string>> _archetype_to_sectors;
    std::unordered_map<std::string, std::unordered_map<std::string, float>> _rivalry_weights;

    float _etf_flow_sensitivity       = 0.5f;
    float _etf_flow_decay             = 0.1f;
    float _etf_rotation_threshold     = 0.03f;
    int   _etf_rotation_cooldown_ticks= 5;
    float _etf_inflow_impact_min      = 0.04f;
    float _etf_inflow_impact_max      = 0.07f;
    float _etf_outflow_impact_min     = 0.02f;
    float _etf_outflow_impact_max     = 0.03f;
    int   _etf_rotation_decay_ticks   = 8;
    int   _etf_flow_lookback          = 5;

    bool _etf_config_loaded = false;

    // ── EtfEngine: runtime state ─────────────────────────────────────────────

    std::vector<EtfEntry>                              _etfs;
    std::unordered_map<std::string, size_t>            _etf_index;   // etf_id → _etfs idx
    std::unordered_map<std::string, SectorFlowState>   _sector_flow_states;  // sector → flow

    // ── ReportEngine: structs ────────────────────────────────────────────────

    struct ReportConfig {
        int   cycle_seasons        = 3;
        int   fiscal_year_start    = 1;
        int   news_stock_min       = 8;
        int   news_stock_max       = 12;
        int   report_day_min       = 5;
        int   report_day_max       = 18;
        int   analyst_day_min      = 3;
        int   analyst_day_max      = 10;
        int   rumor_fire_tick      = 40;
        float rumor_fake_rate      = 0.30f;
        float roe_news_threshold   = 0.03f;
        float surprise_threshold   = 0.05f;
        float shock_threshold      = 0.05f;
        float consensus_uncert_max = 0.08f;
        float uncertainty_decay    = 8.0f;
        float sector_ripple_ratio  = 0.30f;
        float sector_noise         = 0.03f;
        float stock_noise          = 0.02f;
        float roe_min              = -0.30f;
        float roe_max              = 0.50f;
        float per_negative_sentinel= -1.0f;
        float roe_drift_scale      = 0.04f;
        float sector_ripple_impact = 0.06f;
        int   sector_ripple_decay  = 4;
        int   preliminary_offset   = 3;
        bool  preliminary_enabled  = true;
        float prelim_prob[4]       = {0.90f, 0.70f, 0.30f, 0.00f}; // LOW…EXTREME
    };

    struct ReportEntry {
        std::string stock_id;
        int   season           = 0;
        int   reporting_day    = 0;
        int   preliminary_day  = 0;
        int   rumor_day        = 0;
        int   analyst_day      = 0;
        bool  has_preliminary  = false;
        bool  is_fake_rumor    = false;
        int   event_sign       = 1;   // +1 or -1
        float consensus_roe    = 0.0f;
        bool  analyst_done     = false;
        bool  preliminary_done = false;
        bool  rumor_done       = false;
        bool  report_done      = false;
        bool  quiet            = false;
    };

    // ── ReportEngine: config & runtime state ─────────────────────────────────

    ReportConfig                                  _re_cfg;
    bool                                          _re_config_loaded = false;
    std::unordered_map<std::string, ReportEntry>  _re_pending;
    bool                                          _re_is_active = false;
    int                                           _re_season    = 0;
    Pcg32                                         _re_rng;
    Pcg32                                         _re_consensus_rng;
    // Pre-market event buffer: populated by _re_process_pre_market() in start_day(),
    // flushed into process_all_ticks(tick=0) results to preserve timing.
    Array                                         _re_buffered_ui_events;
    Array                                         _re_buffered_a3_updates;

    // ── ReportEngine: methods ────────────────────────────────────────────────

    void        _re_init_from_config(const Dictionary &cfg);
    void        _re_start_season(int season);
    bool        _re_is_report_season(int season) const noexcept;
    std::vector<std::string> _re_select_newsworthy(int season);
    ReportEntry _re_build_entry(const std::string &stock_id, int season);
    float       _re_compute_new_roe(const std::string &stock_id);
    float       _re_compute_consensus_roe(const std::string &stock_id, int day);
    float       _re_get_theme_drift(const std::string &sector) const noexcept;
    std::string _re_classify_event(float prev_roe, float new_roe,
                                   float consensus_roe) const noexcept;
    void        _re_process_pre_market(int day, Array &out_ui, Array &out_a3);
    void        _re_process_tick(int tick_in_day, Array &out_ui);
    void        _re_fire_analyst(const ReportEntry &ev, Array &out_ui);
    void        _re_fire_preliminary(const ReportEntry &ev, Array &out_ui);
    void        _re_fire_official(ReportEntry &ev, Array &out_ui, Array &out_a3);
    void        _re_fire_rumor(const ReportEntry &ev, Array &out_ui);
    void        _re_do_quiet_update(const std::string &stock_id, Array &out_a3);
    void        _re_apply_a3_update(StockState &s, float new_roe, Array &out_a3);
    void        _re_fire_sector_ripple(const std::string &sector,
                                       float shock_mag, int direction);
    Dictionary  _re_build_ui_event(const std::string &subtype,
                                   const std::string &stock_id,
                                   int direction, const std::string &impact_tier,
                                   int tick) const;

    // ── EtfEngine: methods ───────────────────────────────────────────────────

    void        _etf_process_tick(int tick_in_day, Array &out_ui_events);
    float       _etf_calc_price(const std::string &sector) const noexcept;
    void        _etf_update_flow(const std::string &sector, SectorFlowState &fs) noexcept;
    void        _etf_check_rotation(const std::string &sector, SectorFlowState &fs,
                                    int tick_in_day, Array &out_ui_events);
    void        _etf_fire_rotation(const std::string &sector, int direction,
                                   int tick_in_day, Array &out_ui_events);
    std::string _etf_pick_rival_sector(const std::string &hot_sector) noexcept;

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
    Dictionary get_macro_states() const;
    void       add_player_pressure(String stock_id, float delta);
    void       set_rumor(String stock_id, float delta_per_tick, int ticks_remaining);
    void       inject_event(Dictionary event_entry);

    // Phase D: ReportEngine save/load state serialization
    Dictionary get_report_state() const;
    void       restore_report_state(Dictionary state);
};

} // namespace godot
