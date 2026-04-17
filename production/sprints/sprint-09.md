# Sprint 9 — 2026-04-17 to 2026-04-30

## Sprint Goal

TR3 공매도·TR4 레버리지로 고급 거래 브랜치를 완성하고, B-09 설정 화면으로
플레이어 제어권을 확보한다. 주봉/월봉 차트 구현의 선행 조건인 OHLCV
시즌 간 영구 히스토리 누적(TD-HIST-01)을 이 스프린트에서 해결한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 8 velocity: Must Have 6/6 ✅ Should Have 3/3 ✅ Nice-to-Have 0/1

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-01 | TR3 공매도 GDD 작성 (B-07b) | game-designer | 0.5 | — | `design/gdd/short-selling.md` 9개 섹션 완성. 공매도 개시·상환·강제청산 조건, 증거금 공식, 리스크 표시 패널 와이어프레임. S9-02 선행 조건. |
| S9-02 | TR3 공매도 구현 (B-07b) | gameplay-programmer | 1.5 | S9-01 완료 | **(1)** `OrderEngine`에 `SELL_SHORT` 주문 타입 추가. **(2)** 증거금 계산 + 강제청산 트리거 (`margin_ratio < 0.2`). **(3)** 포트폴리오 뷰에 공매도 포지션 표시 (음수 수량, 손익). **(4)** `SkillTree.has_short_selling()` 미해금 시 주문 거부. **(5)** 테스트 추가 + 빌드 성공. |
| S9-03 | TR4 레버리지 GDD 작성 (B-07c) | game-designer | 0.5 | — | `design/gdd/leverage-trading.md` 9개 섹션 완성. 레버리지 배율(2×/3×/5×), 이자 비용 공식, 마진콜 조건, 리스크 경고 UI. S9-04 선행 조건. |
| S9-04 | TR4 레버리지 구현 (B-07c) | gameplay-programmer | 1.5 | S9-03 완료 | **(1)** `OrderEngine`에 레버리지 배율 파라미터 추가. **(2)** 일별 이자 자동 차감 (`LifestyleManager.process_offseason()` 패턴 참조). **(3)** 마진콜 → 자동 포지션 청산. **(4)** `SkillTree.has_leverage()` 미해금 시 배율 선택 UI 잠금. **(5)** 테스트 추가 + 빌드 성공. |
| S9-05 | B-09 설정 화면 GDD + 구현 | game-designer + ui-programmer | 2.5 | — | **(1)** `design/gdd/settings-screen.md` 9개 섹션 완성 (볼륨 슬라이더, 뉴스 자동 감속 On/Off, 색각 모드, 키 리맵 와이어프레임). **(2)** `SettingsScreen` 씬: 볼륨 슬라이더 → `AudioManager` 연결, 뉴스 자동 감속 토글 → `GameClock.AUTO_SLOW_ON_EVENT` 적용. **(3)** 설정값 세이브/로드 직렬화. **(4)** `MainScreen` 탭바 또는 일시정지 메뉴에서 접근 가능. **(5)** 테스트 추가 + 빌드 성공. |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-06 | TD-HIST-01 OHLCV 시즌 간 영구 누적 (주봉/월봉 선행 조건) | gameplay-programmer | 1.5 | — | **(1)** `PriceEngine.ohlcv_daily`를 시즌 시작 시 초기화하지 않고 `season_id` 필드와 함께 누적. **(2)** `StockData.get_save_data()` / `load_save_data()`에 시즌 간 OHLCV 배열 직렬화 추가. **(3)** 세이브 파일 용량 검증 (10시즌 ≈ 2MB 이내). **(4)** 5시즌 이상 플레이 후 주봉/월봉 집계 데이터 로그 확인. **(5)** 테스트 추가. |
| S9-07 | TD-CR-03 SaveSystem.active_slot_id private 전환 | lead-programmer | 0.5 | — | `active_slot_id` → `_active_slot_id` (private). `get_active_slot_id()` getter 추가. 외부 직접 쓰기 6개 테스트 파일 `before_each` 패턴 수정. 기존 테스트 전부 통과. |
| S9-08 | TD-CR-11 UIState enum 중복 통합 | lead-programmer | 0.5 | — | `ui_state_types.gd` (autoload 또는 `src/core/`) 공유 enum 파일 생성. `StatusBar.UIState` / `TradingScreen.UIState` 양쪽 참조를 공유 enum으로 교체. 기존 테스트 전부 통과. |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-09 | TD-CR-06 portfolio_view.gd 메서드 분리 | lead-programmer | 0.5 | — | `_on_stop_take_btn_pressed()` 138줄 → `_build_stop_take_dialog()` 등으로 분리, 각 함수 40줄 이내. Stop/Take 다이얼로그 문자열에 `tr()` 추가. |
| S9-10 | TD-AUDIT-01 settlement_reporter.gd 레이스 컨디션 조사 | qa-lead | 0.5 | — | 팝업 닫힘 중 타이머 발화 재현 시도. 재현 성공 시 수정 + 테스트. 재현 불가 시 "재현 불가 확인" 주석 + tech-debt 항목 종결. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 6.5 (S9-01×0.5 + S9-02×1.5 + S9-03×0.5 + S9-04×1.5 + S9-05×2.5) |
| Should Have | 2.5 (S9-06×1.5 + S9-07×0.5 + S9-08×0.5) |
| Nice to Have | 1.0 |
| **Must Have 적합성** | **6.5 / 8 ✅** |
| **전체 합계** | **10.0 (buffer 내 Must Have 소진 — Should Have는 우선순위 순 진행)** |

## Critical Path

```
Day 0:    S9-01 TR3 GDD (game-designer)
          S9-03 TR4 GDD (game-designer, 병행)
          S9-05 설정화면 GDD + 구현 착수 (ui-programmer, 병행)
Day 1-2:  S9-02 TR3 구현 (S9-01 완료 후)
          S9-04 TR4 구현 (S9-03 완료 후, S9-02와 병행 가능)
Day 3-4:  S9-06 TD-HIST-01 OHLCV 누적 (Should Have, 병행)
Day 5:    S9-05 설정화면 완성 + 세이브/로드
Day 6:    S9-07 SaveSystem private 전환
          S9-08 UIState enum 통합
Day 7-8:  S9-09 portfolio_view 분리 (Nice-to-Have)
          S9-10 settlement_reporter 레이스 컨디션 조사 (Nice-to-Have)
```

## DoD (Definition of Done)

- [ ] S9-01: `design/gdd/short-selling.md` 9개 섹션 Approved
- [ ] S9-02: TR3 해금 → 공매도 주문 E2E + 강제청산 트리거 확인 + 테스트 통과 + 빌드 성공
- [ ] S9-03: `design/gdd/leverage-trading.md` 9개 섹션 Approved
- [ ] S9-04: TR4 해금 → 레버리지 주문 E2E + 마진콜 자동 청산 확인 + 테스트 통과 + 빌드 성공
- [ ] S9-05: 설정화면 볼륨·자동감속 E2E + 세이브/로드 확인 + 빌드 성공
- [ ] S9-06 (Should Have): 5시즌 누적 데이터 세이브/로드 + 용량 검증 + 테스트 통과
- [ ] S9-07 (Should Have): `active_slot_id` private 전환 + 기존 테스트 전부 통과
- [ ] S9-08 (Should Have): UIState 공유 enum 전환 + 기존 테스트 전부 통과
- [ ] `sprint-09.md` DoD 전 항목 `[x]` — Producer 확인
