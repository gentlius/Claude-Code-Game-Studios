# ADR-025: Stock Archetype Markov Matrices

## Status

Proposed

## Context

The current price generation system (ADR-024) uses a single 7x7 Markov transition
matrix for all stocks. The only differentiation between stocks comes from
`volatility_profile` (LOW/MEDIUM/HIGH/EXTREME), which scales self-transition and
breakout probabilities but does not change the fundamental price behavior pattern.

This produces homogeneous price trajectories: every stock mean-reverts toward
`base_price` at the same rate and with the same state distribution. Real markets
exhibit distinct behavioral archetypes — growth stocks trending upward over seasons,
value stocks oscillating in a narrow band, cyclical stocks following macro patterns,
etc.

### Proposed addition

6 archetypes, each with its own asymmetric 7x7 transition matrix and a per-season
drift (`seasonDrift`) that shifts `base_price` at season boundaries:

| Archetype | Intent |
|-----------|--------|
| GROWTH | Upward bias, higher uptrend/breakout_up probabilities |
| VALUE_DIVIDEND | Tight sideways band, very sticky SIDEWAYS state |
| CYCLICAL | Wider oscillation, balanced up/down transitions |
| EVENT_DRIVEN | Ultra-sticky SIDEWAYS (0.995 self), breakout-dependent |
| RECOVERY_UNCERTAIN | Per-stock seasonDrift (can go either way) |
| DECLINING_TRAP | Downward bias, occasional bull-trap breakout_up |

### Key design questions

This ADR resolves 6 architectural questions raised during the audit.

---

## Decision

### Q1: seasonDrift ownership — C++ MarkovGenerator (baked) vs GDScript (season boundary)

**Decision: GDScript PriceEngine applies seasonDrift at season boundary as a
`base_price` mutation, NOT baked into M1 bars by C++ MarkovGenerator.**

Rationale:
- `base_price` is the mean-reversion anchor. The C++ Markov kernel uses `BP`
  (line 214 of markov_generator.cpp) as the drift target throughout the entire
  cache generation run. Baking seasonDrift into the kernel would require the
  kernel to track a sliding anchor across simulated seasons — breaking the
  stateless design of `generate_stock_m1()`.
- The M1 cache is pre-generated for `history_seasons * 20` days in one call.
  seasonDrift is a between-season concept that only makes sense during live
  gameplay progression, not during pre-history generation.
- During live gameplay, PriceEngine already rebuilds `_stock_states` at season
  start (`_reset_season_mechanics`, `_on_season_start`). This is the natural
  point to apply `base_price += base_price * season_drift`.

**State ownership**: `base_price` remains on `StockData` resource as the
**initial** anchor (loaded from stocks.json, immutable during gameplay).
PriceEngine's `_stock_states[stock_id]["base_price"]` is the **live** anchor
that receives drift mutations. This is already the pattern — line 455 of
price_engine.gd copies `stock.base_price` into `_stock_states` at season init.

**Save/load**: `base_price` is NOT currently saved by `PriceEngine.get_save_data()`
(line 502-519). After implementing seasonDrift, the live `base_price` in
`_stock_states` diverges from `StockData.base_price` across seasons. Therefore,
`get_save_data()` must add `"base_price"` to the per-stock save dictionary, and
`load_save_data()` must restore it (falling back to `stock.base_price` for
pre-archetype saves).

**Pre-history generation**: seasonDrift does NOT apply to pre-history M1 cache
generation. The pre-history represents the stock's entire trading history
compressed into a single deterministic run. Applying drift per simulated season
inside the cache generator would require segmenting the generation into season
chunks with anchor shifts — excessive complexity for historical chart display.
The archetype matrix alone provides sufficient behavioral differentiation in
pre-history.

### Q2: C++/GDScript boundary — new parameter vs StockData dictionary

**Decision: Add `archetype_key: String` as a new parameter to
`generate_stock_m1()`. Do NOT pass the entire StockData dictionary.**

Current C++ signature (markov_generator.h line 103-104):
```cpp
Dictionary generate_stock_m1(int vol_profile, int base_price, int n_days,
                              int m1_capacity, int d1_capacity, int64_t seed) const;
```

New signature:
```cpp
Dictionary generate_stock_m1(int vol_profile, int base_price, int n_days,
                              int m1_capacity, int d1_capacity, int64_t seed,
                              String archetype_key = "") const;
```

Rationale:
- The C++ kernel is deliberately stateless and receives scalar parameters.
  Passing a GDScript Resource or Dictionary across the GDExtension boundary
  adds complexity and coupling.
- `archetype_key` is a string that the kernel uses to select which matrix from
  its loaded config to use. Empty string or unrecognized key falls back to the
  existing `_tm` (backward compatible).
- `set_config()` already parses the full config JSON. It will be extended to
  parse `archetypeMatrices` into a `std::unordered_map<std::string, double[7][7]>`
  (or equivalent). The kernel selects the correct matrix at generation time.

GDScript call site in `generate_stock_m1_cache()` (price_engine.gd line 873):
```gdscript
return _markov.generate_stock_m1(
    vol_profile, base_price, n_days, m1_capacity, d1_capacity, stock_seed,
    stock.archetype)  # new parameter
```

The GDScript fallback path (line 878+) similarly selects the archetype matrix
before calling `_build_transition_matrix()`.

### Q3: Cache version bump — sufficient for invalidation?

**Decision: Yes. Bump `CACHE_VERSION` from 2 to 3 in m1_cache_manager.gd
(line 25). This is sufficient.**

The disk cache validation (`_disk_cache_valid()`) already checks `CACHE_VERSION`
against the stored header. A version mismatch triggers full regeneration. Since
the archetype changes the transition matrix used during generation, any cached
bars from version 2 are invalid and must be regenerated.

No additional invalidation key is needed because:
- `history_seed` is already part of the cache key (checked by `_disk_cache_valid`)
- Archetype is a static property of the stock (from stocks.json), so changing
  a stock's archetype in the data file is equivalent to changing the generation
  algorithm — exactly what CACHE_VERSION covers.

### Q4: StockData resource — typed properties vs raw Dictionary

**Decision: Add typed properties to StockData.**

```gdscript
@export var archetype: String = ""  ## GROWTH, VALUE_DIVIDEND, etc. Empty = default matrix.
@export var season_drift: float = 0.0  ## Per-season % shift of base_price anchor.
```

Rationale:
- StockData is a typed Resource with `@export` properties (stock_data.gd).
  Adding raw Dictionary access would break the established pattern.
- `stock_database.gd` line 167 already maps JSON fields to typed properties.
  Adding two more fields follows the same pattern.
- The C++ kernel receives `archetype` as a String parameter (Q2 decision),
  not by reading StockData directly. StockData is the GDScript-side typed
  accessor; the kernel does not need to know about it.
- Empty string `""` as default preserves backward compatibility with stocks.json
  v1.0 entries that have no archetype field.

### Q5: EVENT_DRIVEN ultra-sticky SIDEWAYS (0.995) vs event pipeline interaction

**Decision: The design is safe but requires a documented constraint.**

Analysis of the interaction:
1. The Markov matrix controls **intraday price generation** (pre-history cache
   and live tick generation). A 0.995 SIDEWAYS self-transition means the stock
   spends ~99.5% of minutes in SIDEWAYS state during normal conditions.
2. Events (ADR-022: NewsEventSystem -> PriceEngine) are **additive pressure**
   on top of Markov output. They do NOT change the Markov state — they add
   `event_delta` to `pattern_delta` in the tick loop.
3. The SIDEWAYS state has `bias: 0.0`, `magMin: -0.000125`, `magMax: +0.000125`,
   `noiseStd: 0.0002` (price_engine_config.json line 9). This produces very
   small per-minute moves (~0.025% range).
4. Event pressure is added on top: `pattern_delta + event_delta`. Even with
   ultra-sticky SIDEWAYS, events shift price.

**Risk**: With 0.995 SIDEWAYS self-transition, the stock almost never enters
BREAKOUT states organically. It relies entirely on events for significant moves.
This is the intended design for EVENT_DRIVEN archetype, but creates a dependency:
if no events fire for this stock, it becomes a near-flat line.

**Documented constraint**: EVENT_DRIVEN archetype stocks MUST have at least one
`event_tag` in stocks.json that maps to active event sources. The game designer
must ensure event coverage. This is a data validation responsibility, not a
code enforcement (no runtime check — the designer ensures it at design time).

**No mean-reversion dead zone**: The drift formula (markov_generator.cpp line
287-298) still operates. Even in SIDEWAYS, if price drifts from `base_price`
due to accumulated event pressure, the reversion force pulls it back. Events
push price away; drift pulls it back. The system is stable.

### Q6: seasonDrift + save/load interaction

**Decision: Extend PriceEngine save/load to persist the drifted `base_price`.**

Current state:
- `PriceEngine.get_save_data()` (line 502) does NOT include `base_price`.
- On load (line 452-473), `base_price` is always read from `StockData.base_price`
  (which comes from stocks.json).
- This means `base_price` resets to the JSON value on every load — currently
  correct because there is no drift.

After seasonDrift:
- `base_price` in `_stock_states` will diverge from `StockData.base_price` after
  the first season boundary where drift is applied.
- `get_save_data()` must include `"base_price": s.get("base_price", 0)`.
- `load_save_data()` must read it: `"base_price": saved.get("base_price", stock.base_price)`.
  The fallback to `stock.base_price` handles pre-archetype save migration.

**Hard clamp interaction**: The price clamp bounds (markov_generator.cpp lines
244-245, price_engine.gd lines 142-143) use `base_price` to compute
`HARD_CLAMP_MIN_RATIO * base_price` and `HARD_CLAMP_MAX_RATIO * base_price`.
After drift, the live `base_price` shifts, and clamp bounds shift with it.
This is correct behavior: a GROWTH stock whose base_price drifts upward should
have its valid price range shift upward accordingly.

**Drift accumulation bound**: Over many seasons, drift compounds. A GROWTH stock
with `seasonDrift: 0.025` (+2.5%/season) grows ~28% over 10 seasons. After 100
seasons, ~12x. The game designer must set seasonDrift values that produce
reasonable price ranges over the maximum expected play duration. This is a
tuning responsibility, not a code guard. Document in the GDD.

---

## Consequences

### Positive

- Each stock exhibits distinct long-term price behavior matching its archetype,
  creating meaningful differentiation for player strategy.
- Backward compatible: empty archetype string falls back to existing global matrix.
- C++ kernel remains stateless — archetype is just a matrix lookup key.
- Pre-history charts show archetype-specific patterns (GROWTH trends up,
  DECLINING_TRAP trends down) without any special-case code.
- DLC markets can define new archetypes by adding entries to
  `archetypeMatrices` in price_engine_config.json — no code changes needed.

### Negative

- `base_price` becomes mutable state in PriceEngine (was effectively read-only).
  This adds a new field to save data and a potential source of drift-related bugs.
- EVENT_DRIVEN stocks have a hard dependency on event coverage — no events means
  flat price. Requires game design discipline.
- CACHE_VERSION bump (2 -> 3) forces full cache regeneration for all players
  on first load after the update. One-time cost.
- 6 matrices in price_engine_config.json increase the file size and tuning
  surface area. Each matrix has 49 values that must sum to 1.0 per row.

### Performance Implications

- Zero performance impact on the hot path. The matrix lookup happens once per
  `generate_stock_m1()` call (per stock, not per tick). The inner tick loop
  is unchanged.
- Config parsing in `set_config()` adds ~6 matrix copies (6 * 49 doubles =
  ~2.4KB). Negligible.
- No additional memory per tick or per bar.

---

## Implementation Guide

### Step 1: StockData + stocks.json

1. `src/data/stock_data.gd`: Add two properties after line 25:
   ```gdscript
   @export var archetype: String = ""
   @export var season_drift: float = 0.0
   ```
2. `src/core/stock_database.gd`: Add field loading after line 167:
   ```gdscript
   stock.archetype = str(entry.get("archetype", ""))
   stock.season_drift = float(entry.get("seasonDrift", 0.0))
   ```
3. `assets/data/stocks.json`: Bump version to "2.0". Add `"archetype"` and
   `"seasonDrift"` fields to each stock entry. Stocks without an archetype
   default to `""` (global matrix fallback).

### Step 2: price_engine_config.json v3

1. Bump `"version": 3`.
2. Add `"archetypeMatrices"` object with 6 archetype keys, each containing
   `"transitionMatrix"` (7x7 array). Keep existing `"transitionMatrix"` as
   the default fallback.
3. Validate: every row in every matrix must sum to 1.0 (within float tolerance).

### Step 3: C++ MarkovGenerator

1. `markov_generator.h`:
   - Add `#include <unordered_map>` and `#include <godot_cpp/variant/string.hpp>`.
   - Add member: `std::unordered_map<std::string, double[7][7]> _archetype_matrices;`
     (or use a fixed-size array with enum mapping if preferred).
   - Change `generate_stock_m1` signature to add `String archetype_key = ""`.

2. `markov_generator.cpp`:
   - In `set_config()`: parse `archetypeMatrices` dictionary. For each key,
     read the 7x7 `transitionMatrix` into `_archetype_matrices[key]`.
   - In `generate_stock_m1()`: if `archetype_key` is non-empty and exists in
     `_archetype_matrices`, copy that matrix into the local `_tm` equivalent
     before calling `_build_scaled_matrix()`. Otherwise use `_tm` (default).
   - `_build_scaled_matrix()` is unchanged — it operates on whatever base
     matrix is provided.

3. `_bind_methods()`: Update the `D_METHOD` for `generate_stock_m1` to include
   the new parameter with a default value.

### Step 4: GDScript PriceEngine

1. `_build_markov_cfg()` (line 338): Already passes the full config dict.
   Ensure `archetypeMatrices` from the JSON is included in the dict passed
   to `set_config()`.
2. `generate_stock_m1_cache()` (line 857): Pass `stock.archetype` as the 7th
   argument to `_markov.generate_stock_m1()`.
3. GDScript fallback path (line 878): Add archetype matrix selection before
   `_build_transition_matrix()`. If `stock.archetype` is non-empty, look up
   the archetype matrix from `_cfg_archetype_matrices` (new parsed field)
   and use it as the base for `_build_matrix_row()`.
4. Live tick path: `_build_transition_matrix()` (line 1991) currently reads
   from `_cfg_transition_matrix`. For per-stock archetype support in live
   ticks, store the archetype key in `_stock_states[stock_id]` and look up
   the correct base matrix in `_build_matrix_row()`.

### Step 5: seasonDrift in PriceEngine

1. `_reset_season_mechanics()` / `_on_season_start()`: After building
   `_stock_states`, apply drift:
   ```gdscript
   var drift: float = stock.season_drift
   var old_base: int = _stock_states[stock_id]["base_price"]
   _stock_states[stock_id]["base_price"] = int(round(float(old_base) * (1.0 + drift)))
   ```
   Skip drift on the first season (season_count == 1) or when loading a save
   that already has the drifted base_price.
2. `get_save_data()` (line 502): Add `"base_price": s.get("base_price", 0)`.
3. `load_save_data()`: Read `saved.get("base_price", stock.base_price)`.

### Step 6: M1CacheManager

1. Bump `CACHE_VERSION` from 2 to 3 (line 25).
2. No other changes needed — M1CacheManager calls
   `PriceEngine.generate_stock_m1_cache(stock, ...)` which handles archetype
   selection internally.

### Step 7: Tests

1. Unit tests for archetype matrix selection in C++ (if test harness exists)
   or via GDScript integration test calling `generate_stock_m1_cache()` with
   different archetype values and verifying different price distributions.
2. Save/load round-trip test: save with drifted base_price, load, verify
   base_price restored correctly.
3. API contracts: register new `StockData.archetype` and
   `StockData.season_drift` properties.

---

## Alternatives Considered

**Alt A: Per-stock stateParams (not just matrix)**
Each archetype could also override `stateParams` (bias, magnitude, noise).
Rejected for Phase 1: the matrix alone provides sufficient behavioral
differentiation. stateParams override can be added later as an incremental
enhancement without architectural changes.

**Alt B: seasonDrift baked into C++ cache generation**
The kernel would segment generation into season-length chunks, shifting
`base_price` between segments. Rejected: breaks the stateless kernel design,
adds complexity for a feature that only matters during live gameplay (not
pre-history), and creates cache invalidation issues when seasonDrift values
are tuned.

**Alt C: Archetype as enum instead of String**
Using an integer enum for archetype would be faster for C++ lookup. Rejected:
String keys are more extensible (DLC can add new archetypes without code
changes), and the lookup happens once per stock per generation call — not a
hot path.

**Alt D: Store archetype matrix in StockData resource directly**
Each StockData would carry its own 7x7 matrix. Rejected: massive duplication
(46 stocks * 49 floats), harder to tune (change one archetype = edit 10+
stock entries), and violates the data-driven config pattern established in
price_engine_config.json.
