# 라이프스타일 소비 시스템 (Lifestyle Spending)

> **Status**: Draft (Skeleton)
> **Author**: user + agents
> **Last Updated**: 2026-04-14
> **Target Milestone**: Beta
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

---

## 1. Overview

> **Alpha 폴백**: 이 시스템은 Beta 스코프다. Alpha 빌드에서는 `LifestyleManager`가 존재하지 않으며,
> `SeasonManager._on_season_end()`는 `LifestyleManager.process_offseason()` 호출을 건너뛴다.
> Alpha 시즌 전환 흐름: 시즌 종료 → 강제 청산 → 상금 `settle_to_cash()` → PRE_SEASON 직접 진입.
> 라이프스타일 화면 없음, 거주지 배경 변경 없음, `tangible_assets = 0`으로 고정.
> Beta Sprint 9(B-02)에서 주거 아트 추가 시 이 시스템의 첫 기능이 활성화된다.

라이프스타일 소비 시스템은 투자 대회 경쟁과 병렬로 운영되는 자산 성장 루프다.
플레이어는 투자 수익을 현금 자산으로 전환하여 부동산·사치품·사회공헌·대안 투자 등에 지출하고,
이를 통해 총 자산(F3)이 성장하는 시각적·서사적 피드백을 받는다.

라이프스타일 소비는 **현금 자산**에서만 이루어진다. 경쟁 자금(예수금/계좌 총 평가금액)과
완전히 분리되어 있으며, 라이프스타일 지출이 다음 시즌 시드나 티어에 직접 영향을 주지 않는다.

**두 종류의 라이프스타일 이벤트:**
- **자동 정산** (장 종료 후 매일): 부동산 임대 수익, 사치품 Recurring 비용 등이 현금 자산에 자동 반영
- **능동 구매** (휴장 시간): 부동산·사치품 등 신규 구매. 매일 장 마감 후 접근 가능

---

## 2. Player Fantasy

<!-- TODO: 작성 예정 -->

---

## 3. Detailed Design

### 3-1. 라이프스타일 플로우

```
[장 종료 후 — 매일]
  ↓
[자동 라이프스타일 정산]
  ├─ 부동산 임대 수익 → 현금 자산 입금
  ├─ Recurring 비용 차감 (골프 클럽 연회비 등) → 현금 자산 차감
  └─ 스타트업 엑싯 이벤트 (만기 도달 시) → 현금 자산 입금 또는 0원
  ↓
[정산 리포트 시퀀스]
  일일 정산 리포트                           ← 매일
  → (5거래일째) 주간 정산 리포트             ← 주말에 추가
    → (20거래일째) 시즌 정산 리포트          ← 시즌 종료에 추가
  → 라이프스타일 정산 리포트                 ← 매일 항상 마지막
      (자동 정산 내역: 임대 수익 / 비용 / 엑싯 결과 요약)
  ↓
[휴장 시간 — 능동 구매 가능]
  ├─ 거주지 업그레이드
  ├─ 사치품 구매
  ├─ 대안 투자 (부동산 매입, 스타트업 투자)
  └─ 사회공헌

※ 시즌 종료 후: 예수금 전액 현금 자산 전환 → [시즌 시작 전]
```

### 3-2. 소비 카테고리

#### 카테고리 1: 거주지 (Residence)

<!-- TODO: 가격표, 업그레이드 경로, 언락 조건 -->

season-manager.md의 11단계 티어 거주지 진행표를 기반으로 한다.
티어 자산 임계값이 "해금" 조건이고, 명성 포인트 소비가 "실제 입주" 조건이다.

| 거주지 | 구매 비용 (cash_assets 차감) | 해금 조건 |
|-------|------------------------|---------|
| 고시원 | 기본 제공 | — |
| 원룸 월세 보증금 | TODO | TODO |
| 도심 오피스텔 전세 | TODO | TODO |
| 강남 아파트 | TODO | TODO |
| 한남더힐 펜트하우스 | TODO | TODO |
| 평창동 대저택 | TODO | TODO |
| 개인 섬 | TODO | TODO |

#### 카테고리 2: 사치품 (Luxury Goods)

<!-- TODO: 품목 목록, 가격, 칭호 연동 -->

일회성 구매. 구매 후 F3 화면 배경 레이어에 추가 요소로 합성된다.

| 품목 | 가격 | 획득 칭호 |
|------|------|---------|
| 수입차 (포르쉐 카이엔 급) | TODO | "수입차 애호가" |
| 명품 시계 (파텍 필립 급) | TODO | TODO |
| 프라이빗 골프 클럽 멤버십 | TODO (연회비 recurring) | "멤버스 온리" |
| 요트 계류권 | TODO | TODO |

#### 카테고리 3: 인맥/네트워크 (Network)

<!-- TODO: 한국 HNW 특유 카테고리. 효과 미정 -->

| 품목 | 비용 | 특이사항 |
|------|------|---------|
| 프라이빗 투자 클럽 연회비 | TODO | Recurring |
| 경제 포럼 VIP석 | TODO | 일회성 |

#### 카테고리 4: 사회공헌 (Social Contribution)

<!-- TODO: 재단 설립 조건, 칭호, XP 보너스 규칙 -->

| 품목 | 비용 | 보상 |
|------|------|------|
| 장학재단 설립 | TODO (고액 일회성) | F2 리그 프로필에 "[플레이어명] 장학재단" 표시, "사회공헌인" 칭호, XP 보너스 (시즌 1회 캡) |
| 사회적 기업 후원 | TODO | Recurring, XP 보너스 |
| 공익 캠페인 기부 | TODO | 일회성, 소액 XP |

#### 카테고리 5: 대안 투자 (Alternative Investments)

<!-- TODO: 수익률 공식, 랭킹 산정 제외 규칙, 엑싯 분포 확정 -->

**부동산 (임대 수익형)**

- 매입 시 cash_assets 차감 → 매 시즌 비시즌 정산 시 임대 수익 cash_assets 입금
- 수익률: 시즌당 TODO % (연 3~6% 기준 환산)
- 시즌 사이 매각 가능: 원가 ± 가격 변동 모디파이어
- **랭킹 산정에서 제외**: `account_total_value = sim_cash + reserved_cash + portfolio_value` (부동산 미포함)

| 부동산 종류 | 매입가 | 시즌 수익 | 비고 |
|-----------|--------|---------|------|
| 소형 오피스텔 | TODO | TODO | |
| 강남 상가 | TODO | TODO | |
| 빌딩 | TODO | TODO | |

**스타트업 엔젤 투자**

- 최소 투자금: TODO
- 만기: 투자 후 3~6시즌 (투자 시점에 랜덤 결정)
- 엑싯 확률 분포:

| 결과 | 확률 | 배수 |
|------|------|------|
| IPO | 20% | 2~5× |
| M&A 성사 | 50% | 1~1.5× |
| 폐업 | 30% | 0× |

### 3-3. 라이프스타일 소비 화면 레이아웃

<!-- TODO: 와이어프레임 -->

```
┌──────────────────────────────────────────────────────────────┐
│  [현재 거주지 배경 이미지 — 좌측 패널]  [소비 카테고리 탭 — 우측] │
│                                                              │
│  시즌 결산 자산: ₩3,200,000,000                               │
│  소비 후 잔여 (다음 시즌 시드): ₩2,800,000,000  ← 실시간 갱신   │
│                                          [다음 시즌 시작 →]   │
└──────────────────────────────────────────────────────────────┘
```

### 3-4. 거주지 업그레이드 연출 ("이사 날")

<!-- TODO: 연출 시퀀스 세부 타이밍, 오디오 큐 -->

1. 구매 확정 → 2단계 확인 클릭 (대금 차감 규모가 크므로 의도적 마찰)
2. 화면 페이드 블랙 1~2초
3. 새 거주지 배경 풀스크린 페이드인 — UI 전부 제거. 배경 + 앰비언트 오디오만. 3초 정지
4. 타이틀 카드 페이드인: 거주지명 + 지불 금액 소자. 2초
5. F3 UI 레이어인 → 정상 화면으로 복귀
6. 뉴스 피드 이벤트 생성: "[플레이어명] 트레이더, [거주지명] 입주"

### 3-5. F3 화면 연동

<!-- TODO: F3 레이아웃 변경 사항 확정 (growth-screen.md와 싱크) -->

- F3 화면 배경 = 현재 거주지 이미지
- 배경은 레이어드 구조: 기본 거주지 배경 + 사치품 오브젝트 레이어 (외제차, 명품시계 진열장 등)
- F3 하단: 현재 거주지명 + 획득 칭호 목록 표시
- 라이프스타일 소비 화면 진입 버튼 위치: TODO (비시즌 기간에만 활성)

#### 거주지 배경 에셋 현황

| 티어 | 거주지 | 파일 | 상태 |
|------|--------|------|------|
| 브론즈 (시작) | 쪽방/고시원 | `assets/art/housing/bronze_jjokbang.png` | ✅ 완료 |
| 실버 | 원룸 | — | ⬜ 미제작 |
| 골드 | 오피스텔 | — | ⬜ 미제작 |
| 플래티넘 | 강남 아파트 | — | ⬜ 미제작 |
| 다이아 | 한남더힐 펜트하우스 | `assets/art/housing/diamond_penthouse.png` | ✅ 완료 |
| 마스터+ | 평창동 대저택 / 개인 섬 | — | ⬜ 미제작 |

> 시작(쪽방)과 정점(펜트하우스) 이미지가 완성된 상태. 중간 티어 4개 제작 필요.
> 이미지 규격: TODO (diamond_penthouse.png 기준으로 통일 예정)

### 3-6. 칭호 시스템

<!-- TODO: 전체 칭호 목록, 복수 칭호 표시 규칙 -->

소비 마일스톤 달성 시 칭호 부여. F2 리그 프로필의 플레이어명 옆에 표시.

| 칭호 | 조건 |
|------|------|
| 건물주 | 부동산 TODO원 이상 보유 |
| 수입차 애호가 | 수입차 구매 |
| 멤버스 온리 | 프라이빗 클럽 가입 |
| 사회공헌인 | 재단 설립 또는 총 후원 TODO원 이상 |
| 투자의 신사 | 전 카테고리 1개 이상 해금 |

복수 칭호 보유 시: F2에 대표 칭호 1개 표시 (플레이어 선택).

---

## 4. Formulas

<!-- TODO: 작성 예정 -->

### 부동산 임대 수익

```
rental_income_per_season = property_value × RENTAL_YIELD_RATE
```

- `RENTAL_YIELD_RATE`: TODO (연 3~6% 기준, 시즌당 환산)
- 범위: [TODO, TODO]
- 예시: 강남 상가 10억 × TODO% = 시즌당 TODO만원

### 총 자산

```
total_assets = cash_assets + account_total_value + Σ(tangible_asset_values)

account_total_value = sim_cash + trading_pnl          # 시즌 중 (sim_cash = 예수금 잔액)
                    = 0                               # 시즌 시작 전 (예수금 입금 전)

tangible_asset_value = purchase_price
                     × (1 - DEPRECIATION_RATE) ^ seasons_held  # 고정 감가
                     × price_modifier                           # 확률 변동 + 이벤트 바이어스
```

### 일일 현금 자산 자동 정산

```
cash_assets += Σ(rental_income_today)
cash_assets -= Σ(recurring_costs_today)
cash_assets += Σ(startup_exit_proceeds_today)   # 만기 도달 시
```

### 시즌 정산 후 예수금 → 현금 자산 전환

```
cash_assets += account_total_value   # 예수금 + 시즌 거래 P&L 전액
account_total_value = 0
```

### 시즌 시작 전 예수금 자동 입금

```
season_start_deposit = tier_threshold(max_tier_accessible(cash_assets))
# 단, cash_assets ≤ 100만원이면 season_start_deposit = cash_assets (전액)
# 단, season_start_deposit < 100만원이면 출금 불가 (최소 보장)
sim_cash = season_start_deposit          # 예수금 자동 입금 (CurrencySystem.auto_deposit_to_sim())
cash_assets -= season_start_deposit
tier = tier_by_deposit(season_start_deposit)
```

---

## 5. Edge Cases

<!-- TODO: 작성 예정 -->

| 케이스 | 처리 |
|--------|------|
| 소비 후 잔여 자산 < 100만원 | 경고 표시: "소비 후 프리마켓으로 진입하게 됩니다". 확인 후 진행 가능 |
| 소비 후 잔여 자산 < 1만원 | TODO (한강 엔딩 트리거 여부) |
| 스타트업 엑싯 동시 2건 이상 | 순서대로 처리. 각각 별도 결과 카드 표시 |
| 부동산 매각 시 마이너스 수익 | 허용. 손실 확정 후 sim_cash 반영 |
| Recurring 비용 납부 불가 (잔액 부족) | TODO (체납 처리 규칙 미정) |
| 비시즌 윈도우 스킵 (소비 없이 바로 다음 시즌) | 허용. 비시즌 정산은 자동 처리, 소비만 선택사항 |
| 라이프스타일 소비 화면 중 앱 종료 | TODO (자동 저장 타이밍) |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `SeasonManager` | ← LifestyleSpending | 비시즌 윈도우 진입/종료 신호. 시즌 결산 자산 제공 |
| `CurrencySystem` | ← LifestyleSpending | `cash_deduct()` / `cash_add()` — 현금 자산 직접 차감/입금 |
| `SaveSystem` | ← LifestyleSpending | 보유 부동산, 스타트업 투자, 구매 품목, 칭호 직렬화 |
| `GrowthScreen (F3)` | ← LifestyleSpending | 현재 거주지 배경 이미지, 칭호 목록 표시 |
| `LeagueUI (F2)` | ← LifestyleSpending | 플레이어 칭호, 재단명 표시 |
| `NewsEventSystem` | ← LifestyleSpending | 대형 구매 시 뉴스 이벤트 생성 |
| `AudioManager` | ← LifestyleSpending | "이사 날" 연출 앰비언트 오디오 |
| `design/gdd/season-manager.md` | 준수 | 비시즌 윈도우 타이밍, 티어 배정 기준 |
| `design/gdd/growth-screen.md` | 싱크 필요 | F3 배경 레이어드 구조 |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 | 범위 | 설명 |
|---------|--------|------|------|
| `RENTAL_YIELD_RATE` | TODO | 0.01~0.03/시즌 | 부동산 시즌당 임대 수익률 |
| `STARTUP_IPO_PROB` | 0.20 | 0.10~0.30 | 스타트업 IPO 확률 |
| `STARTUP_MA_PROB` | 0.50 | 0.30~0.60 | M&A 성사 확률 |
| `STARTUP_FAIL_PROB` | 0.30 | 0.20~0.50 | 폐업 확률 |
| `STARTUP_MIN_SEASONS` | 3 | 2~4 | 스타트업 최소 만기 시즌 수 |
| `STARTUP_MAX_SEASONS` | 6 | 4~10 | 스타트업 최대 만기 시즌 수 |
| `PROPERTY_PRICE_VARIANCE` | TODO | ±0~30% | 부동산 매각 시 가격 변동 범위 |

---

## 8. Acceptance Criteria

<!-- TODO: 작성 예정 -->

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 비시즌 정산(임대 수익, 스타트업 엑싯, Recurring 비용)이 시즌 종료 후 자동 처리된다 | 부동산 보유 상태로 시즌 종료 후 cash_assets 갱신 확인 |
| AC-02 | 라이프스타일 소비 화면에서 구매 시 cash_assets가 즉시 차감된다 | 구매 전후 잔액 비교 |
| AC-03 | "소비 후 잔여" 수치가 구매 선택에 따라 실시간 갱신된다 | 여러 항목 선택 중 수치 변화 확인 |
| AC-04 | 소비 후 잔여 자산이 다음 시즌 시드 및 티어 배정 기준이 된다 | 의도적으로 티어 임계값 이하로 소비 후 티어 하락 확인 |
| AC-05 | 거주지 업그레이드 시 "이사 날" 연출이 재생된다 | 거주지 구매 후 풀스크린 페이드 연출 확인 |
| AC-06 | F3 화면 배경이 현재 거주지 이미지로 표시된다 | 거주지 변경 후 F3 진입 확인 |
| AC-07 | 획득 칭호가 F2 리그 프로필에 표시된다 | 칭호 조건 충족 후 F2 확인 |
| AC-08 | 부동산 자산이 리그 랭킹 산정 account_total_value에 포함되지 않는다 | 부동산 보유 상태에서 랭킹 계산 로직 검증 (유형자산은 tangible_assets 별도 집계) |
| AC-09 | 비시즌 윈도우 스킵 시 비시즌 정산은 자동 처리된다 | 소비 없이 "다음 시즌 시작" 클릭 후 임대 수익 반영 확인 |
| AC-10 | 소비 후 잔여 < 100만원이면 프리마켓 진입 경고가 표시된다 | 경고 없이 프리마켓 진입 불가 확인 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

> **⚠️ Beta 스코프 시스템. Alpha 완료 전 구현 시작 금지.**

### 진입점
- 비시즌 정산: `SeasonManager._on_season_end()` → `LifestyleManager.process_offseason()`
- 소비 화면: `LifestyleManager.offseason_settled` 신호 → `GameMain._show_lifestyle_screen()`

### 호출 경로

**비시즌 정산**
- [ ] `lifestyle_manager.gd`: 신규 작성. `process_offseason()` — 임대 수익, 스타트업 엑싯, Recurring 비용 순차 처리
- [ ] `lifestyle_manager.gd`: `offseason_settled` 신호 선언 + emit
- [ ] `season_manager.gd`: `_on_season_end()` 후 `LifestyleManager.process_offseason()` 호출 연결

**소비 화면**
- [ ] `lifestyle_screen.gd`: 신규 작성. 5개 카테고리 탭 + 잔여 자산 실시간 표시
- [ ] `game_main.gd`: `offseason_settled` 신호 → `_show_lifestyle_screen()` 연결

**F3 연동**
- [ ] `growth_screen.gd`: 배경 이미지 레이어드 구조로 변경 (거주지 레이어 + 사치품 오브젝트 레이어)
- [ ] `growth_screen.gd`: 하단 거주지명 + 칭호 표시 추가

**세이브/로드**
- [ ] `save_system.gd`: 라이프스타일 상태 직렬화 추가 (보유 부동산, 스타트업 투자, 구매 품목, 칭호)

### 의존하는 외부 메서드 존재 확인
- [ ] `CurrencySystem.cash_deduct(amount)` — 신규 추가 필요
- [ ] `CurrencySystem.cash_add(amount)` — 신규 추가 필요
- [ ] `SeasonManager.get_settled_assets()` — 신규 추가 필요 여부 확인
- [ ] `NewsEventSystem.inject_event(text)` 또는 동등 메서드 — 존재 확인

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_lifestyle_manager.gd` | `test_offseason_rental_income()` |
| AC-02 | `tests/unit/test_lifestyle_manager.gd` | `test_purchase_deducts_cash()` |
| AC-04 | `tests/unit/test_lifestyle_manager.gd` | `test_next_season_seed_after_spending()` |
| AC-08 | `tests/unit/test_lifestyle_manager.gd` | `test_property_excluded_from_ranking_assets()` |
| AC-05~07, AC-09~10 | 수동 플레이테스트 | — |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
