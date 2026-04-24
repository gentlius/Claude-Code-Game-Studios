# 코드 리뷰 보고서 — 2026-04-24

> 상태: 완료 (2026-04-24)

## High (H)

### H-01 — `src/gameplay/price_engine.gd` L467-470: 이벤트 풀 시장 ID 하드코딩
`_build_kernel_cfg()`에서 C++ 커널에 전달하는 이벤트 풀을 `"KR"` 고정으로 필터링한다.
DLC로 다른 시장이 추가되면 해당 시장 이벤트가 커널에 전혀 전달되지 않는다.

```gdscript
cfg["event_pool"] = all_tpl.filter(
    func(t: Dictionary) -> bool:
        return t.get("market_id", "KR").to_upper() == "KR"
)
```

수정 방향: `MarketProfile.get_active_market_id()` 또는 `NewsEventSystem`이 관리하는 활성 시장 ID로 교체.

---

### H-02 — `src/gameplay/ai_competitor.gd` L128-130: 컴파일-타임 상수 vs 런타임 config 비교 assert
`TOTAL_PARTICIPANTS`(컴파일-타임 const 19999)를 `SeasonManager.TOTAL_PARTICIPANTS - 1`(런타임 var)과 assert로 비교한다.
`season_config.json`이 `totalParticipants`를 20000이 아닌 값으로 설정하면 게임 시작 시 즉시 crash.

```gdscript
assert(TOTAL_PARTICIPANTS == SeasonManager.TOTAL_PARTICIPANTS - 1, ...)
```

수정 방향: assert 제거 후 `TOTAL_PARTICIPANTS = SeasonManager.TOTAL_PARTICIPANTS - 1` 런타임 계산으로 교체, 또는 SeasonManager.TOTAL_PARTICIPANTS를 const로 선언.

---

### H-03 — `src/gameplay/news_event_system.gd` L510: DLC 시장 틱/일 불일치
`abs_tick % GameClock.TICKS_PER_DAY`(컴파일-타임 const = 1560)로 일 내 틱을 계산한다.
DLC 시장이 거래 시간이 다르면(`configure_trading_hours()`로 변경된 경우) 틱 인덱스가 범위를 벗어나거나 잘못된 시간대로 뉴스가 표시된다.

```gdscript
var tick_in_day: int = abs_tick % GameClock.TICKS_PER_DAY
```

수정 방향: `GameClock.get_effective_ticks_per_day()`로 교체.

---

## Medium (M)

### M-01 — `src/gameplay/m1_cache_manager.gd` L491: 슬롯 미설정 시 `slot_-1` 캐시 디렉토리 생성
`_cache_dir()`가 `SaveSystem.get_active_slot_id()`를 -1 가드 없이 사용한다.
슬롯 로드 전에 호출되면 `user://m1_cache/slot_-1/`가 생성된다.

수정 방향: `var slot_id := SaveSystem.get_active_slot_id(); if slot_id < 0: return ""` 선행 가드 추가 후 호출부에서 빈 문자열 처리.

---

### M-02 — `src/gameplay/short_selling_system.gd` L267-271: 미납 대여료 → margin_ratio 불반영
현금 부족으로 대여료를 전액 납부하지 못한 경우 차액이 무시된다.
`margin_deposited`가 감소하지 않으므로 margin_ratio 체크에서 shortfall이 보이지 않아 강제 청산 조건이 늦게 트리거된다.

수정 방향: 미납액을 `margin_deposited`에서 차감하거나 별도 `unpaid_fee` 필드에 누적하여 ratio 계산에 포함.

---

### M-03 — `src/gameplay/leverage_manager.gd` L204-205: 수동 청산 초과 손실 무음 흡수
`close_position()` → `_settle_partial_close()`에서 `mini(loss, sim_cash)`로 손실을 sim_cash 범위로 잘라낸다.
초과 손실이 `on_loan_shark_ending_triggered`를 발화하지 않아 강제 청산(`_forced_liquidation()`)과 동작이 불일치한다.

수정 방향: `net < 0 and loss > available`일 때 `on_loan_shark_ending_triggered` 발화 추가 (또는 GDD §3-4에서 수동 청산 시 사채업자 엔딩 미적용임을 명시하고 주석으로 근거 기록).

---

### M-04 — `src/gameplay/m1_cache_manager.gd` L189: `TICKS_PER_M1` 상수 중복
`const TICKS_PER_M1: int = 4`가 `GameClock.TICKS_PER_MINUTE`와 동일한 값을 별도로 선언한다.
GameClock 값이 변경되면 묵묵히 발산한다.

수정 방향: `const TICKS_PER_M1: int = GameClock.TICKS_PER_MINUTE` 또는 상수 직접 참조로 교체.

---

### M-05 — `src/gameplay/etf_manager.gd`: `inject_price()` 순서 의존성
`_on_season_started`가 PriceEngine에 `inject_price()`를 호출하지만, `PriceEngine._on_season_start()`(동일 시그널에 연결)는 `_stock_states`를 초기화한다.
autoload 등록 순서에 따라 PriceEngine 핸들러가 먼저 실행되면 주입된 ETF 가격이 유지되고, 나중에 실행되면 초기화에 의해 삭제된다.

수정 방향: `PriceEngine.on_season_start` 시그널(EtfManager가 구독) 또는 PriceEngine 내부에서 ETF 초기화를 명시적으로 호출하는 API 추가로 순서 보장.

---

## Low (L)

### L-01 — `src/gameplay/xp_system.gd` L215: `_cumulative_xp_for_level()` O(level) 반복
XP 지급마다 레벨업 체크 시 O(level) 루프 실행. 레벨 상한이 수십 이상이면 tick마다 부하.

수정 방향: 레벨별 누적 XP를 미리 계산한 `PackedInt64Array`로 캐시.

---

### L-02 — `src/gameplay/ai_competitor.gd` L503: tick마다 `RandomNumberGenerator.new()` 반복 할당
`_compute_eod_for()` 내부에서 매 호출마다 `var rng := RandomNumberGenerator.new()`.
13 participants/tick × 1560 ticks/day = 20,280 객체/day 생성.

수정 방향: `_rng: RandomNumberGenerator`를 클래스 멤버로 선언하고 `_ready()`에서 1회 초기화, 각 호출에서 seed만 교체.

---

### L-03 — `src/gameplay/news_event_system.gd` L514-518: 이벤트 풀 O(n) 선형 탐색
`_queue_kernel_event()`에서 `template_id`로 템플릿을 매번 선형 탐색.
이벤트 풀 크기(~수십~수백 항목)에 비례하여 매 커널 이벤트마다 비용 발생.

수정 방향: `_on_ready()`에서 `{ template_id → template_dict }` Dictionary로 역인덱스 구축.

---

### L-04 — `src/gameplay/season_manager.gd` L330: `seasons_played=0` 시 음수 모듈로
`(_seasons_played - 1) % SEASON_MONTH_STARTS.size()`에서 `_seasons_played=0`이면 -1 % size()를 계산한다.
GDScript는 음수 모듈로에서 음수 결과를 반환하므로 배열 인덱스로 사용하면 out-of-bounds.
현재 guard가 존재하지만 로직이 취약하다.

수정 방향: `maxi(0, _seasons_played - 1) % SEASON_MONTH_STARTS.size()`.

---

### L-05 — `src/gameplay/skill_tree.gd` L19-30: 튜닝 상수 하드코딩 (TODO 미이행)
`NEWS_DELAY_T0_MIN`, `MAX_HOLDINGS_T0` 등 튜닝 var들이 autoload 상단에 리터럴로 선언되어 있다.
파일 헤더에 "TODO: JSON config로 이동" 주석이 존재하나 미이행.
코딩 표준 "게임플레이 값은 외부 config에서" 위반.

수정 방향: `assets/data/skill_config.json`에 이동, `_load_config()`에서 로드.

---

## Phase 2 — ui/

### H-04 — `src/ui/lifestyle_screen.gd`: 라이프스타일 아이템 데이터 GDScript 하드코딩
`RESIDENCE_ITEMS`, `LUXURY_ITEMS`, `NETWORK_ITEMS`, `SOCIAL_ITEMS`, `PROPERTY_ITEMS`가 모두 `const Array`로 GDScript 내부에 하드코딩되어 있다. 각 항목에는 구매 비용, 티어 조건, 아트 파일 경로, XP 보너스 등 게임 밸런스 값이 포함된다.

```gdscript
const RESIDENCE_ITEMS: Array = [
    {"tier": 0, "name": "쪽방/고시원", "cost": 0, "art": "bronze_jjokbang.png"},
    {"tier": 1, "name": "변두리 원룸", "cost": 500_000, ...},
    ...  # 11 티어 하드코딩
]
const LUXURY_ITEMS: Array = [...]
const NETWORK_ITEMS: Array = [...]
const SOCIAL_ITEMS: Array = [...]
const PROPERTY_ITEMS: Array = [...]
```

코딩 표준 "Configuration values loaded from data files, never hardcoded" 위반. 비용이나 XP 보너스 조정 시 GDScript 파일을 직접 수정해야 하며, LifestyleManager와 데이터 소유권이 분리되지 않는다.

수정 방향: `assets/data/lifestyle_items.json`으로 이동, LifestyleManager(또는 lifestyle_screen._ready())에서 로드. UI는 데이터를 소유하지 않는다.

---

### M-06 — `src/ui/settlement_reporter.gd` L19-22: BBCode 색상 상수 ThemeSetup 수동 복사
`_C_PROFIT = "EB3833"`, `_C_LOSS = "2E6BE6"` 등 BBCode용 16진수 색상 문자열이 `ThemeSetup` Color 값을 수동으로 복사한 것이다. 주석에 "동기화 유지"라고 명시되어 있으나 강제 수단이 없어 `ThemeSetup.PROFIT_RED` 변경 시 묵묵히 발산한다.

```gdscript
const _C_PROFIT: String  = "EB3833"  ## ThemeSetup.PROFIT_RED.to_html(false)
const _C_LOSS: String    = "2E6BE6"  ## ThemeSetup.LOSS_BLUE.to_html(false)
```

수정 방향: `const`를 `var`로 전환하고 `_ready()`에서 `ThemeSetup.PROFIT_RED.to_html(false)` 등으로 초기화. 또는 `ThemeSetup`에 `bbcode_profit_color() -> String` 헬퍼를 추가하여 단일 소스 보장.

---

### M-07 — `src/ui/sector_comparison_view.gd` `_set_mini_bar_fill()`: 핫 패스 노드 재할당
`_set_mini_bar_fill()`이 인-플레이스 업데이트 경로에서 매 호출마다 `get_children()` → `queue_free()` → `Panel.new()` + `StyleBoxFlat.new()` 을 실행한다. 이 함수는 매 tick × 11 섹터 행 = 1560 tick/day × 11 = 17,160 회/day 호출된다. 핫 패스 노드 할당 금지(S5-03) 위반.

수정 방향: 각 행 생성 시 fill Panel을 캐시 배열에 저장하고, 업데이트 시 `anchor_left`/`anchor_right`만 교체. `order_panel.gd`의 bar fill 업데이트 패턴과 동일하게 구현.

---

### M-08 — `src/ui/portfolio_view.gd` `_refresh_transactions()` L469: 거래 내역 전체 재빌드
`_refresh_transactions()`가 `valuation_updated` 시그널(매 tick)마다 전체 Label 노드를 `queue_free()`로 제거 후 재생성한다. holdings 섹션은 diff 가드를 사용하는 반면 transactions 섹션은 동일 방식을 적용하지 않는다. 1560 tick/day × 거래 내역 수만큼 Label 할당 발생.

수정 방향: `_last_tx_count` 캐시로 항목 수 변화 여부를 확인하고, 변화 없으면 기존 Label의 `text`만 갱신. 또는 `valuation_updated` 연결을 끊고 `on_transaction_added` 시그널에서만 재빌드.

---

### M-09 — `src/ui/chart_renderer.gd` L553: `TICKS_PER_MINUTE` 리터럴 중복
`var m1_per_chart: int = tf / 4` — 리터럴 `4`가 `GameClock.TICKS_PER_MINUTE`와 동일한 값이다. M-04(`m1_cache_manager.gd`)와 동일 패턴. `GameClock.TICKS_PER_MINUTE`가 변경될 경우 차트 타임프레임 계산이 묵묵히 틀어진다.

수정 방향: `var m1_per_chart: int = tf / GameClock.TICKS_PER_MINUTE`.

---

### L-06 — `src/ui/order_panel.gd` L1275: `tr()` 누락 플레이어 노출 문자열
`_on_order_rejected` 폴백 분기에서 `"주문 거부됨"` 문자열이 `tr()` 없이 직접 Label에 할당된다. 로컬라이제이션 시스템을 우회한다.

수정 방향: `tr("주문 거부됨")`으로 교체 후 `ko.po`/`en.po`에 키 추가.

---

### L-07 — `src/ui/portfolio_view.gd` L354: 현재가 정수 나눗셈 역산
`var current_price: int = h.get("current_value", 0) / maxi(h.get("quantity", 1), 1)` — 평가금액을 수량으로 나눠 현재가를 역산한다. 정수 나눗셈으로 인해 오차가 발생하며, 평가금액 자체가 스냅샷 시점 가격 기반이어서 실시간 현재가와 다를 수 있다.

수정 방향: `PriceEngine.get_current_price(stock_id)`를 직접 호출하여 현재가를 읽는다.

---

## Phase 3 — C++ (gdextension/src/)

### L-08 — `gdextension/src/price_kernel.cpp` L1428, L1545: `TICKS_PER_MINUTE` 매직 넘버
`decay_ticks = final_tmpl->decay_minutes * 4`와 `cd_ticks = EE_INDIVIDUAL_COOLDOWN_MIN * 4`에서 `4`가 분당 틱 수를 의미하지만 상수로 선언되지 않았다. 주석으로 `// TICKS_PER_MINUTE = 4` 명시되어 있으나 실제 GDScript의 `GameClock.TICKS_PER_MINUTE`와 동기화 강제 수단 없음.

수정 방향: `price_kernel.h`에 `static constexpr int TICKS_PER_MINUTE = 4;` 추가 후 두 줄 교체.

---

## 요약 (최종)

| 심각도 | 건수 | 항목 |
|--------|------|------|
| High   | 4건  | H-01~H-04 |
| Medium | 9건  | M-01~M-09 |
| Low    | 8건  | L-01~L-08 |
| **합계** | **21건** | |

### 수정 우선순위
**즉시 수정 (버그/크래시 위험)**
- H-02: ai_competitor.gd assert → 런타임 크래시
- M-01: m1_cache_manager.gd slot_-1 디렉토리 생성
- M-03: leverage_manager.gd 초과 손실 무음 흡수 (사채업자 엔딩 미발화)

**Sprint 내 수정 (데이터 정합성)**
- H-01: price_engine.gd 시장 ID 하드코딩
- H-03: news_event_system.gd TICKS_PER_DAY 하드코딩
- M-02: short_selling_system.gd 미납 대여료 margin_ratio 불반영
- M-05: etf_manager.gd inject_price 순서 의존성
- M-06: settlement_reporter.gd BBCode 색상 ThemeSetup 수동 복사
- M-07: sector_comparison_view.gd 핫 패스 노드 재할당
- M-08: portfolio_view.gd 거래 내역 전체 재빌드
- M-09: chart_renderer.gd TICKS_PER_MINUTE 리터럴

**백로그 (성능/관례)**
- H-04: lifestyle_screen.gd 아이템 데이터 하드코딩
- L-01~L-08: 성능 최적화 및 관례 위반
