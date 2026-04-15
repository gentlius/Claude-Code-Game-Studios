> **Status**: Draft
> **Sprint**: S7-08
> **Owner**: art-director

# 아트 바이블 — 시드머니 (Seed Money)

## 비주얼 정체성

**한 줄 요약**: "한국 HTS의 정보 밀도 + Toss Securities의 화이트 클린 미니멀"

기관 투자자들이 쓰는 전문적이고 신뢰감 있는 UI. 화려한 게임 UI가 아니라
실제 증권사 앱처럼 생겼다는 인상이 첫 번째 목표.

---

## 색상 팔레트 (ThemeSetup 단일 소스)

모든 색상은 `src/ui/theme_setup.gd`에 정의된 상수만 사용.
새 색상이 필요하면 ThemeSetup에 추가하고 상수명으로 참조. 리터럴 금지.

### 기본 배경 (White Base — 콘텐츠 영역)

| 상수명 | 헥스 | 용도 |
|--------|------|------|
| `BG_DARKEST` | `#F5F5F8` | 페이지 최외곽 배경 |
| `BG_DARK` | `#FAFAFC` | 섹션 배경 |
| `BG_PANEL` | `#FFFFFF` | 카드 / 패널 |
| `BG_HOVER` | `#F2F2F8` | 호버 상태 |
| `BG_SELECTED` | `#E8F0FF` | 선택 상태 (파란 틴트) |

### 다크 프레임 (레이아웃 외곽 — HTS 크롬)

| 상수명 | 헥스 | 용도 |
|--------|------|------|
| `LAYOUT_BG` | `#141416` | 전체 프레임 배경 |
| `LAYOUT_PANEL` | `#1F1F21` | 탭 바 / 비활성 탭 |
| `LAYOUT_TAB_ACTIVE_BG` | `#2E2E33` | 활성 탭 배경 |
| `LAYOUT_TAB_BORDER` | `#4D99FF` | 활성 탭 하단 강조선 |

### 텍스트

| 상수명 | 헥스 | 용도 |
|--------|------|------|
| `TEXT_PRIMARY` | `#212126` | 주요 정보 |
| `TEXT_SECONDARY` | `#5A5A66` | 보조 정보 |
| `TEXT_DIM` | `#808087` | 비활성 / 힌트 |

### 시장 색상 (KRX 관행)

| 상수명 | 헥스 | 의미 |
|--------|------|------|
| `PROFIT_RED` | `#EB3833` | 수익 / 상승 (한국: 빨강) |
| `LOSS_BLUE` | `#2E6BE6` | 손실 / 하락 (한국: 파랑) |
| `NEUTRAL_GRAY` | `#8C8C94` | 보합 |

> **주의**: 글로벌 시장용 색상 반전은 `ThemeSetup.set_market_colors()`로만.
> UI 컴포넌트에 직접 색상 하드코딩 금지.

---

## 타이포그래피

현재 Godot 기본 폰트 사용. 커스텀 폰트 도입 시 이 섹션 업데이트.

### 폰트 크기 계층

| 레벨 | 크기 | 사용처 |
|------|------|--------|
| Display | 28px | 레벨업 배너 숫자, 잭팟 알림 |
| Heading | 20px | 화면 타이틀 |
| SubHeading | 15~16px | 섹션 헤더, 종목명 |
| Body | 13~14px | 일반 정보, 탭 레이블 |
| Small | 12px | 보조 수치, 크레딧, 에러 메시지 |

### 규칙

- 숫자 데이터(가격, 수익률)는 Body 이상 크기, `TEXT_PRIMARY` 색상
- 수익/손실 수치에는 반드시 `PROFIT_RED` / `LOSS_BLUE` 색상 적용
- 모든 금액은 `FormatUtils.number()` 단일 메서드 경유 (천 단위 콤마)

---

## UI 컴포넌트 스타일 가이드

### 패널 / 카드

- 배경: `BG_PANEL (#FFFFFF)`
- 모서리 반경: 8px (`make_panel_style()` 기본값)
- 테두리: `BORDER_DIM` 1px 또는 테두리 없음
- 그림자: 없음 (플랫 디자인 원칙)

### 버튼

| 종류 | 색상 | 용도 |
|------|------|------|
| 기본 | `BTN_NORMAL #E0E0E8` | 닫기, 취소 |
| 강조 | `BTN_ACCENT #333338` | 주문 실행, 확인 |
| 매수 | `BTN_BUY #EB3833` | 매수 버튼 |
| 매도 | `BTN_SELL #2E6BE6` | 매도 버튼 |

- 모서리 반경: 4px
- 최소 높이: 26~30px

### 구분선

- `SEPARATOR #EBEBEE` 단색, 1px

### 상태 배지 / 알림

- 긴급 경보 (VI/서킷): `ALERT_BORDER_MEGA`, 배경 `ALERT_BG_MEGA`
- 대형 이벤트: `ALERT_BORDER_LARGE`, 배경 `ALERT_BG_LARGE`
- SL 발동: `#E64D4D` (빨강 계열)
- TP 발동: `#4DAD66` (초록 계열)

---

## 애니메이션 원칙

- **감쇠(Ease Out)** 기본: 빠르게 시작 → 부드럽게 멈춤 (정보 전달 우선)
- 슬라이드 인/아웃: `TRANS_BACK` 또는 `TRANS_CUBIC`, 0.3~0.5초
- 레벨업 강조: `TRANS_ELASTIC` (팡 튀어나오는 느낌, 예외적 허용)
- **reduced_motion 필수**: `ProjectSettings.get_setting("accessibility/reduced_motion")` 체크 후 애니메이션 스킵

---

## 예외: 거주지 배경 이미지

UI는 플랫 미니멀 원칙을 따르지만, **F3 성장 화면의 거주지 배경**은 포토리얼(Photorealistic AI-Generated) 이미지를 사용한다.

- 기준 에셋: `assets/art/housing/bronze_jjokbang.png` (쪽방, 차가운 청회색), `assets/art/housing/diamond_penthouse.png` (한남더힐, 따뜻한 야경)
- 이 이미지들은 UI 요소가 아니라 배경 콘텐츠이므로 플랫 원칙의 예외로 허용한다
- 신규 거주지 이미지 제작 시 `design/residence-art-direction.md` 가이드라인 따를 것

---

## 금지 사항

- 리터럴 색상값 (`Color(0.92, 0.22, 0.20)` 등) UI 코드에 직접 사용 금지 → ThemeSetup 상수 사용
- 그라디언트 배경 금지 (플랫 원칙) — 거주지 배경 이미지 제외
- 드롭 섀도우 남용 금지
- 폰트 크기 14px 미만 주요 정보 표시 금지
