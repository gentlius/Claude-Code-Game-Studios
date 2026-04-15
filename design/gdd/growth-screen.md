# F3 성장 화면 (Growth Screen)

> **Status**: In Review
> **Author**: user + agents
> **Last Updated**: 2026-04-14
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

## 1. Overview

F3 성장 화면은 플레이어의 트레이더 캐릭터 성장 상태를 전담하는 탭이다.
"내 트레이더가 얼마나 성장했고, 무엇을 해금할 수 있나?" 이 한 가지 질문에만 답한다.

레벨·XP 진행 바·가용 스킬 포인트(SP) 그리고 4브랜치 스킬 트리를 한 화면에 상시 펼쳐
보여준다. 팝업·오버레이 없음. 스킬 트리는 F3에서만 접근 가능하다.

스킬 트리 외에 **총 자산** (현금 자산 + 계좌 총 평가금액 + 유형자산)을 F3 하단에 표시한다.
세부 포트폴리오·거래내역은 F1 담당. 리그 순위는 F2 담당.

## 2. Player Fantasy

시즌이 끝났다. F3 탭을 누른다. 내 레벨과 XP 진행 바가 보인다.
스킬 포인트 1개가 빛나고 있다. 브랜치 4개가 펼쳐진다.
이동평균선? 빠른 뉴스? 지정가 주문? 종목 슬롯?
버튼 하나를 누른다. 해금. 다음 시즌, 차트가 달라 보인다.

## 3. Detailed Design

### 3-1. 화면 구성

F3 전체를 스킬 트리 한 가지가 채운다. 레이아웃:

```
┌─────────────────────────────────────────────────────────────┐
│  Lv.3    [████████████░░░░░░░░]  420 / 600 XP   SP: 1개    │  ← 상단 헤더 (1행)
├───────────────┬───────────────┬───────────────┬─────────────┤
│   분석 도구   │   시장 감지   │   거래 스킬   │  포트폴리오 │  ← 브랜치 헤더
├───────────────┼───────────────┼───────────────┼─────────────┤
│ ● 캔들+거래량 │ ● 뉴스 5분딜 │ ● 시장가 매매 │ ● 3종목 보유│
│   (기본 제공) │   (기본 제공) │   (기본 제공) │  (기본 제공)│
│       ↓       │       ↓       │       ↓       │      ↓      │
│ ✦ 이동평균선  │ ○ 빠른 뉴스  │ ○ 지정가 주문 │ ○ 5종목 보유│
│  [해금 가능]  │   [잠금]     │   [잠금]      │   [잠금]    │
│       ↓       │       ↓       │       ↓       │      ↓      │
│ ○ RSI/MACD   │ ○ 실시간 뉴스│ ○ 손절/익절   │ ○ 10종목   │
│   [잠금]      │   [잠금]     │ ←(A2 필요)    │   [잠금]    │
│       ↓       │       ↓       │       ↓       │      ↓      │
│ ○ 재무제표    │ ○ 루머 채널  │ ○ 공매도      │ ○ 섹터 ETF │
│   [잠금]      │   [잠금]     │   [잠금]      │ ←(A4 필요) │
│       ↓       │               │       ↓       │             │
│ ○ 섹터 비교   │               │ ○ 레버리지   │             │
│   [잠금]      │               │   [잠금]      │             │
├───────────────┴───────────────┴───────────────┴─────────────┤
│  ┌─ 노드 상세 패널 (클릭 선택 시 표시) ───────────────────┐  │
│  │  이동평균선 (분석 도구 A1)                              │  │
│  │  효과: 차트에 5일/20일 이동평균선 오버레이 표시         │  │
│  │  선행 조건: 없음   비용: SP 1개                        │  │
│  │                              [해금] (SP 보유 시 활성)  │  │
│  └─────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  총 자산  ₩123,456,789                                      │  ← 하단 자산 패널
│  현금 자산 ₩80,000,000  │  계좌  ₩43,000,000  │  유형 ₩456,789│
└─────────────────────────────────────────────────────────────┘
  ● 해금됨   ✦ 해금 가능 (SP 보유 + 선행 조건 충족)   ○ 잠금
```

노드 상세 패널은 스킬 트리 그리드 하단에 고정 배치된다 (팝업 아님).
노드를 선택하지 않은 초기 상태에서는 빈 상태 또는 가이드 텍스트를 표시한다.

### 3-2. 노드 상태 표시 (GDD skill-tree.md §States 참조)

| 상태 | 시각 표현 |
|------|----------|
| `UNLOCKED` | 채워진 원 ● + 스킬명 흰색 |
| `AVAILABLE` | 금색 별 ✦ + 스킬명 금색 + 펄스 애니메이션 + [해금] 버튼 활성 |
| `LOCKED` | 빈 원 ○ + 스킬명 회색 + [해금] 버튼 비활성 |
| `PREREQ_MISSING` | 빈 원 ○ + 스킬명 어두운 회색 + "선행 조건: XX 필요" 툴팁 |

크로스 브랜치 선행 조건(TR3←A2, P3←A4)은 화살표 라인으로 표시.

### 3-3. 헤더 (상단 1행)

| 요소 | 내용 | 데이터 소스 |
|------|------|-------------|
| 레벨 | `Lv.N` | `XpSystem.get_current_level()` |
| XP 진행 바 | 현재 XP / 다음 레벨 XP | `XpSystem.get_total_xp()`, `XpSystem.get_xp_progress()` |
| XP 숫자 | `N / M XP` | 위와 동일 |
| SP 카운트 | `SP: N개` | `XpSystem.get_available_skill_points()` (SP=0이면 표시 안 함) |

### 3-4. 스킬 해금 흐름

1. 플레이어가 `AVAILABLE` 노드 클릭 → 노드 상세(스킬명, 효과 설명, 선행 조건) 표시
2. [해금] 버튼 클릭 → `SkillTree.unlock_skill(id)` 호출
3. 해금 성공 → 노드 상태 `UNLOCKED`로 즉시 갱신, 헤더 SP 카운트 갱신
4. SP 부족 또는 선행 조건 미충족 시 [해금] 버튼 disabled (클릭 불가)

**갱신 트리거**: GrowthScreen은 두 가지 이벤트에서 전체 UI를 갱신한다.

| 트리거 | 처리 |
|--------|------|
| `SkillTree.on_skill_unlocked(skill_id)` | 노드 상태 + 헤더 SP 카운트 재렌더 |
| F3 탭 visibility 변경 (탭 전환 → F3 진입) | `_refresh()` 전체 갱신 — 다른 탭 체류 중 XP/SP가 변경될 수 있으므로 |

`XpSystem.xp_gained` / `XpSystem.level_up` 시그널은 GrowthScreen이 직접 구독하지 않는다.
F3 탭에 진입할 때 `_refresh()`가 호출되므로 최신 값이 보장된다.

### 3-5. 총 자산 표시 패널 (하단)

F3 스킬 트리 아래 고정 패널. 항상 표시 (탭 진입 시 갱신, `_refresh()` 포함).

| 요소 | 내용 | 데이터 소스 |
|------|------|-------------|
| 총 자산 (대형) | `₩NNN,NNN,NNN` | `PortfolioManager.get_total_assets()` |
| 현금 자산 | `₩NNN,NNN,NNN` | `CurrencySystem.get_cash_assets()` |
| 계좌 총 평가금액 | `₩NNN,NNN,NNN` | `PortfolioManager.get_account_total_value()` |
| 유형자산 | `₩NNN,NNN,NNN` | `LifestyleManager.get_tangible_value()` (Beta 구현 시, 그 이전 0 표시) |

총 자산 패널은 투자 대회 성과와 라이프스타일 성장의 합산 결과를 보여주는 "성장 체감" 핵심 요소다.
시즌 중에는 `계좌 총 평가금액`이 실시간으로 변하지 않는다 — F3 탭 진입 시 스냅샷 기준.

### 3-6. SP 알림 → F3 탭 연결

PRE_MARKET 상태에서 미사용 SP가 있을 때 상태바 하단에 알림이 표시된다.
알림을 클릭하면 F3 탭으로 이동한다. 텍스트에서 "K" 키 안내 제거.

```
[기존] "미사용 스킬 포인트 1개 — 스킬 트리 열기 K"  (Label, 클릭 불가)
[변경] "미사용 스킬 포인트 1개 — F3 성장 화면에서 해금"  (Button 또는 클릭 가능 Label)
       → 클릭 시 F3 탭 전환
```

### 3-7. 제거되는 요소

| 제거 항목 | 이유 | 대체 |
|----------|------|------|
| Status bar Row 2의 XpBar | 트레이딩 지표 영역에 성장 지표 혼재 | F3 헤더 |
| K 단축키 스킬트리 팝업 | F3가 상시 스킬트리를 표시 | F3 탭 (F3 키) |
| SkillTreeOverlay 팝업 | F3 임베드로 대체 | `growth_screen.gd` |
| LevelUpBanner의 "스킬 트리 열기  K" 버튼 텍스트 | K 단축키 제거, overlay 제거 | 버튼 텍스트 "해금하러 가기"로 변경 → F3 탭 전환 신호 |
| `status_bar.gd`에서 `xp_animate_requested` 구독 | XpBar가 StatusBar에서 제거됨 | 해당 연결 제거 (GrowthScreen은 탭 진입 시 갱신) |

## 4. Formulas

별도 산식 없음. XP·레벨·SP 공식은 `design/gdd/xp-system.md` 정본.
스킬 해금 조건은 `design/gdd/skill-tree.md` 정본.

## 5. Edge Cases

| 케이스 | 처리 |
|--------|------|
| SP = 0 | 헤더에서 "SP: 0개" 미표시. 모든 `AVAILABLE` 노드가 없으므로 UI 변화 없음 |
| 레벨 최대 (모든 스킬 해금) | XP 진행 바 100% 고정, "최대 레벨" 표시, SP 표시 없음 |
| 크로스 브랜치 선행 조건 미충족 | 노드 `PREREQ_MISSING` 상태. 툴팁: "공매도 해금에는 RSI/MACD(A2)가 필요합니다" |
| F3 장 중 접근 | MainScreen이 F1 이탈 시 자동 일시정지(ADR-006). F3도 동일 규칙 적용 (변경 없음) |
| SP 알림 클릭 → F3 전환 시 장 중 | ADR-006 pause_request 동일하게 트리거됨 |
| [해금] 버튼 빠른 이중 클릭 | `SkillTree.unlock_skill(id)` 첫 호출 후 노드 상태 즉시 `UNLOCKED`로 변경. 두 번째 클릭 시 이미 UNLOCKED이므로 `unlock_skill()` 내부에서 중복 호출 무시 (멱등성 보장). [해금] 버튼은 `UNLOCKED` 상태 전환 직후 비활성화됨 |
| 세이브/로드로 SP 조작 | 스킬 해금은 `SkillTree.save_data()`에 영구 저장됨. 슬롯 로드 시 해금된 스킬과 소비된 SP가 함께 복원됨. 해금 전 세이브 파일로 롤백하면 SP가 복구되나 스킬도 잠금으로 복구됨 → 순이익 없음 |

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `XpSystem` | → GrowthScreen | `get_current_level()`, `get_total_xp()`, `get_xp_progress()`, `get_available_skill_points()` |
| `SkillTree` | → GrowthScreen | `get_all_skills()`, `get_skill_state(id)`, `unlock_skill(id)`, `on_skill_unlocked` |
| `CurrencySystem` | → GrowthScreen | `get_cash_assets()` — 현금 자산 표시 |
| `LifestyleManager` | → GrowthScreen | `get_tangible_value()` — 유형자산 평가액. `get_current_residence()` — 거주지 배경 이미지 경로. `get_unlocked_items()` — 사치품 레이어 오브젝트 목록. `get_earned_titles()` — 획득 칭호 목록. (Beta 구현 시 추가) |
| `MainScreen` | ↔ GrowthScreen | F3 탭 씬 교체. `_switch_tab(TAB_F3)` 호출 수신 |
| `StatusBar` | → TradingScreen → MainScreen | SP 알림 클릭 시 3단 릴레이: `StatusBar.growth_tab_requested` → `TradingScreen.growth_tab_requested` → `MainScreen._switch_tab(TAB_F3)`. StatusBar는 TradingScreen 내부 자식이므로 TradingScreen이 릴레이를 담당한다 |
| `TradingScreen` | → MainScreen | `growth_tab_requested` 신호 (StatusBar + LevelUpBanner 릴레이). 동일 3단 구조 |
| `LevelUpBanner` | → TradingScreen | `skill_tree_requested` → TradingScreen이 `growth_tab_requested`로 릴레이 |
| `design/gdd/xp-system.md` | ← GrowthScreen | XpSystem API 소비자로 GrowthScreen 추가 필요 (역방향 의존 등록) |
| `design/gdd/skill-tree.md` | ← GrowthScreen | SkillTreeOverlay 제거 + F3 임베드로 변경 사항 반영 필요 |
| `ADR-006` | 준수 | F3도 F1 이탈 pause_request 규칙 동일 적용 |

## 7. Tuning Knobs

| 파라미터 | 현재값 | 범위 | 설명 |
|---------|--------|------|------|
| `SKILL_NODE_SIZE` | 64px | 48–80px | 노드 버튼 크기 |
| `PULSE_DURATION` | 1.5초 | 0.8–3.0초 | AVAILABLE 노드 펄스 주기 |
| `AVAILABLE_COLOR` | 금색 #D9B233 | — | 해금 가능 노드 강조색 |

## 8. Acceptance Criteria

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | F3 탭에 XP 바·레벨·SP 카운트가 표시된다 | 레벨 1 상태에서 F3 진입 확인 |
| AC-02 | 스킬트리 4브랜치가 노드 상태(●/✦/○)와 함께 표시된다 | F3 화면 육안 확인 |
| AC-03 | AVAILABLE 노드 클릭 → [해금] → 즉시 UNLOCKED 전환 | SP 보유 상태에서 해금 테스트 |
| AC-04 | SP 없을 때 [해금] 버튼 비활성화 | SP=0 상태에서 AVAILABLE 노드 클릭 |
| AC-05 | K 키를 눌러도 스킬트리 팝업이 뜨지 않는다 | F1 장 중 K 키 입력 |
| AC-06 | SP 알림 클릭 → F3 탭으로 전환된다 | PRE_MARKET + SP>0 상태에서 알림 클릭 |
| AC-07 | LevelUpBanner "해금하러 가기" 버튼 클릭 → F3 탭으로 전환된다 (구 텍스트 "스킬 트리 열기  K"에서 변경) | 레벨업 후 배너 버튼 클릭 |
| AC-08 | Status bar Row 2에 XP 바가 없다 | 화면 육안 확인 |
| AC-09 | F3 장 중 접근 시 ADR-006 pause_request 발동 | 장 중 F3 탭 전환 확인 |
| AC-10 | 크로스 브랜치 선행 조건 미충족 노드에 PREREQ_MISSING 툴팁 표시 | A2 미해금 상태에서 TR3 노드 클릭 |
| AC-11 | E2E: XP 충족 → 레벨업 → SP 알림 표시(F3로 이동 유도) → F3 탭 진입 → AVAILABLE 노드 클릭 → [해금] → SP 차감 확인 → 다음 시즌에서 해당 스킬 효과 동작 확인 | 시즌 종료 후 레벨업 상황에서 전체 흐름 수동 검증 |
| AC-12 | F3 하단 자산 패널에 총 자산·현금 자산·계좌 총 평가금액·유형자산이 표시된다 | F3 진입 후 패널 수치 확인 + 시즌 사이 현금 자산 변동 후 재진입하여 갱신 확인 |

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- F3 탭 전환: `MainScreen._switch_tab(TAB_F3)` → `GrowthScreen._ready()` 자동 렌더

### 호출 경로
- [ ] `main_screen.gd`: placeholder `_growth_screen` → `GrowthScreen` 씬 교체
- [ ] `growth_screen.gd`: 신규 작성. XP 헤더 + 4브랜치 스킬트리 임베드
- [ ] `status_bar.gd`: Row 2에서 `xp_bar` 제거. `_lbl_sp_alert` → 클릭 가능 Button 또는 Label로 교체, `growth_tab_requested` 신호 emit
- [ ] `status_bar.gd`: `growth_tab_requested` 신호 선언
- [ ] `trading_screen.gd`: `KEY_K` → `_toggle_skill_tree()` 블록 제거
- [ ] `trading_screen.gd`: `_status_bar.xp_bar.skill_tree_requested` 연결 제거 (xp_bar 없어짐)
- [ ] `trading_screen.gd`: `_skill_tree_overlay` 관련 코드 제거
- [ ] `trading_screen.gd`: `growth_tab_requested` 신호 선언 + LevelUpBanner `skill_tree_requested` → `growth_tab_requested` 재연결
- [ ] `trading_screen.gd`: `level_up_banner.gd` 버튼 텍스트 "스킬 트리 열기  K" → "해금하러 가기"로 변경
- [ ] `status_bar.gd`: `xp_animate_requested` 관련 구독 제거 (XpBar 제거에 따른 연결 정리)
- [ ] `main_screen.gd`: `TradingScreen.growth_tab_requested` → `_switch_tab(TAB_F3)` 연결
- [ ] `main_screen.gd`: `StatusBar.growth_tab_requested` 경로 확인 (StatusBar는 TradingScreen 내부 — TradingScreen이 릴레이)
- [ ] `skill_tree_overlay.gd`: 사용 제거 확인 (orphan 검사)
- [ ] `design/gdd/xp-system.md`: Dependencies 섹션에 GrowthScreen 소비자 추가
- [ ] `design/gdd/skill-tree.md`: SkillTreeOverlay 제거 + F3 임베드 변경 반영

### 의존하는 외부 메서드 존재 확인
- [ ] `XpSystem.get_current_level()` — 존재 확인
- [ ] `XpSystem.get_total_xp()` — 존재 확인
- [ ] `XpSystem.get_xp_progress()` — 존재 확인
- [ ] `XpSystem.get_available_skill_points()` — 존재 확인
- [ ] `SkillTree.get_all_skills()` — 존재 확인
- [ ] `SkillTree.get_skill_state(id)` — 존재 확인
- [ ] `SkillTree.unlock_skill(id)` — 존재 확인
- [ ] `SkillTree.on_skill_unlocked` 신호 — 존재 확인
- [ ] `PortfolioManager.get_total_assets()` — 존재 확인 (계좌 총 평가금액; 총 자산 패널의 "계좌" 수치)
- [ ] `CurrencySystem.get_cash_assets()` — 신규 추가 필요 (현금 자산 패널)
- [ ] `LifestyleManager.get_tangible_value()` — Beta 구현 시 추가 (유형자산 패널, 그 이전 0 반환)

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-03 | `tests/unit/test_skill_tree.gd` | `test_unlock_available_skill()` |
| AC-04 | `tests/unit/test_skill_tree.gd` | `test_unlock_fails_without_sp()` |
| AC-05 | 수동 플레이테스트 | — |
| AC-06 | 수동 플레이테스트 | — |
| AC-12 | 수동 플레이테스트 | — |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
