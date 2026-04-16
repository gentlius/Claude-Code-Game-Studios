# ADR-019 — Player Order Market Impact (Price Pressure + Volume Feedback)

**Status**: Accepted  
**Date**: 2026-04-16  
**Deciders**: technical-director, game-designer, lead-programmer

---

## Context

The order book system (ADR-013, GDD order-book.md) generates intraday liquidity based on
each stock's `volatility_profile`. A large player — or even a normal one trading a
small-cap — could fill the entire order book in one tick with zero price impact,
because `consume_order_book()` was invisible to the price simulation loop.

Two structural gaps:
1. Player fills did not add to `tick_volumes`, so the volume display and the
   volume-correlated order book refresh (`_update_order_books()` Phase 2) did not
   reflect real player activity.
2. `_process_stock_tick()` had no mechanism for player fills to shift the price.
   A whale buying 100% of a 10B market-cap company's daily volume in one tick
   produced the same price outcome as buying zero shares.

---

## Decision

### Fix 1 — Volume Feedback

In `consume_order_book()`, after a successful fill, append `filled_qty` to the
last entry of `tick_volumes` for that stock. This feeds into the existing
`volume_factor` calculation in `_update_order_books()` Phase 2 without any
further changes.

### Fix 2 — Price Pressure (Next-Tick Delta)

Introduce `_player_pressure: Dictionary` (stock_id → float) as a per-tick
accumulator. When a fill occurs:

```
pressure = filled_qty / daily_volume * PLAYER_PRESSURE_SCALE
side == "sell" → pressure is negative
```

`_process_stock_tick()` reads and erases the entry at **Step 4b** (after event
processing, before the additive combination in Step 5), adding it to `total_delta`.

**Scale constant**: `PLAYER_PRESSURE_SCALE = 0.30`

Calibration: a player filling 100% of the stock's daily volume in a single tick
contributes a 30% raw price delta before daily-limit clamping. At 10% of daily
volume, the contribution is 3% — comparable to a strong news event.

---

## Alternatives Considered

- **Immediate price adjustment**: Modifying `current_price` directly inside
  `consume_order_book()` would break the single-writer invariant (`_process_stock_tick()`
  is the sole owner of price updates). Rejected.
- **Proportional spread widening**: Temporarily widening the bid-ask spread as a
  proxy for impact. Rejected — doesn't affect the Markov simulation at all, so
  a reload would erase it.

---

## Consequences

- Small fills (< 1% of daily volume) produce < 0.3% price impact — negligible,
  as intended.
- Large fills on small-cap stocks produce visible and meaningful price movement.
- `_player_pressure` is cleared on `reset()`, `_reset_season_mechanics()`, and
  `initialize_for_load()` so stale pressure never survives a save/load cycle.
- The pressure is **one-directional per tick**: multiple buys within the same tick
  (not currently possible in single-player, but safe via accumulation) stack additively.

---

## Design Assessment (2026-04-16)

현재 모델의 구조적 판단:

- **압력 누적 → 다음 틱 소비** 방식은 단일-작성자 불변식(single-writer invariant)을
  깨지 않으면서 플레이어 영향을 시뮬레이션에 통합하는 올바른 접근. 유지.
- **선형 압력 모델** (`filled / daily_vol * SCALE`)은 1차 근사로 충분히 합리적.
  현실 미시구조의 제곱근 충격 법칙 (`sqrt(filled / daily_vol) * SCALE`)이 더 정확하지만,
  이는 재무제표 스킬 스프린트에서 total_shares 도입 시 함께 고도화할 것.

---

## 이연된 개선 (재무제표 스킬 스프린트)

현재 `DAILY_VOLUME_BY_PROFILE`는 시총·발행주식수와 단절된 고정값이다.
실제로는 `daily_volume = total_shares * turnover_rate_by_profile`이어야 하며,
이 값이 정확해질 때 아래 세 가지가 자동으로 정교해진다:

1. **호가잔량 규모**: 소형주는 얇고, 대형주는 두껍게 — 시총 비례 자연 조정
2. **압력 정규화**: `filled / daily_vol`이 사실상 유통주식 점유율 기반으로 변환됨
3. **충격 공식 고도화**: 선형 → 제곱근 충격 법칙으로 교체 가능

재무제표 스킬 설계 시 `StockData`에 `total_shares: int`, `major_shareholder_pct: float`
추가 예정. 그 시점에 `DAILY_VOLUME_BY_PROFILE`를 파생값으로 교체하고
이 ADR을 갱신한다.

**현재 `DAILY_VOLUME_BY_PROFILE`는 재무제표 스킬 전까지 placeholder로 유지.**

---

## Related

- GDD: `design/gdd/order-book.md` §3-4 (consume_order_book)
- ADR-013: TradingScreen 5-component split
- ADR-018: PriceEngine session RNG entropy isolation
- 재무제표 스킬 GDD (미작성) — total_shares, turnover_rate 도입 시 이 ADR 갱신
