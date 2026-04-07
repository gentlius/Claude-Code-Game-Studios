# Audio System — GDD

**Status**: Approved (2026-04-07, QA Lead 리뷰 완료)  
**Sprint**: S5-02, S5-08  
**Owner**: audio-director + gameplay-programmer

---

## 1. Overview

AudioManager autoload을 통해 게임 이벤트에 SFX를 연결하는 기반 시스템.
Phase 1 (Alpha): 4개 핵심 이벤트 SFX + 볼륨/음소거 설정 저장.
실 에셋 미확보 구간에서는 GDScript로 생성된 프로그래매틱 placeholder 사용.

---

## 2. Player Fantasy

거래가 체결될 때 피드백 소리가 난다.
레벨업은 특별하게 느껴진다.
뉴스가 뜨기 전에 소리로 먼저 알 수 있다.

---

## 3. Detailed Design

### 3-1 AudioManager Autoload

- 파일: `src/core/audio_manager.gd`
- 클래스: `AudioManager` (autoload)
- 채널: `AudioStreamPlayer` 4개 (Master bus; Beta 단계에서 UI/SFX 버스 분리 예정)

### 3-2 SFX 이벤트 4종

| 이벤트 ID | 트리거 | 설명 |
|----------|--------|------|
| `sfx_order_filled` | `OrderEngine.on_order_filled` | 주문 체결음 |
| `sfx_level_up` | `XpSystem.on_level_up` | 레벨업 |
| `sfx_vi_alert` | `PriceEngine.on_vi_triggered` | VI(변동성 완화) 발동 |
| `sfx_news_notify` | `NewsEventSystem.on_news_display` | 뉴스 알림 |

### 3-3 볼륨 설정

- 음소거(mute) / 마스터 볼륨(0.0~1.0) 설정 지원
- 설정은 `user://audio_settings.cfg` 에 저장 (ConfigFile)
- 앱 시작 시 자동 로드

### 3-4 Placeholder SFX (S5-08 연동)

실 에셋 교체 전까지 `AudioStreamWAV` 를 GDScript로 생성해 메모리에서 직접 재생.
실 에셋 교체 시 `AudioManager._load_sfx()` 에서 파일 경로만 바꾸면 된다.

---

## 4. Formulas

볼륨 선형 → dB 변환:
```
db = linear_to_db(volume_linear)   # Godot built-in
```

---

## 5. Edge Cases

| Code | 상황 | 처리 |
|------|------|------|
| EC-01 | SFX 파일 없음 / placeholder 생성 실패 | push_warning, 무음 재생 |
| EC-02 | 음소거 상태 | 재생 호출 자체를 스킵 (CPU 절약) |
| EC-03 | 설정 파일 읽기 실패 | 기본값(볼륨 1.0, 음소거 false) 사용 |
| EC-04 | (해소됨) on_vi_triggered 시그널 확인됨 | `PriceEngine`에 시그널 존재. EC-04 방어 분기 불필요. |

---

## 6. Dependencies

- `OrderEngine.on_order_filled` 시그널
- `XpSystem.on_level_up` 시그널
- `PriceEngine` — on_vi_triggered 시그널 (미구현 시 EC-04 적용)
- `NewsEventSystem.on_news_display` 시그널
- `SaveSystem` — 설정 저장과는 별도 (ConfigFile 사용)

---

## 7. Tuning Knobs

| 이름 | 기본값 | 안전 범위 | 게임플레이 영향 |
|------|--------|-----------|----------------|
| `DEFAULT_VOLUME` | 1.0 | 0.0~1.0 | 초기 볼륨. 0이면 무음 시작 |
| `SETTINGS_PATH` | `user://audio_settings.cfg` | Godot `user://` 접두사 유지 | 변경 시 기존 설정 파일 접근 불가 |
| `SFX_ORDER_FREQ` | 220.0 Hz | 80~2000 Hz (가청 주파수) | 체결음 음높이. 낮을수록 둔탁, 높을수록 날카로움 |
| `SFX_LEVEL_FREQS` | [261.6, 329.6, 392.0] Hz | 각 80~4000 Hz | 레벨업 아르페지오 음정. C4→E4→G4 장3화음 느낌 |
| `SFX_VI_FREQS` | [330.0, 440.0] Hz | 각 80~4000 Hz | VI 경보 2음. 상승 인터벌이 긴박감 부여 |
| `SFX_NEWS_FREQS` | [440.0, 330.0] Hz | 각 80~4000 Hz | 뉴스 알림 하강 2음. 체결음과 대비되도록 설계 |

---

## 8. Acceptance Criteria

| AC | 조건 |
|----|------|
| AC-01 | `AudioManager` autoload project.godot 등록 확인 |
| AC-02 | 주문 체결 시 체결음 인게임 발동 확인 |
| AC-03 | 레벨업 시 레벨업음 발동 확인 |
| AC-04 | VI 발동 시 VI 경보음 발동 확인 |
| AC-05 | 뉴스 발행 시 뉴스 알림음 발동 확인 |
| AC-06 | 음소거 설정 후 재시작 시 음소거 유지 |
| AC-07 | 볼륨 설정 저장·복원 |
| AC-08 | `--export-release` 빌드 성공 + SCRIPT ERROR 없음 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `AudioManager._ready()` → 시그널 연결 + SFX placeholder 생성 + 설정 로드

### 호출 경로
- [x] `OrderEngine.on_order_filled` → `AudioManager._on_order_filled()`
- [x] `XpSystem.on_level_up` → `AudioManager._on_level_up()`
- [x] `NewsEventSystem.on_news_display` → `AudioManager._on_news_display()`
- [x] `PriceEngine.on_vi_triggered` → `AudioManager._on_vi_triggered()` (시그널 존재 시)
- [x] `AudioManager` → `project.godot` autoload 등록

### AC → 테스트 매핑
테스트는 시그널 연결 확인 + 음소거 상태에서 재생 skip 확인 수준.
SFX 실제 발음은 인게임 확인.

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_audio_manager.gd` | `test_autoload_signals_connected()` |
| AC-06/07 | `tests/unit/test_audio_manager.gd` | `test_mute_persists_after_reload()` |
| AC-02~05 | E2E 인게임 확인 | 각 이벤트 발동 후 사운드 청취 |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 2026-04-07 (SCRIPT ERROR 0)
