# Asset Acquisition Plan

**작성일**: 2026-04-07  
**범위**: SplashScreen · SavingOverlay · StartScreen  
**담당**: art-director / audio-director

---

## 1. 아트 에셋

| ID | 에셋 | 경로 | 규격 | 우선순위 | 수급 방법 | 비고 |
|----|------|------|------|---------|---------|------|
| A-01 | 로고 | `assets/ui/logo.png` | 1024×512, PNG 투명 | **P0** | Figma 자체 제작 → SVG export | SplashScreen + StartScreen 공용. 현재 코드에 Label 플레이스홀더 있음 |
| A-02 | 스타트 배경 | `assets/ui/start_bg.png` | 1920×1080, JPG/PNG | P1 | AI 생성 (Midjourney) | 단색으로 먼저 구현 가능. 로고 오버레이됨 |
| A-03 | 저장 스피너 링 | `assets/ui/spinner_ring.png` | 48×48, PNG 투명 | P2 | Figma 30초 작업 | 원형 stroke, #ebebeb. 현재 ColorRect 플레이스홀더 있음 |

### A-01 로고 제작 가이드

- 폰트: 세리프 또는 모노스페이스 계열 (터미널/트레이딩 분위기)
- 컬러: 단색 흰색 (#ebebeb) — 배경 #0a0a0a 위에 표시
- 심볼 아이디어: 씨앗(▽) + 상승 차트(↗) 합성 픽토그램
- 포맷: Figma에서 벡터 작업 → PNG export (2x 해상도)
- 사이즈: 로고타입 + 심볼 포함 1024×256 권장 (높이는 유연)

### A-02 배경 AI 생성 프롬프트

```
dark city skyline at night, minimalist, stock market trading theme,
moody atmosphere, no people, no text, 16:9 ratio, dark background #0a0a0a tone,
subtle neon reflections, photorealistic, high detail
```

대안 (무료 스톡): Unsplash `dark city night` — CC0 라이선스 확인 필수.  
대안 (Alpha MVP): 코드로 단색 그라디언트 처리 (에셋 불필요).

---

## 2. 사운드 에셋

| ID | 에셋 | 경로 | 길이 | 우선순위 | 수급 방법 | 설명 |
|----|------|------|------|---------|---------|------|
| S-01 | 스타트 스크린 BGM | `assets/audio/bgm/bgm_start_screen.ogg` | 29초 루프 | **P0** | Freesound #155139 (CC0) — burning-mir | "Action music loop with dark ambient drones". 루프 가능 명시됨 |
| S-02 | 로고 스팅 | `assets/audio/sfx/sfx_logo_sting.ogg` | ~2초 (트리밍) | P1 | Freesound #335860 (CC BY 4.0) — pcruzn, 또는 Bfxr | "Intro-Logo Sound.wav" 앞부분 2초 트리밍. CC BY = 크레딧 필요 |
| S-03 | 저장 완료 SFX | `assets/audio/sfx/sfx_save_complete.ogg` | 짧은 블립 | P1 | Freesound #452998 (CC0) — Breviceps | "Blip Wave" |
| S-04 | 슬롯 선택 SFX | `assets/audio/sfx/sfx_slot_select.ogg` | 306ms | P2 | Freesound #677860 (CC0) — el_boss | "UI Button Click Snap" |
| S-05 | 슬롯 호버 SFX | `assets/audio/sfx/sfx_slot_hover.ogg` | 48ms | P2 | Freesound #448086 (CC0) — Breviceps | "Normal click", -6dB 권장 |
| S-06 | 삭제 확인 SFX | `assets/audio/sfx/sfx_delete_confirm.ogg` | 짧은 에러음 | P2 | Freesound #445976 (CC0) — Breviceps | "Error Signal 1" |
| S-07 | 수익 실현 소 SFX | `assets/audio/sfx/sfx_profit_small.ogg` | ~0.3초 | P3 (Beta) | Freesound "coin clink" CC0 (예: #362204) | 동전 1~2개 딸랑 |
| S-08 | 수익 실현 중 SFX | `assets/audio/sfx/sfx_profit_medium.ogg` | ~1.0초 | P3 (Beta) | Freesound "win jingle short" CC0, 또는 Bfxr | 동전 여러 개 + 짧은 멜로디 |
| S-09 | 수익 실현 대 SFX | `assets/audio/sfx/sfx_profit_large.ogg` | ~2.0초 | P3 (Beta) | Freesound "fanfare short" CC0 (예: #270402 확인) | 팡파레 풀버전 |
| S-10 | 수익 실현 잭팟 SFX | `assets/audio/sfx/sfx_profit_jackpot.ogg` | ~3.0초 | P3 (Beta) | Freesound "jackpot big win" CC0, 또는 S-09+동전 Audacity 믹스 | 시그니처 잭팟 사운드 |

### S-01 BGM 검색 키워드

- Freesound.org: `ambient dark tension loop`, `dark electronic ambient`, `minimalist tension`
- 라이선스: CC0 (상업 이용 가능) 또는 CC BY (크레딧 표기 필요)
- BPM: 60~80 권장 (느리고 무거운 분위기)
- 루프 편집: Audacity로 자연스러운 루프 포인트 편집

### S-02~06 Bfxr 생성 가이드

Bfxr (https://www.bfxr.net) 또는 로컬 실행:

| ID | 카테고리 | 주요 파라미터 |
|----|---------|-------------|
| S-02 | Blip/Tone | Frequency: 낮음→높음 sweep, 길이 1.0s |
| S-03 | Blip | Short click, 높은 주파수, 부드러운 decay |
| S-04 | Blip | 짧고 선명한 클릭 |
| S-05 | Blip | 매우 짧음(50ms), 낮은 볼륨 |
| S-06 | Noise | 낮은 피치, 짧은 버스트 |

---

## 3. 구현 연동 위치

| 에셋 | 연동 파일 | 연동 방법 | 현재 상태 |
|------|---------|---------|---------|
| A-01 로고 | `src/ui/splash_screen.gd` L35 | Label → TextureRect 교체 (TODO 주석 있음) | 플레이스홀더 |
| A-01 로고 | `src/ui/start_screen.gd` L52 | "SEED MONEY" Label → TextureRect 교체 | 플레이스홀더 |
| A-02 배경 | `src/ui/start_screen.gd` | bg ColorRect → TextureRect + stretch_mode=COVER | 단색 플레이스홀더 |
| A-03 스피너 | `src/ui/saving_overlay.gd` L44 | ColorRect ring → TextureRect (TODO 주석 있음) | 플레이스홀더 |
| S-01 BGM | `src/ui/start_screen.gd` | `_ready()`에서 AudioManager.play_bgm("bgm_start_screen") | 미구현 (AudioManager S5-02) |
| S-02 로고 스팅 | `src/ui/splash_screen.gd` | `_build_ui()` 완료 후 AudioManager.play_sfx | 미구현 |
| S-03~06 SFX | `src/ui/start_screen.gd` | 버튼 pressed 핸들러에서 AudioManager.play_sfx | 미구현 |

> **AudioManager 의존**: S-01~06은 AudioManager(S5-02) 구현 완료 후 연동.  
> 에셋 파일은 미리 `assets/audio/` 디렉터리에 배치 가능.

---

## 4. 우선순위 요약

| 순위 | 에셋 | 이유 |
|------|------|------|
| P0 | A-01 로고 | Splash·Start 공용. 없으면 텍스트 플레이스홀더로 진행 |
| P0 | S-01 BGM | Start Screen 체류 중 무음 시 허전함 |
| P1 | A-02 배경 | 단색으로 먼저 구현 가능. 나중에 교체 |
| P1 | S-02 로고 스팅 | Splash 인상에 직접 기여 |
| P1 | S-03 저장 완료 SFX | 저장 완료 피드백 |
| P2 | A-03 스피너 링 | Godot 기본 UI로 대체 가능 |
| P2 | S-04~06 UI SFX | Bfxr로 당일 제작 가능 |
| P3 (Beta) | A-VFX-01 금화 스프라이트 | 수익 팡파레 파티클 — Beta 전 확보 필요 |
| P3 (Beta) | S-07~10 수익 팡파레 SFX | 4등급 각각. Freesound CC0 우선, 없으면 Audacity 믹스 |
| P3 (Beta) | A-Housing-03~06 거주지 배경 | 실버~마스터+ 중간 4티어 (쪽방·펜트하우스 완료) |

---

## 5. Beta 추가 에셋 — 수급 상세

### A-VFX-01 — 금화 스프라이트 (ProfitCelebration)

| 항목 | 내용 |
|------|------|
| 파일 | `assets/art/vfx/coin_gold.png` |
| 규격 | 32×32 또는 64×64 PNG 투명 배경 |
| 용도 | `GPUParticles2D` 스프라이트 |
| 수급 | OpenGameArt.org `"gold coin"` CC0, 또는 Kenney.nl UI Pack (CC0) |
| 추천 | Kenney.nl → `kenney_ui-pack` → coin 스프라이트 추출 (CC0, 크레딧 불필요) |
| 대안 | Figma에서 원형 + 골드 그라디언트 10분 제작 |

### A-Housing-03~06 — 거주지 배경 중간 4티어

| ID | 거주지 | 파일 | 수급 방법 |
|----|-------|------|---------|
| A-Housing-03 | 변두리 원룸 | `assets/art/housing/silver_oneroom.png` | AI 생성 (Midjourney/DALL-E). 프롬프트 아래 참조 |
| A-Housing-04 | 도심 오피스텔 | `assets/art/housing/gold_officetel.png` | AI 생성 |
| A-Housing-05 | 강남 아파트 | `assets/art/housing/platinum_gangnam_apt.png` | AI 생성 |
| A-Housing-06 | 평창동 대저택 | `assets/art/housing/master_mansion.png` | AI 생성 |

**AI 생성 프롬프트 템플릿**:
```
[거주지명] interior, Korean style, realistic photography, moody ambient lighting,
dark background, cinematic composition, no people, 16:9 ratio,
high detail, photorealistic
```
규격: 1280×720 이상 PNG/JPG. `bronze_jjokbang.png` / `diamond_penthouse.png` 톤 참조.

### S-07~10 수급 우선순위

```
1. Freesound.org에서 CC0 검색 (DOWNLOAD_GUIDE.md §S-07~10 참조)
2. 없으면 Bfxr 자체 생성 (S-07, S-08 가능)
3. 없으면 Audacity로 기존 SFX 레이어 믹스 (S-10 추천)
```
