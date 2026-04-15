# 거주지 배경 이미지 — 생성 프롬프트

> **목표 해상도**: 2752 × 1536 (16:9) — `diamond_penthouse.png` 기준
> **스타일 앵커**: 기존 두 이미지를 스타일 레퍼런스로 사용 (Midjourney: `--sref`)
> **파일 위치**: `assets/art/housing/`

## 공통 스타일 규칙 (모든 프롬프트에 적용)

```
photorealistic interior photography, Korean residential interior, no people,
cinematic lighting, architectural photography style,
camera positioned inside the room looking across the space,
--ar 16:9 --style raw
```

Midjourney 사용 시: `--sref [bronze_jjokbang.png URL] [diamond_penthouse.png URL]` 추가로 스타일 일관성 확보 권장.

---

## 티어별 프롬프트

### T1. 브론즈 — 고시원 / 쪽방
**파일명**: `bronze_jjokbang.png` *(기존 존재 — 재생성 여부 선택)*

```
photorealistic interior photography, cramped Korean gosiwon single room at night,
narrow single bed pushed against the wall, small worn desk with a cheap lamp,
cold bluish-white fluorescent overhead light casting harsh shadows,
small frosted window with faint neon signage glowing outside,
worn linoleum floor, water-stained ceiling, bare walls with a few peeling stickers,
3x3 meter space, claustrophobic and isolating atmosphere, urban poverty,
no people, cinematic, --ar 16:9 --style raw
```

---

### T2. 실버 — 변두리 원룸
**파일명**: `silver_oneroom.png`

```
photorealistic interior photography, small Korean studio apartment (원룸) in an aging
low-rise building, single room with a compact kitchenette along one wall,
small window overlooking a quiet residential alley with utility poles and older buildings,
white fluorescent ceiling light, modest IKEA-style furniture — a fold-out table, single bed,
basic bookshelf, clean but sparse and humble, vinyl wood-pattern flooring,
thin curtains, a sense of frugal optimism, no people, cinematic, --ar 16:9 --style raw
```

---

### T3. 골드 — 도심 오피스텔
**파일명**: `gold_officetel.png`

```
photorealistic interior photography, modern Korean officetel studio in an urban high-rise,
dusk light through floor-to-ceiling window overlooking a dense city grid,
recessed track lighting, minimalist grey and white interior,
efficient open layout — a clean workspace desk area and a sleeping zone visible,
glass-panel bathroom divider, glossy white kitchen along one wall,
city lights beginning to flicker on outside, functional urban professionalism,
no people, cinematic, --ar 16:9 --style raw
```

---

### T4. 플래티넘 — 강남 아파트 (중형)
**파일명**: `platinum_apartment.png`

```
photorealistic interior photography, Korean mid-size apartment living room (30~40평),
wide double window with an evening view of mid-rise apartment blocks and city lights,
warm LED indirect cove lighting, modern Korean apartment furniture —
L-shaped sectional sofa, low rectangular coffee table, console TV wall,
light oak hardwood floors, tasteful neutral interior with quality finishes,
aspirational but attainable Gangnam feel, no people, cinematic, --ar 16:9 --style raw
```

---

### T5. 에메랄드 — 도심 대형 아파트
**파일명**: `emerald_large_apartment.png`

```
photorealistic interior photography, spacious Korean luxury apartment interior,
large living room with panoramic floor-to-ceiling windows showing Han River and Seoul skyline
at golden hour, warm sunlight flooding hardwood floors, premium open-concept layout,
upscale sectional sofa and designer coffee table, marble accent wall behind TV,
open kitchen with island visible in background, modern Korean luxury interior,
sense of quiet achievement, no people, cinematic, --ar 16:9 --style raw
```

---

### T6. 다이아 — 초고층 펜트하우스
**파일명**: `diamond_penthouse.png` *(기존 존재 — 재생성 여부 선택)*

```
photorealistic interior photography, ultra-luxury Seoul penthouse at night,
panoramic floor-to-ceiling windows spanning an entire wall overlooking Seoul city lights,
polished marble floors, bespoke designer furniture — a sculptural sofa, art on walls,
warm amber indirect lighting, private outdoor terrace with infinity-edge pool hinting
at the edge of the frame, sky above the city visible, exclusive and powerful atmosphere,
no people, cinematic, --ar 16:9 --style raw
```

---

### T7. 마스터 — 교외 대저택
**파일명**: `master_mansion.png`

```
photorealistic interior photography, grand Korean estate villa in Pyeongchang-dong,
high-ceilinged living room with exposed natural stone walls and heavy timber beams,
large picture windows opening to a manicured garden of pine trees and maples,
afternoon natural daylight streaming in, blend of Korean traditional aesthetics and
modern luxury — celadon vase on display, low Korean-style furniture arrangement,
stone fireplace, premium natural materials: slate, oak, linen,
serene and powerful, no people, cinematic, --ar 16:9 --style raw
```

---

### T8. 그랜드마스터 — 개인 섬 / 별장
**파일명**: `grandmaster_island_villa.png`

```
photorealistic interior photography, private island villa on a Korean southern island,
open-plan living space with retractable glass walls fully open to a private beach terrace,
turquoise-blue sea and rocky coastline stretching to the horizon,
bright natural midday light, teak wood floors flowing to stone terrace,
organic architecture — curved ceiling, natural rattan and linen furniture,
private infinity pool edge visible at the terrace, total seclusion and freedom,
no people, cinematic, --ar 16:9 --style raw
```

---

### T9. 챌린저 — 자산운용사 / 스카이 레지던스
**파일명**: `challenger_sky_residence.png`

```
photorealistic interior photography, private penthouse executive floor of a Seoul
Yeouido or Gangnam skyscraper used as both residence and personal trading office,
360-degree panoramic windows showing the entire Seoul Basin — Han River, Namsan Tower,
Bukhansan in the distance, dusk-to-night transition lighting,
a large command desk with multiple screens faces the skyline,
a lounge area with premium leather and glass on the other side,
steel-and-glass architecture, sense of absolute command over a city,
no people, cinematic, --ar 16:9 --style raw
```

---

### T10. 레전드 — 국가 경제 고문 / 영빈관급 저택
**파일명**: `legend_official_residence.png`

```
photorealistic interior photography, grand Korean official residence compound,
formal reception room of a Pyeongchang-dong or Hannam-dong estate at the level of a
state guesthouse, traditional Korean architecture — exposed timber ceiling, hanji-screened
windows (창호) filtering soft morning light onto dark-stained wood floors,
a classical ink painting scroll on the wall, celadon and white porcelain displayed,
modern comfort integrated without disrupting the formal dignity, Korean national prestige,
sense of history and power wielded quietly, no people, cinematic, --ar 16:9 --style raw
```

---

### T11. 거장 — 투자의 거장 (엔딩 이미지)
**파일명**: `grandmaster_ending.png`

```
photorealistic interior photography, transcendent private observatory residence on a
mountain summit overlooking the Korean coastline and sea, impossibly large curved
glass windows spanning the entire curved wall, golden hour light bathing endless ocean
and distant islands in warm haze, minimalist white and natural stone interior,
a single leather Eames chair positioned facing the view — empty, waiting,
the room feels like the top of the world, zen-like and monumental,
sense of having arrived at the absolute end of a journey,
no people, cinematic wide, --ar 16:9 --style raw
```

---

## 파일 명명 규칙 요약

| 티어 | 파일명 | 상태 |
|------|--------|------|
| 브론즈 | `bronze_jjokbang.png` | ✅ 기존 |
| 실버 | `silver_oneroom.png` | ⬜ 신규 |
| 골드 | `gold_officetel.png` | ⬜ 신규 |
| 플래티넘 | `platinum_apartment.png` | ⬜ 신규 |
| 에메랄드 | `emerald_large_apartment.png` | ⬜ 신규 |
| 다이아 | `diamond_penthouse.png` | ✅ 기존 |
| 마스터 | `master_mansion.png` | ⬜ 신규 |
| 그랜드마스터 | `grandmaster_island_villa.png` | ⬜ 신규 |
| 챌린저 | `challenger_sky_residence.png` | ⬜ 신규 |
| 레전드 | `legend_official_residence.png` | ⬜ 신규 |
| 거장 | `grandmaster_ending.png` | ⬜ 신규 |
