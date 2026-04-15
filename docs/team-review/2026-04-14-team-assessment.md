# 팀 전체 기획 리뷰 — 2026-04-14

> **맥락**: Beta 마일스톤 진입 직전, GDD 일괄 감사(season-manager, save-load, portfolio-manager,
> currency-system, xp-system, lifestyle-spending 등 22개 파일) 완료 후 팀 전원이 게임 기획에
> 대해 자유롭게 의견을 제시한 기록. Creative Director 주재.

---

## 1. Creative Director

**총평**: 코어 게임플레이 루프는 탄탄하다. 판타지가 명확하고 진행 곡선도 설득력 있다.

**주요 의견**:
- **한강 엔딩의 서사 무게**: `cash_assets < 10,000원` 파산 조건이 코드에 있지만, 그 순간의 연출이
  아직 placeholder 수준이다. "1,000만원이었다가 10,000원 미만으로 무너진다"는 감정적 낙폭이
  게임의 가장 강한 서사 순간 중 하나여야 한다. Beta Sprint 9 이전에 연출 스크립트가 필요하다.
- **이중 승리 경로 의미 차이**: 현금 1,000억(루트 A)과 총 자산 1조(루트 B)가 같은 "거장" 엔딩으로
  수렴하는데, 두 경로를 걷는 플레이어의 경험과 감정이 달라야 한다. 루트 A는 "현금 집중, 안전
  플레이"; 루트 B는 "부동산·스타트업 등 자산 다각화, 고위험 고수익". 현재 엔딩 연출이 이를
  반영하지 않는다.
- 해결 방향: Narrative Director에게 두 루트 각각의 엔딩 대사·분위기 차이를 설계하도록 위임.

---

## 2. Game Designer

**총평**: 시스템 설계는 완성도 높다. 시즌당 20거래일·4주 구조는 검증된 리듬이다.

**주요 의견**:
- **프리마켓 참여도 부족**: 현재 PRE_MARKET은 "장 시작 버튼 누르는 곳"에 그친다. 뉴스 확인,
  포지션 계획, 전일 차트 검토 등 플레이어의 분석 행위를 유도하는 요소가 필요하다.
  예: PRE_MARKET 전용 분석 메모장, 종목별 예상 방향 태깅, 알림 프리셋.
- **세션 단위 체감 확인**: TICKS_PER_DAY=1560, BASE_TICK_INTERVAL=0.192s → 1거래일=5분(1x 기준).
  1주=25분 순수 거래시간 + PRE_MARKET 사고시간 ≈ 40-55분. game-concept.md의 "30-60분 세션"
  (주 단위)과 수치적으로 일치함을 재확인. **조치 불필요.**
- **주간 리포트 강화**: 4개 주간 리포트가 세션의 자연스러운 종료점이 되어야 한다.
  현재 리포트는 정보 제공에 그치고 있어, 다음 세션 시작을 유인하는 훅이 약하다.

---

## 3. Lead Programmer

**총평**: 코드베이스는 ADR로 잘 관리되고 있다. GDD-코드 불일치 1건이 Beta 블로커다.

**주요 의견**:
- **[CRITICAL] API 이름 불일치 — Beta Sprint 7 블로커**:
  GDD는 `season_start_deposit`을 명시하지만, 코드는 `_season_start_capital` /
  `get_season_start_capital()` / JSON key `"season_start_capital"`을 사용한다.
  영향 파일: `portfolio_manager.gd`, `season_manager.gd`, `portfolio_view.gd`, `league_screen.gd`.
  세이브 파일 마이그레이션 로직도 동시에 작성해야 한다.
- **익스플로잇 방어 ADR 필요**: 가격 정찰 익스플로잇(동일 날 반복 로드) 방어 설계가 ADR 없이
  구현되면 향후 혼란을 초래한다. ADR-018 작성 필수.
- 테스트 커버리지: `tests/unit/test_api_contracts.gd`에 `season_start_deposit` 계약 테스트 추가 필요.

---

## 4. QA Lead

**총평**: 기능 구현은 충실하나, 테스트 명세의 측정 방법이 모호한 항목이 많다.

**주요 의견**:
- **수동 플레이테스트 AC의 측정 기준 불명확**: 여러 GDD의 "수동 플레이테스트" 항목이
  "재미있어야 한다" 수준으로 모호하다. 합격/불합격 기준을 수치 또는 체크리스트로 변환해야 한다.
  예: `AC: 주간 리포트를 읽은 후 세션 지속 의향 조사 → 3명 중 2명 이상 "계속하고 싶다"`.
- **Beta 판정기준 측정법 미정**: `beta.md`의 "3시즌 후 4시즌 하고 싶은가" 기준에
  측정 방법(대상 인원, 플레이테스트 세션 설계, 판정 방식)이 없다.
  → 플레이테스트 프로토콜 문서(`docs/testing/playtest-protocol-beta.md`) 작성 필요.
- **이중 승리 조건 Beta DoD 누락**: `beta.md` Success Criteria에 "현금 자산 ≥ 1,000억 OR
  총 자산 ≥ 1조로 거장 엔딩 도달 가능 경로 검증"이 빠져 있다.

---

## 5. Producer

**총평**: 마일스톤 진행은 순조롭다. Beta Sprint 7~10 계획이 명확하다.

**주요 의견**:
- **Art/Audio 스케줄 공백**: Art Director의 아트 바이블 작업과 Audio Director의 앰비언트
  음악 계획이 어떤 스프린트에도 태스크로 등록되지 않았다. Sprint 7에서 주 1세션 규모로
  반드시 스케줄링한다.
- **가격 정찰 익스플로잇 차단이 Sprint 7 Must Have**: 유저가 "반드시 막아"를 명시했으므로
  Must Have로 분류. ADR + 구현 포함.
- **P-RULE-02 준수 확인**: Sprint 6 DoD 전 항목 `[x]` 여부를 Sprint 7 착수 전에 교차 확인.

---

## 6. Narrative Director

**총평**: 세계관과 배경 서사는 완성도 있다. 인게임 서사 훅이 현재 너무 조용하다.

**주요 의견**:
- **티어업 순간의 서사 훅 부재**: 플레이어가 브론즈 → 실버 → 골드로 올라갈 때 단순 UI 팝업 외에
  서사적 텍스트가 없다. 짧은 1-2줄 대사("여의도에서 너의 이름이 들리기 시작했다")로
  성취감을 증폭시킬 수 있다. 스킬 트리 해금과도 연동 가능.
- **한강 엔딩 대사 초안**: Creative Director 요청에 따라 루트 A(현금 집중)와 루트 B(자산 다각화)
  두 버전의 엔딩 대사 초안을 Sprint 8 전에 작성.
- **시즌 테마 뉴스 텍스트**: 테마별 뉴스 이벤트 텍스트(현재 placeholder)를 Beta Sprint 9에서
  완성. 테마가 플레이어에게 "읽히는 재미"를 제공해야 한다.

---

## 7. Art Director

**총평**: 기능 구현 중심으로 진행되어 비주얼 방향이 아직 정의되지 않았다. 적극적으로 주도해야 한다.

**주요 의견 및 자체 제안 (Sprint 스케줄 요청)**:
- **[URGENT] 아트 바이블 미작성**: 색상 팔레트, 타이포그래피, UI 컴포넌트 스타일 가이드가 없는
  상태다. 현재 ThemeSetup이 임시 값으로 운영 중. Sprint 7에서 아트 바이블 초안 1세션을 배정해야
  한다. 자체 일정: Sprint 7 Week 1.
- **[URGENT] 거주지 배경 비주얼 정의**: 11개 거주지 티어(쪽방→개인 섬)의 배경 이미지 스타일이
  결정되지 않았다. 픽셀아트인가, 미니멀 벡터인가, 포토리얼인가. Sprint 7에서 레퍼런스 무드보드
  작성 + 방향 결정. 자체 일정: Sprint 7 Week 2.
- **UI 비주얼 감사**: 현재 trading_screen, portfolio_view, league_ui의 색상 사용이 ThemeSetup을
  일관적으로 따르는지 감사. Sprint 8.

---

## 8. Audio Director

**총평**: SFX 4종 완료, BGM 스타트 스크린 완료. 인게임 앰비언트는 아직 비어 있다.

**주요 의견 및 자체 제안 (Sprint 스케줄 요청)**:
- **[URGENT] 앰비언트 음악 계획 미수립**: 시장 상태(PRE_MARKET, MARKET_OPEN, MARKET_CLOSED,
  PAUSED)별 BGM 테마가 정의되지 않았다. "데이 트레이딩 분위기 — 긴장감 있되 집중 방해 안 됨"이라는
  방향성은 있으나 구체적 레퍼런스·악기 구성이 없다. Sprint 7에서 앰비언트 음악 계획서 작성.
  자체 일정: Sprint 7 Week 1.
- **코어 SFX 가이드 완성**: `DOWNLOAD_GUIDE`에 S-11~S-14 가이드 초안이 있다.
  Sprint 7에서 오디오 디렉터가 직접 완성본을 제출. 자체 일정: Sprint 7 Week 2.
- **VI/CB 발동음 설계**: VI 발동(서킷브레이커 느낌), CB(강제 정지 경보) 두 이벤트의 SFX
  성격이 아직 명세화되지 않았다. Sprint 8에서 설계.

---

## 요약 테이블

| 팀원 | 핵심 이슈 | 긴급도 | 배정 스프린트 |
|------|-----------|--------|--------------|
| Creative Director | 한강 엔딩 연출 미비, 이중 승리 루트 서사 차이 | Medium | S8 |
| Game Designer | 프리마켓 참여도 설계, 주간 리포트 훅 강화 | Low | S9 |
| Lead Programmer | API 이름 불일치 (`season_start_capital` → `season_start_deposit`) | **CRITICAL** | **S7** |
| Lead Programmer | 가격 정찰 익스플로잇 방어 ADR+구현 | **CRITICAL** | **S7** |
| QA Lead | 수동 플레이테스트 AC 합격 기준 수치화 | Medium | S7 |
| QA Lead | Beta 판정기준 측정 프로토콜 문서 작성 | High | S7 |
| QA Lead | Beta DoD에 이중 승리 조건 추가 | High | S7 |
| Producer | Art/Audio 스케줄 확보 | High | S7 |
| Narrative Director | 티어업 서사 훅 텍스트, 엔딩 대사 초안 | Medium | S8 |
| Art Director | 아트 바이블 초안, 거주지 배경 방향 결정 | High | **S7** |
| Audio Director | 앰비언트 음악 계획서, SFX 가이드 완성 | High | **S7** |

---

## 액션 아이템 (리더그룹 결의)

리더그룹(creative-director · technical-director · producer + tier-2 전원)은 위 의견에서
아래 Sprint 7 Must Have 태스크를 추출한다:

1. **S7-01** API 이름 일치화: `season_start_capital` → `season_start_deposit` (코드 + 세이브 마이그레이션)
2. **S7-02** 가격 정찰 익스플로잇 차단: ADR-018 + `PriceEngine._rng` 세션 엔트로피 구현
3. **S7-03** Beta DoD 업데이트: 이중 승리 조건 검증 항목 추가
4. **S7-04** QA 플레이테스트 프로토콜 문서 작성
5. **S7-05** Art Director: 아트 바이블 초안 + 거주지 배경 방향 결정
6. **S7-06** Audio Director: 앰비언트 음악 계획서 + SFX 가이드 완성

> 이 문서는 팀 기록용이며, 세션 간 결정 근거로 보존된다.
> 작성일: 2026-04-14 | 다음 리뷰: Beta 종료 직전 (Sprint 10 완료 후)
