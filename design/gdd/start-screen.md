# Start Screen — GDD

**Status**: In Review
**Sprint**: S5
**Owner**: ui-programmer / gameplay-programmer

---

## 1. Overview

앱 시작 시 로고 스플래시(2초) → 슬롯 선택 화면(Start Screen) 순으로 진입한다.
Start Screen에서 기존 슬롯을 클릭해 이어하거나, 새 슬롯을 생성해 새 게임을 시작한다.
슬롯은 무제한이며 카드마다 레벨·시즌 번호·픽션 날짜·평가금액을 표시한다.
인게임에서 F4 나가기로 언제든 이 화면으로 돌아올 수 있다.

---

## 2. Player Fantasy

내 기록이 고스란히 남아 있다. 어느 슬롯에서 어디까지 왔는지 한눈에 보인다.
원하는 슬롯을 골라 이어하거나, 새 도전을 시작하거나, 여러 플레이를 번갈아 할 수 있다.

---

## 3. Detailed Design

### 3-1. 진입 흐름

```
앱 시작
  └─ SplashScreen (로고 2초, 클릭/스페이스/엔터 스킵)
       └─ StartScreen (슬롯 목록)
            ├─ 슬롯 클릭 → SaveSystem.load_slot(id) → MainScreen (인트로 없음)
            └─ [새 게임 +] → 이름 입력 팝업 → 확인
                              → IntroSequence.play()
                                → MainScreen
                                    └─ F4 / [나가기] → StartScreen (저장 없이)
```

### 3-2. SplashScreen

| 항목 | 값 |
|------|----|
| 배경 | `#0a0a0a` |
| 로고 | 네이티브 노드로 구현 (SVG `<text>` 미지원). 상승 바 차트 ColorRect 5개 + 구분선 + "SEED" 72px / "M O N E Y" 28px Label 2개. 화면 중앙 |
| 자동 전환 | `SPLASH_DURATION`(2.0s) 경과 후 StartScreen으로 페이드 전환 |
| 스킵 입력 | 마우스 좌클릭, Space, Enter |
| 전환 페이드 | `SPLASH_FADE_DURATION`(0.3s) 페이드아웃 → StartScreen |
| 중복 방지 | `_transitioning` 플래그, 전환 시작 후 추가 입력 무시 |

### 3-3. StartScreen 레이아웃

```
┌──────────────────────────────────────────────────┐
│  SEED MONEY                          [새 게임 +]  │
│──────────────────────────────────────────────────│
│  ┌──────────────────────────────────────────┐    │
│  │ 나의 첫 도전                        [삭제] │    │
│  │ Lv.4 · 시즌 2 · 2주차 3일                │    │
│  │ 평가금액  ₩1,250,000                     │    │
│  │ 저장: 2026-04-07                         │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │ 슬롯 2                              [삭제] │    │
│  │ ...                                      │    │
│  └──────────────────────────────────────────┘    │
│  (슬롯 0개: "저장된 게임이 없습니다.")              │
└──────────────────────────────────────────────────┘
```

슬롯 목록은 `saved_at` 기준 최신순 정렬.

### 3-4. 슬롯 카드 표시 정보

| 항목 | 출처 | 포맷 |
|------|------|------|
| 슬롯 이름 | `save_index.json` — 유저 편집 가능 | 자유 문자열 (최대 `SLOT_NAME_MAX_LENGTH`자) |
| 레벨 | `XpSystem.current_level` 캐시 | `Lv.{N}` |
| 시즌 번호 | `SeasonManager.seasons_played + 1` 캐시 | `시즌 {N}` |
| 픽션 날짜 | `GameClock.current_week / current_day` 캐시 | `{N}주차 {M}일` |
| 평가금액 | 저장 시점 계산·캐시 | `₩{N:,}` |
| 저장 시각 | `save_index.json saved_at` | `YYYY-MM-DD` |

**평가금액** = `sim_cash + Σ(holding.quantity × current_price)`  
저장 시점에 계산하여 `save_index.json`에 캐시. 로드 없이 표시.

**슬롯 이름 인라인 편집**: 이름 텍스트 클릭 → LineEdit 진입 → Enter 또는 포커스 해제로 확정
→ 빈 칸이면 원래 이름 복원 → `save_index.json` 즉시 갱신.

### 3-5. 새 게임 플로우

1. `[새 게임 +]` 버튼 클릭
2. 이름 입력 팝업 표시
   - 자동 추천 이름: `"슬롯 " + str(next_id + 1)`
   - 최대 `SLOT_NAME_MAX_LENGTH`자, 빈 칸이면 `[시작]` 버튼 비활성
3. `[시작]` 확인 → 새 슬롯 ID 할당 → `save_index.json` 갱신
4. `IntroSequence.play()` 호출 (항상 재생)
5. `IntroSequence.intro_finished` 시그널 → `MainScreen` 진입
6. `MainScreen._ready()` 완료 직후 `SaveSystem.save_slot(id)` — 초기 상태 저장

**슬롯 ID**: `max(기존 id 목록) + 1` (0부터 시작, 삭제 후 공백 미재사용).

### 3-6. 슬롯 삭제

1. 슬롯 카드 `[삭제]` 버튼 클릭
2. 확인 팝업: `"'{이름}' 슬롯을 삭제합니다. 복구할 수 없습니다."`
3. `[확인]` → `SaveSystem.delete_slot(id)` → `save_index.json` 갱신 → 목록 새로고침

### 3-7. F4 나가기

| 항목 | 규격 |
|------|------|
| 트리거 | F4 키 또는 `MainScreen` 탭바 `[나가기]` 버튼 (F1/F2/F3 우측) |
| 동작 | MainScreen → StartScreen 전환 (저장 없음) |
| 블로킹 조건 | `SavingOverlay` 표시 중 → F4 무반응 |
| 현재 슬롯 ID | StartScreen에서 선택한 슬롯 ID를 `SaveSystem.active_slot_id`로 유지 |

---

## 4. Formulas

```
평가금액 = sim_cash + Σ(holding.quantity × current_price)

슬롯 ID 할당:
  next_id = max(existing_ids) + 1  # 기존 슬롯 없으면 0
  # 삭제된 ID 재사용 없음

자동 슬롯 이름 = "슬롯 " + str(next_id + 1)

슬롯 목록 정렬 = saved_at DESC (최신순)
```

---

## 5. Edge Cases

| Code | 상황 | 처리 |
|------|------|------|
| EC-01 | 슬롯 0개 | "저장된 게임이 없습니다." 문구 표시, `[새 게임 +]` 버튼만 강조 |
| EC-02 | `save_index.json` 없음 | 빈 슬롯 목록으로 StartScreen 표시 (EC-01과 동일 처리) |
| EC-03 | 슬롯 파일 손상 (JSON 파싱 실패) | 해당 카드에 "⚠ 손상된 파일" 표시, 선택 불가, `[삭제]`만 가능 |
| EC-04 | 이름 팝업에서 빈 칸 확인 | `[시작]` 버튼 비활성, "이름을 입력하세요" 힌트 표시 |
| EC-05 | 이름 `SLOT_NAME_MAX_LENGTH` 초과 입력 | LineEdit `max_length` 속성으로 입력 차단 |
| EC-06 | 저장 중 F4 입력 | `SavingOverlay` 표시 중이면 무반응 |
| EC-07 | SplashScreen 중 연속 클릭 | `_transitioning` 플래그로 중복 전환 방지 |
| EC-08 | 인라인 편집 후 빈 칸 확정 | 원래 이름 복원, `save_index.json` 변경 없음 |
| EC-09 | 삭제 팝업에서 [취소] | 팝업만 닫힘, 슬롯 유지 |
| EC-10 | 슬롯 로드 중 파일 없음 | `push_error`, StartScreen으로 복귀, "파일을 불러올 수 없습니다." 알림 |

---

## 6. Dependencies

| 의존 방향 | 시스템 | 설명 |
|----------|--------|------|
| StartScreen → | `SaveSystem` | `load_slot()`, `delete_slot()`, `get_slot_list()` |
| StartScreen → | `IntroSequence` | 새 게임 시 `play()` 호출 |
| StartScreen → | `MainScreen` | 슬롯 로드 또는 새 게임 후 씬 전환 |
| MainScreen → | StartScreen | F4 나가기 시 전환 |
| SplashScreen → | StartScreen | `SPLASH_DURATION` 후 자동 전환 |

역방향:
- `save-load.md` §6: StartScreen이 `load_slot()` / `delete_slot()` 호출자
- `intro-sequence.md` §6: StartScreen이 `play()` 호출자
- `trading-screen.md` §6: F4 → StartScreen 전환 명시

---

## 7. Tuning Knobs

| 이름 | 기본값 | 안전 범위 | 게임플레이 영향 |
|------|--------|-----------|----------------|
| `SPLASH_DURATION` | 2.0s | 0.5 ~ 5.0 | 로고 노출 시간 |
| `SPLASH_FADE_DURATION` | 0.3s | 0.1 ~ 1.0 | 스플래시 전환 페이드 속도 |
| `SLOT_NAME_MAX_LENGTH` | 20 | 8 ~ 40 | 슬롯 이름 최대 글자 수 |

---

## 8. Acceptance Criteria

| AC | 조건 |
|----|------|
| AC-01 | 앱 시작 시 SplashScreen 로고가 `SPLASH_DURATION`(2초)간 표시된 후 StartScreen으로 자동 전환 |
| AC-02 | SplashScreen 중 클릭/스페이스/엔터 → 즉시 StartScreen 전환 |
| AC-03 | 슬롯 0개일 때 "저장된 게임이 없습니다." 표시, `[새 게임 +]` 버튼 표시 |
| AC-04 | 슬롯 카드에 이름·레벨·시즌·픽션날짜·평가금액·저장시각 모두 표시 |
| AC-05 | 슬롯 클릭 → 해당 세이브 로드 → MainScreen 진입 (인트로 없음) |
| AC-06 | `[새 게임 +]` → 이름 팝업 → 확인 → IntroSequence 재생 → MainScreen 진입 |
| AC-07 | 새 게임 후 MainScreen 진입 직후 초기 상태 자동 저장 |
| AC-08 | 이름 팝업에서 빈 칸 → `[시작]` 버튼 비활성 |
| AC-09 | 슬롯 이름 인라인 편집 후 확정 → `save_index.json` 즉시 갱신 |
| AC-10 | `[삭제]` → 확인 팝업 → 파일 삭제 → 목록 갱신 |
| AC-11 | F4 → 저장 없이 StartScreen 복귀 |
| AC-12 | 저장 중 F4 → 무반응 |
| AC-13 | 손상된 슬롯 → "⚠ 손상된 파일" 표시, 선택 불가, `[삭제]` 가능 |
| AC-14 | 슬롯 목록 최신순(saved_at DESC) 정렬 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `game_main.gd._ready()` → SplashScreen 씬 인스턴스화 → `add_child()`
- `SplashScreen.splash_finished` → StartScreen 씬 로드
- `StartScreen.slot_selected(id)` → `SaveSystem.load_slot(id)` → MainScreen
- `StartScreen.new_game_confirmed(name)` → `IntroSequence.play()` → MainScreen
- `trading_screen.gd._input(event)` F4 감지 → StartScreen 표시

### 호출 경로
- [ ] `SplashScreen`: Timer(`SPLASH_DURATION`) + 입력 처리 → `splash_finished` 시그널
- [ ] `StartScreen`: `SaveSystem.get_slot_list()` → 슬롯 카드 동적 생성
- [ ] `SaveSystem.get_slot_list()`: `save_index.json` 읽기 → `Array[Dictionary]` 반환
- [ ] `SaveSystem.load_slot(id)`: `save_slot_{id}.json` 읽기 → 각 시스템 `load_save_data()`
- [ ] `SaveSystem.delete_slot(id)`: `save_slot_{id}.json` 삭제 + `save_index.json` 갱신
- [ ] `SaveSystem.active_slot_id`: 현재 활성 슬롯 ID 보관 (로드 또는 새 게임 시 세팅)
- [ ] `IntroSequence.play()`: 씬 인스턴스화 → `add_child()` → `intro_finished` → 씬 제거
- [ ] F4 핸들러: `trading_screen.gd` — `SavingOverlay` 미표시 시에만 StartScreen 전환

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-05 | `tests/unit/test_save_system.gd` | `test_load_slot_restores_data()` |
| AC-07 | `tests/unit/test_save_system.gd` | `test_new_game_saves_initial_state()` |
| AC-10 | `tests/unit/test_save_system.gd` | `test_delete_slot_removes_files()` |
| AC-13 | `tests/unit/test_save_system.gd` | `test_corrupted_slot_detected()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
