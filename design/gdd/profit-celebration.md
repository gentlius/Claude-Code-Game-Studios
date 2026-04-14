# 수익 실현 팡파레 이펙트 (Profit Celebration)

> **Status**: Draft
> **Author**: user + agents
> **Last Updated**: 2026-04-14
> **Target Milestone**: Beta
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

---

## 1. Overview

매도 주문 체결 시 실현 손익이 양수(+)이면 수익 규모에 비례한 시각/청각 이펙트를 재생한다.
동전 비, 숫자 롤업, 화면 플래시, 팡파레 사운드를 조합해 슬롯머신 잭팟 감각을 제공한다.

이펙트는 4등급으로 차등 적용된다. 등급 기준은 **수익률 (%)** — 시드 자본 대비가 아닌
해당 거래의 실현 손익 / 평균 매수 단가 기준. 초보·고티어 플레이어 모두 동일 조건으로
잭팟을 경험할 수 있다.

---

## 2. Player Fantasy

매수한 종목이 올랐다. 매도 버튼을 눌렀다. 체결.
숫자가 빠르게 올라가며 `+₩1,234,567` — 금화가 쏟아진다.
팡파레가 울린다. 아, 이 맛에 한다.

---

## 3. Detailed Design

### 3-1. 트리거 조건

`PortfolioManager.holding_removed(stock_id, quantity, price, realized_pnl)` 시그널을 구독.
`OrderEngine.on_order_filled`에는 `realized_pnl`이 포함되지 않으므로 PortfolioManager 시그널을 사용.

```
holding_removed(stock_id, quantity, price, realized_pnl):
  if realized_pnl > 0:
    cost_basis = price * quantity - realized_pnl   # = avg_buy_price × quantity
    pnl_pct = float(realized_pnl) / float(cost_basis) * 100.0
    ProfitCelebration.play(realized_pnl, pnl_pct)
```

손절 매도(realized_pnl ≤ 0)에는 이펙트 없음.

### 3-2. 등급 테이블

| 등급 | 수익률 기준 | 코드명 |
|------|-----------|--------|
| **소 (SMALL)** | 0% < pnl_pct < 5% | `GRADE_SMALL` |
| **중 (MEDIUM)** | 5% ≤ pnl_pct < 10% | `GRADE_MEDIUM` |
| **대 (LARGE)** | 10% ≤ pnl_pct < 15% | `GRADE_LARGE` |
| **잭팟 (JACKPOT)** | pnl_pct ≥ 15% | `GRADE_JACKPOT` |

> **기준**: 해당 거래의 `realized_pnl / (avg_buy_price × quantity) × 100`.
> 시드 대비 % 아님 — 초보·고티어 동일 조건으로 잭팟 달성 가능.

### 3-3. 등급별 이펙트 상세

#### 비주얼

| 요소 | SMALL | MEDIUM | LARGE | JACKPOT |
|------|-------|--------|-------|---------|
| **동전 파티클** | 10개, 0.8초 | 40개, 1.2초 | 100개, 1.8초 | 200개, 2.5초 |
| **숫자 롤업** | ✅ 0.4초 | ✅ 0.6초 | ✅ 1.0초 | ✅ 1.5초 + 0.5초 홀드 |
| **화면 테두리 플래시** | — | 골드 1회 | 골드 2회 | 골드 3회 + 펄스 |
| **배너** | — | — | — | "수익 실현!" 배너 1.5초 |
| **화면 진동 (Shake)** | — | — | — | 진폭 4px, 0.3초 |
| **컨페티** | — | — | ✅ | ✅ |

**동전 파티클 스펙**
- `GPUParticles2D`, 금화 스프라이트 (`assets/art/vfx/coin_gold.png`)
- 발사 위치: 체결 토스트 위치 (화면 우하단) 기준
- 물리: 중력 `980`, 초기 속도 랜덤 (위/사선 방향), 회전 포함
- 바닥 도달 시 통통 튀다 `modulate.a` 페이드아웃

**숫자 롤업**
- `0` → `+₩{realized_pnl}` 빠르게 카운팅 (easeOut 커브)
- 색상: 수익 빨강 `#EB3833`, 폰트 굵게 Bold, 크기 28px
- 위치: 체결 토스트 바로 위
- 최종값 도달 후 등급별 홀드 시간, 이후 `modulate.a` 페이드아웃

**골드 플래시**
- 반투명 골드 `ColorRect` (`Color(1.0, 0.84, 0.0, 0.15)`)
- 화면 테두리 영역만 (`border_width` 40px — 중앙 게임 영역 비차단)
- SMALL: — / MEDIUM: 0.05초 on → 0.2초 fade / LARGE: 2회 / JACKPOT: 3회 + 0.5초 펄스 반복

### 3-4. 이펙트 재생 흐름

```
ProfitCelebration.play(realized_pnl, pnl_pct):
  1. _cancel_current()  ← 진행 중인 이펙트 강제 종료
  2. grade = _calc_grade(pnl_pct)
  3. _play_particles(grade)
  4. _play_number_rollup(realized_pnl, grade)
  5. _play_flash(grade)
  6. _play_banner(grade)   ← JACKPOT만
  7. _play_sfx(grade)
  8. 이펙트 종료 후 자동 정리 (queue_free 또는 hide)
```

### 3-5. 스킵 / 중단

- 이펙트 진행 중 임의 클릭 또는 키 입력: **즉시 종료** (최종 숫자 표시 후 0.2초 유지 → 사라짐)
- 연속 체결 시: 이전 이펙트 강제 종료 → 새 이펙트 시작
- 장 마감(`MARKET_CLOSED`) 신호 수신 시: 즉시 종료

### 3-6. 배속 연동

| 배속 | 처리 |
|------|------|
| 1x | 이펙트 정상 재생 |
| 2x | 이펙트 시간 70% |
| 4x | 이펙트 시간 50%, LARGE → MEDIUM으로 등급 강제 하향 (JACKPOT 유지) |

> **4x 배속 중 자동 감속 (기존 정책)**: `GameClock.AUTO_SLOW_ON_EVENT`에 의해
> 체결 시 1x로 감속됨. 팡파레 이펙트는 이 감속 이후 정상 재생.
> 배속 연동은 AUTO_SLOW가 비활성화된 경우를 위한 보조 규칙.

### 3-7. 구현 구조

```
src/ui/profit_celebration.gd    ← 신규. ProfitCelebration class (CanvasLayer)
src/ui/trading_screen.gd        ← _on_order_filled() 에서 호출
assets/art/vfx/coin_gold.png    ← 금화 스프라이트 (신규 에셋)
assets/audio/sfx/
  sfx_profit_small.ogg          ← 신규
  sfx_profit_medium.ogg         ← 신규
  sfx_profit_large.ogg          ← 신규
  sfx_profit_jackpot.ogg        ← 신규
```

**CanvasLayer 레이어**: `layer = 5` (SavingOverlay layer=10 아래, 게임 UI 위)

---

## 4. Formulas

### 등급 판정

```
pnl_pct = realized_pnl / (avg_buy_price × quantity) × 100.0

GRADE_SMALL   : 0 < pnl_pct < 5
GRADE_MEDIUM  : 5 ≤ pnl_pct < 10
GRADE_LARGE   : 10 ≤ pnl_pct < 15
GRADE_JACKPOT : pnl_pct ≥ 15
```

- `realized_pnl`: `PortfolioManager.holding_removed` 시그널의 4번째 파라미터 (원)
- `cost_basis`: `price × quantity − realized_pnl` — 평균 매수가 × 수량과 수학적으로 동치
- `price`, `quantity`: 동일 시그널의 2·3번째 파라미터 (체결가, 체결 수량)

### 숫자 롤업 커브

```
value(t) = realized_pnl × ease_out_quad(t / duration)
ease_out_quad(x) = 1 - (1 - x)²
```

- `t`: 경과 시간 (초)
- `duration`: 등급별 롤업 시간 (§3-3 테이블)

---

## 5. Edge Cases

| 케이스 | 처리 |
|--------|------|
| realized_pnl = 1원 (극소) | SMALL 등급 재생 (0 초과이면 항상 트리거) |
| pnl_pct 정확히 경계값 (예: 5.000%) | 상위 등급 적용 (≥ 조건) |
| 연속 체결 (같은 틱에 2건 이상) | 첫 이펙트 즉시 취소 → 마지막 체결 기준으로 재생 |
| 4x 배속 중 JACKPOT | 시간 50% 단축. 등급 유지 (JACKPOT은 강등 없음) |
| 이펙트 중 장 마감 | 즉시 종료. 정산 UI가 우선 |
| 이펙트 중 F3/F2 탭 전환 | 즉시 종료 (다른 화면에서 팡파레 노출 방지) |
| cost_basis = 0 (이론상 불가, 방어) | pnl_pct = 0으로 처리 → 이펙트 미발동 |
| 접근성 설정 "이펙트 OFF" | 숫자 롤업만 재생. 파티클·플래시·사운드 없음 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `PortfolioManager` | → ProfitCelebration | `holding_removed(stock_id, quantity, price, realized_pnl)` 시그널 구독 — `realized_pnl` + `cost_basis` 계산 |
| `TradingScreen` | → ProfitCelebration | `_on_holding_removed()` 에서 `ProfitCelebration.play()` 호출 |
| `AudioManager` | → ProfitCelebration | `AudioManager.play_sfx(sfx_id)` 경유 재생 |
| `GameClock` | → ProfitCelebration | `on_market_state_changed` — MARKET_CLOSED 시 이펙트 즉시 종료 |
| `design/gdd/audio.md` | 싱크 | SFX 4종 (`sfx_profit_*`) 등록 필요 |
| `design/gdd/trading-screen.md` | 싱크 | `_on_order_filled()` 변경 사항 반영 필요 |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 | 범위 | 설명 |
|---------|--------|------|------|
| `GRADE_MEDIUM_THRESHOLD` | 5.0% | 3~8% | SMALL/MEDIUM 경계 수익률 |
| `GRADE_LARGE_THRESHOLD` | 10.0% | 7~13% | MEDIUM/LARGE 경계 수익률 |
| `GRADE_JACKPOT_THRESHOLD` | 15.0% | 12~20% | LARGE/JACKPOT 경계 수익률 |
| `COIN_COUNT_SMALL` | 10 | 5~20 | SMALL 동전 파티클 수 |
| `COIN_COUNT_MEDIUM` | 40 | 20~60 | MEDIUM 동전 파티클 수 |
| `COIN_COUNT_LARGE` | 100 | 60~150 | LARGE 동전 파티클 수 |
| `COIN_COUNT_JACKPOT` | 200 | 150~300 | JACKPOT 동전 파티클 수 |
| `FLASH_BORDER_WIDTH` | 40px | 20~80px | 화면 테두리 골드 플래시 폭 |
| `SHAKE_AMPLITUDE` | 4px | 2~8px | JACKPOT 화면 진동 진폭 |
| `SHAKE_DURATION` | 0.3초 | 0.1~0.6초 | JACKPOT 화면 진동 지속 |
| `SPEED_4X_DURATION_MULT` | 0.5 | 0.3~0.8 | 4x 배속 시 이펙트 시간 배율 |

---

## 8. Acceptance Criteria

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 매도 체결 + realized_pnl > 0이면 이펙트가 재생된다 | 수익 매도 후 이펙트 확인 |
| AC-02 | 매도 체결 + realized_pnl ≤ 0이면 이펙트가 없다 | 손절 매도 후 이펙트 미발생 확인 |
| AC-03 | 매수 체결 시 이펙트가 없다 | 매수 체결 후 이펙트 미발생 확인 |
| AC-04 | pnl_pct 등급 경계값(5%, 10%, 15%)에서 상위 등급이 적용된다 | 정확히 5% 수익 매도 → MEDIUM 확인 |
| AC-05 | 숫자 롤업이 0에서 최종 realized_pnl까지 easeOut으로 올라간다 | 육안 확인 |
| AC-06 | JACKPOT 등급에서 화면 진동과 "수익 실현!" 배너가 표시된다 | pnl_pct ≥ 15% 매도 후 확인 |
| AC-07 | 이펙트 중 클릭 시 즉시 종료된다 | 이펙트 재생 중 클릭 입력 |
| AC-08 | 연속 체결 시 이전 이펙트가 취소되고 새 이펙트가 시작된다 | 같은 틱에 2건 체결 유발 |
| AC-09 | MARKET_CLOSED 시그널 수신 시 이펙트가 즉시 종료된다 | 이펙트 재생 중 장 마감 유발 |
| AC-10 | 4x 배속 중 이펙트 재생 시간이 50%로 단축된다 | 4x 배속에서 수익 매도 후 시간 측정 |
| AC-11 | 접근성 설정 "이펙트 OFF" 시 숫자 롤업만 표시된다 | 설정 변경 후 수익 매도 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

> **⚠️ Beta 스코프 시스템. Alpha 완료 전 구현 시작 금지.**

### 진입점
- `PortfolioManager.holding_removed` 시그널 → `TradingScreen._on_holding_removed(stock_id, qty, price, realized_pnl)` → `realized_pnl > 0` 확인 → `cost_basis` 계산 → `ProfitCelebration.play(realized_pnl, pnl_pct)`

### 호출 경로
- [ ] `profit_celebration.gd`: 신규 작성. CanvasLayer(layer=5). `play(realized_pnl, pnl_pct)` 공개 메서드
- [ ] `profit_celebration.gd`: `_calc_grade(pnl_pct) -> int` 내부 메서드
- [ ] `profit_celebration.gd`: `GPUParticles2D` 설정 — `coin_gold.png` 스프라이트, 등급별 파티클 수
- [ ] `profit_celebration.gd`: 숫자 롤업 `Label` + `Tween` easeOut 구현
- [ ] `profit_celebration.gd`: 골드 테두리 플래시 `ColorRect` 구현
- [ ] `profit_celebration.gd`: JACKPOT 배너 + 화면 shake 구현
- [ ] `profit_celebration.gd`: `_cancel_current()` — 진행 중 이펙트 강제 종료
- [ ] `profit_celebration.gd`: `GameClock.on_market_state_changed` 구독 → MARKET_CLOSED 시 취소
- [ ] `trading_screen.gd`: `PortfolioManager.holding_removed` 구독 → `_on_holding_removed()` 에서 `cost_basis` 계산 + `ProfitCelebration.play()` 호출
- [ ] `audio.gd` (audio.md): SFX 4종 등록 — `sfx_profit_small`, `sfx_profit_medium`, `sfx_profit_large`, `sfx_profit_jackpot`

### 에셋 수급
- [ ] `assets/art/vfx/coin_gold.png` — 금화 스프라이트 확보 (production/asset-plan.md §VFX 참조)
- [ ] `assets/audio/sfx/sfx_profit_small.ogg` — 확보 (DOWNLOAD_GUIDE.md §S-07)
- [ ] `assets/audio/sfx/sfx_profit_medium.ogg` — 확보 (DOWNLOAD_GUIDE.md §S-08)
- [ ] `assets/audio/sfx/sfx_profit_large.ogg` — 확보 (DOWNLOAD_GUIDE.md §S-09)
- [ ] `assets/audio/sfx/sfx_profit_jackpot.ogg` — 확보 (DOWNLOAD_GUIDE.md §S-10)

### 의존하는 외부 메서드 존재 확인
- [x] `PortfolioManager.holding_removed(stock_id, quantity, price, realized_pnl)` 시그널 존재 확인 (portfolio_manager.gd L9)
- [ ] `AudioManager.play_sfx(sfx_id: String)` 존재 확인

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01~04 | `tests/unit/test_profit_celebration.gd` | `test_grade_calculation()` |
| AC-07~09 | `tests/unit/test_profit_celebration.gd` | `test_cancel_behavior()` |
| AC-05~06, AC-10~11 | 수동 플레이테스트 | — |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
