# 설정 화면 (Settings Screen)

> **Status**: Approved (구현 완료 2026-04-17)
> **Sprint**: S9-05 (계획: S8-06, 구현: S9-05)
> **Owner**: game-designer + ui-programmer

---

## 1. Overview

게임 내 설정 화면. 볼륨 슬라이더, 뉴스 자동 감속 On/Off, 색각 모드(와이어프레임),
키 리맵(와이어프레임) 4개 컨트롤을 제공한다.

`MainScreen` 탭바 우측 ⚙ 버튼으로 오버레이 형태로 열린다.
볼륨/음소거는 `AudioManager` 기존 API(`user://audio_settings.cfg`)에 위임.
뉴스 자동 감속은 `GameClock.set_auto_slow_on_event()` + `user://game_settings.cfg` 저장.
색각 모드·키 리맵은 UI만 표시하고 비활성화 (Full Release에서 구현).

설정 화면은 **게임 중 언제든지** 접근 가능하다 (GameClock 자동 일시정지 없음).

---

## 2. Player Fantasy

음악이 너무 크다 싶을 때, 뉴스 뜰 때마다 게임이 느려지는 게 짜증날 때,
메뉴 하나로 바로 조정하고 돌아온다. 설정이 즉시 반영되고 재시작 불필요.

---

## 3. Detailed Design

### 3-1. 진입점

- `MainScreen` 탭바 우측, 스페이서 왼쪽에 ⚙ 버튼 배치
- 버튼 클릭 → 설정 오버레이 토글 (show/hide)
- ESC 키 → 닫기 (`SettingsScreen._unhandled_input`)
- × 버튼 → 닫기

GameClock은 설정 화면 진입 시 자동 일시정지하지 않는다.

### 3-2. 설정 항목

| 항목 | 컨트롤 | 기본값 | 구현 여부 | 연결 대상 |
|------|--------|--------|----------|-----------|
| 마스터 볼륨 | HSlider 0–100 | 80 | S9-05 구현 | `AudioManager.set_volume()` |
| 음소거 | CheckButton | OFF | S9-05 구현 | `AudioManager.set_muted()` |
| 뉴스 자동 감속 | CheckButton | ON | S9-05 구현 | `GameClock.set_auto_slow_on_event()` |
| 색각 모드 | OptionButton | Normal | 와이어프레임 | Full Release |
| 키 리맵 | Button "(예정)" | — | 와이어프레임 | Full Release |

- 볼륨: `HSlider` 드래그 시 `AudioManager.set_volume(value / 100.0)` 즉시 호출
- 음소거: CheckButton toggled → `AudioManager.set_muted(toggled)`
- 자동 감속: CheckButton toggled → `GameClock.set_auto_slow_on_event(toggled)` + `_save_game_settings()`
- 색각 모드·키 리맵: `disabled = true`, 마우스 오버 툴팁 "(예정)"

### 3-3. 설정 파일 구조

오디오 설정: `AudioManager` 기존 `user://audio_settings.cfg` 그대로 사용.

게임 설정: `SettingsScreen` 자체가 `user://game_settings.cfg`에 저장.

```ini
[gameplay]
auto_slow_on_news=true
```

### 3-4. 오버레이 씬 구조

```
SettingsScreen (Control, anchor=FULL_RECT, z_index=1)
  └─ PanelContainer (PRESET_CENTER, min_size=(360, 0))
       └─ MarginContainer
            └─ VBoxContainer
                 ├─ HBoxContainer (헤더)
                 │    ├─ Label "설정"
                 │    └─ Button "×"
                 ├─ HSeparator
                 ├─ [오디오] Label 섹션 헤더
                 ├─ HBoxContainer (볼륨 슬라이더 행)
                 ├─ HBoxContainer (음소거 행)
                 ├─ [게임플레이] Label 섹션 헤더
                 ├─ HBoxContainer (뉴스 자동 감속 행)
                 ├─ [접근성] Label 섹션 헤더
                 ├─ HBoxContainer (색각 모드 행, disabled)
                 └─ HBoxContainer (키 리맵 행, disabled)
```

---

## 4. Formulas

### F1. 볼륨 변환

```
# UI → AudioManager
AudioManager 볼륨 = slider_value / 100.0    ## slider_value: [0, 100]

# AudioManager → UI (초기값 읽기)
slider_value = round(AudioManager.get_volume() * 100.0)
```

*(dB 변환은 `AudioManager._apply_volume()` 내부에서 처리)*

### F2. 뉴스 감속 적용

```
# TradingScreen._on_news_received():
if GameClock.get_auto_slow_on_event() and GameClock.get_speed_multiplier() > 1.0:
    GameClock.set_speed(1.0)

# 기존 const 교체:
## const AUTO_SLOW_ON_EVENT: bool = true   → 삭제
## var _auto_slow_on_event: bool = true    → 추가 (get/set API 제공)
```

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| `game_settings.cfg` 없음 (최초 실행) | 기본값(`auto_slow=true`) 사용. 파일 생성은 첫 변경 시점 |
| 볼륨 슬라이더 0 설정 | `AudioManager.set_volume(0.0)` → dB -80. 음소거(`_muted`) 플래그와 독립 |
| 음소거 ON + 볼륨 0 | 모두 무음. 음소거 해제 시 볼륨 0 상태로 복귀 (볼륨 자체는 변경 안 됨) |
| 설정 화면 열린 채 뉴스 발생 | SettingsScreen은 오버레이 — 뒤에서 게임 계속 진행. `auto_slow_on_news=false` 변경 즉시 적용 (다음 뉴스부터) |
| `auto_slow_on_news = false` 상태에서 뉴스 발생 | GameClock 속도 변경 없음. 뉴스 카드 표시는 영향 없음 |
| 비활성 컨트롤(색각/키리맵) 클릭 | `disabled=true`라 입력 이벤트 없음. 툴팁 "(예정)" 표시 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `AudioManager` (autoload) | SettingsScreen → | `set_volume()`, `get_volume()`, `set_muted()`, `is_muted()` |
| `GameClock` (autoload) | SettingsScreen → | `set_auto_slow_on_event(bool)`, `get_auto_slow_on_event() → bool` (S9-05 신규) |
| `MainScreen` | MainScreen → SettingsScreen | 인스턴스 생성 + ⚙ 버튼 토글 |
| `TradingScreen` | TradingScreen → | 기존 `GameClock.AUTO_SLOW_ON_EVENT` 참조를 `get_auto_slow_on_event()` 호출로 변경 |
| `ConfigFile` (Godot built-in) | SettingsScreen | `user://game_settings.cfg` 읽기/쓰기 |

---

## 7. Tuning Knobs

| 변수 | 위치 | 기본값 | 범위 | 영향 |
|------|------|--------|------|------|
| `DEFAULT_VOLUME` | `AudioManager` | 1.0 | 0.0~1.0 | 최초 실행 볼륨 (기존 상수) |
| `DEFAULT_AUTO_SLOW` | `SettingsScreen` | `true` | bool | 뉴스 자동 감속 초기 상태 (cfg 없을 때) |
| `SETTINGS_PATH` | `SettingsScreen` | `"user://game_settings.cfg"` | — | 게임 설정 파일 경로 |
| `PANEL_MIN_WIDTH` | `SettingsScreen` | `360` | px | 오버레이 패널 최소 너비 |

---

## 8. Acceptance Criteria

| # | 조건 | 판정 방법 |
|---|------|---------|
| AC-01 | ⚙ 버튼 클릭 시 설정 오버레이 표시, 재클릭 시 닫힘 | 수동 클릭 확인 |
| AC-02 | 볼륨 슬라이더 조작 시 `AudioManager.get_volume()` 즉시 반영 | 단위 테스트 |
| AC-03 | 음소거 CheckButton 토글 시 `AudioManager.is_muted()` 즉시 반영 | 단위 테스트 |
| AC-04 | 자동 감속 CheckButton 토글 시 `GameClock.get_auto_slow_on_event()` 즉시 반영 | 단위 테스트 |
| AC-05 | 자동 감속 설정이 게임 재시작 후 복원됨 (`user://game_settings.cfg`) | 단위 테스트 (cfg 저장/재로드) |
| AC-06 | ESC 또는 × 버튼 → 오버레이 닫힘 | 수동 확인 |
| AC-07 | 색각 모드·키 리맵 컨트롤은 `disabled=true` 와이어프레임 | 수동 확인 |
| AC-08 | `--export-release` 빌드 성공, SCRIPT ERROR 없음 | QA Lead 빌드 검증 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
이 기능은 `MainScreen._build_ui()` → ⚙ 버튼 pressed → `_settings_screen.visible` 토글

### 호출 경로

**GameClock 변경 (const → var)**
- [x] `game_clock.gd`: `const AUTO_SLOW_ON_EVENT: bool = true` → `var _auto_slow_on_event: bool = true`
- [x] `game_clock.gd`: `get_auto_slow_on_event() → bool` 추가
- [x] `game_clock.gd`: `set_auto_slow_on_event(value: bool)` 추가
- [x] `game_clock.gd`: `reset()` 에 `_auto_slow_on_event = true` 추가

**TradingScreen 참조 수정**
- [x] `trading_screen.gd:248`: `GameClock.AUTO_SLOW_ON_EVENT` → `GameClock.get_auto_slow_on_event()`

**SettingsScreen 신규**
- [x] `src/ui/settings_screen.gd` 신규 작성
- [x] `_ready()`: `_load_settings()` → `GameClock.set_auto_slow_on_event()`; AudioManager 상태 읽어 UI 초기화
- [x] 볼륨 HSlider `value_changed` → `AudioManager.set_volume(v / 100.0)`
- [x] 음소거 CheckButton `toggled` → `AudioManager.set_muted(b)`
- [x] 자동 감속 CheckButton `toggled` → `GameClock.set_auto_slow_on_event(b)` + `_save_settings()`
- [x] 색각 모드 OptionButton: `disabled=true`, 툴팁 "(예정)"
- [x] 키 리맵 Button: `disabled=true`, 툴팁 "(예정)"
- [x] ESC → `hide()`
- [x] × 버튼 → `hide()`

**MainScreen 변경**
- [x] `main_screen.gd`: `_settings_screen: SettingsScreen` 멤버 추가
- [x] `main_screen.gd`: ⚙ 버튼 탭바에 추가
- [x] `main_screen.gd`: `_toggle_settings()` → `_settings_screen.visible` 토글

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-02 | `tests/unit/test_settings_screen.gd` | `test_volume_slider_updates_audio_manager()` |
| AC-03 | `tests/unit/test_settings_screen.gd` | `test_mute_toggle_updates_audio_manager()` |
| AC-04 | `tests/unit/test_settings_screen.gd` | `test_auto_slow_toggle_updates_game_clock()` |
| AC-05 | `tests/unit/test_settings_screen.gd` | `test_auto_slow_persists_and_loads()` |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 _______ (2026-04-17)
