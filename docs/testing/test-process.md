# 테스트 프로세스 — Seed Money 개발팀 기준

**버전**: 1.0  
**최초 작성**: 2026-04-08  
**작성자**: QA Lead + Lead Programmer  

---

## 개요

이 문서는 Seed Money 개발팀의 공식 테스트 방법론을 정의한다.  
세 가지 계층으로 나뉘며 각 계층은 서로 다른 결함 유형을 포착한다.

```
계층 1 — 단위 테스트     : 개별 시스템 API 계약 검증
계층 2 — 통합 시뮬레이션  : 다중 시스템 연동 + Save/Load 데이터 정합성
계층 3 — UI 레이블 검증   : 화면 텍스트 포맷 + 갱신 타이밍 검증
```

> **계층 간 관계**: 각 계층은 독립적이다. 계층 2가 데이터를 검증해도 계층 3에서
> 포맷 버그를 잡을 수 있다. 모두 실행해야 "통과"다.

---

## 계층 1 — 단위 테스트

### 목적

- 개별 autoload/시스템의 공개 API 계약 검증
- 경계 조건, 오류 경로 (EC-XX 시나리오) 커버
- 회귀 방지 (버그 수정 시 재현 테스트 추가 의무)

### 테스트 위치

```
tests/unit/
  test_save_system.gd     ← SaveSystem 멀티슬롯 API (ADR-009)
  test_api_contracts.gd   ← 핵심 autoload API 계약
  (시스템별 추가)
```

### 실행 명령

```bash
# GUT CLI (Godot 헤드리스)
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit/ \
  -gexit

# 특정 파일만
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_save_system.gd \
  -gexit
```

### 통과 기준

| 항목 | 기준 |
|------|------|
| 전체 통과율 | 100% (기존 오디오 관련 3건 제외 — 사전 확인된 결함) |
| Unexpected Errors | 0건 (의도적 JSON 손상 테스트는 별도 처리 필요 — ISSUE-02) |
| 실행 시간 | 60초 이내 |

### 새 단위 테스트 추가 규칙

1. 버그를 수정했으면 **반드시** 해당 버그를 재현하는 회귀 테스트를 추가한다
2. 새 public 메서드를 추가했으면 해당 메서드의 정상 + 오류 경로를 테스트한다
3. 테스트 이름: `test_[시스템]_[시나리오]_[기대결과]` 패턴 준수
4. Arrange / Act / Assert 구조 의무

---

## 계층 2 — 통합 시뮬레이션

### 목적

- **데이터 계층** 간 연동 검증: 여러 autoload가 협력할 때 상태 일관성 유지 여부
- **Save/Load 정합성**: 저장 직전 상태와 로드 직후 상태가 완전히 일치하는지
- 장기 플레이(N일) 후 누적 오류 탐지

### 메인 시나리오: 10일 Save/Load 재현 테스트

```
새 게임 초기화
→ 10일 플레이 (Day 0에 KSF 10주 매수, Day 5에 STC 5주 매수)
→ 저장 (save_slot)
→ 모든 autoload 리셋 (프로그램 재시작 시뮬레이션)
→ 로드 (load_slot)
→ 저장 직전 / 로드 직후 스냅샷 비교 → 불일치 = 테스트 실패
```

### 테스트 파일

```
tests/integration/
  sim_driver.gd          ← N일 시뮬레이션 엔진 (GameClock._process_tick() 직접 구동)
  data_snapshot.gd       ← 전체 시스템 상태 캡처 + diff 비교
  screenshot_helper.gd   ← HTML 보고서 생성 (헤드리스에서 스크린샷 생략)
  test_10day_scenario.gd ← 메인 QA 시나리오 (GUT 테스트)
```

### 실행 명령

```bash
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gexit
```

### 통과 기준

| 항목 | 기준 |
|------|------|
| 10일 시나리오 | PASS (Save/Load 불일치 0건) |
| 스냅샷 diff | 모든 필드 일치 (float 허용 오차 0.001) |
| Unexpected Errors | 0건 |

### 검증 대상 필드 (DataSnapshot)

```
GameClock   : current_tick, current_day, current_week, market_state
CurrencySystem : sim_cash
PortfolioManager : 보유 종목별 quantity/avg_buy_price/total_invested, initial_seed
XpSystem    : total_xp, current_level, spent_skill_points
SkillTree   : unlocked_skills
SeasonManager : current_season, season_start_capital, weekly_data
PriceEngine : 전 종목 current_price, prev_day_close
AiCompetitor : top-10 순위 + return_pct
```

### 인프라 제거 절차 (완전 걷어내기 필요 시)

1. `tests/integration/` 폴더 전체 삭제
2. `.gutconfig.json` 에서 `"res://tests/integration/"` 항목 제거
3. `src/` 변경 없음

---

## 계층 3 — UI 레이블 검증

### 목적

계층 2가 데이터 정합성을 검증한다면, 계층 3은 **화면 표시**를 검증한다:

- UI가 올바른 필드를 읽는가 (wrong field bug)
- 포맷 문자열이 올바르게 적용되는가 (formatting bug)
- 시그널 수신 후 레이블이 갱신되는가 (stale label bug)
- `FormatUtils.number()` 호출 경로가 일관되는가

### 구현 방식: Method 1 — Label.text 메모리 읽기

GPU/렌더링 없이 `Label.text` 속성을 직접 읽는다.  
헤드리스 모드에서 완전히 동작. 스크린샷 불필요.

```gdscript
# 패턴 예시
var view = load("res://src/ui/portfolio_view.gd").new()
add_child(view)
await get_tree().process_frame          # _ready() 실행 대기
GameClock.on_tick.emit(0, 0, 0)        # 갱신 트리거 (필요한 경우)

var summary = PortfolioManager.get_portfolio_summary()
var expected = "총 자산: ₩%s" % FormatUtils.number(summary["total_assets"])
assert_eq(view._lbl_total_assets.text, expected)
```

### 테스트 파일

```
tests/integration/
  test_ui_label_verification.gd  ← UI 레이블 포맷 검증 (헤드리스 호환)
```

### 커버 대상

| 화면 | 검증 레이블 |
|------|------------|
| PortfolioView | `_lbl_total_assets`, `_lbl_return_rate`, `_lbl_cash_info`, 보유 행 수량 |
| StatusBar | `_lbl_total_assets`, `_lbl_cash`, `_lbl_season_info` |
| StockListPanel | 가격 레이블(child[2]), 등락률 레이블(child[3]) |

### 실행 명령

```bash
# 통합 테스트 전체 (계층 2 + 계층 3 함께)
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gexit

# UI 레이블 테스트만
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_ui_label_verification.gd \
  -gexit
```

### 통과 기준

| 항목 | 기준 |
|------|------|
| 전체 assert | 100% PASS |
| Unexpected Errors | 0건 |

### 새 UI 레이블 테스트 추가 규칙

1. 새 화면/레이블을 추가했으면 해당 레이블의 포맷을 테스트한다
2. UI 버그를 수정했으면 해당 버그를 재현하는 레이블 테스트를 추가한다
3. 예상 문자열은 **같은 포맷 함수**로 계산한다 (하드코딩 금지)

```gdscript
# 좋음 — 포맷 함수 재사용
var expected = "총 자산: ₩%s" % FormatUtils.number(summary["total_assets"])
assert_eq(view._lbl_total_assets.text, expected)

# 나쁨 — 하드코딩
assert_eq(view._lbl_total_assets.text, "총 자산: ₩1,000,000")
```

---

## 전체 테스트 실행 (CI / PR 전 필수)

```bash
# 1단계: 단위 테스트
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit/ \
  -gexit

# 2단계: 통합 테스트 (시뮬레이션 + UI 레이블)
D:\Godot4\godot.exe --headless res:// \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration/ \
  -gexit
```

---

## 결함 분류 기준

| 분류 | 설명 | 탐지 계층 |
|------|------|-----------|
| 데이터 계층 버그 | autoload 내부 상태 오류, 계산 오류 | 계층 1, 2 |
| Save/Load 정합성 버그 | 저장/복원 시 필드 누락/타입 불일치 | 계층 2 |
| UI 포맷 버그 | 잘못된 포맷 문자열, 잘못된 필드 참조 | 계층 3 |
| UI 갱신 타이밍 버그 | 시그널 미연결, stale label | 계층 3 |
| 렌더링 버그 | 색상, 레이아웃, 폰트 | 수동 검토 |

---

## 실패 조사 가이드

### 계층 1 실패 시

1. GUT 출력에서 실패한 `assert_*` 위치 확인
2. `before_each` / `after_each` 정리 확인 (상태 오염 의심 시 독립 실행)
3. 최근 관련 파일 변경 이력 `git log --oneline -10 src/[시스템].gd` 확인

### 계층 2 실패 시

1. `user://test_results/` 아래 HTML 보고서 확인
2. `pre_save.json` vs `post_load.json` diff 확인 — 불일치 필드가 원인
3. 불일치 필드가 속한 시스템의 `save_save_data()` / `load_save_data()` 검토
4. JSON round-trip 타입 변환 확인 (`int` → `float` — `int()` 캐스트 필요)

**공통 원인 패턴:**

| 증상 | 원인 | 수정 |
|------|------|------|
| int 필드가 float으로 복원 | JSON.parse_string()이 모든 숫자를 float 반환 | `int(dict.get("field", 0))` 명시 |
| 시그널 핸들러 2회 호출 | load_save_data()가 init_season() 재호출 → 중복 연결 | `is_connected()` 가드 추가 |
| 시그널 핸들러 미호출 | 핸들러 파라미터 수가 시그널 정의와 불일치 | 시그널 정의와 핸들러 시그니처 일치 확인 |
| 특정 필드 save 안 됨 | save_save_data()에서 해당 필드 누락 | 저장/복원 쌍 완결성 확인 |

### 계층 3 실패 시

1. 실패한 `assert_eq`에서 실제 텍스트 vs 예상 텍스트 비교
2. 실제 텍스트가 올바른 값을 포함하지만 포맷이 다른 경우 → 포맷 문자열 수정
3. 실제 텍스트가 초기값(빌드 시 설정된 값)과 같은 경우 → 시그널 미수신 (연결 확인)
4. `await get_tree().process_frame` 누락 여부 확인

---

## 테스트 결과 기록 (ADR 연동)

버그를 발견하고 수정했을 때:

1. 회귀 테스트를 추가한다 (`tests/unit/` 또는 `tests/integration/`)
2. 아키텍처 결정을 포함하는 경우 새 ADR(`docs/architecture/NNN-*.md`)을 작성한다
3. ADR은 `technical-preferences.md` Architecture Decisions Log에 등록한다

**참고**: ADR-016(`docs/architecture/016-qa-10day-scenario-findings.md`)은  
통합 테스트로 발견된 버그와 미해결 과제(ISSUE-01~03)를 기록하고 있다.

---

## 미해결 과제 (후속 조치 필요)

| ID | 내용 | 우선순위 |
|----|------|----------|
| ISSUE-01 | SaveSystem.delete_slot() 후 ID 재사용 (ADR-009 위반) | High |
| ISSUE-02 | 손상 파일 로드 시 GUT Unexpected Errors 판정 (실동작 올바름) | Low |
| ISSUE-03 | v1 마이그레이션 테스트 실패 — 추가 조사 필요 | Medium |

상세: [ADR-016](../architecture/016-qa-10day-scenario-findings.md)
