# Sprint 8 — 2026-04-29 to 2026-05-12

## Sprint Goal

오더북(호가창) 구현으로 거래 깊이를 완성하고, A3 재무제표·S3 루머 채널로
분석 스킬 브랜치를 확장한다. 주거 아트 에셋 수령을 기점으로 라이프스타일 소비 시스템을
Sprint 9에서 앞당겨 구현한다. 설정 화면은 Sprint 9로 이월.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 7 velocity: Must Have 6/6 ✅ Should Have 3/3 ✅ Nice-to-Have 1/1 ✅

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S8-01 | 오더북 구현 (B-11) | lead-programmer + gameplay-programmer | 2.5 | `order-book.md` In Review | **(1)** `PriceEngine`에 per-stock `order_book` 상태 초기화 (`confirm_market_open()` 시점, §4-1 공식). **(2)** `OrderEngine`이 플레이어 주문 체결 시 호가 잔량 소진 + 슬리피지 적용. **(3)** `TradingScreen`에 10단 호가창 패널 (매도5·현재가·매수5) 상시 표시, 매 틱 갱신. **(4)** 장 마감 시 order_book 폐기 (저장 안 함). **(5)** 기존 테스트 전부 통과 + 오더북 신규 테스트. **(6)** `--export-release` 빌드 성공. |
| S8-02 | A3 재무제표 GDD 작성 | game-designer | 0.5 | — | `design/gdd/financial-statements.md` 9개 섹션 완성. PER/PBR/ROE 공식, 데이터 소스(`StockData`), 패널 레이아웃 wireframe. B-06 구현 선행 조건. |
| S8-03 | A3 재무제표 구현 (B-06) | gameplay-programmer | 1 | S8-02 완료 | **(1)** A3 해금 시 거래 화면 종목 패널에 PER/PBR/ROE 정보 표시. **(2)** `StockData`에 `per`, `pbr`, `roe` 필드 추가 (틱마다 경미하게 변동). **(3)** A3 미해금 시 패널 숨김/잠금 표시. **(4)** 테스트 추가 + 빌드 성공. |
| S8-04 | S3 루머 채널 GDD 작성 | game-designer | 0.5 | — | `design/gdd/rumor-channel.md` 9개 섹션 완성. 확률 70%, 선행 60틱, 방향 반전 엣지 케이스. B-07a 구현 선행 조건. |
| S8-05 | S3 루머 채널 구현 (B-07a) | gameplay-programmer | 1 | S8-04 완료 | **(1)** `NewsEventSystem`이 뉴스 발생 60틱 전 루머 시그널 발생. **(2)** 루머 정확도 70% — 30% 확률 방향 반전. **(3)** `SkillTree.has_rumor_channel()` 미해금 시 루머 수신 안 됨. **(4)** 뉴스 피드 UI에 루머 카드 스타일 구분. **(5)** 테스트 + 빌드 성공. |
| S8-06 | 라이프스타일 소비 시스템 구현 (B-12) | gameplay-programmer + ui-programmer | 2.5 | `lifestyle-spending.md` In Review ✅ | **(1)** `CurrencySystem.cash_deduct()` / `cash_add()` 추가. **(2)** `LifestyleManager`: `process_offseason()` — 임대 수익·스타트업 엑싯·Recurring 비용 자동 처리. **(3)** `LifestyleScreen`: 5개 카테고리 탭 + 잔여 자산 실시간 표시. **(4)** 거주지 업그레이드 "이사 날" 풀스크린 연출. **(5)** 세이브/로드 직렬화 추가. **(6)** 테스트 6개 + 빌드 성공. |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S8-07 | 주거 시각화 시스템 (B-02) | gameplay-programmer + ui-programmer | 1.0 | 주거 아트 에셋 수령 ✅ | **(1)** `GrowthScreen` F3 배경 = 현재 거주지 이미지 레이어드 구조. **(2)** 거주지 변경 시 F3 배경 즉시 반영. **(3)** 빌드 성공. (아트 에셋 2026-04-15 수령 완료 — B-02 조건 충족) |
| S8-08 | Beta QA 10일 시나리오 — A3·S3·라이프스타일 검증 추가 | qa-lead | 0.5 | S8-03, S8-05, S8-06 완료 | A3 재무제표 + S3 루머 + 라이프스타일 비시즌 정산을 `docs/testing/` QA 시나리오에 추가. |
| S8-09 | 오더북 ADR 작성 (ADR-019) | technical-director | 0.5 | S8-01 완료 | `docs/architecture/019-order-book-price-impact-model.md` 작성. `technical-preferences.md` ADR 목록 추가. |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S8-10 | start-screen.md Implementation Checklist 검증 | qa-lead | 0.5 | — | `design/gdd/start-screen.md` Checklist 항목 실제 구현 여부 확인. 미구현 항목 tech-debt 등록 또는 `[x]` 체크 완결. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 8.0 (S8-01×2.5 + S8-02×0.5 + S8-03×1 + S8-04×0.5 + S8-05×1 + S8-06×2.5) |
| Should Have | 2.0 (B-02×1.0 + S8-08×0.5 + S8-09×0.5) |
| Nice to Have | 0.5 |
| **Must Have 적합성** | **8.0 / 8 ✅** |
| **전체 합계** | **10.5 (buffer 내 Must Have 소진 — Should Have는 우선순위 순 진행)** |

## Critical Path

```
Day 0-1:  S8-01 오더북 구현 착수 (PriceEngine + OrderEngine)
          S8-02 A3 재무제표 GDD (game-designer, 병행)
          S8-04 S3 루머 채널 GDD (game-designer, 병행)
Day 2:    S8-06 설정 화면 GDD + 구현 착수 (병행 가능)
Day 3-4:  S8-03 A3 재무제표 구현 (S8-02 완료 후)
          S8-05 S3 루머 채널 구현 (S8-04 완료 후)
Day 5:    S8-01 오더북 UI 패널 완성
Day 6:    S8-07 QA 시나리오 추가 (S8-03, S8-05 완료 후)
          S8-08 ADR-019 작성 (S8-01 완료 후)
Day 7-8:  S8-09 start-screen 검증 (Nice-to-Have)
```

## DoD (Definition of Done)

- [ ] S8-01: 10단 호가창 UI 표시 + 슬리피지 체결 E2E 동작 확인 + 빌드 성공
- [ ] S8-02: `design/gdd/financial-statements.md` 9개 섹션 Approved
- [ ] S8-03: A3 해금 → PER/PBR/ROE 패널 표시 확인 + 테스트 통과 + 빌드 성공
- [ ] S8-04: `design/gdd/rumor-channel.md` 9개 섹션 Approved
- [ ] S8-05: S3 해금 → 루머 60틱 선행 수신 + 30% 반전 확인 + 테스트 통과 + 빌드 성공
- [ ] S8-06: 라이프스타일 비시즌 정산 E2E + 소비 화면 + 거주지 연출 + 세이브/로드 + 빌드 성공
- [ ] S8-07 (Should Have): B-02 주거 시각화 F3 배경 전환 확인 + 빌드 성공
- [ ] S8-08 (Should Have): QA 시나리오 문서 업데이트
- [ ] S8-09 (Should Have): ADR-019 작성 + `technical-preferences.md` 링크 추가
- [ ] `sprint-08.md` DoD 전 항목 `[x]` — Producer 확인
