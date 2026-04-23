# Cross-GDD Review Report — Seed Money (시드머니)

> **Date**: 2026-04-23
> **GDDs Reviewed**: 34개 시스템 전체
> **Method**: Phase 2 (Cross-GDD Consistency) + Phase 3 (Game Design Holism) + Phase 4 (Scenario Walkthrough)
> **Verdict**: ❌ FAIL — BLOCKING 9개 해결 전 Beta 출시 불가

---

## 최종 판정 요약

| 심각도 | 건수 |
|--------|------|
| 🔴 BLOCKING | 9 |
| ⚠️ WARNING | 24 |
| ℹ️ INFO | 10 |

---

## BLOCKING Issues

### B-01 — 레버리지 통화 API 오류
**GDD**: `leverage-trading.md` + `currency-system.md`

`leverage-trading.md §3-1, §3-2, §3-4`가 레버리지 자기자본·이자·손실 차감에 `CurrencySystem.cash_deduct()` 사용.
`cash_deduct()`는 `cash_assets` (실생활 자금) 차감 메서드. 투자 계좌인 `sim_deduct()` 사용 필수.
강제 청산(§3-3)은 `sim_deduct` 올바르게 사용하나 수동 매도(§3-4)는 `cash_deduct` — 동일 GDD 내 불일치.

**Fix**: `leverage-trading.md §3-1, §3-2, §3-4`의 모든 `cash_deduct` → `sim_deduct`/`sim_add`로 교체.

---

### B-02 — 마진콜 equity 수식 불일치
**GDD**: `leverage-trading.md` vs `skill-tree.md`

```
leverage-trading.md §3-3:  equity = position_market_value - borrowed
skill-tree.md §F4 (올바름): equity = position_market_value - borrowed - accrued_interest
```

`accrued_interest` 누락 시 마진콜이 실제보다 늦게 발동 → 예상보다 큰 손실 허용.

**Fix**: `leverage-trading.md §3-3` equity 수식에 `- accrued_interest` 추가.

---

### B-03 — PortfolioManager 레버리지 의존성 전무
**GDD**: `leverage-trading.md` + `portfolio-manager.md`

`leverage-trading.md §6`이 `PortfolioManager.add_leverage_holding()`, `remove_leverage_holding()`, `get_all_leverage_positions()` Hard 의존 선언.
`portfolio-manager.md`에 해당 메서드 없음, `HoldingEntry`/`SimPortfolio` 구조에 레버리지 필드 없음,
`account_total_value §F4`에 레버리지 포지션 미포함 → 레버리지 사용자의 시즌 수익률 과소계산.

**Fix**: `portfolio-manager.md`에 LeveragePosition 통합 섹션 추가:
- `add_leverage_holding()`, `remove_leverage_holding()` 메서드 정의
- `account_total_value = sim_cash + reserved_cash + Σholdings + Σ(leverage_equity)` 수식 갱신
- Dependencies에 `LeverageManager` 추가

---

### B-04 — XP 일일수익률 소유자 없음
**GDD**: `xp-system.md` + `portfolio-manager.md`

`xp-system.md §F1`: `player_return_pct = (close_assets - prev_close_assets) / prev_close_assets`
→ daily return 필요.

`portfolio.get_return_rate()`: 시즌 누적 수익률 반환 → Day 2부터 alpha 계산 무의미.

`prev_close_assets` (전일 장마감 총자산) 저장·제공하는 시스템 없음.

**Fix**:
- `portfolio-manager.md`: `prev_day_close_assets` 필드 추가, `on_market_close` 시 스냅샷 저장
- `get_daily_return_rate() -> float` 메서드 추가
- `xp-system.md §F1` 호출 대상을 `portfolio.get_daily_return_rate()`로 수정

---

### B-05 — `grant_season_bonus` 시그니처 불일치
**GDD**: `season-manager.md` vs `xp-system.md`

```
xp-system.md:      grant_season_bonus(rank, is_free_market, return_pct, trade_count)  # 4 params
season-manager.md: grant_season_bonus(final_rank, is_free_market, season_return_pct)  # 3 params
```

`trade_count` 미전달 시 `completion_bonus` (MIN_TRADES_FOR_RANK 조건) 계산 불가.

**Fix**: `season-manager.md §6 Dependencies`의 호출 시그니처에 `trade_count` 추가.

---

### B-06 — "사채업자 엔딩" 미등록
**GDD**: `leverage-trading.md` + `endings-achievements.md`

`leverage-trading.md §3-3`: `emit("on_loan_shark_ending_triggered")` 발생.
`endings-achievements.md`에 해당 엔딩 없음 → 신호 핸들러 없이 소실, 엔딩 미발동.

`design-docs.md` 엔딩 등록 프로토콜: "새 엔딩은 `endings-achievements.md §9 Candidate Pool`에 먼저 등록" 위반.

**Fix**: 두 가지 옵션 중 선택:
- Option A: `endings-achievements.md §9 Candidate Pool`에 사채업자 엔딩 등록 후 game-designer 승인 → §3 이동
- Option B: 사채업자 엔딩 제거, 채무 불이행 시 기존 "한강의 바람" 경로로 통합

---

### B-07 — `max_holdings` 이중 소유
**GDD**: `portfolio-manager.md` + `skill-tree.md`

| GDD | T0 | T1 범위 | T2 범위 |
|-----|----|---------|---------| 
| portfolio-manager.md | 3 | 3~7 | 5~15 |
| skill-tree.md | 3 | 4~7 | 8~15 |

안전 범위 다름. 어느 GDD가 실제 소유자인지 불명확.

**Fix**: `skill-tree.md`를 단일 소유자로 선언. `portfolio-manager.md`의 tuning knob 테이블 제거 → `skill-tree.md §F2` 참조로 교체.

---

### B-08 — 수수료 미반영 주문 검증
**GDD**: `order-engine.md` + `trading-fees.md`

```
주문 검증 (order-engine.md §Validation Step 7):
  current_price × quantity > available_cash → REJECTED

실제 차감 (trading-fees.md §3-2):
  차감액 = price × qty × (1 + buy_tax + commission) = price × qty × 1.00015
```

잔액이 딱 `price × qty`인 플레이어: 검증 통과 → 실제 차감 시 0.015% 부족 → 미정의 동작.

**Fix**: `order-engine.md §Validation Step 7` 수식 수정:
```
current_price × quantity × (1 + fee_rate) > available_cash → REJECTED
```
fee_rate는 `TradingFees.get_buy_fee_rate()`로 조회.

---

### B-09 — S3(루머) + TR2(손절) 지배 전략
**GDD**: `rumor-channel.md` + `stop-loss-take-profit.md` + `skill-tree.md`

RUMOR_BASE_ACCURACY=70% + TR2 -2% 손절 조합 기대수익:
```
EV = (0.70 × 3% pre-reflection) + (0.30 × -2% stop) - 0.23% fee
   = 2.1% - 0.6% - 0.23% = +1.27% per rumor
```
매 루머마다 기계적 실행 시 위험 없는 복리 엔진. "판단이 곧 실력" 핵심 필라 파괴.

**Fix**: RUMOR_BASE_ACCURACY 55%로 하향.
```
EV(55%) = (0.55 × 3%) - (0.45 × 2%) - 0.23% = 1.65% - 0.9% - 0.23% = +0.52%
```
의미 있는 엣지(루머 분석 = 가치 있음)이나 stop-loss hedge가 리스크를 완전히 제거하지 못함.

추가 방어: `rumor-channel.md §5 Edge Cases`에 "S3 + TR2 조합 EV 계산 및 설계 의도 명시" 항목 추가.

---

## WARNING Issues

### Phase 2 Consistency Warnings

**W-01** — `order-engine.md`의 `fee_rate` tuning knob이 `trading-fees.md`로 대체됐으나 미갱신.  
**W-02** — `news-events.md`가 `rumor-channel.md`를 downstream 의존성으로 미등록.  
**W-03** — `price-engine.md`가 `financial-report-system.md`를 미등록.  
**W-04** — `portfolio-manager.md`가 `stop-loss-take-profit.md`를 미등록.  
**W-05** — `game-clock.md` 틱 처리 순서에 TR2(손절), TR4(마진콜) 단계 미기재.  
**W-06** — `short-selling.md` 강제 청산 margin_ratio 예시 계산 없음.  
**W-07** — 라이프스타일 임대 수익 타이밍 vs 시즌 정산 순서 모호 (`on_market_close` vs `SEASON_END` 전후 관계).  
**W-08** — `order-engine.md §Tuning Knobs`의 `fee_rate` stale (trading-fees.md로 대체).  
**W-09** — `portfolio-manager.md §Open Questions`의 거래 내역 보존 여부: `save-load.md`에서 이미 결정됐으나 "미정" 표기 잔존.  
**W-10** — `grant_daily_bonus()` 메서드가 `season-manager.md`에서 참조하나 `xp-system.md` Implementation Checklist에 없음.  
**W-11** — `max_single_impact`↔`pre_market_buffer_pct` 결합이 `order-engine.md`에만 문서화, `news-events.md`에 없음.  
**W-12** — (B-08로 승격됨)  
**W-13** — `portfolio-manager.md §F4` account_total_value에 레버리지 포지션 미포함 (B-03 관련).  
**W-14** — `currency-system.md §Open Questions`의 거장 엔딩 조건이 "미정"으로 표기 — `season-manager.md`에 이미 확정됨.  
**W-15** — `order-engine.md` AC 4건이 S10-12 QA 대기 → `xp-system.md` alpha XP 검증 차단.

### Phase 3 Design Warnings

**W-16** — 4개 진행 축(XP/랭크/현금자산/스킬) 동시 경쟁, 플레이어 우선순위 지침 없음.  
**W-17** — 최고 스킬 상태(TR2+TR3+TR4+S2+S3+P3) 동시 관리 인지 부하 초과.  
**W-18** — 5× 레버리지 이자율(0.10%/일, 시즌 2.0%)이 너무 낮아 확신 있는 모든 포지션에 5× 레버리지가 합리적 선택 → 선택지 아닌 자동 결정.  
**W-19** — "최다 거래상" 어워드가 "판단이 곧 실력" 필라 직접 위반. XP 시스템이 거래량 XP를 의도적으로 제거한 것과 모순.  
**W-20** — `lifestyle-spending.md §4` 스타트업 투자: 30% 실패가 순수 랜덤, "NOT 운 게임" 안티필라 위반. 투자 금액·수익 공식 미정의.  
**W-21** — 전체 경제 수도꼭지(faucet)/배수구(sink) 밸런스 문서 없음.  
**W-22** — AI 경쟁자 고정 분포 → 동일 티어 반복 플레이 시 점점 쉬워짐, 티어 내 동적 조정 없음.  
**W-23** — 재무적 티어 진행 피드백 없음. 플레이어가 승격 페이스인지 알 수 없음 (SDT Competence gap).  
**W-24** — S3의 "인사이더 정보" 판타지가 "읽는 재미/차트 분석" 핵심 미학과 충돌.

---

## INFO Issues (Polish 단계)

**I-01** — `game-clock.md`: 최종 날 WEEK_END → SEASON_END 이중 전환 시퀀스 미기재.  
**I-02** — `RUMOR_BASE_ACCURACY`/`RUMOR_LEAD_TICKS` 소유 GDD 불명확 (rumor-channel vs skill-tree).  
**I-03** — `xp-system.md §F4` 추정치(~1,900 XP) vs AC-9 범위(1,400~1,800) 불일치.  
**I-04** — 일일 라이프스타일 화면 타이밍 미명시 (장중 vs 장후).  
**I-05** — 시즌 여정 의도 미문서화 (티어당 예상 시즌 수: 상위 플레이어 vs 평균 플레이어).  
**I-06** — 첫 시즌 콜드스타트 경험 미설계 (스킬 없음, 상위 입상 어려움).  
**I-07** — AI 경쟁자 UI 표현 프레이밍 미결정 (통계적 시뮬레이션을 플레이어에게 어떻게 보여줄 것인가).  
**I-08** — `portfolio-manager.md §Open Questions` 거래 내역 보존 여부 stale (W-09와 동일 — 닫기 필요).  
**I-09** — `season-manager.md §3`: 프라이즈 복리 압축이 의도한 8~10 시즌 여정과 맞는지 검증 미완.  
**I-10** — `short-selling.md`: 신규 포지션 margin_ratio 시작값 예시 계산 추가 필요.

---

## Phase 4 Scenario Walkthrough — 핵심 실패 케이스

### Scenario A: S3+TR2+TR4 연계 플레이 (BLOCKER)
루머 발생 → 레버리지 진입 → `cash_deduct` 오호출 (B-01) → 손절 설정 → 뉴스 확인/반전 →
청산 시 `PortfolioManager.remove_leverage_holding()` 미정의 (B-03) → 포트폴리오 상태 오염.

### Scenario B: 시즌 마지막 날 정산 체인 (BLOCKER)
`on_market_close` → LifestyleManager 임대 수익 입금 → SEASON_END → 정산 →
`grant_season_bonus(3 params)` 호출 → `trade_count` 미전달 → completion_bonus 0 고정 (B-05).

### Scenario C: 일일 XP 계산 (BLOCKER)
`on_day_end` → `xp-system` → `portfolio.get_return_rate()` (시즌 누적 반환) →
Day 2부터 alpha 계산 오염 → 전체 시즌 XP 분배 왜곡 (B-04).

### Scenario D: 레버리지 강제 청산 → 사채업자 엔딩 (BLOCKER)
가격 급락 → 마진콜: `equity = mv - borrowed` (accrued_interest 누락, B-02) → 늦은 발동 →
청산 후 `net_proceeds < 0` → `emit("on_loan_shark_ending_triggered")` → **핸들러 없음** → 신호 소실, 엔딩 미발동 (B-06).

---

## GDD 수정 대상 목록

| GDD | BLOCKING | WARNING | INFO |
|-----|----------|---------|------|
| leverage-trading.md | B-01, B-02, B-03, B-06 | W-05, W-18 | — |
| portfolio-manager.md | B-03, B-04, B-07 | W-04, W-09, W-13 | I-08 |
| xp-system.md | B-04, B-05 | W-10, W-15 | I-03 |
| season-manager.md | B-05 | W-07, W-19 | I-05, I-09 |
| endings-achievements.md | B-06 | — | — |
| order-engine.md | B-08 | W-01, W-05, W-08, W-11, W-15 | — |
| rumor-channel.md | B-09 | W-02, W-24 | I-02 |
| skill-tree.md | B-07 | — | I-02 |
| game-clock.md | — | W-05 | I-01 |
| news-events.md | — | W-02, W-03, W-11 | — |
| price-engine.md | — | W-03 | — |
| stop-loss-take-profit.md | — | W-04 | — |
| trading-fees.md | — | W-01, W-08 | — |
| lifestyle-spending.md | — | W-07, W-20 | I-04 |
| currency-system.md | — | W-14 | — |
| short-selling.md | — | W-06 | I-10 |
| financial-report-system.md | — | W-03 | — |
| ai-competitor.md | — | W-22 | I-07 |
| **신규: economy-balance.md** | — | W-21 | — |
