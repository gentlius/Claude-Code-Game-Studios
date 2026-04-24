// markov_generator.h — C++ GDExtension: stateless Markov kernel for M1 price generation.
// Ported from PriceEngine.generate_stock_m1_cache() (GDScript, Phase 1 reference).
// See: design/gdd/price-engine.md, docs/architecture/024-price-engine-gdextension.md
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <cstdint>
#include <string>
#include <unordered_map>

#include "markov_defaults.h"

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
    // Defined in markov_defaults.h (shared with PriceKernel) at namespace godot scope.
    // Used when set_config() has not been called or JSON is missing a field.

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
    double _tm[7][7]  = {};    // base transition matrix (default fallback)
    double _vss[4]    = {};    // vol_self_scale
    double _vbs[4]    = {};    // vol_breakout_scale
    double _vps[4]    = {};    // vol_pattern_scale
    double _bvr_min[4]= {};
    double _bvr_max[4]= {};
    double _svm[7]    = {};

    // ── Per-archetype matrices (ADR-025) ──
    // Keyed by archetype string (e.g. "GROWTH"). Loaded from archetypeMatrices in config.
    struct ArchMatrix { double tm[7][7]; };
    std::unordered_map<std::string, ArchMatrix> _archetype_matrices;

    // ── Macro trend layer (ADR-026) ──
    // Day-granularity 3-state Markov: 0=TREND_UP, 1=FLAT, 2=TREND_DOWN.
    // MacroState biases M1 micro-state transition matrix so weekly/monthly charts trend.
    // Self-prob 0.96 → avg duration 25d per trend (sufficient to dominate a 20-day month).
    // DEFAULT_MACRO_TM, DEFAULT_MACRO_VM, DEFAULT_MACRO_BIAS, DEFAULT_MACRO_DS —
    // defined in markov_defaults.h at namespace godot scope.

    double _macro_tm[3][3]         = {};
    double _macro_vm[3][2]         = {};    // vol multiplier [state][min/max]
    double _macro_bias             = DEFAULT_MACRO_BIAS;
    double _macro_drift_scale[3]   = {};    // k_drift multiplier per MacroState

    // Per-archetype macro 3×3 matrices (keyed by archetype string).
    struct MacroArchMatrix { double tm[3][3]; };
    std::unordered_map<std::string, MacroArchMatrix> _macro_arch_matrices;

    // Apply MacroState column bias to in_m → out_m (row-wise renormalized).
    // macro_state: 0=TREND_UP (boosts cols 0,1), 1=FLAT (no-op), 2=TREND_DOWN (boosts cols 3,4).
    void _apply_macro_bias(const double in_m[7][7], double out_m[7][7], int macro_state) const;

    // ── Tick-size table (ADR-002, DLC extensibility) ──
    // TickEntry, MAX_TICK_ENTRIES, DEFAULT_TICK_TABLE — defined in markov_defaults.h.
    TickEntry _tick_table[MAX_TICK_ENTRIES];
    int       _tick_table_size = 0;

    int _get_tick_size(int price) const noexcept {
        for (int i = 0; i < _tick_table_size; ++i) {
            if (price < _tick_table[i].threshold)
                return _tick_table[i].tick_size;
        }
        return _tick_table_size > 0 ? _tick_table[_tick_table_size - 1].tick_size : 1;
    }
    int round_to_tick(double raw) const noexcept {
        int r  = static_cast<int>(std::lround(raw));
        int ts = _get_tick_size(r);
        return static_cast<int>(std::lround(raw / static_cast<double>(ts))) * ts;
    }

    // ── Internal helpers ──
    void _copy_defaults();
    // base_tm: if non-null, used as the source matrix instead of _tm.
    void _build_scaled_matrix(int vol_profile, double out_m[7][7],
                               const double (*base_tm)[7] = nullptr) const;

    static void _bind_methods();

public:
    MarkovGenerator();

    // Load Markov config from a Dictionary matching price_engine_config.json schema.
    // Call once before first generate_stock_m1(); safe to call again after JSON reload.
    void set_config(Dictionary cfg);

    // Generate M1 + D1 rolling cache for one stock.
    // vol_profile   : 0=LOW, 1=MEDIUM, 2=HIGH, 3=EXTREME
    // base_price    : stock base price (KRW integer)
    // n_days        : total simulation days (history_seasons * DAYS_PER_SEASON)
    // m1_capacity   : M1 ring-buffer size in bars (M1CacheManager.M1_CACHE_BARS)
    // d1_capacity   : D1 ring-buffer size in bars (M1CacheManager.D1_CACHE_BARS)
    // seed          : (history_seed ^ hash(stock_id)) & 0x7FFFFFFF  (pre-computed by caller)
    // archetype_key : stock archetype string (e.g. "GROWTH"). Empty = default matrix. (ADR-025)
    //
    // Returns the same Dictionary shape as PriceEngine.generate_stock_m1_cache():
    //   m1_ohlc(PackedInt32Array), m1_vol(PackedFloat32Array),
    //   d1_ohlc(PackedInt32Array), d1_vol(PackedFloat32Array),
    //   m1_count(int), d1_count(int)
    Dictionary generate_stock_m1(int vol_profile, int base_price, int n_days,
                                  int m1_capacity, int d1_capacity, int64_t seed,
                                  String archetype_key = String()) const;
};

} // namespace godot
