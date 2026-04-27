# GDD 크로스 리뷰 리포트 — 2차 (2026-04-23)

**리뷰 일자**: 2026-04-23  
**대상 GDD**: 34개  
**시스템 수**: 39개  
**이전 리뷰**: 2026-04-23 1차 (`design/gdd-cross-review-2026-04-23.md`) — 9 BLOCKING + 24 WARNING 해소  
**이번 범위**: 신규 이슈만 (이전 해소 항목 제외)

---

## 최종 판정: 🔴 FAIL

BLOCKING 4건 해결 전까지 아키텍처 시작 불가.

---

## Consistency Issues (Phase 2)

### 🔴 BLOCKING — 4건

**NEW-B01 — season-manager.md §3-3 AI API 이름 obsolete**
- `AiCompetitor.get_tier_return_pct(participant_id)`, `get_all_return_pcts(tier)` 존재하지 않음
- 실제 API (ai-competitor.md §3-4): `get_eod_snapshot(tier)`, `get_sorted_indices(tier)`, `estimate_player_rank(player_pct)`
- season-manager.md만 보고 구현 시 인터페이스 오류 필연

**NEW-B02 — news-events.md §5-4 "정확도 70%" 미갱신**
- Line 538: "정확도 70% — 30% 확률로 방향 반전"
- B-09 fix로 55%로 변경됐으나 이 파일 누락 → 이 파일만 보면 지배 전략 익스플로잇 재생성

**NEW-B03 — rumor-channel.md Edge Case "70% 수렴" 미갱신**
- Line 222: "30% 반전 / 장기 통계로만 70% 수렴"
- 같은 파일 §F1에서 55%로 수정했으나 Edge Case 절 누락 → 동일 문서 내 자기 모순

**NEW-B04 — rumor-channel.md AC-04 테스트 함수명 obsolete**
- Line 310: `test_accuracy_converges_to_70pct()`
- AC-04 어설션은 55%인데 함수명이 70% → 구현자 혼란

---

### ⚠️ WARNING — 10건

**NEW-W01** — ai-competitor.md §4-2 레전드 sigma 예시 오류  
Line 255: `sigma_daily = 15 / sqrt(20) ≈ 3.4%` → 레전드 sigma_tier=28%, 정답: `28 / sqrt(20) ≈ 6.3%`

**NEW-W02** — systems-index.md GDD Status 11개 불일치  
index "In Review" vs 실제 파일 "Approved": game-clock, news-events, order-engine, currency-system, trading-screen, chart-renderer, news-feed-ui, portfolio-ui, growth-screen, start-screen, stop-loss-take-profit

**NEW-W03** — portfolio-manager.md Tuning Knobs max_holdings 이중 소유  
B-07 단일화했으나 portfolio-manager.md Tuning Knobs에 값 잔존 → skill-tree.md §F2 참조로 교체 필요

**NEW-W04** — game-clock.md 틱 처리 순서 Step 4/5 누락  
rule 7이 3단계만 명시. StopTakeSystem(Step 4), LeverageManager 마진콜(Step 5) 누락

**NEW-W05** — stop-loss-take-profit.md §6 "GDD 동기화 필요" 상태 불명확  
동기화 완료 여부가 §9 체크리스트와 불일치

**NEW-W06** — save-load.md LifestyleManager "미저장" vs lifestyle-spending.md §9 "완료" 모순

**NEW-W07** — order-book.md §3-5 블록6 설계-구현 불일치  
§3-5: "StockData 필드 필요, 미구현" vs §9: "PriceEngine 동적 계산으로 완료, StockData 필드 불필요"

**NEW-W08** — financial-statements.md vs financial-report-system.md PER 갱신 타이밍 미명시  
보고서 발표 후 StockData.per 덮어쓰기 시 PER_current 공식 의미 변화 — 두 GDD에 미서술

**NEW-W09** — sector-etf.md "10슬롯" 하드코딩  
B-07 단일 소유권 원칙 위반. `skill-tree.md §F2 참조`로 교체 필요

**NEW-W10** — max_short_positions 소유권 미선언  
short-selling.md §규칙11 정의, Tuning Knobs 섹션 없음, skill-tree.md 미등록

---

### ℹ️ INFO — 5건

**NEW-I01** trading-fees.md Dependencies "(신규)" 태그 stale  
**NEW-I02** lifestyle-spending.md Overview Alpha 폴백 공지 stale  
**NEW-I03** price-engine.md Overview "플레이어 매매가 가격에 영향 없다" stale (ADR-019 + 오더북 구현됨)  
**NEW-I04** game-clock.md Dependencies에 LifestyleManager on_market_close 구독 미등록  
**NEW-I05** design/CLAUDE.md "8 required sections" → 실제 9개

---

## Game Design Issues (Phase 3)

### 🔴 BLOCKING — 0건

### ⚠️ WARNING — 8건

**H3a-01** — 스킬 트리 소진(~4-5시즌) 후 XP 의미 소멸  
14 SP 전부 해금 후 Pillar 3(체감있는 성장) 기계적 표현 없음. economy-balance.md에 "Sprint 12+ 후속"으로만 언급.

**H3b-01** — 공매도 + 레버리지 마진 모니터링 인지 중복  
두 시스템의 "마진 비율 감시 → 청산 판단" 결정 패턴 동일. 늦은 게임에서 6-7개 동시 활성 시스템.

**H3c-01** — 공매도 대차료 없음 → 무비용 헤지  
long + short pairs trade 시 short leg 보유 비용 0. TR3+TR2+A4 조합으로 구조적 우위 형성.

**H3c-02** — 스타트업 C등급 EV≈2.48x → 거래 루프 우회  
IPO 30%×7.5x + M&A 20%×1.15x = EV≈2.48x. 충분한 cash_assets에서 거래 판단 없이 최적 전략이 됨.

**H3d-01** — 부동산 감가상각/유지비 없음 → 영구 자산 증가 루프  
rental income 2.5-4%/시즌 + 비용 0 = 매수 후 방치 최적. 양의 피드백 루프.

**H3e-01** — AI sigma 압축 vs 스킬 소진 난이도 미스매치  
스킬 소진 후에도 AI sigma 계속 줄어 난이도 상승. 성장 없이 난이도 증가. 설계 의도 미문서화.

**H3f-01** — 장학재단 50 XP가 Pillar 1(판단이 곧 실력) 위반  
거래 판단 없이 cash 지출 → XP 획득. BASE_SEASON_XP의 25%.

**H3g-01** — 프리마켓 0.5x XP 패널티 → 바닥에서 더 짓밟기  
"맨바닥에서 거장까지" 판타지와 충돌. 재기 서사가 아닌 스파이럴.

---

### ℹ️ INFO — 7건

H3a-02 중간 게임 메타 진행 우선순위 가이드 없음  
H3b-02 퍼즈 중심 플레이 스타일이 설계적으로 다뤄지지 않음  
H3c-03 루머 잔여 EV +0.52% — 의도적이며 허용 범위  
H3d-02 상위 티어 Recurring 생활비 무의미화  
H3e-02 시즌 상금 구조상 긴 후반 타임라인  
H3f-02 사회공헌 기부 XP 5점 — Pillar-safe  
H3g-02 라이프스타일 거주지 업그레이드 판타지 강화 (긍정)

---

## Cross-System Scenario Issues (Phase 4)

**⚠️ WARNING — Scenario A-1**: LeverageManager(Step 5) 강제청산 시 OrderEngine 재진입 여부 미명시  
**ℹ️ INFO — Scenario B-1**: 분기 보고서 후 PER_current 표시 의미 미명시  
**ℹ️ INFO — Scenario C-1**: LifestyleManager → SeasonManager 사이 cash_assets 동기성 미명시  
**ℹ️ INFO — Scenario D-1**: 공매도 + ETF 동시 보유 허용 여부 미명시

---

## 수정 이력 (이 리뷰 결과 적용)

| ID | 파일 | 수정 내용 | 적용일 |
|----|------|----------|--------|
| NEW-B01~B04 | season-manager, news-events, rumor-channel | BLOCKING 해소 | 2026-04-23 |
| NEW-W01~W10 | 다수 | WARNING 해소 | 2026-04-23 |
| H3c-01 | short-selling | 대차료 신설 (0.03%/일) | 2026-04-23 |
| H3c-02 | lifestyle-spending | C등급 확률 재조정 (IPO15%/M&A15%/실패70%) | 2026-04-23 |
| H3d-01 | lifestyle-spending | 부동산 유지비 신설 (0.5%/시즌) | 2026-04-23 |
| H3f-01 | lifestyle-spending | 장학재단 XP 제거 → 뉴스 딜레이 버프 | 2026-04-23 |
| H3g-01 | season-manager | 프리마켓 0.5x → 1.0x + 역경 보너스 | 2026-04-23 |
| H3a-01 | xp-system, skill-tree | 스킬 소진 후 설계 의도 명시 | 2026-04-23 |
| H3b-01 | short-selling, leverage-trading | 모니터링 UX 노트 추가 | 2026-04-23 |
| H3e-01 | ai-competitor, xp-system | 순수 판단 구간 설계 의도 명시 | 2026-04-23 |
