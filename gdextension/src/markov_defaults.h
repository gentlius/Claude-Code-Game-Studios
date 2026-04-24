// markov_defaults.h — Shared Markov constants and PCG32 for MarkovGenerator + PriceKernel.
// ADR-027: single source of truth for state-machine parameters shared between the two kernels.
// Both markov_generator.h and price_kernel.h include this file; their class-level duplicates
// have been removed. Do not add class-specific constants here.
#pragma once

#include <cstdint>
#include <cmath>

namespace godot {

// ── PCG32 ────────────────────────────────────────────────────────────────────
// Deterministic 32-bit generator. NOT identical to Godot's RandomNumberGenerator.
// Shared between MarkovGenerator (batch history) and PriceKernel (live ticks).
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

    float randf() noexcept {
        return static_cast<float>(next() >> 8u) * (1.0f / 16777216.0f);
    }

    float randf_range(float lo, float hi) noexcept {
        return lo + (hi - lo) * randf();
    }
};

// ── Tick-size table ──────────────────────────────────────────────────────────
// KRX default tick table. Loaded from MarketProfile JSON at runtime; this is the
// fallback when set_config() has not been called or tickTable is absent.
struct TickEntry { int threshold; int tick_size; };
inline constexpr int      MAX_TICK_ENTRIES  = 16;
inline constexpr TickEntry DEFAULT_TICK_TABLE[7] = {
    {    1000,    1 },
    {    5000,    5 },
    {   10000,   10 },
    {   50000,   50 },
    {  100000,  100 },
    {  500000,  500 },
    { 2147483647, 1000 },  // INT_MAX — catch-all
};

// ── Markov micro-state parameters (shared) ───────────────────────────────────
inline constexpr double DEFAULT_SP[7][5] = {
    //  bias        mag_min     mag_max     noise_std   min_dur(min)
    { +0.00030,  +0.000075, +0.00050,  0.0004,  5.0 }, // STRONG_UP
    { +0.000125, +0.000025, +0.00025,  0.0003,  8.0 }, // UPTREND
    {  0.0,      -0.000125, +0.000125, 0.0002, 10.0 }, // SIDEWAYS
    { -0.000125, -0.00025,  -0.000025, 0.0003,  8.0 }, // DOWNTREND
    { -0.00030,  -0.00050,  -0.000075, 0.0004,  5.0 }, // STRONG_DOWN
    { +0.00075,  +0.00025,  +0.00125,  0.00075, 1.0 }, // BREAKOUT_UP
    { -0.00075,  -0.00125,  -0.00025,  0.00075, 1.0 }, // BREAKOUT_DOWN
};

inline constexpr double DEFAULT_TM[7][7] = {
    { 0.980, 0.010, 0.003, 0.001, 0.000, 0.005, 0.001 }, // STRONG_UP
    { 0.005, 0.985, 0.005, 0.001, 0.000, 0.003, 0.001 }, // UPTREND
    { 0.003, 0.008, 0.975, 0.008, 0.003, 0.002, 0.001 }, // SIDEWAYS
    { 0.000, 0.001, 0.005, 0.985, 0.005, 0.001, 0.003 }, // DOWNTREND
    { 0.000, 0.001, 0.003, 0.010, 0.980, 0.001, 0.005 }, // STRONG_DOWN
    { 0.075, 0.250, 0.125, 0.040, 0.000, 0.500, 0.010 }, // BREAKOUT_UP
    { 0.000, 0.040, 0.125, 0.250, 0.075, 0.010, 0.500 }, // BREAKOUT_DOWN
};

inline constexpr double DEFAULT_VSS[4]     = { 1.15, 1.00, 0.90, 0.75 };
inline constexpr double DEFAULT_VBS[4]     = { 0.30, 1.00, 2.00, 4.00 };
inline constexpr double DEFAULT_VPS[4]     = { 0.60, 1.00, 1.30, 1.80 };
inline constexpr double DEFAULT_BVR_MIN[4] = { 100.0, 200.0,  400.0,  800.0 };
inline constexpr double DEFAULT_BVR_MAX[4] = { 300.0, 600.0, 1200.0, 3000.0 };
inline constexpr double DEFAULT_SVM[7]     = { 1.3, 1.1, 0.7, 1.1, 1.3, 2.0, 2.0 };

// ── Macro trend layer (ADR-026, shared) ──────────────────────────────────────
inline constexpr double DEFAULT_MACRO_TM[3][3] = {
    { 0.96, 0.03, 0.01 },  // TREND_UP
    { 0.02, 0.96, 0.02 },  // FLAT
    { 0.01, 0.03, 0.96 },  // TREND_DOWN
};
inline constexpr double DEFAULT_MACRO_VM[3][2] = {
    { 1.15, 1.45 },  // TREND_UP: elevated volume
    { 0.75, 1.05 },  // FLAT: subdued volume
    { 1.05, 1.35 },  // TREND_DOWN: elevated (panic) volume
};
inline constexpr double DEFAULT_MACRO_BIAS = 3.0;
inline constexpr double DEFAULT_MACRO_DS[3] = { 0.2, 1.0, 0.2 };

} // namespace godot
