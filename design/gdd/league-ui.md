# League & Season UI

*Created: 2026-04-03*
*Status: In Review*
*Sprint: S2-02*

---

## 1. Overview

리그/시즌 UI는 거래 화면(F1)과 완전히 분리된 F2 탭으로, 플레이어가 현재 시즌의
경쟁 현황을 한눈에 파악할 수 있는 대시보드다. 시즌 수익률, 티어 내 순위, 글로벌 순위,
주간 수익률/순위, 리더보드, 상금 현황을 제공한다. 거래 화면 상태바에는
**티어명+순위 · 시즌 수익률 · 주간 수익률**을 항상 표시하여 F2로 진입하지 않아도
핵심 지표를 확인할 수 있다. 장 중(`MARKET_OPEN`) F2 탭 진입 시 싱글플레이어 모드에서는
자동 일시정지가 발동되며, F1으로 복귀 시 재개된다. 멀티플레이어 모드에서는
일시정지 없이 탭 전환만 이루어진다.

## 2. Player Fantasy

장 마감 후 F2를 열면 "오늘 내가 몇 위였지?"가 한눈에 들어온다. 리더보드에서 바로 위
경쟁자와의 수익률 차이를 확인하고, "저 사람만 잡으면 한 계단 올라간다"는 집중감이 생긴다.
주간 수익률상 수상 여부가 매주 금요일 F2에서 확인되고, 시즌 상금 예상액이 실시간으로
갱신되며 "이번 시즌 끝나면 얼마 들어오지?"라는 기대감을 유지한다. 거래 화면을 떠나지
않아도 상태바의 세 숫자(순위·시즌 수익률·주간 수익률)가 경쟁 긴장감을 장 내내 유지시킨다.

## 3. Detailed Design

### 3-1. 전체 화면 구조 (네비게이션)

**씬 소유권 (TD 결정: Option B — 독립 씬 + MainScreen 부모)**

```
MainScreen.tscn
├── TabBar (상단 고정)
│    ├── [F1 거래]  → TradingScreen.tscn 인스턴스
│    ├── [F2 리그/시즌]  → LeagueScreen.tscn 인스턴스
│    └── [F3 성장]  → GrowthScreen.tscn 인스턴스
└── PauseOverlay (일시정지 배너, 필요 시 show)
```

- TabBar와 탭 전환 로직은 `MainScreen`이 소유
- 일시정지 호출(`GameClock.pause_request(source_id)` / `pause_release(source_id)`)도 `MainScreen`이 단일 진입점으로 처리 — 복수 일시정지 소스 충돌 방지
- F2와 F3는 동시에 열릴 수 없음 (탭 구조상 상호배제 보장)
- autoload(GameClock, PriceEngine 등)는 씬 트리와 무관하게 항상 실행

```
┌─────────────────────────────────────────────────────┐
│  [F1 거래]  [F2 리그/시즌]  [F3 성장]               │  ← MainScreen TabBar
├─────────────────────────────────────────────────────┤
│  (F2 활성 시 LeagueScreen 내용 표시)                  │
└─────────────────────────────────────────────────────┘
```

**탭 전환 일시정지 정책:**
- 장 중(`MARKET_OPEN`) + 싱글플레이어: F1 외 탭 클릭 시 `GameClock.pause_request("tab_switch")` + 배너 "⏸ 장 중 일시정지 — [F1] 거래로 돌아가기"
- F1 복귀 시: `GameClock.pause_release("tab_switch")`
- 멀티플레이어: `pause_request` 호출 없이 탭 전환만
- PRE_MARKET / MARKET_CLOSED: 일시정지 없이 자유 전환
- EC-08 참고: 싱글플레이어 전용. 멀티플레이어 설계 시 재검토 필요

### 3-2. 거래 화면 상태바 HUD

**통합 방식 (UX 결정: Option C — 행 2 우측 인라인)**

기존 상태바 2행 구조를 유지하고, 행 2 우측에 리그 HUD를 인라인 추가:

```
┌──────────────────────────────────────────────────────────────────────┐
│  시즌 3 | 2주차 화요일 | ■■■□ 틱 152/390 | ▶ 1x [⏸]               │  행 1 (변경 없음)
│  총 자산: ₩1,015,000 (+1.5%) | 시드: ₩300,000    [브론즈 38위] | 시즌 +12.3% | 주간 +2.1%  │  행 2 (우측 추가)
└──────────────────────────────────────────────────────────────────────┘
```

- 행 2를 좌우로 분할: 좌측 = 자산 정보 (기존), 우측 = 리그 HUD (신규)
- 리그 HUD 클릭 영역: 행 2 우측 전체 → F2 탭으로 이동
- 세로 공간 추가 소모 없음

| 항목 | 표시 형식 | 갱신 주기 | 클릭 동작 |
|------|----------|---------|---------|
| 티어명 + 순위 | `브론즈 38위` | 매 틱 | F2 탭으로 이동 |
| 시즌 수익률 | `시즌 +12.3%` (양수 빨강(`ThemeSetup.PRICE_UP`), 음수 파랑(`ThemeSetup.PRICE_DOWN`) — KRX 관행) | 매 틱 | F2 탭으로 이동 |
| 주간 수익률 | `주간 +2.1%` (양수 빨강(`ThemeSetup.PRICE_UP`), 음수 파랑(`ThemeSetup.PRICE_DOWN`) — KRX 관행) | 매 틱 | F2 탭으로 이동 |

> `trading-screen.md` 규칙 2의 상태바 다이어그램을 이 명세 기준으로 업데이트해야 한다.

### 3-3. F2 리그/시즌 화면 레이아웃

```
┌─────────────────────────────────────────────────────────┐
│  [F1 거래]  [F2 리그/시즌 ●]  [F3 성장]                │
├──────────────────┬──────────────────────────────────────┤
│  내 현황         │  리더보드 (티어 내)                   │
│ ─────────────── │ ─────────────────────────────────── │
│  티어: 브론즈    │  # │ 닉네임      │ 수익률  │ 상금예상 │
│  38위 / 7,600명  │ ───┼─────────────┼─────────┼──────── │
│                  │  1 │ 투자고수    │ +31.2%  │ 500,000 │
│  시즌 수익률     │  2 │ 황금손      │ +28.7%  │ 300,000 │
│  +12.3%          │  3 │ 차트마스터  │ +25.1%  │ 150,000 │
│  ₩1,000,000      │  4 │ 뉴스헌터    │ +22.4%  │  80,000 │
│  → ₩1,123,000    │  5 │ 저점매수    │ +20.8%  │  50,000 │
│                  │  6 │ 섹터분석가  │ +19.3%  │  30,000 │
│  주간 수익률     │  7 │ 단타왕      │ +17.7%  │  30,000 │
│  +2.1%           │  8 │ 장기투자자  │ +16.2%  │  30,000 │
│  (주간 순위 15위) │  9 │ 모멘텀라이더│ +14.8%  │  30,000 │
│                  │ 10 │ 리스크테이커│ +13.9%  │  30,000 │
│  주간 수익률상   │ ── │ ─────────── │ ─────── │ ─────── │
│  주간 15위       │ 36 │ 어제의나    │ +13.1%  │       — │
│  체결 3회 ✓      │ 37 │ 빠른매매    │ +12.8%  │       — │
│                  │▶38 │ 나 (YOU)    │ +12.3%  │       — │◀ 강조
│                  │ 39 │ 느린황소    │ +11.9%  │       — │
│                  │ 40 │ 분산왕      │ +11.5%  │       — │
│                  │ ─────────────────────────────────── │
│                  │  글로벌: 2,847위 / 20,000명          │
│                  │  (일 1회 갱신 — 어제 기준)            │
└──────────────────┴──────────────────────────────────────┘
```

**리더보드 규칙**:
- 1~`LEADERBOARD_FIXED_ROWS`위: 항상 고정 표시 (스크롤 없음, 고정 높이 컨테이너)
- 구분선 (──) 후 내 순위 ±`LEADERBOARD_CONTEXT_RANGE`위 표시
- 내 순위가 `LEADERBOARD_FIXED_ROWS + LEADERBOARD_CONTEXT_RANGE` 이내이면 구분선 없이 연속 표시
- 내 행(YOU) 배경색 강조
- 상금예상 열: `is_rank_eligible == false`이면 "체결 부족" 표시, 11위 이하는 "—"
- **거장 AI 행**: SeasonManager 리더보드 행 데이터의 `is_grandmaster_ai == true`이면 닉네임 옆에 `[거장]` 뱃지 렌더링 (season-manager.md §3-3 방침 참조)
- 전체 스크롤 없음 (D-03: Option A 확정)
- **글로벌 순위 패널** (`글로벌: 2,847위 / 20,000명`)은 스크롤 영역 **외부** 고정 — 리더보드 컨테이너 하단에 항상 표시

**주간 수익률상 좌측 패널 표시 상태:**

| 상태 | 표시 |
|------|------|
| 주간 집계 중 (금요일 장 마감 전) | `주간 순위 15위 (집계 중) / 체결 3회 ✓` |
| 수상 (주간 1위 + 자격 충족) | `🏆 주간 수익률상 수상! / 체결 3회 ✓` |
| 미수상 (자격 충족, 1위 아님) | `주간 순위 15위 / 체결 3회 ✓` |
| 자격 미달 (체결 부족) | `주간 순위 15위 / 체결 1회 ✗ (최소 2회 필요)` |
| 주간 집계 완료 (금요일 장 마감 후) | 위 상태에 `(확정)` 레이블 추가 |

## 4. Formulas

> **UI는 계산하지 않는다.** 모든 값은 SeasonManager 게터를 통해 수신한다.
> 공식의 단일 소스는 `season-manager.md`다.

### 4-1. 상태바 HUD 데이터 소스

```
# UI가 호출하는 게터 (계산은 SeasonManager 내부)
hud_tier_name    = SeasonManager.get_tier_name()
hud_tier_rank    = SeasonManager.get_tier_rank()
hud_season_return = SeasonManager.get_season_return_pct()  # % 단위
hud_weekly_return = SeasonManager.get_weekly_return_pct()  # % 단위
hud_day          = SeasonManager.get_current_trading_day() # "Day 8/20"

# 갱신 트리거: GameClock.on_tick 시그널 수신 시 호출
```

### 4-2. 리더보드 표시 범위

```
MERGE_THRESHOLD = LEADERBOARD_FIXED_ROWS + LEADERBOARD_CONTEXT_RANGE  # 기본 12

fixed_rows   = SeasonManager.get_leaderboard(tier, 1, LEADERBOARD_FIXED_ROWS)
context_rows = SeasonManager.get_leaderboard(tier, my_rank - LEADERBOARD_CONTEXT_RANGE,
                                                    my_rank + LEADERBOARD_CONTEXT_RANGE)

# 병합 규칙:
# my_rank ≤ MERGE_THRESHOLD → 구분선 없이 연속 표시
# my_rank > MERGE_THRESHOLD → fixed_rows + 구분선(──) + context_rows
```

### 4-3. 상금 예상액 (리더보드 열)

```
# UI는 SeasonManager.get_prize_preview(rank, tier) 호출
# 반환값 규칙 (SeasonManager 내부, season-manager.md §4-6 참조):
#   rank ≤ 10 AND is_rank_eligible  → 금액 문자열
#   rank ≤ 10 AND NOT is_rank_eligible → "체결 부족"
#   rank > 10 → "—"
```

## 5. Edge Cases

| # | 상황 | 처리 |
|---|------|------|
| EC-01 | 내 순위가 1~12위 이내 (±2 범위가 1~10 블록과 겹침) | 구분선 없이 1위부터 연속 표시. 내 행만 강조색 적용 |
| EC-02 | 내 순위가 최하위권 (예: 7,598위) — ±2위 하단이 존재하지 않음 | 존재하는 행까지만 표시 (7,598~7,600위) |
| EC-03 | 시즌 시작 직후 (season_start_deposit 스냅샷 직후 첫 틱) | 수익률 0.0% 표시. 나누기 0 방지: season_start_deposit > 0 가드 |
| EC-04 | 주간 첫날 (weekly_start_capital 스냅샷 직후) | 주간 수익률 0.0% 표시 |
| EC-05 | 프리마켓 상태 (리그 미참여) | F2 화면에 "현재 프리마켓 참여 중 — 공식 리그 순위 없음" 안내 표시. 리더보드 숨김 |
| EC-06 | 시즌 미시작 (첫 실행 또는 시즌 간 대기) | F2 화면에 "시즌 시작 전 — [시즌 시작] 버튼" 표시 |
| EC-07 | 글로벌 순위 데이터 미갱신 (당일 첫 장 마감 전) | "어제 기준" 레이블로 명시. 첫날은 "집계 전" 표시 |
| EC-08 | 장 중 F2 탭 진입 후 일시정지 상태에서 복귀 지연 | 일시정지는 플레이어가 F1으로 복귀할 때까지 유지. 타임아웃 없음 (싱글플레이어 전용. 멀티플레이어 설계 시 재검토 필요) |
| EC-09 | 동점 (동일 수익률) | 시즌 시작 시각 기준 먼저 진입한 참가자 우선. 동점 행은 같은 색으로 표시 |

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `SeasonManager` | 읽기 | `get_tier()`, `get_tier_rank()`, `get_global_rank()`, `get_season_return_pct()`, `get_weekly_return_pct()`, `get_weekly_tier_rank()`, `get_leaderboard(tier, range)` → 행마다 `{rank, nickname, return_pct, prize_preview, is_grandmaster_ai: bool}`, `get_prize_preview(rank, tier)`, `is_rank_eligible()`, `get_current_trading_day()` |
| `CurrencySystem` | (없음) | UI는 수익률을 직접 계산하지 않음. 모든 값은 SeasonManager 게터를 통해 수신. CurrencySystem 직접 의존 불필요 |
| `GameClock` | 구독 | `on_market_open` → 일시정지 해제 여부 판단; `on_tick` → HUD 갱신 트리거 |
| `TradingScreen` | 연동 | 상태바 HUD 컴포넌트 공유. F1/F2/F3 탭 전환 시 `toggle_pause()` 호출 |

**이 문서가 역참조되어야 하는 GDD:**
- `season-manager.md` — 순위·수익률·상금 산정 공식의 단일 소스
- `trading-screen.md` — 상태바 HUD 레이아웃 수정 필요 (§3-2 반영)
- `progression-ui.md` — F3 탭 구조 및 K키 동작 수정 필요

## 7. Tuning Knobs

| 파라미터 | 현재값 | 안전 범위 | 영향 |
|----------|--------|----------|------|
| `LEADERBOARD_FIXED_ROWS` | 10 | 5 – 20 | 항상 표시되는 상위권 행 수. 높을수록 경쟁 맥락 풍부, 화면 공간 소모 |
| `LEADERBOARD_CONTEXT_RANGE` | ±2 | ±1 – ±5 | 내 순위 주변 표시 범위. 넓을수록 맥락 풍부, 좁을수록 집중감 |
| `HUD_REFRESH_INTERVAL` | 매 틱 | 매 틱 – 5틱 | 상태바 갱신 주기. 높이면 성능 개선, 낮추면 수익률 실시간성 감소 |
| `GLOBAL_RANK_REFRESH` | 일 1회 | 일 1회 – 주 1회 | 글로벌 순위 갱신 빈도. 자주 갱신할수록 정렬 연산 비용 증가 (O(N log N), N=20,000) |

## 8. Acceptance Criteria

#### 상태바 HUD

- [ ] AC-01: 거래 화면 상태바에 티어명+순위, 시즌 수익률, 주간 수익률, Day X/20이 항상 표시된다
- [ ] AC-02: 시즌 수익률과 주간 수익률은 양수 빨강(`ThemeSetup.PRICE_UP`), 음수 파랑(`ThemeSetup.PRICE_DOWN`) — KRX 관행으로 색상 구분된다
- [ ] AC-03: 상태바의 순위/수익률 영역 클릭 시 F2 탭으로 이동한다

#### 탭 전환 및 일시정지

- [ ] AC-04: 싱글플레이어 + 장 중(`MARKET_OPEN`)에 F2 또는 F3 클릭 시 자동 일시정지되고 배너가 표시된다
- [ ] AC-05: F1 탭으로 복귀 시 일시정지가 해제되고 게임이 재개된다
- [ ] AC-06: 멀티플레이어 모드에서는 탭 전환 시 일시정지가 발동되지 않는다
- [ ] AC-07: PRE_MARKET, MARKET_CLOSED 상태에서는 탭 전환 시 일시정지가 발동되지 않는다

#### F2 리그/시즌 화면

- [ ] AC-08: 리더보드에 1~10위가 항상 고정 표시된다
- [ ] AC-09: 내 순위 ±2위가 구분선 후 표시된다. 내 순위가 12위 이내이면 구분선 없이 연속 표시된다
- [ ] AC-10: 내 행(YOU)이 배경색 강조로 구분된다
- [ ] AC-11: 상금예상 열은 `is_rank_eligible == false`일 때 "체결 부족"을 표시한다
- [ ] AC-12: 글로벌 순위는 "어제 기준" 레이블과 함께 표시된다. 시즌 첫날은 "집계 전" 표시된다
- [ ] AC-13: 프리마켓 참여 중에는 리더보드 대신 "프리마켓 참여 중" 안내가 표시된다
- [ ] AC-14: 시즌 미시작 상태에서는 "시즌 시작 전" 안내와 [시즌 시작] 버튼이 표시된다
- [ ] AC-15: 좌측 패널에 주간 수익률상 현황(주간 순위, 체결 횟수 자격 여부)이 표시된다
- [ ] AC-16: HUD 갱신(매 틱 SeasonManager 게터 호출 + 라벨 업데이트) 처리 시간이 16.6ms 이하임을 Godot 프로파일러로 확인한다. 측정 구간: `on_tick` 콜백 진입 ~ 모든 라벨 갱신 완료. 기준 환경: 프로젝트 최소 사양 기기 (미확정 시 개발 PC 기준, 별도 명시 필요)

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 상태바 HUD (티어·수익률) | `trading_screen.gd._update_status_bar()` — 매 틱 자동 갱신 ✅ 구현됨 |
| HUD → F2 탭 클릭 이동 | `trading_screen.gd._lbl_league_tier` `gui_input` → `league_tab_requested` 시그널 → `main_screen.gd._switch_tab(TAB_F2)` ✅ 구현됨 (S3-06) |
| F2 탭 전환 | `main_screen.gd._switch_tab(TAB_F2)` → `LeagueScreen.tscn` 인스턴스 표시 ✅ 구현됨 (S3-04) |
| 장 중 자동 일시정지 | `main_screen.gd._switch_tab()` → `GameClock.pause_request("tab_switch")` ✅ 구현됨 (S3-02/S3-04) |
| 리더보드 데이터 | `league_screen.gd._refresh()` → `SeasonManager.get_leaderboard()` ✅ 구현됨 (S3-05) |

### 의존 메서드 존재 확인

| 메서드 | 파일 | 상태 |
|--------|------|------|
| `SeasonManager.get_season_return_pct()` | `season_manager.gd` | ✅ |
| `SeasonManager.get_weekly_return_pct()` | `season_manager.gd` | ✅ |
| `SeasonManager.get_current_tier()` | `season_manager.gd` | ✅ |
| `SeasonManager.get_tier_name()` | `season_manager.gd` | ✅ |
| `SeasonManager.get_is_free_market()` | `season_manager.gd` | ✅ |
| `SeasonManager.get_leaderboard()` | `season_manager.gd` | ✅ (S3-03) |
| `SeasonManager.get_tier_rank()` | `season_manager.gd` | ✅ (S3-05 추가) |
| `SeasonManager.get_weekly_trade_count()` | `season_manager.gd` | ✅ (S3-05 추가) |
| `SeasonManager.is_season_trade_eligible()` | `season_manager.gd` | ✅ (S3-05 추가) |
| `GameClock.pause_request(source_id)` | `game_clock.gd` | ✅ (S3-02) |
| `GameClock.pause_release(source_id)` | `game_clock.gd` | ✅ (S3-02) |

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| AC-01 (HUD 표시) | `test_api_contracts.gd` | `test_season_manager_api()` | 부분 |
| AC-08 ~ AC-15 (F2 화면) | 미작성 | — | ❌ |
| AC-16 (프레임 버짓) | 퍼포먼스 프로파일링 | — | ❌ |

### 구현 완료 (S3-01 ~ S3-05)

1. ✅ `MainScreen.tscn` + F1/F2/F3 TabBar — `main_screen.gd` (S3-04)
2. ✅ `LeagueScreen.tscn` + `league_screen.gd` 구현 (S3-05)
3. ✅ `GameClock.pause_request/release()` 참조 카운팅 일시정지 (S3-02)
4. ✅ `SeasonManager.get_leaderboard()` 구현 (S3-03)
5. ✅ HUD 클릭 영역 → F2 탭 이동 (`league_tab_requested` 시그널, S3-06)

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
