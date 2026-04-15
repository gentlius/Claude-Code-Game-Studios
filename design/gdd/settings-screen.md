# 설정 화면 (Settings Screen)

> **Status**: In Review
> **Sprint**: Sprint 8 (S8-06)
> **Owner**: game-designer + ui-programmer

---

## 1. Overview

게임 내 설정 화면. 볼륨, 게임 속도 자동 감속, 접근성(reduced motion) 옵션을 제공한다.
키 리맵은 Beta 범위에서 기본 항목만 지원하며 Full Release에서 완성한다.

설정값은 `user://settings.cfg` 단일 파일에 저장된다. 기존 `AudioManager`가 사용하는
`user://audio_settings.cfg`는 이 스프린트에서 `settings.cfg`로 통합 마이그레이션한다.

설정 화면은 **게임 중 언제든지** 접근 가능하다 (GameClock 자동 일시정지 없음 — 플레이어 선택).

---

## 2. Player Fantasy

음악이 너무 크다 싶을 때, 뉴스 뜰 때마다 게임이 느려지는 게 짜증날 때,
메뉴 하나로 바로 조정하고 돌아온다. 설정이 즉시 반영되고 재시작 불필요.

---

## 3. Detailed Design

### 3-1. 진입점

- 트레이딩 화면 우상단 ⚙ 버튼 → 설정 화면 오버레이 (모달)
- ESC 키 → 닫기

GameClock은 설정 화면 진입 시 자동 일시정지하지 않는다.
플레이어가 원하면 `[게임 일시정지]` 체크박스로 수동 일시정지 가능.

### 3-2. 설정 항목

#### 카테고리 1: 오디오

| 항목 | 컨트롤 | 기본값 | 저장키 |
|------|--------|--------|--------|
| 마스터 볼륨 | 슬라이더 0~100 | 80 | `audio/master_volume` |
| 음소거 | 토글 | OFF | `audio/muted` |

- 슬라이더 드래그 시 즉시 `AudioManager.set_volume()` 호출 → 실시간 반영
- `AudioManager.set_volume()` / `set_mute()` 내부에서 `settings.cfg` 저장

#### 카테고리 2: 게임플레이

| 항목 | 컨트롤 | 기본값 | 저장키 |
|------|--------|--------|--------|
| 뉴스 자동 감속 | 토글 On/Off | ON | `gameplay/auto_slow_on_news` |

- ON: 뉴스 이벤트 발생 시 `GameClock`이 자동으로 1× 속도로 전환 (현재 `AUTO_SLOW_ON_EVENT = true` 하드코딩 → 이 설정으로 대체)
- OFF: 뉴스 발생 시 속도 변경 없음

#### 카테고리 3: 접근성

| 항목 | 컨트롤 | 기본값 | 저장키 |
|------|--------|--------|--------|
| 모션 감소 (Reduced Motion) | 토글 On/Off | OFF | `accessibility/reduced_motion` |

- ON: 카드 슬라이드인/아웃 애니메이션 제거, 틱 점프 없이 즉시 전환
- 파티클/VFX는 Beta 범위에서 reduced_motion 연동 제외 (Full Release)

#### 카테고리 4: 키 리맵 (Beta 최소 범위)

| 항목 | 기본값 | 저장키 |
|------|--------|--------|
| 일시정지 | Space | `keys/pause` |
| 속도 1× | 1 | `keys/speed_1` |
| 속도 2× | 2 | `keys/speed_2` |
| 속도 4× | 3 | `keys/speed_3` |
| F1 트레이딩 | F1 | `keys/tab_trading` |
| F2 포트폴리오 | F2 | `keys/tab_portfolio` |
| F3 성장 | F3 | `keys/tab_growth` |

- 각 항목 클릭 → 입력 대기 상태 → 키 입력 → 저장
- 충돌 검사: 동일 키에 두 가지 액션 할당 시 경고 표시
- `[기본값 복원]` 버튼 → 전체 키 리맵 초기화

### 3-3. 설정 파일 구조 (`user://settings.cfg`)

```ini
[audio]
master_volume=0.8
muted=false

[gameplay]
auto_slow_on_news=true

[accessibility]
reduced_motion=false

[keys]
pause=32
speed_1=49
speed_2=50
speed_3=51
tab_trading=16777268
tab_portfolio=16777269
tab_growth=16777270
```

### 3-4. 마이그레이션 — `audio_settings.cfg` → `settings.cfg`

`AudioManager._load_settings()`:
1. `settings.cfg` 로드 시도
2. 실패(파일 없음) 시 → `audio_settings.cfg` 로드 시도 (레거시 폴백)
3. 레거시 로드 성공 시 → `settings.cfg`로 즉시 재저장 후 `audio_settings.cfg` 삭제

---

## 4. Formulas

### F1. 볼륨 → dB 변환

```
volume_db = linear_to_db(master_volume)   ## master_volume: [0.0, 1.0]
muted_db  = -80.0                          ## 사실상 무음
```

*(기존 `AudioManager._apply_volume()` 로직 그대로 유지)*

### F2. 뉴스 감속 적용

```
if auto_slow_on_news AND current_event_is_news:
    GameClock.set_speed(1.0)
    ## 이전 속도 복원 없음 — 플레이어가 수동으로 속도 변경

## 기존 게임클락 상수 대체:
## const AUTO_SLOW_ON_EVENT: bool = true
## → UserSettings.get_bool("gameplay/auto_slow_on_news", true)
```

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| `settings.cfg` 없음 (최초 실행) | 기본값 적용. 파일 생성은 첫 변경 시점 |
| 볼륨 슬라이더 0 설정 | dB 최솟값 적용 (-80dB). 음소거 토글과 독립 |
| 키 리맵 충돌 | 동일 키 중복 할당 시 UI에 빨간 경고. 저장 허용하되 실행 시 충돌 액션 중 먼저 등록된 것만 발동 |
| 설정 화면 열린 채 게임 속도 변경 | 설정 화면은 오버레이 — 뒤에서 게임 계속 진행. 뉴스 감속 토글이 현재 게임 상태에 즉시 영향 없음 (다음 뉴스부터 적용) |
| `auto_slow_on_news = false` 상태에서 뉴스 발생 | GameClock 속도 변경 없음. 루머 카드(S3) 표시는 영향 없음 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `AudioManager` | Hard | `set_volume()`, `set_mute()` API (이미 존재 ✅). `SETTINGS_PATH` → `settings.cfg`로 변경 |
| `GameClock` | Hard | `AUTO_SLOW_ON_EVENT` 상수 → `UserSettings` 참조로 교체 |
| `UserSettings` | Hard | 신규 Autoload 필요. `get_bool()`, `get_float()`, `set_value()`, `save()` |
| `TradingScreen` | Hard | ⚙ 버튼 + 설정 화면 오버레이 연결 |
| `InputMap` (Godot) | Soft | 키 리맵: `InputMap.action_erase_events()`, `InputMap.action_add_event()` |

---

## 7. Tuning Knobs

| 변수 | 위치 | 기본값 | 범위 | 영향 |
|------|------|--------|------|------|
| `DEFAULT_VOLUME` | `AudioManager` | 0.8 | 0.0~1.0 | 최초 실행 볼륨 |
| `auto_slow_on_news` 기본값 | `UserSettings` 또는 상수 | true | — | 뉴스 자동 감속 초기 상태 |

---

## 8. Acceptance Criteria

| # | 조건 | 판정 방법 |
|---|------|---------|
| AC-01 | ⚙ 버튼 클릭 시 설정 화면 오버레이 표시 | 클릭 → 오버레이 확인 |
| AC-02 | 볼륨 슬라이더 조작 시 즉시 음량 반영 | 슬라이더 드래그 중 SFX 재생하여 볼륨 변화 확인 |
| AC-03 | 설정값이 재시작 후에도 유지됨 (`user://settings.cfg`) | 볼륨 변경 → 게임 재시작 → 볼륨 동일 확인 |
| AC-04 | `auto_slow_on_news = OFF` 시 뉴스 발동해도 속도 유지 | 설정 OFF → 2× 속도 → 뉴스 발동 → 2× 유지 확인 |
| AC-05 | `auto_slow_on_news = ON` 시 뉴스 발동 시 1× 전환 | 설정 ON → 2× 속도 → 뉴스 발동 → 1× 전환 확인 |
| AC-06 | 키 리맵 저장 후 재시작 시 적용 | F1 키 리맵 변경 → 재시작 → 새 키로 탭 전환 확인 |
| AC-07 | `audio_settings.cfg` 레거시 마이그레이션 정상 동작 | 구파일 있는 상태로 실행 → `settings.cfg` 생성 + 구파일 삭제 확인 |
| AC-08 | `--export-release` 빌드 성공, SCRIPT ERROR 없음 | QA Lead 빌드 검증 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `TradingScreen._on_settings_button_pressed()` → `SettingsScreen` 오버레이 표시

### 호출 경로

**UserSettings Autoload (신규)**
- [ ] `src/core/user_settings.gd` 신규 작성: `get_bool()`, `get_float()`, `set_value()`, `save()`, `load()`
- [ ] `project.godot` autoload 등록: `UserSettings = res://src/core/user_settings.gd`

**AudioManager 마이그레이션**
- [ ] `audio_manager.gd`: `SETTINGS_PATH` → `UserSettings`로 읽기/쓰기 위임
- [ ] `audio_manager.gd`: 레거시 `audio_settings.cfg` 폴백 → 마이그레이션 → 삭제

**GameClock 연동**
- [ ] `game_clock.gd`: `AUTO_SLOW_ON_EVENT` 상수 → `UserSettings.get_bool("gameplay/auto_slow_on_news", true)` 교체

**설정 화면 UI**
- [ ] `src/ui/settings_screen.gd` 신규 작성: 4개 카테고리 패널
- [ ] 볼륨 슬라이더 → `AudioManager.set_volume()` 실시간 연결
- [ ] 뉴스 자동 감속 토글 → `UserSettings.set_value()` + 저장
- [ ] 접근성 토글 → `UserSettings.set_value()` + 저장
- [ ] 키 리맵 7개 항목 → `InputMap` 연동 + `UserSettings` 저장
- [ ] `[기본값 복원]` 버튼 → 키 리맵 전체 초기화
- [ ] TradingScreen에 ⚙ 버튼 추가 → `settings_screen.gd` 인스턴스 표시

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-03 | `tests/unit/test_user_settings.gd` | `test_settings_persist_after_reload()` |
| AC-04 | `tests/unit/test_user_settings.gd` | `test_auto_slow_off_no_speed_change()` |
| AC-05 | `tests/unit/test_user_settings.gd` | `test_auto_slow_on_triggers_1x()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
