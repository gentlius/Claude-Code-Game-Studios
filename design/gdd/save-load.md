# Save/Load System — GDD

**Status**: Approved (2026-04-07, QA Lead 리뷰 완료)  
**Sprint**: S5-01  
**Owner**: gameplay-programmer

---

## 1. Overview

단일 슬롯 자동 저장 시스템. 장 마감(on_market_close)마다 자동으로 JSON 파일에 저장하고,
앱 시작 시 파일이 있으면 자동으로 로드한다. XP·레벨·스킬·시즌 상태·포트폴리오·현금을
모두 복원해 게임을 재개할 수 있게 한다.

멀티 슬롯과 클라우드 동기화는 Beta 이관.

---

## 2. Player Fantasy

앱을 꺼도 내 포지션, XP, 스킬트리가 그대로다.
다음 날 켜면 어제 장 마감 이후부터 이어서 플레이할 수 있다.

---

## 3. Detailed Design

### 3-1 SaveSystem Autoload

- 파일: `src/core/save_system.gd`
- 클래스: `SaveSystem` (autoload)
- 저장 경로: `user://save_data.json`

### 3-2 저장 타이밍

| 트리거 | 설명 |
|-------|------|
| `GameClock.on_market_close` | 매일 장 마감 후 자동 저장 |
| `SeasonManager.on_season_ended` | 시즌 종료 후 자동 저장 |

### 3-3 직렬화 대상 시스템 (6개)

| 시스템 | 저장 필드 |
|--------|----------|
| `XpSystem` | total_xp, current_level, spent_skill_points |
| `SkillTree` | unlocked_skills (Array[String]) |
| `SeasonManager` | current_tier, is_free_market, season_start_capital, weekly_start_capital, weekly_trade_count, **seasons_played** |
| `CurrencySystem` | sim_cash, deposit, **season_active** |
| `PortfolioManager` | holdings (stock_id→{quantity, avg_buy_price, total_invested}) |
| `PriceEngine` | **closing_prices** (stock_id→int) |

> **seasons_played**: 픽션 날짜 계산(`get_fiction_date()`)에 사용. 미복원 시 항상 Q1(1월)로 표시됨.  
> **season_active**: 잔고 0인 시즌(파산 직전) 상태를 잔고로 추론하면 비활성으로 오복원. 명시적 저장 필요.  
> **closing_prices**: 세이브는 장 마감 후 발생하므로 current_price == prev_day_close. 로드 시 두 필드 모두 복원. 마코프 상태·OHLCV 히스토리는 미저장(세션 초기화). 미저장 시 base_price로 폴백 — 보유 주식 가치가 매수가 기준이 아닌 base_price로 표시되는 버그 발생.

### 3-4 저장 포맷 (JSON)

```json
{
  "save_version": 1,
  "timestamp": 1712345678,
  "xp": {
    "total_xp": 1500,
    "current_level": 4,
    "spent_skill_points": 2
  },
  "skill_tree": {
    "unlocked_skills": ["A1", "S1"]
  },
  "season": {
    "current_tier": 0,
    "is_free_market": false,
    "season_start_capital": 1000000,
    "weekly_start_capital": 980000,
    "weekly_trade_count": 3,
    "seasons_played": 2
  },
  "currency": {
    "sim_cash": 850000,
    "deposit": 1000000,
    "season_active": true
  },
  "portfolio": {
    "holdings": {
      "005930": {
        "quantity": 10,
        "avg_buy_price": 72000,
        "total_invested": 720000
      }
    }
  },
  "prices": {
    "closing_prices": {
      "005930": 71500,
      "000660": 138000
    }
  }
}
```

### 3-5 로드 타이밍

`game_main.gd` `_ready()` 에서 `CurrencySystem.init_first_season()` 호출 **직전**에
`SaveSystem.load_game()` 호출.

세이브 파일이 없으면 `init_first_season()` 을 정상 실행(새 게임).
세이브 파일이 있으면 `init_first_season()` 을 건너뛰고 저장된 값을 복원.

### 3-6 마이그레이션

`save_version` 필드 불일치 시:
- 알려진 필드만 로드, 나머지는 시스템 기본값 사용.
- `push_warning` 으로 로그 출력.
- 게임플레이 차단하지 않음.

---

## 4. Formulas

저장: `JSON.stringify(data, "\t")` — data는 각 시스템 get_save_data() 결과를 합친 딕셔너리  
로드: `JSON.parse_string(text)` → `Dictionary` 캐스팅 → 각 시스템 `load_save_data(sub_dict)` 호출

**직렬화 예시**:
- `_unlocked_skills = {"A1": true, "S1": true}` → `"unlocked_skills": ["A1", "S1"]`
- `_holdings = {"005930": {...}}` → JSON 그대로 직렬화
- `total_xp = 1500` → `"total_xp": 1500`

**범위 보증**: 로드 시 `maxi(data.get("field", default), 0)` 패턴으로 음수 방지. 포맷이 올바르면 데이터 손실 없음.

---

## 5. Edge Cases

| Code | 상황 | 처리 |
|------|------|------|
| EC-01 | 파일 없음 (첫 실행) | 새 게임으로 정상 시작 |
| EC-02 | 저장 파일 열기 실패 | push_warning, 게임 차단 없음 |
| EC-03 | JSON 파싱 실패 | push_error, 새 게임 시작 |
| EC-04 | save_version 불일치 | 알려진 필드만 로드, push_warning |
| EC-05 | 포트폴리오 빈 상태로 저장 | holdings: {} 정상 복원 |
| EC-06 | 저장 중 디스크 공간 부족 | push_warning, 기존 파일 유지 |

---

## 6. Dependencies

- `XpSystem`, `SkillTree`, `SeasonManager` — 이미 get_save_data/load_save_data 구현됨
- `CurrencySystem`, `PortfolioManager` — 이번 스프린트에서 추가
- `GameClock.on_market_close`, `SeasonManager.on_season_ended` 시그널

---

## 7. Tuning Knobs

| 이름 | 기본값 | 안전 범위 | 게임플레이 영향 |
|------|--------|-----------|----------------|
| `SAVE_VERSION` | 1 | 1 이상 정수, 절대 감소 금지 | 필드 추가·삭제 시 increment. 낮추면 신규 세이브를 구버전으로 잘못 해석 |
| `SAVE_PATH` | `user://save_data.json` | Godot `user://` 접두사 유지 | 변경 시 기존 세이브 접근 불가 — 변경 금지 또는 마이그레이션 필수 |

---

## 8. Acceptance Criteria

| AC | 조건 |
|----|------|
| AC-01 | `save_game()` 호출 후 `user://save_data.json` 파일 생성 |
| AC-02 | 로드 후 XP/레벨/스킬포인트 정확히 복원 |
| AC-03 | 세이브 → 종료 → 로드 → 재개 E2E 통과 |
| AC-04 | 보유 주식(종목·수량·평균단가) 복원 |
| AC-05 | 시즌 상태(티어·시즌시작자본) 복원 |
| AC-06 | sim_cash·deposit 복원 |
| AC-07 | 파일 없을 때 새 게임 정상 시작 |
| AC-08 | 저장 실패 시 게임플레이 차단 없음 |
| AC-09 | save_version 불일치 시 알려진 필드만 로드, 경고만 출력 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `game_main.gd._ready()` → `SaveSystem.load_game()` (init_first_season 이전)
- `GameClock.on_market_close` → `SaveSystem.save_game()`
- `SeasonManager.on_season_ended` → `SaveSystem.save_game()`

### 호출 경로
- [x] `SaveSystem.save_game()` → 5개 시스템 `get_save_data()` 수집 → JSON 기록
- [x] `SaveSystem.load_game()` → JSON 읽기 → 5개 시스템 `load_save_data()` 복원
- [x] `CurrencySystem.get_save_data()` / `load_save_data()` — 이번 스프린트 추가
- [x] `PortfolioManager.get_save_data()` / `load_save_data()` — 이번 스프린트 추가
- [x] `SaveSystem` autoload → `project.godot` 등록

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_save_system.gd` | `test_save_game_creates_file()` |
| AC-02 | `tests/unit/test_save_system.gd` | `test_load_game_restores_xp()` |
| AC-03 | E2E 수동 테스트 | 세이브 → 앱 재시작 → 로드 → 시즌/XP/포트폴리오 동일 확인 |
| AC-04 | `tests/unit/test_save_system.gd` | `test_load_game_restores_holdings()` |
| AC-05 | `tests/unit/test_save_system.gd` | `test_load_game_restores_season()` |
| AC-06 | `tests/unit/test_save_system.gd` | `test_load_game_restores_currency()` |
| AC-07 | `tests/unit/test_save_system.gd` | `test_load_game_no_file_starts_fresh()` |
| AC-08 | `tests/unit/test_save_system.gd` | `test_save_failure_does_not_block_gameplay()` |
| AC-09 | `tests/unit/test_save_system.gd` | `test_load_game_version_mismatch_loads_known_fields()` |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 2026-04-07 (SCRIPT ERROR 0, AiCompetitor push_error는 시즌 미시작 예상 동작)
