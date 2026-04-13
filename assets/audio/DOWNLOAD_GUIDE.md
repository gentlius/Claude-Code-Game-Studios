# Audio Asset Download Guide

**작성일**: 2026-04-07  
**참조**: production/asset-plan.md

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

## 다운로드 순서 (우선순위)

```
1. bgm_start_screen  — P0, 가장 먼저 (ID: 155139)
2. sfx_logo_sting    — P1 (ID: 335860, 또는 Bfxr 자체 생성)
3. sfx_save_complete — P1 (ID: 452998)
4. sfx_slot_select   — P2 (ID: 677860)
5. sfx_slot_hover    — P2 (ID: 448086)
6. sfx_delete_confirm — P2 (ID: 445976)
```

---

## WAV → OGG 변환 (Audacity)

1. File → Import → Audio (WAV 파일 선택)
2. 트리밍 필요 시 Selection Tool로 범위 선택 → Ctrl+T
3. File → Export → Export as OGG Vorbis
4. Quality: 6 (게임 SFX 기준 충분)
5. `assets/audio/bgm/` 또는 `assets/audio/sfx/` 에 저장

---

## 크레딧 표기 (CC BY 라이선스 적용 항목)

게임 내 크레딧 또는 README에 아래 표기 필요:

```
S-02 "Intro-Logo Sound.wav" by pcruzn (freesound.org/s/335860/)
Licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0/)
```

CC0 항목(S-01, S-03~S-06)은 크레딧 불필요.
