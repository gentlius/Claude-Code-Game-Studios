# Save/Load System — GDD

**Status**: Approved (2026-04-07, QA Lead 리뷰 완료)  
**Sprint**: S5-01  
**Owner**: gameplay-programmer

---

## 1. Overview

멀티 슬롯 자동 저장 시스템. 슬롯마다 `user://save_slot_{id}.json`에 데이터를 저장하고,
슬롯 목록은 `user://save_index.json`으로 관리한다.
장 마감(on_market_close)마다 활성 슬롯에 자동 저장하며, 저장 중에는 전체화면 스피너
오버레이로 진행을 알리고 유저 입력을 차단한다.
XP·레벨·스킬·시즌 상태·포트폴리오·현금을 모두 복원해 게임을 재개할 수 있게 한다.

클라우드 동기화는 Beta 이관.

---

## 2. Player Fantasy

앱을 꺼도 내 포지션, XP, 스킬트리가 그대로다.
여러 슬롯에서 서로 다른 도전을 번갈아 플레이할 수 있다.
저장 중임을 알 수 있으며, 저장이 완료되기 전에는 나가지 않는다.

---

## 3. Detailed Design

### 3-1 파일 구조

| 파일 | 역할 |
|------|------|
| `user://save_index.json` | 슬롯 목록 + 메타데이터 캐시 (레벨·시즌·날짜·평가금액) |
| `user://save_slot_{id}.json` | 슬롯별 전체 게임 상태 |

`save_index.json` 형식:
```json
{
  "index_version": 1,
  "slots": [
    {
      "id": 0,
      "name": "나의 첫 도전",
      "level": 4,
      "season_number": 2,
      "fiction_week": 2,
      "fiction_day": 3,
      "portfolio_value": 1250000,
      "saved_at": 1712345678
    }
  ]
}
```

`save_slot_{id}.json` 형식: §3-4 참조 (`save_version`: 3. v2→v3: `stop_take` 필드 추가, 미존재 시 빈 배열 기본값).

### 3-2 SaveSystem Autoload

- 파일: `src/core/save_system.gd`
- 클래스: `SaveSystem` (autoload)
- 공개 프로퍼티: `active_slot_id: int` — 현재 로드된 슬롯 ID (-1이면 미로드)

### 3-3 저장 타이밍

| 트리거 | 설명 |
|-------|------|
| `GameClock.on_market_close` | 매일 장 마감 후 활성 슬롯 자동 저장 |
| `SeasonManager.on_season_ended` | 시즌 종료 후 활성 슬롯 자동 저장 |
| 새 게임 진입 직후 | `MainScreen._ready()` 완료 후 초기 상태 1회 저장 |

저장 흐름:
1. `save_started` 시그널 emit → `SavingOverlay` 표시, 입력 차단
2. 직렬화 → 파일 쓰기 → `save_index.json` 메타 갱신
3. `save_completed` 시그널 emit → `SavingOverlay` 해제

### 3-4 직렬화 대상 시스템 (9개)

| 시스템 | 저장 필드 |
|--------|----------|
| `XpSystem` | total_xp, current_level, spent_skill_points |
| `SkillTree` | unlocked_skills (Array[String]) |
| `SeasonManager` | current_tier, is_free_market, season_start_deposit, weekly_start_capital, weekly_trade_count, **seasons_played** |
| `CurrencySystem` | sim_cash, **cash_assets**, **total_prize_earned**, **season_active** |
| `PortfolioManager` | holdings (stock_id→{quantity, avg_buy_price, total_invested}) |
| `PriceEngine` | stocks (stock_id→{current_price, prev_day_close, season_bias, **ohlcv_daily**, **tick_prices**, **tick_volumes**}) |
| `GameClock` | **current_day**, **current_week** |
| `AiCompetitor` | season_seed, player_tier, participant_counts, current_day |
| `StopTakeSystem` | stop_take_settings (Array[Dictionary]: stock_id, stop_loss_price, take_profit_price, quantity, enabled) |

> **stop_take_settings**: TR2 손절/익절 조건은 세션 간 유지돼야 한다. 미복원 시 장 마감 후 재시작하면 설정이 초기화되어 플레이어 의도대로 감시가 재개되지 않음. `save_version` 불일치 시 빈 배열로 기본값 처리. 상세 설계: `design/gdd/stop-loss-take-profit.md`.

**미저장 시스템 및 이유:**

| 시스템 | 미저장 이유 | 로드 시 기본값 | 게임플레이 영향 |
|--------|------------|--------------|--------------|
| `GameClock._current_tick` | 장 마감 후 저장 → 로드 시 항상 0 (새 거래일 시작) | 0 | 없음 |
| `GameClock.MarketState` | 로드 후 항상 PRE_MARKET에서 재개 | PRE_MARKET | 없음 |
| `PriceEngine` 마코프 상태 | 세션 초기화 허용 — 가격·bias·차트 데이터는 복원됨 | SIDEWAYS | 없음 (Markov는 세션 스코프) |
| `PriceEngine` 호가창 | KRX 미체결 잔량은 장 마감 시 초기화. 다음 날 장 시작 시 재생성 (`order-book.md`) | 빈 상태 | 없음 |
| `OrderEngine` 미체결 주문 | 장 마감 후 저장 → 미체결 주문 없음 | 빈 큐 | 없음 |
| `LifestyleManager` | Beta Sprint 9 이후 구현. Alpha 폴백 기간: 미저장, 로드 시 기본값(거주지 Tier 0) 사용 | 거주지 Tier 0, 빈 목록 | 없음 (Alpha 폴백 구간은 라이프스타일 기능 비활성) |
| `NewsEventSystem` 딜레이 큐 | 장 마감 후 저장 → 큐 비어있음 | 빈 큐 | 없음 |

> **ohlcv_daily / tick_prices / tick_volumes**: 차트 렌더러가 1시즌 전체 틱 버퍼를 유지하므로 (GDD chart-renderer §5-1 max_tick_history=31200) 전체를 저장·복원해야 봉차트·보조지표가 연속성을 유지한다.  
> **season_seed**: AiCompetitor의 참가자 수익률은 시드+일수로 결정론적으로 계산되므로 시드만 저장하면 전체 순위를 재현할 수 있다.  
> **season_active**: 잔고 0인 시즌(파산 직전) 상태를 잔고로 추론하면 비활성으로 오복원. 명시적 저장 필요.  
> **current_day / current_week**: 미복원 시 항상 week=0, day=0으로 리셋 → 3주차에 저장하면 로드 후 5일 뒤에 "1주차 종료" 이벤트 발생. 주간 보상·시즌 종료 타이밍 오작동.  
> **cash_assets**: 현금 자산(시즌 상금 환급·라이프스타일 지출 등 반영)은 예수금(`sim_cash`)과 별도 저장. 미복원 시 로드 후 현금 자산이 0으로 리셋 → 라이프스타일 지출·티어 배정 오작동.  
> **total_prize_earned**: 누적 상금 합계. 미복원 시 0으로 리셋 — 게임 내 "총 획득 상금" 통계 표시 오류. save_version 1 이전 세이브(구 `deposit` 필드)는 마이그레이션 시 `total_prize_earned`로 매핑.

### 3-5 저장 포맷 (save_slot_{id}.json)

```json
{
  "save_version": 3,
  "timestamp": 1712345678,
  "xp": { "total_xp": 1500, "current_level": 4, "spent_skill_points": 2 },
  "skill_tree": { "unlocked_skills": ["A1", "S1"] },
  "season": {
    "current_tier": 0, "is_free_market": false,
    "season_start_deposit": 1000000, "weekly_start_capital": 980000,
    "weekly_trade_count": 3, "seasons_played": 2
  },
  "currency": { "sim_cash": 850000, "cash_assets": 2000000, "total_prize_earned": 500000, "season_active": true },
  "portfolio": {
    "holdings": {
      "005930": { "quantity": 10, "avg_buy_price": 72000, "total_invested": 720000 }
    }
  },
  "prices": {
    "stocks": {
      "005930": {
        "current_price": 71500, "prev_day_close": 71500, "season_bias": 0,
        "ohlcv_daily": [
          { "open": 72000, "high": 73500, "low": 70000, "close": 71500, "volume": 1234.5 }
        ],
        "tick_prices": [72000, 72050, "..."],
        "tick_volumes": [0.8, 0.9, "..."]
      }
    }
  },
  "clock": { "current_day": 9, "current_week": 1 },
  "ai": {
    "season_seed": 987654321, "player_tier": 0,
    "participant_counts": { "0": 7600, "1": 3200 },
    "current_day": 9
  },
  "stop_take": {
    "settings": [
      { "stock_id": "005930", "stop_loss_price": 68000, "take_profit_price": 80000, "quantity": 10, "enabled": true }
    ]
  }
}
```

### 3-6 로드 타이밍

`StartScreen`에서 슬롯 클릭 → `SaveSystem.load_slot(id)` 호출 → 각 시스템 `load_save_data()` 복원 → MainScreen 진입.

새 게임의 경우: `StartScreen`이 `IntroSequence.play()` → `MainScreen._ready()` → `SaveSystem.save_slot(id)` (초기 상태 저장).

### 3-7 마이그레이션

**v1 단일 슬롯 → 멀티 슬롯 자동 마이그레이션**:  
`user://save_data.json` 존재 + `user://save_index.json` 없음 → 앱 시작 시 자동 실행:
1. `save_data.json` → `save_slot_0.json` 복사
2. `save_slot_0.json`의 데이터로 `save_index.json` 생성 (슬롯 이름: "슬롯 1")
3. `save_data.json` 삭제
4. `push_warning("save_data.json migrated to slot 0")`

**save_version 불일치** 시:
- 알려진 필드만 로드, 나머지는 시스템 기본값.
- `push_warning` 로그, 게임플레이 차단 없음.

### 3-8 SavingOverlay

저장 진행 중임을 알리는 전체화면 UI 컴포넌트.

| 항목 | 규격 |
|------|------|
| 씬 위치 | MainScreen 루트의 최상단 레이어 (CanvasLayer layer=10) |
| 배경 | `#000000` 반투명 오버레이 (alpha 0.6) |
| 스피너 | 인디케이터 원형 스피너, 48px, `#ebebeb`, 중앙 배치 |
| 텍스트 | "저장 중..." 14px, 스피너 하단 8px |
| 입력 차단 | 오버레이 Panel `mouse_filter = MOUSE_FILTER_STOP`, 하위 노드 비활성화 불필요 |
| 표시 트리거 | `SaveSystem.save_started` 시그널 |
| 해제 트리거 | `SaveSystem.save_completed` 시그널 |
| F4 차단 | `trading_screen.gd`가 `SavingOverlay.visible`을 체크해 F4 무반응 처리 |

---

## 4. Formulas

저장: `JSON.stringify(data, "\t")` — data는 각 시스템 `get_save_data()` 결과를 합친 딕셔너리  
로드: `JSON.parse_string(text)` → `Dictionary` 캐스팅 → 각 시스템 `load_save_data(sub_dict)` 호출

**save_index 메타 갱신** (저장 시마다):
```
portfolio_value = CurrencySystem.get_account_total_value()
                # = sim_cash + reserved_cash + Σ(holding.quantity × current_price)
```

**직렬화 예시**:
- `_unlocked_skills = {"A1": true, "S1": true}` → `"unlocked_skills": ["A1", "S1"]`
- `_holdings = {"005930": {...}}` → JSON 그대로 직렬화
- `total_xp = 1500` → `"total_xp": 1500`

**범위 보증**: 로드 시 `maxi(data.get("field", default), 0)` 패턴으로 음수 방지.

---

## 5. Edge Cases

| Code | 상황 | 처리 |
|------|------|------|
| EC-01 | `save_index.json` 없음 (첫 실행) | 빈 슬롯 목록, 새 게임으로 정상 시작 |
| EC-02 | 슬롯 파일 열기 실패 | `push_warning`, StartScreen 복귀, 알림 팝업 |
| EC-03 | JSON 파싱 실패 | `push_error`, 슬롯 카드에 "⚠ 손상된 파일" 표시 |
| EC-04 | save_version 불일치 | 알려진 필드만 로드, `push_warning` |
| EC-05 | 포트폴리오 빈 상태로 저장 | `holdings: {}` 정상 복원 |
| EC-06 | 저장 중 디스크 공간 부족 | `push_warning`, 기존 파일 유지, `save_completed` emit (실패 상태로) |
| EC-07 | 세이브 파일 변조 — 선행조건 없는 스킬 해금 | `SkillTree.load_save_data()`가 선행조건 미충족 스킬 탐지·제거. 연쇄 무효화. `push_warning`. |
| EC-08 | `save_data.json` 존재 (구버전 단일 슬롯) | §3-7 마이그레이션 자동 실행 |
| EC-09 | 저장 중 앱 강제 종료 | 이전 정상 저장 파일 유지 (원자적 쓰기: 임시 파일 → rename) |
| EC-10 | 시즌 정산 직전 저장 → 로드 → 상금 이중 수령 시도 | `SeasonManager.on_season_ended` 직후 즉시 저장 → `season_active = false`로 저장됨. 재로드 시 이미 정산 완료 상태로 복원되어 재정산 불가. |
| EC-11 | SEASON_SETTLING 상태 중 저장 → 로드 | `season_active = false` + `sim_cash = 0`으로 복원. PRE_SEASON 화면에서 재개. `cash_assets`에 상금 반영 여부는 `total_prize_earned` 증분으로 확인 가능. |

> **EC-09 원자적 쓰기**: `save_slot_{id}.tmp`에 먼저 기록 후 `save_slot_{id}.json`으로 rename. Godot `FileAccess`는 rename 미지원이므로 임시 파일 쓰기 후 원본 삭제 → 임시 파일 이름 변경 순서.

---

## 6. Dependencies

- `XpSystem`, `SkillTree`, `SeasonManager` — `get_save_data` / `load_save_data` 구현됨
- `CurrencySystem`, `PortfolioManager` — S5-01에서 추가됨
- `PriceEngine` — `get_save_data` / `initialize_for_load()` 구현됨
- `AiCompetitor` — `get_save_data` / `load_save_data` 구현됨
- `GameClock.on_market_close`, `SeasonManager.on_season_ended` 시그널
- `StartScreen` — `load_slot()` / `delete_slot()` / `get_slot_list()` 호출자 (`start-screen.md`)
- `SavingOverlay` — `save_started` / `save_completed` 시그널 구독자 (`trading-screen.md`)
- `LifestyleManager` — Beta 구현 시 `get_save_data` / `load_save_data` 추가 필요. 직렬화 대상: 현재 거주지, 보유 부동산 목록(매입가/만기), 스타트업 투자 목록(투자금/엑싯 시즌), 구매 품목 목록, 획득 칭호 목록, Recurring 비용 항목

---

## 7. Tuning Knobs

| 이름 | 기본값 | 안전 범위 | 게임플레이 영향 |
|------|--------|-----------|----------------|
| `SAVE_VERSION` | 3 | 1 이상 정수, 절대 감소 금지 | 필드 추가·삭제 시 increment. 낮추면 신규 세이브를 구버전으로 잘못 해석 |
| `INDEX_VERSION` | 1 | 1 이상 정수, 절대 감소 금지 | `save_index.json` 포맷 변경 시 increment |
| `SAVE_PATH_SLOT` | `user://save_slot_{id}.json` | `user://` 접두사 유지 | 변경 시 기존 슬롯 접근 불가 |
| `SAVE_INDEX_PATH` | `user://save_index.json` | `user://` 접두사 유지 | 변경 시 슬롯 목록 유실 |

---

## 8. Acceptance Criteria

| AC | 조건 |
|----|------|
| AC-01 | `save_slot_{id}.json` 파일 생성 확인 |
| AC-02 | 로드 후 XP/레벨/스킬포인트 정확히 복원 |
| AC-03 | 세이브 → 종료 → 로드 → 재개 E2E 통과 |
| AC-04 | 보유 주식(종목·수량·평균단가) 복원 |
| AC-05 | 시즌 상태(티어·시즌시작자본) 복원 |
| AC-06 | sim_cash·cash_assets·total_prize_earned 복원 |
| AC-07 | 슬롯 없을 때 새 게임 정상 시작 |
| AC-08 | 저장 실패 시 게임플레이 차단 없음 |
| AC-09 | save_version 불일치 시 알려진 필드만 로드, 경고만 출력 |
| AC-10 | 저장 중 SavingOverlay 표시, 입력 차단 |
| AC-11 | save_completed 시 SavingOverlay 해제 |
| AC-12 | `save_data.json` 존재 시 slot_0으로 자동 마이그레이션 |
| AC-13 | save_index.json에 레벨·시즌·픽션날짜·평가금액 정확히 기록 |
| AC-14 | 멀티 슬롯 독립 저장·로드 (슬롯 A 로드가 슬롯 B 파일에 영향 없음) |
| AC-15 | SEASON_ACTIVE 중 저장 → 로드 시 season_active=true, sim_cash, cash_assets, 포트폴리오 정확히 복원되어 당일 거래 재개 가능 |
| AC-16 | 시즌 정산(SEASON_SETTLING) 후 저장 → 로드 시 season_active=false, cash_assets에 상금 반영, sim_cash=0으로 복원 |
| AC-17 | EC-10 익스플로잇 방어: 정산 전 세이브를 로드해도 상금이 이중 지급되지 않는다 (`season_active=false` 상태로만 저장됨) |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `StartScreen.slot_selected(id)` → `SaveSystem.load_slot(id)`
- `StartScreen.new_game_confirmed(name)` → `SaveSystem.create_slot(name)` → `MainScreen._ready()` → `SaveSystem.save_slot(active_slot_id)`
- `GameClock.on_market_close` → `SaveSystem.save_slot(active_slot_id)`
- `SeasonManager.on_season_ended` → `SaveSystem.save_slot(active_slot_id)`

### 호출 경로
- [x] `SaveSystem.save_slot(id)` → emit `save_started` → 8개 시스템 `get_save_data()` → JSON 기록 → index 갱신 → emit `save_completed`
- [x] `SaveSystem.load_slot(id)` → JSON 읽기 → 8개 시스템 `load_save_data()` 복원
- [x] `SaveSystem.get_slot_list()` → `save_index.json` 읽기 → `Array[Dictionary]` 반환
- [x] `SaveSystem.create_slot(name)` → 새 ID 할당 → `save_index.json` 갱신 → `active_slot_id` 세팅
- [x] `SaveSystem.delete_slot(id)` → `save_slot_{id}.json` 삭제 → `save_index.json` 갱신
- [x] `SavingOverlay` — `save_started` / `save_completed` 구독, `mouse_filter = STOP`
- [x] `SaveSystem` autoload → `project.godot` 등록
- [x] v1 마이그레이션: `save_data.json` 감지 → slot_0 변환 → index 생성

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_save_system.gd` | `test_save_slot_creates_file()` |
| AC-02 | `tests/unit/test_save_system.gd` | `test_load_slot_restores_xp()` |
| AC-03 | E2E 수동 테스트 | 세이브 → 앱 재시작 → 슬롯 선택 → 시즌/XP/포트폴리오 동일 확인 |
| AC-04 | `tests/unit/test_save_system.gd` | `test_load_slot_restores_holdings()` |
| AC-05 | `tests/unit/test_save_system.gd` | `test_load_slot_restores_season()` |
| AC-06 | `tests/unit/test_save_system.gd` | `test_load_slot_restores_currency()` |
| AC-07 | `tests/unit/test_save_system.gd` | `test_no_slots_starts_fresh()` |
| AC-08 | `tests/unit/test_save_system.gd` | `test_save_failure_does_not_block_gameplay()` |
| AC-09 | `tests/unit/test_save_system.gd` | `test_load_version_mismatch_loads_known_fields()` |
| AC-12 | `tests/unit/test_save_system.gd` | `test_v1_migration_creates_slot_0()` |
| AC-13 | `tests/unit/test_save_system.gd` | `test_index_meta_portfolio_value_correct()` |
| AC-14 | `tests/unit/test_save_system.gd` | `test_multi_slot_independence()` |
| AC-15 | E2E 수동 테스트 | SEASON_ACTIVE 중 앱 재시작 → 슬롯 로드 → 거래 재개 확인 |
| AC-16 | E2E 수동 테스트 | 시즌 정산 후 앱 재시작 → 슬롯 로드 → PRE_SEASON 화면, cash_assets 상금 반영 확인 |
| AC-17 | `tests/unit/test_save_system.gd` | `test_no_prize_double_collect_on_reload()` |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 2026-04-07 (SCRIPT ERROR 0, AiCompetitor push_error는 시즌 미시작 예상 동작 — 기존과 동일)
