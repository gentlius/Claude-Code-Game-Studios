# ADR-016: QA 자동화 — 10일 Save/Load 시나리오 발견 버그 기록

**Status**: Active  
**Date**: 2026-04-08  
**Author**: QA Automation (test_10day_scenario.gd)

---

## 개요

`tests/integration/test_10day_scenario.gd`가 발견한 버그와 수정 기록.  
새 게임 → 10일 플레이 → 저장 → 프로그램 종료 시뮬레이션 → 로드 → 재현 정확도 검증.

---

## 발견 및 수정된 버그

### BUG-01: NewsEventSystem._on_day_transition 시그널 인자 불일치

| 항목 | 내용 |
|------|------|
| **파일** | `src/gameplay/news_event_system.gd:253` |
| **증상** | 10일 시뮬레이션 매 일 `ERROR: Error calling from signal 'on_day_transition'... Method expected 1 argument(s), but called with 0` |
| **원인** | `GameClock.on_day_transition`은 인자 없이 emit (시그널 정의: `signal on_day_transition()`). 하지만 핸들러가 `_on_day_transition(_day: int)`로 1개 인자를 요구 |
| **영향** | `_generate_overnight_disclosures()` 미실행 → 장 전 뉴스(오버나이트 공시) 생성 안 됨 |
| **수정** | `_on_day_transition(_day: int)` → `_on_day_transition()` |
| **확인** | 통합 테스트 실행 시 해당 ERROR 미발생 |

---

### BUG-02: PortfolioManager.load_save_data() — 보유 종목 필드 타입 불일치

| 항목 | 내용 |
|------|------|
| **파일** | `src/gameplay/portfolio_manager.gd:246` |
| **증상** | save/load 후 `TYPE_MISMATCH`: `quantity 10 → 10.0`, `avg_buy_price 65000 → 65000.0` 등 |
| **원인** | `JSON.parse_string()`은 모든 숫자를 float으로 반환. untyped Dictionary에 저장 시 자동 변환 없음 → `int` 값이 `float`으로 남음 |
| **영향** | `current_price * h["quantity"]`가 float 반환 → `current_value`, `unrealized_pnl`도 float → 타입 불일치 전파. 수치는 올바르나 타입 정확성 위반 |
| **수정** | `h.get("quantity", 0)` → `int(h.get("quantity", 0))` (동일하게 avg_buy_price, total_invested) |
| **확인** | 통합 테스트: 5건 TYPE_MISMATCH → 0건 |

---

### BUG-03: AiCompetitor.init_season() — 시그널 중복 연결

| 항목 | 내용 |
|------|------|
| **파일** | `src/gameplay/ai_competitor.gd:140` |
| **증상** | `SaveSystem.load_slot()` 호출 시 `ERROR: Signal 'on_day_transition' is already connected` |
| **원인** | `load_save_data()`가 내부적으로 `init_season()`을 재호출. `init_season()`은 `on_day_transition`과 `on_tick` 연결 시 `is_connected` 가드 없음 → 2회 연결 |
| **영향** | `_on_day_transition()`과 `_on_tick()`이 매 이벤트마다 2회 호출됨 → AI 수익률 계산 오류 가능성 |
| **수정** | `on_day_transition`과 `on_tick` 연결 전 `is_connected` 가드 추가 (이미 `on_market_open`에만 있던 패턴 일관 적용) |
| **확인** | 통합 테스트 실행 후 해당 ERROR 미발생 |

---

## 미수정 발견 사항 (후속 과제)

### ISSUE-01: SaveSystem.delete_slot() 후 ID 재사용 (ADR-009 위반)

| 항목 | 내용 |
|------|------|
| **발견** | `test_create_slot_after_delete_no_id_reuse` 실패 |
| **원인** | `create_slot()`이 현재 존재하는 슬롯의 max_id + 1을 사용. 삭제 후 남은 슬롯 없으면 ID 0 재사용 |
| **ADR** | ADR-009: 슬롯 ID는 단조 증가, 재사용 금지 |
| **수정 방향** | 인덱스에 `next_slot_id` 카운터 별도 저장, 삭제와 무관하게 단조 증가 |

### ISSUE-02: 손상 파일 로드 시 JSON 엔진 에러가 GUT "Unexpected Errors"로 판정

| 항목 | 내용 |
|------|------|
| **발견** | `test_load_slot_corrupted_returns_false`, `test_is_slot_valid_false_for_corrupted_file` 실패 |
| **원인** | 손상 JSON 파싱 시 Godot 엔진 레벨 ERROR 발생 → GUT가 "Unexpected Errors" 판정. 실제 동작(false 반환)은 올바름 |
| **수정 방향** | `SaveSystem.load_slot()`에서 JSON 파싱 전 `push_error` 대신 `push_warning` 사용 검토. 또는 `gut.allow_unexpected_errors()` 활용 |

### ISSUE-03: v1 마이그레이션 테스트 실패

| 항목 | 내용 |
|------|------|
| **발견** | `test_v1_migration_converts_legacy_save` — "slot_0으로 마이그레이션" assertion 실패 |
| **원인** | 테스트 정리 시 `save_data.json` 미생성 또는 `_migrate_v1_save()` 로직 버그 |
| **수정 방향** | 추가 조사 필요 |

---

## 최종 테스트 결과

```
통합 테스트 (10-Day Scenario):
  3/3 PASS
  Save/Load 불일치: 0건
  
단위 테스트:
  213/220 PASS (7 fail)
  - 3건: 오디오 매니저 (사전 존재, 이번 세션 무관)
  - 4건: Save System 신규 테스트가 드러낸 기존 버그
```

---

## 테스트 인프라 (걷어내기 가능)

| 파일 | 역할 | 제거 방법 |
|------|------|---------|
| `tests/integration/sim_driver.gd` | N일 시뮬레이션 엔진 | 삭제 |
| `tests/integration/data_snapshot.gd` | 전체 상태 캡처 + 비교 | 삭제 |
| `tests/integration/screenshot_helper.gd` | 스크린샷 + HTML 보고서 | 삭제 |
| `tests/integration/test_10day_scenario.gd` | 메인 QA 시나리오 | 삭제 |
| `.gutconfig.json` | `tests/integration/` 추가됨 | 원래대로 되돌리기 |

`src/` 수정 없음. 위 4개 파일 삭제 + `.gutconfig.json` 롤백으로 완전 제거 가능.
