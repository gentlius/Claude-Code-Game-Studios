# Audio Asset Download Guide

**작성일**: 2026-04-07  

Freesound.org에서 직접 다운로드 필요. 로그인 후 각 링크에서 Download 버튼 클릭.  
OGG 포맷으로 다운로드하거나 WAV → OGG 변환(Audacity).

---

## BGM

### S-01 — 스타트 스크린 배경 음악

**파일명**: `bgm/bgm_start_screen.ogg`  
**트랙**: "Action music loop with dark ambient drones"  
**크리에이터**: burning-mir  
**Freesound ID**: 155139  
**URL**: https://freesound.org/people/burning-mir/sounds/155139/  
**라이선스**: CC0 (공개 도메인, 크레딧 불필요)  
**길이**: 29초 (루프 가능, 설명에 "Perfectly loopable" 명시)  
**처리**: 다운로드 후 Audacity로 루프 포인트 확인. Godot에서 `loop_mode = LOOP_FORWARD` 설정.

---

## SFX

### S-02 — 로고 스팅 (SplashScreen)

**파일명**: `sfx/sfx_logo_sting.ogg`  
**트랙**: "Intro-Logo Sound.wav"  
**크리에이터**: pcruzn  
**Freesound ID**: 335860  
**URL**: https://freesound.org/people/pcruzn/sounds/335860/  
**라이선스**: CC BY 4.0 (크레딧 필요 — 아래 §크레딧 참조)  
**길이**: 7.3초  
**처리**: Audacity에서 앞 1.5~2초 부분 트리밍. 로고 페이드인 타이밍에 맞춤.

> **대안**: Bfxr (https://www.bfxr.net) → Tone 카테고리 → Frequency 낮음→높음 sweep, 길이 1.0s

---

### S-03 — 저장 완료 (SavingOverlay)

**파일명**: `sfx/sfx_save_complete.ogg`  
**트랙**: "Blip Wave"  
**크리에이터**: Breviceps  
**Freesound ID**: 452998  
**URL**: https://freesound.org/people/Breviceps/sounds/452998/  
**라이선스**: CC0  
**길이**: 짧은 블립  
**처리**: 그대로 사용.

---

### S-04 — 슬롯 선택 클릭 (StartScreen)

**파일명**: `sfx/sfx_slot_select.ogg`  
**트랙**: "UI Button Click Snap"  
**크리에이터**: el_boss  
**Freesound ID**: 677860  
**URL**: https://freesound.org/people/el_boss/sounds/677860/  
**라이선스**: CC0  
**길이**: 306ms  
**처리**: 그대로 사용.

---

### S-05 — 슬롯 호버 (StartScreen)

**파일명**: `sfx/sfx_slot_hover.ogg`  
**트랙**: "Normal click"  
**크리에이터**: Breviceps  
**Freesound ID**: 448086  
**URL**: https://freesound.org/people/Breviceps/sounds/448086/  
**라이선스**: CC0  
**길이**: 48ms  
**처리**: 볼륨 -6dB 감소 권장 (너무 선명하지 않게).

---

### S-06 — 슬롯 삭제 경고 (StartScreen)

**파일명**: `sfx/sfx_delete_confirm.ogg`  
**트랙**: "Error Signal 1"  
**크리에이터**: Breviceps  
**Freesound ID**: 445976  
**URL**: https://freesound.org/people/Breviceps/sounds/445976/  
**라이선스**: CC0  
**길이**: 짧은 에러 신호  
**처리**: 그대로 사용.

---

### S-07 — 수익 실현 소 (ProfitCelebration SMALL)

**파일명**: `sfx/sfx_profit_small.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx2.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 1200Hz 기본음 + 2400/3600Hz 배음 지수감쇠 믹스 (동전 딸랑)  
**길이**: 300ms

---

### S-08 — 수익 실현 중 (ProfitCelebration MEDIUM)

**파일명**: `sfx/sfx_profit_medium.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 880/1047/1319Hz 동전 3단 cascade → C5-E5-G5 상승 아르페지오  
**길이**: 900ms

---

### S-09 — 수익 실현 대 (ProfitCelebration LARGE)

**파일명**: `sfx/sfx_profit_large.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: C4-E4-G4-C5 4음 상승 팡파레 아르페지오  
**길이**: 1000ms

---

### S-10 — 수익 실현 잭팟 (ProfitCelebration JACKPOT)

**파일명**: `sfx/sfx_profit_jackpot.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 동전 5단 cascade → C4-E4-G4-C5-E5 팡파레 → C장조 종결 화음  
**길이**: 2800ms

---

### S-11 — 주문 체결음 (OrderPanel)

**파일명**: `sfx/sfx_order_filled.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 250Hz 블립 80ms → 무음 40ms → 280Hz 블립 80ms  
**길이**: 200ms

---

### S-12 — 레벨업 (LevelUpBanner)

**파일명**: `sfx/sfx_level_up.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx2.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: C5→E5→G5 3음 상승 아르페지오 (밝고 높은 레벨업 느낌)  
**길이**: 420ms

---

### S-13 — VI/서킷 브레이커 경보 (TradingScreen)

**파일명**: `sfx/sfx_vi_alert.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 880Hz 120ms → 무음 20ms → 1174.7Hz (D♭6) 200ms 상승 경보 2음  
**길이**: 340ms

---

### S-14 — 뉴스 알림 (ToastManager)

**파일명**: `sfx/sfx_news_alert.wav` ✅ 자체 생성 완료  
**소스**: `tools/gen_sfx.ps1` — CC0 (저작권 없음, 크레딧 불필요)  
**내용**: 440Hz 100ms → 330Hz 140ms 하강 소프트 알림 (4종 중 가장 조용)  
**길이**: 250ms


---

## 현황 (Status)

| ID | 파일명 | 소스 | 상태 |
|----|--------|------|------|
| S-01 | `bgm/bgm_start_screen.ogg` | Freesound CC0 | ✅ 완료 |
| S-02 | `sfx/sfx_logo_sting.ogg` | Freesound CC BY 4.0 | ✅ 완료 |
| S-03 | `sfx/sfx_save_complete.ogg` | Freesound CC0 | ✅ 완료 |
| S-04 | `sfx/sfx_slot_select.ogg` | Freesound CC0 | ✅ 완료 |
| S-05 | `sfx/sfx_slot_hover.ogg` | Freesound CC0 | ✅ 완료 |
| S-06 | `sfx/sfx_delete_confirm.ogg` | Freesound CC0 | ✅ 완료 |
| S-07 | `sfx/sfx_profit_small.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-08 | `sfx/sfx_profit_medium.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-09 | `sfx/sfx_profit_large.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-10 | `sfx/sfx_profit_jackpot.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-11 | `sfx/sfx_order_filled.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-12 | `sfx/sfx_level_up.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-13 | `sfx/sfx_vi_alert.wav` | 자체 생성 CC0 | ✅ 완료 |
| S-14 | `sfx/sfx_news_alert.wav` | 자체 생성 CC0 | ✅ 완료 |

> 모든 SFX 자체 생성 완료. 외부 다운로드 불필요.

---

## WAV → OGG 변환 (Audacity)

1. File → Import → Audio (WAV 파일 선택)
2. 트리밍 필요 시 Selection Tool로 범위 선택 → Ctrl+T
3. File → Export → Export as OGG Vorbis
4. Quality: 6 (게임 SFX 기준 충분)
5. `assets/audio/bgm/` 또는 `assets/audio/sfx/` 에 저장

---

## 저작권 표기 목록

파일명이 곧 출처 정보 (Freesound 표준 형식: `{ID}__{크리에이터}__{제목}`).

### 다운로드 파일 라이선스

| 파일명 (assets/audio/) | 크리에이터 | 라이선스 | 크레딧 필요 |
|----------------------|-----------|---------|-----------|
| `155139__burning-mir__...` (S-01 BGM) | burning-mir | CC0 | 불필요 |
| `335860__pcruzn__intro-logo-sound` (S-02) | pcruzn | **CC BY 4.0** | **필요** |
| `452998__breviceps__blip-wave` (S-03) | Breviceps | CC0 | 불필요 |
| `677860__el_boss__ui-button-click-snap` (S-04) | el_boss | CC0 | 불필요 |
| `448086__breviceps__normal-click` (S-05) | Breviceps | CC0 | 불필요 |
| `445976__breviceps__error-signal-1` (S-06) | Breviceps | CC0 | 불필요 |

자체 생성 (S-07~S-14): CC0, 크레딧 불필요.

### 인게임 크레딧 필수 표기 — CC BY 4.0 (1건)

크레딧 화면(`design/gdd/credits-screen.md`)에 아래 텍스트 표시:

```
"Intro-Logo Sound.wav" by pcruzn
Freesound ID: 335860
License: CC BY 4.0
```

### 엔진 / 프레임워크

| 항목 | 라이선스 |
|------|---------|
| Godot Engine | MIT |
| GUT (Godot Unit Test) | MIT |
