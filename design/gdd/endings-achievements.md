# 엔딩 & Steam 업적 (Endings & Achievements)

> **Status**: In Review (S10-03 Beta 구현 완료 — Steam·DLC·Polish 항목 잔여)
> **Author**: game-designer + creative-director
> **Created**: 2026-04-20
> **Last Updated**: 2026-04-23
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 체감있는 성장 (Feel the Growth)

---

## 1. Overview

시드머니는 세 가지 엔딩과 이를 포함한 Steam 업적 시스템을 가진다.

- **배드 엔딩 2종**: 잘못된 판단의 결과로 즉각 또는 점진적으로 게임이 종료된다.
  - **한강 엔딩**: 프리마켓에서 자산이 완전히 소진될 때 발동하는 점진적 파산 엔딩.
  - **사채업자 엔딩**: 레버리지 강제청산으로 채무 상환 불능 시 즉각 발동하는 과부채 엔딩.
- **굿 엔딩 1종**: 장기 성장의 최종 목표.
  - **투자의 거장 엔딩**: 시즌 정산 후 현금 자산 1,000억 원 돌파 시 발동.

Steam 업적은 엔딩 3종을 포함하여 플레이어의 특이한 행동·성취를 기록한다.
이 문서는 모든 엔딩과 업적의 단일 진원지(Single Source of Truth)다.
각 엔딩의 게임플레이 메카닉 명세는 원본 GDD를 우선한다 (§6 참조).

---

## 2. Player Fantasy

**MDA 타깃 Aesthetics**: Sensation(충격), Fellowship(공감), Discovery(발견)

**한강 엔딩**: 플레이어는 수십 번의 거래일 끝에 서서히 무너진다. 프리마켓 화면에 혼자
남겨진다. 더 이상 살 것도 팔 것도 없다. 조용한 종료다. "그래, 이건 내 잘못이었지."

**사채업자 엔딩**: 갑작스럽다. 레버리지 베팅이 역방향으로 움직이고, 강제청산이 실행되고,
잔고가 0이 되는 그 순간 경보음이 울린다. 화면이 빨갛게 물든다. 사채업자 화면이 뜬다.
한강과 달리 시간이 없다. 레버리지라는 칼을 들었다가 스스로 베인 것이다.

**투자의 거장 엔딩**: 마지막 시즌 정산 숫자가 올라간다. 1,000억 돌파. 팡파레.
쪽방에서 시작해 개인 섬을 넘어 자선 재단 설립까지. 성장 서사의 완결.

---

## 3. Detailed Rules

### 3-1. 한강 엔딩

**발동 조건**:
```
시점: PRE_MARKET 상태 진입 시 (1회 체크)
전제: _is_free_market == true (자유 시장 티어 강등 상태)
AND:  PortfolioManager.get_all_holdings().is_empty() == true
AND:  CurrencySystem.get_sim_cash() < HANGANG_THRESHOLD (10,000원)
```

**보장 조건**:
- `_ending_triggered == false`일 때만 발동 (중복 방지)
- 보유 주식이 1주라도 있으면 미발동 (EC-01)

**발동 주체**: `SeasonManager._on_market_state_changed()`

**시그널**: `SeasonManager.on_hangang_ending_triggered()`

**연출**:
- 블랙유머 텍스트 메시지 ("한강바람이 불어옵니다" 또는 유사)
- 세이브 초기화 — 100만 원으로 재시작 (스킬 트리는 영구 유지)
- 연출 상세: UI 스프린트에서 정의

---

### 3-2. 사채업자 엔딩

**발동 조건**:
```
시점: 레버리지 강제청산 실행 직후 (장 중)
전제: net_proceeds < 0
AND:  abs(net_proceeds) > CurrencySystem.get_sim_cash()  (채무 상환 불능)
```

**처리 순서**:
```
1. 가용 현금 전액 차감 (sim_cash → 0)
2. on_loan_shark_ending_triggered 발동 즉시 return
3. 포지션 제거·정리 불요 (게임오버이므로)
```

**발동 주체**: `LeverageManager._forced_liquidation()`

**시그널**: `LeverageManager.on_loan_shark_ending_triggered(stock_id: String, net_proceeds: int)`

**연출**:
- 빨간 화면 플래시 + 사이렌 사운드
- "채무 상환 불능 — 법원 집행관이 도착했습니다" 류의 화면 (구체 텍스트: 내러티브 팀 결정)
- 세이브 초기화 — 100만 원으로 재시작 (스킬 트리 영구 유지)
- 연출 상세: UI 스프린트에서 정의

**한강 엔딩과의 차이**:
| 구분 | 한강 엔딩 | 사채업자 엔딩 |
|------|----------|-------------|
| 경로 | 점진적 자산 소진 | 레버리지 강제청산 즉각 |
| 시점 | PRE_MARKET 진입 시 | 장 중 (틱 처리 중) |
| 선행 조건 | 보유 주식 없음 + 현금 부족 | TR4 레버리지 보유 + 폭락 |
| 연출 | 조용하고 무거운 | 갑작스럽고 공격적 |
| 트리거 시스템 | SeasonManager | LeverageManager |

---

### 3-3. 투자의 거장 엔딩

**발동 조건**:
```
시점: 시즌 정산 완료 직후 (settle_to_cash() 완료 후)
조건: post_liquidation_assets >= ENDING_THRESHOLD (100,000,000,000원)
```

**처리 순서**:
```
1. SeasonManager.settle_to_cash() 완료
2. post_liquidation_assets 계산
3. >= ENDING_THRESHOLD → _ending_triggered = true
4. on_master_ending_triggered.emit()
```

**발동 주체**: `SeasonManager._settle_season()`

**시그널**: `SeasonManager.on_master_ending_triggered()`

**연출**:
- 팡파레 + 전용 엔딩 화면 (grandmaster_ending.png)
- "자선 재단 설립, 전설로 추앙" 내러티브
- 차기 회차 금수저 모드(1억 원 시작) 해금
- 연출 상세: UI 스프린트에서 정의

---

### 3-4. Steam 업적

| ID | 업적명 | 조건 | 숨김 여부 | 연동 트리거 |
|----|--------|------|----------|------------|
| ACH-01 | **투자의 거장** | 투자의 거장 엔딩 달성 | 공개 | `SeasonManager.on_master_ending_triggered` |
| ACH-02 | **한강의 바람** | 한강 엔딩 달성 | 숨김 | `SeasonManager.on_hangang_ending_triggered` |
| ACH-03 | **빚의 무게** | 사채업자 엔딩 달성 (레버리지 청산 파산) | 숨김 | `LeverageManager.on_loan_shark_ending_triggered` |

> **숨김 업적 원칙**: 숨겨진 업적(ACH-02, ACH-03)은 Steam 업적 창에서 달성 전까지
> 이름·설명·아이콘이 노출되지 않는다. 발견의 쾌감을 보호하기 위함이다.

> **미정 업적**: ACH-01~03은 확정. 추가 업적은 §3-5 Candidate Pool 검토 후 이 표로 승격.
> **이 표에 추가된 항목 = 즉시 구현 대상.** 미확정 상태로 이 표에 올리는 것은 금지.

---

### 3-5. 엔딩·업적 변경 프로토콜

> **원칙**: §3-1~3-4와 §9 Candidate Pool은 항상 동기화된다.
> 아이디어 단계에서는 Candidate Pool에만 존재한다. 이 섹션(§3-1~3-4)에 올라온 순간 구현 의무가 발생한다.

#### 신규 엔딩 추가

```
1. Candidate Pool 등록 (§9 마지막 섹션)
   → 트리거 조건 초안 + 담당 시스템 명시
2. game-designer + creative-director 승인
3. §3에 트리거 조건 전체 명시 (§3-1~3-3 형식 동일)
4. §8 AC 추가
5. §9 구현 체크리스트 추가 (트리거 코드 + MarketProfile endings 블록 + .po 키)
6. Candidate Pool 항목 제거 (중복 관리 금지)
```

**코드 수정 범위**: 트리거 담당 시스템 파일 1개 + market_kr.json + .po.  
`if market == "KR"` 분기 신규 추가 금지 (ADR-021).

#### 신규 업적 추가

```
1. Candidate Pool 등록 (§9 마지막 섹션)
   → 조건 초안 + 연동 시그널 후보 명시
2. game-designer 승인 (단독 결정 가능)
   숨김 여부는 creative-director와 협의
3. §3-4 업적 표에 행 추가 (ID는 ACH-NN 순번)
4. §9 구현 체크리스트에 Steam.activate_achievement() 연결 항목 추가
5. Steam 파트너 대시보드에 업적 등록 (release-manager 담당)
6. Candidate Pool 항목 제거
```

**ID 규칙**: 기본 게임 `ACH-NN`, DLC 전용 `ACH_{MARKET}_NN` (예: `ACH_US_01`).  
**Steam 대시보드 등록**은 코드 머지와 별도로 release-manager가 직접 수행.

#### 엔딩·업적 제거 또는 조건 변경

```
1. 변경 이유를 §3 해당 항목 주석으로 명시
2. game-designer + qa-lead 동시 승인 (테스트 영향 범위 확인)
3. 코드 수정 → 테스트 동시 갱신 (별도 커밋 금지 — coding-standards.md 원칙)
4. 이미 Steam에 등록된 업적 제거는 불가 (Steam 정책).
   조건 완화는 가능, 완전 삭제는 "레거시" 태그로 표에 유지.
```

---

## 4. Formulas

### F1. 한강 엔딩 조건

```
trigger = is_free_market
       AND holdings.is_empty()
       AND sim_cash < HANGANG_THRESHOLD
```

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `is_free_market` | bool | SeasonManager | 자유 시장 강등 여부 |
| `holdings.is_empty()` | bool | PortfolioManager | 보유 주식 0종목 |
| `sim_cash` | int | CurrencySystem | 현재 예수금 |
| `HANGANG_THRESHOLD` | int | season_config.json | 기본값 10,000원 |

### F2. 사채업자 엔딩 조건

```
net_proceeds = (current_price × quantity) - borrowed - accrued_interest
trigger = net_proceeds < 0
       AND abs(net_proceeds) > CurrencySystem.get_sim_cash()
```

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `net_proceeds` | int | LeverageManager | 강제청산 순수익 (음수) |
| `sim_cash` | int | CurrencySystem | 강제청산 직전 예수금 |

### F3. 투자의 거장 엔딩 조건

```
post_liquidation_assets = cash_assets  (settle_to_cash() 완료 후)
trigger = post_liquidation_assets >= ENDING_THRESHOLD
```

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `post_liquidation_assets` | int | CurrencySystem | 시즌 청산 후 현금 자산 |
| `ENDING_THRESHOLD` | int | season_config.json | 기본값 100,000,000,000원 |

---

## 5. Edge Cases

| 시나리오 | 처리 방식 | 근거 |
|---------|----------|------|
| **사채업자 + 한강 동시 발동 가능성** | 불가. 사채업자 엔딩은 장 중 즉각 발동 → 게임오버. 한강 엔딩은 PRE_MARKET 진입 시 체크. 사채업자 엔딩이 먼저 발동하면 PRE_MARKET에 도달하지 않는다. | 시점 분리 보장 |
| **사채업자 + 거장 동시 가능성** | 불가. 거장 엔딩은 시즌 정산 후 발동. 사채업자 엔딩은 장 중. 강제청산 후 sim_cash < 0(채무 불능) 상태에서 거장 엔딩 임계값 도달 불가. | 수학적으로 불가 |
| **한강 + 거장 동시 가능성** | 불가. `_ending_triggered` 플래그가 선착 발동 1건만 허용. 거장 조건(1,000억)에서 한강 조건(현금 1만원 미만) 동시 충족 불가. | 수학적으로 불가 |
| **세이브 초기화 후 업적 상태** | Steam 업적은 서버 측 보관 — 세이브 초기화 후에도 유지. | Steam SDK 표준 동작 |
| **같은 회차에 사채업자 엔딩 재발동** | 엔딩 화면 표시 후 세이브 초기화 → 새 게임 시작. 재발동은 새 게임의 새 이벤트. 동일 회차 내 중복 발동 없음. | 게임오버 직후 씬 전환 |
| **TR4 미해금 상태에서 사채업자 엔딩** | 발동 불가. TR4 없으면 레버리지 포지션 자체가 없음. | 전제 조건 |
| **시즌 종료 강제청산 중 사채업자 엔딩** | `LeverageManager.liquidate_all_positions()` (시즌 종료 시)도 `_forced_liquidation()`을 재사용. 따라서 시즌 종료 청산 중에도 초과 손실 발생 시 사채업자 엔딩 발동 가능. 시즌 정산(거장 엔딩 체크) 이전이므로 우선 발동. | 메서드 재사용 + 시점 선착 |

---

## 6. Dependencies

| 시스템 | 방향 | 의존 성격 | 인터페이스 |
|--------|------|----------|-----------|
| **SeasonManager** | 엔딩이 의존 | Hard | `on_master_ending_triggered()` — 거장 엔딩 시그널. `on_hangang_ending_triggered()` — 한강 엔딩 시그널. |
| **LeverageManager** | 엔딩이 의존 | Hard | `on_loan_shark_ending_triggered(stock_id, net_proceeds)` — 사채업자 엔딩 시그널. |
| **CurrencySystem** | 엔딩이 의존 | Hard | `get_sim_cash()` — 사채업자/한강 조건 평가. |
| **PortfolioManager** | 한강 엔딩 의존 | Hard | `get_all_holdings()` — 보유 주식 0 여부 체크. |
| **GameMain / MainScreen** | UI가 엔딩 시그널 수신 | Soft | 시그널 연결 후 엔딩 화면 전환. 씬 구성: UI 스프린트에서 결정. |
| **SaveSystem** | 엔딩이 의존 | Hard | 세이브 초기화 (한강/사채업자 엔딩) 또는 특수 상태 저장 (거장 엔딩). |
| **AudioManager** | 엔딩이 의존 | Soft | 사채업자 엔딩: 사이렌/경보음. 거장 엔딩: 팡파레. |
| **SteamAPI** | 업적 등록 의존 | Soft | `Steam.activate_achievement("ACH_ID")` — 각 엔딩 시그널 핸들러에서 호출. Godot Steam GDExtension 사용. |

**역방향 고지**:
- `season-manager.md` §8 AC-03(거장), AC-05(한강)는 이 문서 AC와 교차참조.
- `leverage-trading.md` §8 AC-17(사채업자)는 이 문서 AC와 교차참조.

---

## 7. Tuning Knobs

| Parameter | Category | Current Value | Safe Range | Effect |
|-----------|----------|--------------|------------|--------|
| `HANGANG_THRESHOLD` | Gate | 10,000원 | 1,000 ~ 50,000 | 한강 엔딩 발동 기준. 낮을수록 생존 구간이 길어짐. |
| `ENDING_THRESHOLD` | Gate | 100,000,000,000원 | — | 거장 엔딩 발동 자산. 게임의 최종 목표이므로 변경 시 전체 밸런스 재검토 필수. |

두 값 모두 `assets/data/season_config.json`에 외부화. 하드코딩 금지.

---

## 8. Acceptance Criteria

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-E01 | PRE_MARKET 진입 시 보유 주식 없음 AND sim_cash < 10,000원이면 `on_hangang_ending_triggered` 발동 | 단위 테스트: `test_season_manager.gd::test_hangang_ending_triggered()` ✅ 구현됨 |
| AC-E02 | 보유 주식이 1주라도 있으면 한강 엔딩 미발동 | 단위 테스트: `test_season_manager.gd::test_hangang_not_triggered_with_holdings()` ✅ 구현됨 |
| AC-E03 | 시즌 정산 후 cash_assets ≥ 1,000억이면 `on_master_ending_triggered` 발동 | 단위 테스트: `test_season_manager.gd::test_master_ending_triggered()` ✅ 구현됨 |
| AC-E04 | 레버리지 강제청산 후 손실 > 가용 현금이면 `on_loan_shark_ending_triggered` 발동, sim_cash == 0 | 단위 테스트: `test_leverage_trading.gd::test_forced_liquidation_excess_loss_triggers_loan_shark_ending()` ✅ 구현됨 |
| AC-E05 | 한강 엔딩과 거장 엔딩이 동시 발동하지 않는다 (`_ending_triggered` 플래그 보장) | 단위 테스트: `test_season_manager.gd` 기존 테스트에서 묵시적 보장 |
| AC-E06 | 사채업자 엔딩 발동 시 Steam 업적 ACH-03 ("빚의 무게") 활성화 | 플레이테스트: Steam 업적 창 확인 (UI 스프린트) |
| AC-E07 | 한강 엔딩 발동 시 Steam 업적 ACH-02 ("한강의 바람") 활성화 | 플레이테스트: Steam 업적 창 확인 (UI 스프린트) |
| AC-E08 | 거장 엔딩 발동 시 Steam 업적 ACH-01 ("투자의 거장") 활성화 | 플레이테스트: Steam 업적 창 확인 (UI 스프린트) |
| AC-E09 | ACH-02, ACH-03는 Steam에서 숨김 업적으로 등록되어 달성 전 이름/설명 비노출 | Steam 파트너 대시보드 설정 확인 |
| AC-E10 | 세이브 초기화 후 Steam 업적 상태는 유지된다 | Steam SDK 표준 동작 — 별도 테스트 불필요 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 엔딩 | 발동 위치 | 시그널 |
|------|----------|--------|
| 한강 엔딩 | `season_manager.gd::_on_market_state_changed()` | `SeasonManager.on_hangang_ending_triggered` |
| 사채업자 엔딩 | `leverage_manager.gd::_forced_liquidation()` | `LeverageManager.on_loan_shark_ending_triggered` |
| 투자의 거장 엔딩 | `season_manager.gd::_settle_season()` | `SeasonManager.on_master_ending_triggered` |

### 구현 완료 항목

- [x] `SeasonManager.on_hangang_ending_triggered` 시그널 정의 및 발동 로직
- [x] `SeasonManager.on_master_ending_triggered` 시그널 정의 및 발동 로직
- [x] `LeverageManager.on_loan_shark_ending_triggered` 시그널 정의
- [x] `LeverageManager._forced_liquidation()` — 0-클램프 제거 + 초과 손실 시 시그널 발동

### 구현 완료 항목 (S10-03)

- [x] `GameMain` — `on_hangang_ending_triggered` 연결 → `EndingScreen.show_ending("bankruptcy")`
- [x] `GameMain` — `on_master_ending_triggered` 연결 → `EndingScreen.show_ending("win")`
- [x] `GameMain` — `on_loan_shark_ending_triggered` 연결 → `EndingScreen.show_ending("leverage_crash")`
- [x] `src/ui/ending_screen.gd` — 단일 씬 3종 엔딩 (ending_id 파라미터 기반 데이터 바인딩)
- [x] 세이브 초기화 플로우: `GameMain._on_ending_new_game_requested()` → `SaveSystem.delete_slot()` + StartScreen 전환
- [x] 거장 엔딩: `grandmaster_ending.png` 비주얼, `continue_requested` 시그널 → StartScreen 전환
- [x] `src/ui/margin_call_popup.gd` — 증거금 비율 < 임계값 경고 팝업 (CanvasLayer layer=6)
- [x] TradingScreen — `MarginCallPopup` 인스턴스화 (자체 시그널 연결)
- [x] `src/ui/portfolio_view.gd` — TR4 레버리지 포지션 섹션 (배율·손익·증거금비율 실시간 표시)
- [x] `tests/unit/test_s10_03_ending_ui.gd` — AC-E10~E17 테스트 추가
- [x] `tests/unit/test_api_contracts.gd` — EndingScreen / MarginCallPopup API 계약 등록

### 잔여 항목 (Polish 스프린트)

- [ ] 사채업자 엔딩 전용 비주얼 에셋 (`assets/endings/kr_loan_shark.png`) — 아트팀
- [ ] Steam 업적 ACH-01~03 파트너 대시보드 등록
- [ ] Steam 업적 ACH-02, ACH-03 숨김 설정
- [ ] 각 엔딩 핸들러에서 `Steam.activate_achievement()` 호출 연결
- [ ] `AudioManager` — `sfx_ending_hangang` / `sfx_ending_loan_shark` / `sfx_ending_win` 등록
- [ ] TODO(S10-07): 엔딩 데이터 `MarketProfile.get_ending_param(ending_id, field)` 경유로 교체
- [ ] Steam 업적 ACH-01~03 파트너 대시보드 등록
- [ ] Steam 업적 ACH-02, ACH-03 숨김 설정
- [ ] 각 엔딩 핸들러에서 `Steam.activate_achievement()` 호출 연결
- [ ] `AudioManager` — 사채업자 엔딩 사이렌 SFX 등록
- [ ] `AudioManager` — 거장 엔딩 팡파레 SFX 등록
- [ ] 세이브 초기화 플로우: 한강/사채업자 엔딩 후 SaveSystem.reset_to_new_game() 호출

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| AC-E01 | `tests/unit/test_season_manager.gd` | `test_hangang_ending_triggered()` | ✅ |
| AC-E02 | `tests/unit/test_season_manager.gd` | `test_hangang_not_triggered_with_holdings()` | ✅ |
| AC-E03 | `tests/unit/test_season_manager.gd` | `test_master_ending_triggered()` | ✅ |
| AC-E04 | `tests/unit/test_leverage_trading.gd` | `test_forced_liquidation_excess_loss_triggers_loan_shark_ending()` | ✅ |
| AC-E05 | `tests/unit/test_season_manager.gd` | 기존 테스트 묵시적 보장 | ✅ |
| AC-E06~09 | 플레이테스트 / Steam 대시보드 | — | ⬜ Polish 스프린트 |
| AC-E10 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_bankruptcy_shows_hangang_title()` | ✅ |
| AC-E11 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_leverage_crash_is_bad_ending()` | ✅ |
| AC-E12 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_win_is_not_bad_ending()` | ✅ |
| AC-E13 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_bad_ending_action_emits_new_game_requested()` | ✅ |
| AC-E14 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_loan_shark_action_emits_new_game_requested()` | ✅ |
| AC-E15 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_win_action_emits_continue_requested()` | ✅ |
| AC-E16 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_unknown_id_falls_back_to_bankruptcy()` | ✅ |
| AC-E17 | `tests/unit/test_s10_03_ending_ui.gd` | `test_ending_screen_hides_after_action()` | ✅ |

### 빌드 검증

- [ ] `--export-release` 빌드 성공 (ERROR 없음)
- [ ] 바이너리 실행 후 5초 이상 프로세스 생존
- [ ] 실행 로그에 SCRIPT ERROR 없음
- [ ] 바이너리 실행 확인: QA Lead 서명 _______

### DLC 확장성 — MarketProfile 추상화 (Sprint 10, S10-07 — L-02)

> **팀 결정 (2026-04-20)**: Option A 만장일치. 엔딩 메커니즘(트리거 로직, 3종 구조)은 공유.
> 임계값·서사·비주얼은 `market_XX.json` `endings` 블록으로 완전 분리.  
> B(추가 엔딩 DSL) 보류 — 필요 시 GDScript 디스패치 함수로 구현.  
> 근거: [ADR-021](../../docs/architecture/021-market-profile-data-driven.md)

#### 1. market_kr.json `endings` 블록 추가

```json
"source_locale": "ko",
"endings": {
  "bankruptcy": {
    "threshold":  10000,
    "name_key":   "ENDING_KR_BANKRUPTCY_NAME",
    "body_key":   "ENDING_KR_BANKRUPTCY_BODY",
    "visual":     "res://assets/endings/kr_hangang.png"
  },
  "leverage_crash": {
    "name_key":   "ENDING_KR_LEVERAGE_NAME",
    "body_key":   "ENDING_KR_LEVERAGE_BODY",
    "visual":     "res://assets/endings/kr_loansharks.png"
  },
  "win": {
    "threshold":  100000000000,
    "name_key":   "ENDING_KR_WIN_NAME",
    "body_key":   "ENDING_KR_WIN_BODY"
  }
},
"achievements": []
```

- [ ] `assets/data/market_profiles/market_kr.json` — 위 `endings` + `source_locale` + `achievements` 블록 추가

#### 2. 코드 전환 (SeasonManager / LeverageManager)

- [ ] `MASTER_ENDING_THRESHOLD` 하드코딩 → `MarketProfile.get_ending_param("win", "threshold")` 로 교체
- [ ] `HANGANG_THRESHOLD` 하드코딩 → `MarketProfile.get_ending_param("bankruptcy", "threshold")` 로 교체
- [ ] 엔딩 이름·본문 문자열 → `tr(MarketProfile.get_ending_param("bankruptcy", "name_key"))` 경유 동적 생성
- [ ] 엔딩 비주얼 경로 → `MarketProfile.get_ending_param("bankruptcy", "visual")` 로 교체
- [ ] 엔딩 조건 텍스트("1,000억원 달성") → `FormatUtils.format_currency()` 경유 — 통화 단위 하드코딩 제거

#### 3. MarketProfile API 확장

- [ ] `MarketProfile.get_ending_param(ending_id: String, field: String) -> Variant` 메서드 추가
- [ ] `MarketProfile.get_dlc_achievements() -> Array` 메서드 추가 (빈 배열 기본값)

#### 4. 로컬라이제이션

- [ ] `locale/ko_endings.po` 분리 파일 생성 (엔딩 본문은 단문 headline과 혼재 금지)
- [ ] `project.godot` — `ko_endings.po` 추가 등록 (Godot 복수 .po 병합)
- [ ] `ko_endings.po` — `ENDING_KR_*` 키 6개 등록 (NAME + BODY × 3종)
- [ ] `en_endings.po` — KR 엔딩 영어 번역 + Cultural Note 주석 의무 등록

  ```
  # en_endings.po
  # Cultural note: "Han River" = Seoul's Han River, Korean cultural idiom for
  # financial despair/ruin. Retain proper noun. Do NOT simplify to generic river.
  msgid "ENDING_KR_BANKRUPTCY_NAME"
  msgstr "Han River Ending"
  ```

- [ ] 번역자 glossary — "한강 = Han River, Korean cultural idiom for financial ruin" 항목 등록 + 스크린샷 첨부

#### 5. DLC 시장 추가 시 프로토콜 (market_us.json 예시)

> DLC 시장 추가는 아래 파일만 건드리면 된다. 코드 수정 없음.

```json
// market_us.json
"source_locale": "en",
"endings": {
  "bankruptcy":     { "threshold": 100, "name_key": "ENDING_US_BANKRUPTCY_NAME", ... },
  "leverage_crash": { "name_key": "ENDING_US_LEVERAGE_NAME", ... },
  "win":            { "threshold": 100000000, "name_key": "ENDING_US_WIN_NAME", ... }
},
"achievements": [
  { "id": "ACH_US_01", "name_key": "ACH_US_01_NAME", "condition_ref": "us_recession_ending" }
]
```

- `source_locale: "en"` 명시 → 번역 추출 스크립트가 ko↔en 방향 역전 감지
- DLC 전용 Steam 업적: `achievements` 배열 → `SteamManager.register_dlc_achievements()` 호출

#### 6. 테스트

- [ ] `tests/unit/test_endings.gd` — `test_ending_thresholds_from_market_profile()` 추가
- [ ] `tests/unit/test_endings.gd` — `test_ending_name_key_from_market_profile()` 추가
- [ ] `tests/unit/test_market_profile.gd` — `test_endings_block_kr_loaded()` 추가

---

### Candidate Pool (폴리싱 검토 대상 — 미확정)

> **이 섹션에 있는 항목은 구현 의무 없음.**
> 팀 승인 후 §3-4(업적) 또는 §3-1~3-3(엔딩)으로 이동하고 이 표에서 제거.
> 승격 없이 오래 남은 항목은 주기적으로 폐기한다.

| ID | 종류 | 내용 | 조건 초안 | 담당 시그널 후보 | 상태 |
|----|------|------|----------|----------------|------|
| — | — | *(폴리싱 시작 시 채운다)* | — | — | — |
