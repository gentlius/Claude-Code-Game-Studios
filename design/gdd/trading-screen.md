# 트레이딩 스크린 (Main HUD)

> **Status**: In Review
> **Author**: user + game-designer
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 읽는 재미 (Read the Market), 짧고 굵게 (Quick & Punchy)

## Overview

트레이딩 스크린은 시드머니의 메인 게임 화면이다. 차트, 종목 리스트, 주문 패널,
뉴스 피드, 포트폴리오 요약을 한 화면에 배치하여 플레이어가 "뉴스 읽기 → 차트
분석 → 매매 판단 → 결과 확인"의 코어 루프를 화면 전환 없이 수행할 수 있게 한다.

시스템 인덱스에서 Design Risk로 분류된 시스템이다 — 정보 과부하 vs 접근성의
균형이 핵심 과제다. 실제 증권 HTS 레이아웃을 참고하되 안티필라 "NOT 현실 완벽
재현"에 따라 게임에 필요한 핵심 정보만 배치한다. 필라 "읽는 재미"에 따라 정보
가독성이 모든 시각적 요소보다 우선한다.

## Player Fantasy

장이 열린다. 내 트레이딩 룸이다. 왼쪽에 종목 리스트가 실시간으로 등락을 보여주고,
중앙의 차트에 캔들이 하나씩 쌓인다. 오른쪽에 주문 패널, 아래에 뉴스가 흐른다.
모든 정보가 한눈에 보인다. 뉴스를 읽고, 차트를 확인하고, 주문을 넣는다 — 이 모든
게 한 화면에서 3초 안에 이루어진다. "나는 시장을 통제하고 있다"는 느낌.

## Detailed Design

### Core Rules

#### 규칙 1. 레이아웃 구조

##### 1-1. 영역 배치 (권장 1920×1080)

```
┌──────────┬──────────────────────────┬──────────┐
│          │      시간/상태 바        │          │
│  종목    │   (게임 시계 + 배속)      │  주문    │
│  리스트  ├──────────────────────────┤  패널    │
│          │                          │          │
│  (15%)   │     차트 렌더러          │  (13%)   │
│          │                          │          │
│          │       (45%)              │          │
│          ├──────────────────────────┤          │
│          │  뉴스 피드  | 포트폴리오  │          │
│          │       (20%)              │          │
└──────────┴──────────────────────────┴──────────┘
```

> **비율 참고**: 다이어그램의 45%/20%는 중앙 영역 **내부의 세로 비율** (차트 영역/하단 패널)이다.
> 중앙 영역 자체의 **가로 비율**은 stretch 0.60 ≈ 68% (F1 참조). 두 비율의 차원이 다르므로 혼동 주의.

| 영역 | 비율(가로) | 내용 | 우선순위 |
|------|----------|------|---------|
| 종목 리스트 | 15% | 46종목 (11섹터) 실시간 가격/등락률 | 높음 |
| 중앙 (상태바+차트+하단 패널) | stretch 0.60 (≈68%) | 상태바(상) + 차트(중) + 뉴스/VI·CB/포트폴리오(하) | 최고 |
| 주문 패널 | 13% (min 160px) | 매수/매도 주문 입력 + 미체결 목록 | 높음 |
| 상태 바 | 전체 상단 (중앙 영역 내부 상단, 독립 행 아님) | 게임 시계, 배속, 시즌/주차, 총 자산 | 중간 |

하단 패널은 뉴스 피드와 포트폴리오 요약을 탭으로 전환.

##### 1-2. 최소 해상도 대응 (1280×720)

- 종목 리스트: 축소형 (종목코드+등락률만)
- 하단 패널: 탭 전환 유지, 높이 축소
- 주문 패널: 최소 폭 유지
- 차트 영역이 가장 먼저 줄어듦 (정보 > 시각)

#### 규칙 2. 상태 바

> **참조**: 이 규칙은 `league-ui.md §3-2`의 HUD 규격을 구현한다.
> 행 2 우측의 리그 HUD 레이아웃과 데이터 소스는 `league-ui.md §3-2` 및 `§4-1`이 정본이다.

```
┌──────────────────────────────────────────────────────────────────────┐
│  시즌 3 | 2주차 화요일 | ■■■□ 틱 152/390 | ▶ 1x [⏸]               │  행 1
│  총 평가금액: ₩1,015,000 (+1.5%) | 예수금: ₩300,000    [브론즈 38위] | 시즌 +12.3% | 주간 +2.1%  │  행 2
└──────────────────────────────────────────────────────────────────────┘
```

행 2는 좌우로 분할된다:
- **좌측**: 자산 정보 (기존 — 총 평가금액, 예수금/미체결예약)
- **우측**: 리그 HUD (신규 — 티어명+순위, 시즌 수익률, 주간 수익률)

리그 HUD 우측 영역 전체가 클릭 가능하며, 클릭 시 F2 탭(리그/시즌 화면)으로 이동한다.
탭 전환 로직은 `MainScreen`이 소유한다 (`league-ui.md §3-1` 씬 구조 참조).

| 요소 | 표시 | 업데이트 주기 |
|------|------|-------------|
| 시즌/주차/요일 | "시즌 3 \| 2주차 화요일" | 일 단위 |
| 틱 진행바 | ■■■□ + "틱 152/390" | 매 틱 |
| 배속/일시정지 | ▶ 1x / ▶▶ 2x / ▶▶▶▶ 4x / ⏸ | 변경 시 |
| 총 평가금액 | ₩1,015,000 (+1.5%) | 매 틱 |
| 예수금 | ₩300,000 (미체결예약: ₩200,000) | 매매/주문 제출·체결·만료 시 |
| 티어명 + 순위 (리그 HUD) | `브론즈 38위` | 매 틱 |
| 시즌 수익률 (리그 HUD) | `시즌 +12.3%` (양수 초록, 음수 빨강) | 매 틱 |
| 주간 수익률 (리그 HUD) | `주간 +2.1%` (양수 초록, 음수 빨강) | 매 틱 |

총 평가금액의 수익률 색상: +빨강, -파랑, 0 회색.
리그 HUD 수익률 색상: +초록, -빨강 (`league-ui.md §3-2` 명세 기준).

**미체결예약 표시 규칙**: `reserved_cash`는 주문 엔진의 `get_total_reserved_cash()`로
조회한다. 미체결 지정가 매수 주문이 없을 때(= 0) 예약 표시를 숨긴다. 미체결예약이
있을 때만 "(미체결예약: ₩200,000)" 형태로 예수금 옆에 표시한다. 총 평가금액 계산에는
`sim_cash + reserved_cash + 보유 주식 평가액`이 반영된다.

**탭바 소유권**: F1(거래) / F2(리그/시즌) / F3(성장) / F4(나가기) 탭바는 `MainScreen`이 소유한다.
`TradingScreen`은 F1 탭의 자식 씬으로 인스턴스된다. 탭 전환 시 일시정지 정책은
`league-ui.md §3-1`이 정본이다.

**F4 나가기**: F4는 씬 전환 버튼이며 탭이 아니다. 클릭 시 StartScreen으로 전환한다.
`SavingOverlay` 표시 중이면 비활성. 상세 규격: `start-screen.md §3-7`.

#### 규칙 3. 종목 리스트

```
┌─────────────┐
│ 종목 리스트   │
├─────────────┤
│▶ STC  65,000│  ← 선택된 종목 (강조)
│  +2.3% ▲   │
├─────────────┤
│  GRC 320,000│
│  -1.1% ▼   │
├─────────────┤
│  MDG 185,000│
│  +8.7% ▲▲  │
│  ★          │  ← 보유 종목 마커
├─────────────┤
│  ...        │
└─────────────┘
```

| 표시 요소 | 설명 |
|----------|------|
| 종목코드 (Ticker) | 3-4자 약어 |
| 현재가 | 실시간 갱신 |
| 등락률 (%) | 전일 종가 대비. 빨강/파랑 |
| 방향 화살표 | ▲(상승) ▼(하락) |
| 보유 마커 (★) | 현재 보유 종목 표시 |
| 선택 강조 (▶) | 차트/주문 패널에 연동된 종목 |

종목 클릭 → 차트 + 주문 패널이 해당 종목으로 전환.

#### 규칙 4. 주문 패널

> **호가창 통합**: 주문 패널 상단에 10단 호가창(매도5·매수5)이 포함된다.
> 호가 클릭 시 지정가 가격 필드에 자동 입력. 상세 규칙은 `design/gdd/order-book.md` 참조.

```
┌──────────────┐
│  스타칩 (STC)  │
│  현재가 65,000 │
├──────────────┤
│ [호가창 10단]  │  ← order-book.md
├──────────────┤
│ [매수] [매도]  │  ← 탭 전환
├──────────────┤
│ 주문 유형:     │
│ (●) 시장가     │
│ ( ) 지정가  🔒 │  ← TR1 미해금 시 자물쇠
├──────────────┤
│ 수량: [___] 주 │
│ [최대]        │
├──────────────┤
│ 예상 금액:     │
│ ₩650,000     │
├──────────────┤
│ [주문 실행]    │
├──────────────┤
│ ─ 미체결 주문 ─│
│ 매수 GRC      │
│ 310,000×5주   │
│ [취소]        │
└──────────────┘
```

- 종목 선택에 연동
- 수량 입력 + "최대" 버튼 (최대 매수/매도 수량 자동 계산)
- 주문 실행 버튼: 검증 실패 시 에러 메시지 인라인 표시
- 하단에 미체결 지정가 주문 목록 + 개별 취소 버튼

##### 4-1. PRE_MARKET 주문 패널 표시

PRE_MARKET 상태에서 매수 주문 시, 예약금 버퍼 정보를 표시한다:

```
│ 예약 금액:          │
│ ₩1,121,250         │
│  (전일종가 ×1.15)   │
│  장 시작 후 차액 환불│
```

- **예약 금액** = `ceil(전일종가 × 1.15) × 수량` (Order Engine `pre_market_buffer_pct` 참조)
- "장 시작 후 차액 환불" 문구로 예약금 > 실제 체결가임을 사전 고지
- MARKET_OPEN/PAUSED 상태에서는 기존 "예상 금액" 표시 유지

#### 규칙 5. 시간 컨트롤

| 컨트롤 | 키 | 동작 | 가용 상태 |
|--------|-----|------|---------|
| 일시정지 | Space | 시간 정지. UI 조작/주문 가능 | MARKET_OPEN만 |
| 1x | Shift+1 | 기본 속도 | MARKET_OPEN |
| 2x | Shift+2 | 2배속 | MARKET_OPEN |
| 4x | Shift+3 | 4배속 | MARKET_OPEN |
| 다음 날 | Enter | PRE_MARKET 확인 → 장 시작 | PRE_MARKET만 |

> **배속 버튼 활성 상태**: 현재 선택된 배속 버튼은 accent 스타일(어두운 배경 + 흰 텍스트)로 표시. 다른 배속 버튼은 기본 스타일.

##### 5-1. 일시정지 시 동작

- 차트 고정 (현재 틱까지만 표시)
- 주문 입력 가능 (재개 후 첫 틱에 처리)
- 뉴스 피드 스크롤 가능
- 포트폴리오 확인 가능
- 화면 중앙에 "⏸ 일시정지" 오버레이 (반투명)

#### 규칙 6. 상태별 UI 변화

Game Clock의 시장 상태에 따라 트레이딩 스크린의 UI 상태가 결정된다.

| Game Clock 상태 | Trading Screen UI 상태 | UI 변화 |
|----------------|----------------------|--------|
| `PRE_MARKET` | **PRE_MARKET** | 차트: 전일 차트 표시. 뉴스: 프리마켓 묶음. 주문: 예약 가능. **상태 바 중앙**에 "장 시작 `Enter`" 버튼 표시 (정본 위치. 뉴스 피드의 프리마켓 묶음 하단에도 동일 버튼 표시하되, 동일한 `Enter` 키에 바인딩) |
| `MARKET_OPEN` | **MARKET_OPEN** | 풀 트레이딩 모드. 모든 요소 실시간 갱신. 배속/일시정지 가능 |
| `PAUSED` | **PAUSED** | MARKET_OPEN + 반투명 오버레이. 시간 정지. UI 조작 가능 |
| `MARKET_CLOSED` | **SETTLEMENT** | 차트 고정. 주문 비활성화. 순차 정산 큐 시작 |
| `DAY_TRANSITION` | **SETTLEMENT** | 일일 정산 → 다음 날 전환 중. 차트/주문 비활성 |
| `WEEK_END` | **SETTLEMENT** | 주간 리포트를 큐에 추가 |
| `SEASON_END` | **SEASON_RESULT** | 시즌 결과 화면으로 직접 전환 (정산 큐 생략) |

> **참고**: 좌측은 Game Clock이 발행하는 시장 상태, 우측은 Trading Screen의 자체 UI 상태.
> `SETTLEMENT`은 `MARKET_CLOSED`/`WEEK_END`를 통합하는 UI 레벨 상태다. `SEASON_END`는 `SEASON_RESULT`로 직접 전환된다.
>
> **순차 정산 플로우**: 장 마감 시 정산 큐(`_settlement_queue`)에 리포트를 순서대로 적재한다.
> - 일반 평일: `["daily"]` → 일일 정산 확인 → 다음 날
> - 금요일: `["daily", "weekly"]` → 일일 정산 확인 → 주간 리포트 확인 → 다음 주
> - 시즌 마지막 금요일: `["daily", "weekly", "season"]` → 일일 → 주간 → 시즌 결과 순서
>
> 각 리포트 사이 "다음 → Enter" 버튼으로 확인 후 다음 리포트 표시. 마지막 리포트에서 "확인 Enter"로 GameClock.confirm_transition() 호출.

#### 규칙 7. 키보드 단축키

| 키 | 동작 |
|----|------|
| B | 매수 탭 전환 |
| S | 매도 탭 전환 |
| Enter | 상태 의존: PRE_MARKET → "장 시작", MARKET_OPEN/PAUSED → "주문 실행" (주문 패널에 수량 입력이 있을 때만. 미입력 시 무동작) |
| Space | 일시정지/재개 |
| Shift+1/2/3 | 배속 변경 (1x/2x/4x) |
| Tab | 하단 패널 탭 전환 (뉴스↔VI/CB↔포트폴리오) |
| Esc | 주문 취소 / 팝업 닫기 |

**단축키 표시 원칙**: 모든 UI 버튼에 대응하는 단축키를 함께 표시한다.
버튼 텍스트 옆 또는 우측 하단에 연회색으로 키를 보여준다.

| 버튼 | 표시 예시 |
|------|---------|
| 매수 탭 | "매수 `B`" |
| 매도 탭 | "매도 `S`" |
| 주문 실행 | "주문 실행 `Enter`" |
| 일시정지 | "⏸ `Space`" |
| 배속 | "▶ 1x `⇧1`  ▶▶ 2x `⇧2`  ▶▶▶▶ 4x `⇧3`" |
| 장 시작 | "장 시작 `Enter`" |
| 취소 | "취소 `Esc`" |

#### 규칙 8. 체결 피드백

주문 체결 시 즉각적인 시각/청각 피드백:

| 이벤트 | 시각 피드백 | 청각 피드백 |
|--------|-----------|-----------|
| 매수 체결 | 주문 패널 초록 플래시 + "체결!" 텍스트 | 체결 효과음 (차칭) |
| 매도 체결 | 주문 패널 주황 플래시 + "체결!" | 체결 효과음 |
| 주문 거부 | 주문 패널 빨강 셰이크 + 에러 메시지 | 거부 효과음 (버저) |
| PRE_MARKET 버퍼 초과 거절 | 주문 패널 빨강 셰이크 + "개장 가격이 예약 범위를 초과했습니다 (+15% 이상)\n예약금이 전액 환불되었습니다" | 거부 효과음 |
| 지정가 체결 | 화면 상단 토스트 + 해당 종목 깜빡임 | 알림 효과음 |

#### 규칙 9. 하단 탭 안읽음 뱃지

하단 패널의 3개 탭(뉴스, VI/CB, 포트폴리오)은 비활성 탭에 미확인 이벤트가
발생하면 안읽음 표시를 제공한다.

| 탭 | 트리거 | 뱃지 표시 | 클리어 조건 |
|----|--------|---------|-----------|
| **뉴스** | `NewsEventSystem.on_news_display` 수신 (시스템 이벤트 제외) | `"뉴스 (N)"` — N은 미읽은 뉴스 수 | 뉴스 탭 선택 시 카운트 리셋, 텍스트 `"뉴스"`로 복원 |
| **VI/CB** | `NewsEventSystem.on_news_display` 수신 (`is_system_event = true`인 항목) | `"VI/CB ●"` — 읽지 않은 알림 존재 표시 | VI/CB 탭 선택 시 `●` 제거, 텍스트 `"VI/CB"`로 복원 |
| **포트폴리오** | `on_order_filled` 수신 (주문 체결) | `"포트폴리오 (N)"` — N은 미확인 체결 수 | 포트폴리오 탭 선택 시 카운트 리셋, 텍스트 `"포트폴리오"`로 복원 |

- 현재 활성 탭의 이벤트는 뱃지를 증가시키지 않음 (이미 보고 있으므로)
- 뱃지 스타일: 탭 텍스트에 직접 카운트 표시 (별도 뱃지 UI 없음)

#### 규칙 10. 컴포넌트 아키텍처 (TD-04)

> **배경**: `trading_screen.gd`가 2020줄·8개 책임을 단독 보유하면서 매 틱 `get_children()`
> 호출과 `StyleBoxFlat.new()` 반복 생성으로 UI 버벅임이 발생했다 (Sprint 3 이후 확인).
> Sprint 4에서 5개 서브컴포넌트로 분리한다.

##### 10-1. 컴포넌트 책임 분리

```
TradingScreen  (조율자 — UIState 머신, 시그널 라우팅, 서브컴포넌트 구성)
├── StockListPanel      src/ui/stock_list_panel.gd
├── StatusBar           src/ui/status_bar.gd
├── OrderPanel          src/ui/order_panel.gd
├── SettlementReporter  src/ui/settlement_reporter.gd
└── ToastManager        src/ui/toast_manager.gd
```

| 컴포넌트 | 책임 | 소유 노드 |
|---------|------|---------|
| **StockListPanel** | 46종목 행 표시·갱신, 종목 선택 하이라이트 | `_stock_list_container`, `_stock_row_nodes` |
| **StatusBar** | 상태바 행 1/2, 진행바, 배속 버튼 | `_lbl_season_info`, `_progress_bar`, `_btn_speed_*` |
| **OrderPanel** | 매수/매도 폼, 수량·단가 입력, 주문 제출, 미체결 목록 | `_spin_quantity`, `_btn_submit_order`, `_pending_orders_container` |
| **SettlementReporter** | 일일·주간·시즌 정산 팝업 3종, 순차 큐 관리 | `_settlement_panel`, `_settlement_queue` |
| **ToastManager** | 뉴스 토스트 스택, reduced_motion 지원 (TD-07 잔여) | `_toast_container` |

##### 10-2. 서브컴포넌트 시그널 인터페이스

각 컴포넌트가 소유·구독하는 시그널은 아래와 같다.
TradingScreen은 `_connect_signals()`에서 서브컴포넌트 시그널을 수신하여 상위 라우팅한다.

| 컴포넌트 | 구독 (autoload 시그널) | 발신 시그널 | TradingScreen 처리 |
|---------|----------------------|-----------|-------------------|
| **StockListPanel** | `PriceEngine.on_price_updated`, `OrderEngine.on_order_filled` | `stock_selected(stock_id)` | `OrderPanel.set_stock()` + `ChartRenderer.load_stock()` |
| **StatusBar** | `GameClock.on_tick`, `CurrencySystem.sim_cash_changed`, `PortfolioManager.valuation_updated` | `league_hud_clicked()`, `pause_toggled()`, `speed_changed(multiplier)` | 각각 `league_tab_requested`, `pause_toggle_requested`, `speed_change_requested` 상위 emit |
| **OrderPanel** | `OrderEngine.on_order_filled/rejected/cancelled/expired`, `CurrencySystem.sim_cash_changed` | — (OrderEngine 직접 호출) | — |
| **SettlementReporter** | `GameClock.on_market_close`, `on_week_end`, `on_season_end` | `settlement_confirmed()` | `GameClock.confirm_transition()` 호출 |
| **ToastManager** | `NewsEventSystem.on_news_display` | — | — |

##### 10-3. TradingScreen 잔여 책임 (분리 후)

분리 후 `TradingScreen`이 단독 소유하는 책임:

- **UIState 머신**: `GameClock.on_market_state_changed` → `_set_ui_state()` → 각 서브컴포넌트에 상태 전파
- **서브컴포넌트 구성**: `_build_ui()`에서 5개 컴포넌트 인스턴스화 및 계층 배치
- **키보드 단축키**: `_unhandled_input()` — B/S/Space/Enter/Tab/Esc/Shift+1~3
- **XP·레벨업 흐름**: `XpBar`, `LevelUpBanner`, `SkillTreeOverlay` 소유 및 시그널 수신
- **신호 버블업**: `league_tab_requested`, `pause_toggle_requested`, `speed_change_requested` (ADR-006·TD-03)

##### 10-4. StockListPanel 성능 설계

매 틱 UI 버벅임의 직접 원인을 구조적으로 제거한다.

| 문제 | 해결책 |
|------|--------|
| `get_children()` 매 틱 호출 | `_row_nodes: Array[HBoxContainer]` — `_ready()`에서 1회 빌드, 이후 인덱스 접근 |
| 가격 미변동 행도 전체 갱신 | `_last_prices: Dictionary` — 이전 가격과 동일하면 해당 행 skip |
| `StyleBoxFlat.new()` 매 틱 생성 | `_sel_style: StyleBoxFlat` + `_desel_style: StyleBoxFlat` — `_ready()`에서 1회 생성·캐시 |
| 보유 여부 매 틱 autoload 조회 | `_held_stocks: Dictionary` — `on_order_filled` 시에만 갱신 |

##### 10-5. 코딩 제약

- 각 서브컴포넌트 파일: **40줄 메서드 제한** 준수
- 각 서브컴포넌트: `class_name` 선언 (전역 접근 불필요 — TradingScreen만 인스턴스화)
- 서브컴포넌트 ↔ autoload 직접 접근 허용 (읽기 전용 query)
- 서브컴포넌트 → 다른 서브컴포넌트 직접 참조 **금지** — TradingScreen 경유 의무

### States and Transitions

| State | Description | Transition |
|-------|-------------|------------|
| **LOADING** | 시즌/종목 데이터 로드 중. 최초 진입 또는 시즌 전환 시 | → PRE_MARKET (로드 완료) |
| **PRE_MARKET** | 프리마켓 모드. 전일 리뷰 + 프리마켓 뉴스. Game Clock `PRE_MARKET` 대응 | → MARKET_OPEN (장 시작 클릭) |
| **MARKET_OPEN** | 실시간 트레이딩 모드. Game Clock `MARKET_OPEN` 대응 | → PAUSED (일시정지) / SETTLEMENT (장 마감) |
| **PAUSED** | 일시정지 오버레이. Game Clock `PAUSED` 대응 | → MARKET_OPEN (재개) |
| **SETTLEMENT** | 일일 정산 리포트 표시. Game Clock `MARKET_CLOSED`/`DAY_TRANSITION`/`WEEK_END` 통합 | → PRE_MARKET (다음 거래일) / SEASON_RESULT (시즌 종료) |
| **SEASON_RESULT** | 시즌 결과 화면. Game Clock `SEASON_END` 대응 | → LOADING (다음 시즌) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **차트 렌더러** | 트레이딩 스크린이 호스팅 | 차트 영역 배치. 종목 선택 이벤트 전달 |
| **주문 처리 엔진** | 트레이딩 스크린이 의존 | `submit_order()` — 주문 제출. `cancel_order()` — 취소. `get_pending_orders()` — 미체결 목록. `on_order_filled` — 체결 피드백 |
| **포트폴리오 관리** | 트레이딩 스크린이 참조 | `get_portfolio_summary()` — 사이드바/하단 표시. `get_all_holdings()` — 보유 종목 마커 |
| **뉴스 피드 UI** | 트레이딩 스크린이 호스팅 | 뉴스 피드 영역 배치. 종목 클릭을 차트 전환에 연결 |
| **가격 엔진** | 트레이딩 스크린이 참조 | `get_current_price(stock_id)` — 종목 리스트 + 주문 패널 현재가. `get_daily_limits(stock_id)` — 지정가 SpinBox 상/하한가 클램프 |
| **뉴스/이벤트 시스템** | 트레이딩 스크린이 구독 | `on_news_display` — `is_system_event = true`인 항목을 VI/CB 알림 탭에 라우팅. VI/CB 알림의 **단일 소스** (가격 엔진 시그널 직접 구독 아님) |
| **재화 시스템** | 트레이딩 스크린이 참조 | `get_sim_cash()` — 상태 바 현금 표시 |
| **게임 시계** | 트레이딩 스크린이 의존 | 틱/상태 시그널로 UI 갱신. 배속/일시정지 제어 |
| **스킬 트리** | 트레이딩 스크린이 참조 | 주문 유형 해금 여부 (자물쇠 표시) |
| **종목 DB** | 트레이딩 스크린이 참조 | 종목명, 섹터 등 표시 정보 |

## Formulas

### F1. 레이아웃 비율 (가로, Godot stretch_ratio 기반)

```
stock_list.stretch_ratio  = 0.15  // 종목 리스트 (min 180px)
center_area.stretch_ratio = 0.60  // 상태바 + 차트 + 하단 탭(뉴스/VI·CB/포트폴리오)
order_panel.stretch_ratio = 0.13  // 주문 패널 (min 160px)
// 합계 0.88 — Godot stretch_ratio는 합이 1.0일 필요 없음. 비율 기준으로 분배됨
// Godot이 비례 배분: 0.15:0.60:0.13 → 약 17%:68%:15%
```

> **참고**: stretch_ratio는 Godot의 비례 배분 시스템. 합이 1.0일 필요 없으며,
> 각 영역이 비율에 따라 가용 공간을 분배받는다. center_area는 차트뿐 아니라
> 상태 바와 하단 탭 패널을 포함하므로 가장 큰 비율을 가진다.

최소 해상도(1280px) 미만 시 종목 리스트를 접이식으로 전환.

### F2. 종목 등락률

```
change_pct = (current_price - prev_close) / prev_close × 100
```

시즌 첫 거래일: `prev_close = base_price`.

**예시**: 스타칩 base_price=65,000, 시즌 첫날 현재가=66,300
→ `change_pct = (66,300 - 65,000) / 65,000 × 100 = +2.0%`

### F3. 최대 매수 수량 (주문 패널)

```
max_buyable = floor(available_cash / reference_price)
available_cash = get_sim_cash()  // 이미 예약 차감된 금액
reference_price = current_price (시장가) or limit_price (지정가)
```

### F4. 예상 매매 금액

```
estimated_amount = quantity × reference_price
```

실시간으로 수량 입력 시 갱신.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 최소 해상도(1280×720) 미만 | 종목 리스트 접이식 전환. 차트 축소. 핵심 정보 유지 | 최소 사양 대응 |
| BREAKOUT 발생 시 | 차트 자동 스케일 + 해당 종목 리스트 깜빡임 | 중요 이벤트 시각적 알림 |
| 동시 다발 이벤트 (MEGA) | MEGA 뉴스 FLASH + 종목 리스트 전체 등락률 갱신 | 정보 우선순위 |
| 일시정지(PAUSED) 중 주문 입력 + 재개 | 주문이 접수되어 **재개 후 첫 틱**에 처리됨. UI에 "재개 시 체결" 표시. PRE_MARKET 제출 주문과 별도 처리 (상세: Order Engine 규칙 4-3b) | 분석 시간 제공 |
| PRE_MARKET 중 주문 입력 | 주문이 접수되어 **장 시작 첫 틱(틱 1)**에 처리됨. UI에 "장 시작 시 체결" 표시. 매수 시 예약금(`전일종가×1.15×수량`) 선차감 + "장 시작 후 차액 환불" 안내. PAUSED 제출 주문과 별도 처리 (상세: Order Engine 규칙 4-3a) | 프리마켓 선제 주문 |
| 주문 실행 중 가격 변동 | 시장가: 체결 시점 가격 적용. UI 예상 금액과 차이 가능 → 체결 알림에 실제 금액 표시 | "틱이 진실" 원칙 |
| "최대" 버튼 클릭 후 가격 변동 | 계산된 max_buyable 수량으로 주문 제출 시 잔액 부족 가능 → 주문 엔진이 REJECTED 처리 + `reject_reason` 문자열을 인라인 에러로 표시 (사유 문자열은 Order Engine 규칙 3이 정본) | 체결 시점 가격 기준 |
| 종목 리스트에서 빠른 종목 전환 | 차트 로드 100ms 이내. 전환 중 이전 차트 표시 유지 | 빠른 전환 UX |
| 포트폴리오 빈 상태 | 하단 포트폴리오 탭에 "보유 종목 없음. 첫 매수를 시작하세요!" 표시 | 빈 화면 방지 |
| 시즌 결과 화면에서 "다음 시즌" 클릭 | LOADING → 새 시즌 데이터 로드 → PRE_MARKET | 시즌 전환 |
| LOADING 상태에서 데이터 로드 실패 | 에러 화면 표시 + "재시도" 버튼. 트레이딩 스크린 진입 불가. 3회 실패 시 메인 메뉴로 복귀 | 깨진 상태 진입 방지 |
| WEEK_END + SEASON_END 동시 발생 (시즌 마지막 금요일) | **SEASON_RESULT 우선**. 주간+시즌 합산 리포트를 단일 SEASON_RESULT 화면에 표시 (별도 SETTLEMENT 생략). Game Clock 엣지케이스와 일치 | 중복 리포트 방지 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 차트 렌더러 | 트레이딩 스크린이 호스팅 | 중앙 영역 배치. **Hard** |
| 주문 처리 엔진 | 트레이딩 스크린이 의존 | 주문 제출/취소/목록. **Hard** |
| 포트폴리오 관리 | 트레이딩 스크린이 참조 | 보유 종목 표시. **Hard** |
| 뉴스 피드 UI | 트레이딩 스크린이 호스팅 | 하단 영역 배치. **Hard** |
| 가격 엔진 | 트레이딩 스크린이 참조 | 종목 리스트 현재가. **Hard** |
| 재화 시스템 | 트레이딩 스크린이 참조 | 상태 바 잔액 표시. **Soft** |
| 게임 시계 | 트레이딩 스크린이 의존 | 상태 전환, 시간 표시, 배속 제어. **Hard** |
| 스킬 트리 | 트레이딩 스크린이 참조 | 주문 유형 해금 표시. **Soft** |
| 종목 DB | 트레이딩 스크린이 참조 | 종목 정보 표시. **Hard** |
| `SeasonManager` | 트레이딩 스크린이 참조 | 상태 바 리그 HUD 데이터 (`get_tier_name()`, `get_tier_rank()`, `get_season_return_pct()`, `get_weekly_return_pct()`). **Hard** |
| `MainScreen` | 트레이딩 스크린의 부모 | F1/F2/F3 탭바 및 탭 전환 로직 소유. `TradingScreen`은 F1 탭 자식 씬. `league-ui.md §3-1` 씬 구조 참조. **Hard** |
| `league-ui.md` | 역참조 | 상태 바 행 2 리그 HUD 레이아웃 및 데이터 소스의 정본 (§3-2, §4-1). **F3 탭 전환 시 자동 일시정지 정책은 §3-1이 정본** — TradingScreen의 탭 전환 핸들러는 이 정책을 따름. |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `stock_list_width_pct` | 15% | 10~20% | 종목 정보 더 상세 | 차트 영역 확대 |
| `center_stretch_ratio` | 0.60 | 0.45~0.70 | 차트/탭 영역 확대 | 좌우 패널 여유 |
| `order_panel_width_pct` | 13% (min 160px) | 10~20% | 주문 패널 여유 | 차트 영역 확대 |
| `min_resolution_width` | 1280 | 1024~1440 | 넓은 화면만 지원 | 작은 화면 지원 |
| `fill_feedback_duration` | 1초 | 0.5~2초 | 눈에 띄는 피드백 | 빠른 복귀 |
| `price_update_interval` | 1틱 | 1~3틱 | — | 성능 개선 |
| `min_chart_height_px` | 200 | 150~300 | 캔들 패턴 가독성 향상 | 하단 패널 공간 확보 (캔들 가독성 저하 위험) |

## Acceptance Criteria

- [ ] 종목 리스트 클릭 시 차트 + 주문 패널이 해당 종목으로 전환됨
- [ ] 상태 바에 시즌/주차/요일/틱/배속/총자산이 정확히 표시됨
- [ ] 주문 패널에서 시장가/지정가 주문이 정상 제출됨
- [ ] 미해금 주문 유형에 자물쇠 아이콘이 표시됨
- [ ] 체결 시 시각/청각 피드백이 즉각 제공됨
- [ ] 주문 거부 시 에러 메시지가 인라인 표시됨
- [ ] 일시정지 시 오버레이 표시 + UI 조작 가능 + 시간 정지
- [ ] PRE_MARKET에서 프리마켓 뉴스 + "장 시작" 버튼 표시
- [ ] MARKET_CLOSED에서 주문 비활성화 + 정산 리포트 표시
- [ ] 하단 패널에서 뉴스↔VI/CB↔포트폴리오 탭 전환 정상 작동
- [ ] 비활성 탭에 미확인 이벤트 발생 시 안읽음 뱃지(카운트 또는 ●)가 표시됨
- [ ] 탭 선택 시 해당 탭의 안읽음 뱃지가 클리어됨
- [ ] 키보드 단축키가 모두 정상 작동
- [ ] 최소 해상도 1280×720에서 레이아웃 깨짐 없음
- [ ] 성능: 종목 전환 100ms 이내, 틱 처리 및 UI 갱신 비용 16ms 이내 (60fps 프레임 버짓 이내)
- [ ] StockListPanel: 가격 미변동 행은 매 틱 갱신 skip (dirty flag 동작 확인)
- [ ] 각 서브컴포넌트 파일의 메서드 중 40줄 초과 없음

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 일일 정산 리포트 상세 내용 (수익률 차트, 거래 요약 등) | ux-designer | V-Slice | MVP는 총 자산/수익률/순위만 |
| 시즌 결과 화면 상세 (순위 변동 그래프, 상금 연출 등) | art-director | V-Slice | MVP는 텍스트 기반 |
| 모바일/태블릿 대응 레이아웃 | ux-designer | 확장 시점 | MVP는 PC 전용 |
| 다크 모드/라이트 모드 | art-director | Alpha | 미정 |
| 접근성 (스크린 리더, 고대비 모드) | accessibility-specialist | Alpha | 미정 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 메인 HUD 진입 | `StartScreen` → `SaveSystem.load_slot(id)` 또는 새 게임 → `MainScreen.tscn` → `TradingScreen.tscn` (F1 탭) |
| 시즌 시작 버튼 | `TradingScreen._on_btn_market_open_pressed()` → `SeasonManager.start_season()` (is_season_active 분기) |
| 주문 제출 | `OrderPanel._submit_order()` → `OrderEngine.submit_market_order()` / `submit_limit_order()` |
| 탭 전환 → F2 이동 | `StatusBar.league_hud_clicked` → `TradingScreen.league_tab_requested` → `MainScreen._switch_tab(TAB_F2)` (ADR-006) |
| 일시정지/속도 | `StatusBar.pause_toggled` / `speed_changed` → `TradingScreen.pause_toggle_requested` / `speed_change_requested` → `MainScreen` → `GameClock` (TD-03) |
| 정산 확인 | `SettlementReporter.settlement_confirmed` → `TradingScreen` → `GameClock.confirm_transition()` |
| F4 나가기 | `MainScreen._input(F4)` 또는 탭바 `[나가기]` 버튼 클릭 → `SavingOverlay` 미표시 시 → `StartScreen` 전환 |

### 호출 경로

- [x] `SeasonManager.is_season_active()` — PRE_MARKET 버튼 분기
- [x] `SeasonManager.get_season_return_pct()` — StatusBar HUD
- [x] `SeasonManager.get_weekly_return_pct()` — StatusBar HUD
- [x] `SeasonManager.get_tier_name()` — StatusBar HUD
- [x] `GameClock.confirm_market_open()` — 장 시작 버튼
- [x] `GameClock.confirm_transition()` — SettlementReporter 경유
- [x] `OrderEngine.submit_market_order()` / `submit_limit_order()` — OrderPanel 직접 호출
- [x] `TradingScreen.league_tab_requested` 시그널 존재 (S3-06)
- [x] `TradingScreen.pause_toggle_requested` 시그널 존재 (S3-13)
- [x] `TradingScreen.speed_change_requested` 시그널 존재 (S3-13)
- [ ] `MainScreen` 탭바에 `[나가기]` 버튼 추가 (F1/F2/F3 우측)
- [ ] `MainScreen._input(event)`: F4 감지 → `SavingOverlay.visible` 체크 → StartScreen 전환
- [ ] `SavingOverlay`: `SaveSystem.save_started` / `save_completed` 구독, `CanvasLayer layer=10`
- [ ] `StockListPanel._row_nodes` — `_ready()`에서 1회 빌드, `get_children()` 런타임 호출 없음
- [ ] `StockListPanel._last_prices` — dirty flag skip 동작
- [ ] `StockListPanel._sel_style` / `_desel_style` — `_ready()` 1회 캐시, 런타임 `StyleBoxFlat.new()` 없음

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 전체 AC (시각/통합 검증) | E2E 플레이 검증 (S4-02) | — | ⬜ |
| API 계약 (league_tab_requested 등) | `tests/unit/test_api_contracts.gd` | `test_trading_screen_signals()` | ⬜ S4 추가 예정 |
| 성능 AC (16ms, dirty flag) | Godot 프로파일러 (S4-04) | `docs/profiling/v-slice-baseline.md` | ⬜ |

### TD-04 분리 진행 상황

| 서브컴포넌트 | 파일 | 상태 |
|------------|------|------|
| StockListPanel | `src/ui/stock_list_panel.gd` | ⬜ |
| StatusBar | `src/ui/status_bar.gd` | ⬜ |
| OrderPanel | `src/ui/order_panel.gd` | ⬜ |
| SettlementReporter | `src/ui/settlement_reporter.gd` | ⬜ |
| ToastManager | `src/ui/toast_manager.gd` | ⬜ |
| TradingScreen 리팩터 | `src/ui/trading_screen.gd` | ⬜ |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 Eric (2026-04-07)
