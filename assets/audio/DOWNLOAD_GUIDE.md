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

### S-07 — 수익 실현 소 (ProfitCelebration SMALL)

**파일명**: `sfx/sfx_profit_small.ogg`  
**설명**: 동전 1~2개 딸랑거리는 소리. 0.3초 이내.  
**추천 소스**: Freesound.org 검색어 `"coin clink"` `"single coin"` CC0  
**추천 후보**:
- ID 362204 "Coin" by ProjectsU012 — CC0
- ID 331912 "coins" by Robinhood76 — CC BY (크레딧 필요)  

**처리**: 단일 동전 소리 1회. 볼륨 -3dB.

---

### S-08 — 수익 실현 중 (ProfitCelebration MEDIUM)

**파일명**: `sfx/sfx_profit_medium.ogg`  
**설명**: 동전 여러 개 쏟아지는 소리 + 짧은 승리 멜로디. 1.0초 이내.  
**추천 소스**: Freesound.org 검색어 `"coins falling"` `"win jingle short"` CC0  
**추천 후보**:
- ID 341695 "Success jingle" — CC0 검색 확인 필요
- 또는 **Bfxr 자체 생성**: Pickup/Coin 카테고리 → Frequency 중간 → 길이 0.8초

**처리**: 동전 소리와 짧은 멜로디 믹스. 총 길이 0.8~1.0초.

---

### S-09 — 수익 실현 대 (ProfitCelebration LARGE)

**파일명**: `sfx/sfx_profit_large.ogg`  
**설명**: 팡파레 풀버전. 동전 폭발 + 환호 분위기. 1.5~2.0초.  
**추천 소스**: Freesound.org 검색어 `"fanfare short"` `"victory fanfare"` CC0  
**추천 후보**:
- ID 270402 "Fanfare" — 라이선스 확인 필요
- ID 566517 "Success Fanfare Trumpets" — CC0 확인 필요

**처리**: 앞부분 0.5초 트리밍하여 바로 팡파레 시작. 총 2.0초.

---

### S-10 — 수익 실현 잭팟 (ProfitCelebration JACKPOT)

**파일명**: `sfx/sfx_profit_jackpot.ogg`  
**설명**: 시그니처 잭팟 사운드. 슬롯머신 잭팟 + 대규모 환호 + 동전 폭발. 3.0초.  
**추천 소스**: Freesound.org 검색어 `"jackpot"` `"big win"` CC0  
**추천 후보**:
- ID 131142 "Casino win" — 라이선스 확인 필요
- **대안**: S-09 팡파레 + 동전 SFX를 Audacity에서 레이어 믹스하여 제작

**처리**: 가장 임팩트 있는 버전. 길이 2.5~3.0초. 볼륨 +2dB (다른 SFX 대비 강조).

---

### S-11 — 주문 체결음 (OrderPanel)

**파일명**: `sfx/sfx_order_filled.ogg`  
**설명**: 체결 확정 2펄스 블립. 차갑고 정밀한 전자음. 0.2초 이내.  
**추천 소스**: Bfxr (https://www.bfxr.net) 자체 생성 권장  
**Bfxr 설정**: Electronic → Frequency 220→280Hz, 길이 0.08s × 2개 이어붙이기 (50ms 무음 삽입)  
**Freesound 대안**: 검색어 `"blip double"` `"UI beep short"` CC0  
- ID 242502 "Short Blip" by f4ngy — CC0 (단음 × 2 복사·붙여넣기)  

**처리**: 총 200ms. 첫 블립 80ms → 무음 40ms → 두 번째 블립 80ms. Normalize -3dB. OGG Quality 6.

---

### S-12 — 레벨업 (LevelUpBanner)

**파일명**: `sfx/sfx_level_up.ogg`  
**설명**: 3음 상승 아르페지오 (C4→E4→G4 계열). 달성 만족감. 0.4초 이내.  
**추천 소스**: Freesound.org 검색어 `"level up short"` `"arpeggio up"` CC0  
**추천 후보**:
- ID 512763 "Level Up 01" by rhodesmas — CC0  
- **대안**: Bfxr → Powerup → Wave: Sine, Frequency 상승, 길이 0.35s  

**처리**: 0.35~0.4초. Normalize -3dB. OGG Quality 6.

---

### S-13 — VI/서킷 브레이커 경보 (TradingScreen)

**파일명**: `sfx/sfx_vi_alert.ogg`  
**설명**: 2음 상승 경보 톤. 4종 중 가장 긴장감 있는 알림 — 즉각 반응 요구. S-06(삭제 경고)과 음색 겹치지 않게 주의. 0.35초 이내.  
**추천 소스**: Freesound.org — Breviceps Signal 시리즈 탐색  
- https://freesound.org/people/Breviceps/ → CC0, 짧은 전자 시그널 다수 보유  
- "Warning Signal" 또는 "Signal 2" 계열  
- **대안**: 검색어 `"alert beep two note"` `"warning tone short"` CC0  

**처리**: 0.3초 이내. Normalize -2dB (4종 중 가장 크게 — 경보이므로). OGG Quality 6.

---

### S-14 — 뉴스 알림 (ToastManager)

**파일명**: `sfx/sfx_news_alert.ogg`  
**설명**: 2음 하강 소프트 알림. 정보 수신 느낌. 4종 중 가장 조용하게. 0.25초 이내.  
**추천 소스**: Freesound.org 검색어 `"notification tone"` `"soft blip"` CC0  
**추천 후보**:
- ID 341696 "Notification" by rhodesmas — CC0  
- **대안**: Bfxr → Blip/Select → Frequency 440→330Hz 하강, Wave: Sine, 길이 0.2s  

**처리**: 0.2~0.25초. Normalize -4dB (뉴스는 부수적 정보 — 놓쳐도 재확인 가능). OGG Quality 6.

---

## 다운로드 순서 (우선순위)

```
1. bgm_start_screen   — P0, 가장 먼저 (ID: 155139) ✅ 완료
2. sfx_logo_sting     — P1 (ID: 335860, 또는 Bfxr 자체 생성) ✅ 완료
3. sfx_save_complete  — P1 (ID: 452998) ✅ 완료
4. sfx_slot_select    — P2 (ID: 677860) ✅ 완료
5. sfx_slot_hover     — P2 (ID: 448086) ✅ 완료
6. sfx_delete_confirm — P2 (ID: 445976) ✅ 완료
── Beta 코어 SFX (B-05) ──
7. sfx_vi_alert       — P1 (S-13, Breviceps Signal 시리즈 CC0)
8. sfx_order_filled   — P2 (S-11, Bfxr 자체 생성 권장)
9. sfx_level_up       — P2 (S-12, Freesound ID 512763 CC0)
10. sfx_news_alert    — P3 (S-14, Freesound ID 341696 또는 Bfxr)
── Beta 수익 실현 ──
11. sfx_profit_small   — P3 (S-07, Freesound "coin clink" CC0)
12. sfx_profit_medium  — P3 (S-08, Freesound 또는 Bfxr 자체 생성)
13. sfx_profit_large   — P3 (S-09, Freesound "fanfare short" CC0)
14. sfx_profit_jackpot — P3 (S-10, Freesound "jackpot" CC0 또는 Audacity 믹스)
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
