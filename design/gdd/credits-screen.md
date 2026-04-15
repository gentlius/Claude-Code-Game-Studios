> **Status**: Draft
> **Sprint**: S7-09 연계 (오디오 크레딧 확정 후 Approved)
> **Owner**: producer + ui-programmer

# Credits Screen — 크레딧 화면

## 1. Overview

게임 내 법적 의무 크레딧(CC BY 라이선스 표기)과 제작 크레딧을 제공하는 전용 화면.
StartScreen의 "크레딧" 버튼으로 진입. ScrollContainer 기반 단일 스크롤 목록.

---

## 2. Player Fantasy

"이 게임을 만든 게 나 혼자구나, 그리고 써준 에셋들이 제대로 표기됐구나" —
제작 투명성과 법적 요건을 동시에 충족하면서, 플레이어가 불편함 없이 닫을 수 있는 화면.

---

## 3. Detailed Design

### 3-1. 진입 경로

- StartScreen → "크레딧" 버튼 → CreditsScreen 표시 (오버레이 또는 씬 교체)
- Esc / 닫기 버튼 → StartScreen 복귀

### 3-2. 화면 구조

```
┌────────────────────────────────────────┐
│  시드머니 (Seed Money)                 │  ← 타이틀 레이블
├────────────────────────────────────────┤
│  [스크롤 영역]                          │
│                                        │
│  기획 및 총괄                           │  ← 섹션 헤더
│  [제작자명]                             │
│                                        │
│  프로그래밍                             │
│  [제작자명]                             │
│                                        │
│  아트 및 UI                             │
│  [제작자명]                             │
│                                        │
│  ── 외부 리소스 및 라이선스 ──          │  ← 구분선 + 헤더
│                                        │
│  오디오                                 │
│  "Intro-Logo Sound.wav" by pcruzn     │
│  freesound.org/s/335860/              │
│  License: CC BY 4.0                   │
│                                        │
│  엔진                                   │
│  Godot Engine — MIT License           │
│  GUT (Godot Unit Test) — MIT License  │
│                                        │
│  특별히 감사한 분들                      │
│  플레이테스트에 참여해주신 분들           │
│                                        │
│  © 2026 [제작자명]. All Rights Reserved│
├────────────────────────────────────────┤
│  [닫기  Esc]                           │
└────────────────────────────────────────┘
```

### 3-3. 섹션 순서

1. 타이틀 (게임명 + 연도)
2. 제작 크레딧 (기획/프로그래밍/아트 — 실제 담당자로 대체)
3. 구분선: "외부 리소스 및 라이선스"
4. 오디오 (CC BY 항목만 — CC0·자체생성 제외)
5. 엔진/프레임워크 (Godot, GUT)
6. 폰트 (OFL 폰트 사용 시 — 미사용이면 섹션 생략)
7. 특별 감사 (플레이테스터 등)
8. 저작권 고지

### 3-4. 텍스트 포맷 규칙

**섹션 헤더**: 14px, `ThemeSetup.TEXT_SECONDARY` 색상, 위 여백 20px  
**항목 텍스트**: 12px, `ThemeSetup.TEXT_DIM` 색상  
**라이선스 URL**: 12px, 동일 색상 (하이퍼링크 미지원 — 단순 텍스트)

CC BY 오디오 항목 포맷:
```
"[원작 트랙명]" by [크리에이터]
[출처 URL]
License: [라이선스명] — [라이선스 URL]
```

---

## 4. Formulas

해당 없음 (표시 전용 화면).

---

## 5. Edge Cases

- **CC BY 항목이 0개인 경우**: 오디오 섹션 전체 숨김 (self-generated만 있으면 표기 불필요).
- **폰트 섹션**: OFL 폰트 사용 확정 전까지 섹션 생략. 사용 시 추가.
- **스크롤 없는 짧은 내용**: 내용이 화면에 다 들어오면 ScrollContainer는 비활성화 상태 유지 (클리핑만).

---

## 6. Dependencies

- `src/ui/start_screen.gd` — "크레딧" 버튼 진입점
- `assets/audio/DOWNLOAD_GUIDE.md` — CC BY 크레딧 목록 단일 소스
- `ThemeSetup` — 텍스트 스타일 상수

---

## 7. Tuning Knobs

| 항목 | 값 | 비고 |
|------|-----|------|
| 타이틀 폰트 크기 | 20px | |
| 섹션 헤더 폰트 크기 | 14px | |
| 항목 텍스트 폰트 크기 | 12px | |
| 섹션 간 여백 | 20px | VBoxContainer separation |
| 닫기 버튼 위치 | 하단 고정 | 스크롤 영역 바깥 |

---

## 8. Acceptance Criteria

- **AC-01**: StartScreen "크레딧" 버튼 클릭 → 크레딧 화면 표시
- **AC-02**: Esc 키 / 닫기 버튼 → StartScreen 복귀
- **AC-03**: CC BY 항목(현재 S-02 pcruzn)이 "원작명 / 크리에이터 / URL / 라이선스" 4개 항목 모두 표시
- **AC-04**: CC0·자체생성 오디오가 크레딧 화면에 나타나지 않음
- **AC-05**: Godot Engine MIT, GUT MIT 표기 존재
- **AC-06**: 저작권 고지 "© 2026" 표기 존재
- **AC-07**: 화면 내용이 넘칠 경우 스크롤 가능

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `src/ui/start_screen.gd` → "크레딧" 버튼 pressed → CreditsScreen 표시

### 호출 경로
- [ ] StartScreen에 "크레딧" 버튼 추가
- [ ] CreditsScreen 씬 또는 코드 구현 (ScrollContainer + VBoxContainer)
- [ ] CC BY 목록: `assets/audio/DOWNLOAD_GUIDE.md §인게임 크레딧 표기 목록` 기준으로 하드코딩 (런타임 파싱 불필요)
- [ ] Esc 핸들러 → `start_screen_requested` 시그널 emit

### AC → 테스트 매핑
| AC | 테스트 | 방법 |
|----|--------|------|
| AC-01 | 수동 | StartScreen "크레딧" 클릭 |
| AC-02 | 수동 | Esc 키 / 닫기 버튼 |
| AC-03 | 수동 | pcruzn 크레딧 텍스트 육안 확인 |
| AC-04 | 수동 | CC0 파일명(sfx_save_complete 등) 화면에 없음 |
| AC-05~06 | 수동 | Godot/GUT/© 텍스트 육안 확인 |
| AC-07 | 수동 | 내용 추가 후 스크롤 동작 |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
