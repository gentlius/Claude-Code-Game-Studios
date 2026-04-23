# 라이프스타일 소비 시스템 (Lifestyle Spending)

> **Status**: Approved (구현 완료 2026-04-23 — B-12)
> **Sprint**: Sprint 8 (B-12)
> **Owner**: game-designer + ui-programmer
> **Last Updated**: 2026-04-23

---

## 1. Overview

> **Alpha 폴백**: 이 시스템은 Beta 스코프다. Alpha 빌드에서는 `LifestyleManager`가 존재하지 않으며,
> `SeasonManager._on_season_end()`는 `LifestyleManager.process_offseason()` 호출을 건너뛴다.
> Alpha 시즌 전환 흐름: 시즌 종료 → 강제 청산 → 상금 `settle_to_cash()` → PRE_SEASON 직접 진입.
> 라이프스타일 화면 없음, 거주지 배경 변경 없음, `tangible_assets = 0`으로 고정.

라이프스타일 소비 시스템은 투자 대회 경쟁과 병렬로 운영되는 자산 성장 루프다.
플레이어는 투자 수익을 현금 자산으로 전환하여 부동산·사치품·사회공헌·대안 투자 등에 지출하고,
이를 통해 총 자산(F3)이 성장하는 시각적·서사적 피드백을 받는다.

라이프스타일 소비는 **현금 자산**에서만 이루어진다. 경쟁 자금(예수금/계좌 총 평가금액)과
완전히 분리되어 있으며, 라이프스타일 지출이 다음 시즌 시드나 티어에 직접 영향을 주지 않는다.

**두 종류의 라이프스타일 이벤트:**
- **자동 정산** (품목별 주기에 따라 장 마감 시 자동 처리): 부동산 임대 수익(시즌 마지막 날), 스타트업 엑싯(만기일), Recurring 비용(시즌 마지막 날)
- **능동 구매** (매일 장 마감 후 소비 화면): 거주지 업그레이드, 사치품, 대안 투자, 사회공헌

---

## 2. Player Fantasy

장이 끝날 때마다 "이 돈으로 뭘 살까?"가 진짜 선택이 된다.
강남 아파트를 살지, 강남 상가에 투자할지, 아니면 다음 시즌 시드를 아낄지.

거주지가 바뀌는 순간 — 화면이 어두워지고 새 공간이 천천히 밝아오는 3초가 성장의 체감이다.
F3 화면을 열 때마다 내가 어떤 삶을 살고 있는지가 배경 이미지로 보인다.
소비는 단순한 지출이 아니라 "내가 이 게임에서 어디까지 왔나"를 보여주는 기록이다.

---

## 3. Detailed Design

### 3-1. 라이프스타일 플로우

```
[장 마감 — 매일 (MARKET_CLOSED)]
  ↓
[LifestyleManager.process_market_close(day, week)]
  ├─ 매일: 스타트업 만기 도달 시 엑싯 처리 → cash_assets 입금 또는 0원
  └─ 시즌 마지막 날(4주차 금요일)만:
      ├─ 부동산 임대 수익 → cash_assets 입금
      ├─ Recurring 비용 차감 (골프 클럽 연회비 등)
      └─ seasons_held++ (부동산 감가 추적)
  ↓
[정산 리포트 순차 확인]
  ├─ 일반 평일: 일일 정산 확인
  ├─ 금요일: 일일 → 주간 정산 순차 확인
  └─ 시즌 마지막 금요일: 일일 → 주간 → 시즌 결산 순차 확인
  ↓
[라이프스타일 소비 화면 — 매일 등장, 능동 선택]
  ├─ 거주지 업그레이드
  ├─ 사치품 구매
  ├─ 대안 투자 (부동산 매입, 스타트업 투자)
  └─ 사회공헌
  ↓
[다음 날 / 다음 시즌 시작 버튼]
  ├─ 일반 평일 / 금요일: "다음 날 →" → 다음 날 PRE_MARKET
  └─ 시즌 마지막 금요일: "다음 시즌 시작 →" → GameClock.confirm_transition()
```

> **소비 후 잔여 cash_assets**: 시즌 종료 시에는 티어 배정 기준. 일반 장 마감 시에는 다음 날 예수금에 영향 없음 (cash_assets와 sim_cash는 분리).
>
> **자동 정산 트리거**: `LifestyleManager`가 `GameClock.on_market_close`에 직접 연결. `SeasonManager` 의존 없음. 시즌 종료 여부는 `GameClock.get_current_day() / get_current_week()`로 자체 판단.
>
> **⚠️ 일일 소비 화면 표시 타이밍 (I-04)**: 라이프스타일 소비 화면은 **매일 장 마감(MARKET_CLOSED) 직후**,
> 일일/주간/시즌 정산 리포트 확인 완료 이후, 다음 날 PRE_MARKET 시작 이전에 표시된다.
> 시장 개장 시간(PRE_MARKET, MARKET_OPEN, MARKET_PAUSED) 중에는 접근 불가.
> `GameClock.on_market_close` → 자동 정산 → 정산 리포트 UI → 소비 화면 → "다음 날 →" 버튼 → PRE_MARKET 순서가 규범적 순서다.
> `game-clock.md`는 이 UI 진입 시점을 MARKET_CLOSED 상태에서만 허용하도록 명시해야 한다.

### 3-2. 소비 카테고리

#### 카테고리 1: 거주지 (Residence)

해금 조건 = 해당 티어 진입 기준 자산 이상. 업그레이드는 순차적으로만 가능 (건너뛰기 불가).

| 티어 | 거주지명 | 아트 파일 | 해금 조건 | 구매 비용 |
|------|---------|---------|---------|---------|
| 브론즈 | 쪽방/고시원 | `bronze_jjokbang.png` | — (시작) | 기본 제공 |
| 실버 | 변두리 원룸 | `silver_oneroom.png` | 실버 진입 (₩3M+) | ₩500,000 |
| 골드 | 도심 오피스텔 | `gold_officetel.png` | 골드 진입 (₩10M+) | ₩2,000,000 |
| 플래티넘 | 강남 아파트 (중형) | `platinum_apartment.png` | 플래티넘 진입 (₩30M+) | ₩10,000,000 |
| 에메랄드 | 도심 대형 아파트 | `emerald_large_apartment.png` | 에메랄드 진입 (₩100M+) | ₩30,000,000 |
| 다이아 | 초고층 펜트하우스 | `diamond_penthouse.png` | 다이아 진입 (₩300M+) | ₩100,000,000 |
| 마스터 | 교외 대저택 | `master_mansion.png` | 마스터 진입 (₩1B+) | ₩300,000,000 |
| 그랜드마스터 | 개인 섬/별장 | `grandmaster_island_villa.png` | 그랜드마스터 진입 (₩3B+) | ₩1,000,000,000 |
| 챌린저 | 스카이 레지던스 | `challenger_sky_residence.png` | 챌린저 진입 (₩10B+) | ₩3,000,000,000 |
| 레전드 | 영빈관급 저택 | `legend_official_residence.png` | 레전드 진입 (₩30B+) | ₩10,000,000,000 |
| 거장 | (엔딩 이미지) | `grandmaster_ending.png` | 거장 도달 자동 전환 | 구매 불가 |

#### 카테고리 2: 사치품 (Luxury Goods)

일회성 구매. 구매 후 F3 화면 배경 레이어에 오브젝트로 합성된다.

| 품목 | 가격 | 해금 조건 | Recurring | 획득 칭호 |
|------|------|---------|---------|---------|
| 수입차 (포르쉐 카이엔급) | ₩200,000,000 | 에메랄드+ | — | "수입차 애호가" |
| 명품 시계 (파텍 필립급) | ₩100,000,000 | 다이아+ | — | "컬렉터" |
| 프라이빗 골프 클럽 멤버십 | 입회금 ₩50,000,000 | 플래티넘+ | ₩10,000,000/시즌 | "멤버스 온리" |
| 요트 계류권 | ₩500,000,000 | 마스터+ | — | "요트클럽" |

#### 카테고리 3: 인맥/네트워크 (Network)

한국 HNW 특유 카테고리. 게임플레이 효과는 XP 보너스로 표현.

| 품목 | 비용 | 해금 조건 | 특이사항 |
|------|------|---------|---------|
| 프라이빗 투자 클럽 연회비 | ₩20,000,000/시즌 | 에메랄드+ | Recurring |
| 경제 포럼 VIP석 | ₩30,000,000 | 다이아+ | 일회성, XP +10 |

#### 카테고리 4: 사회공헌 (Social Contribution)

| 품목 | 비용 | 해금 조건 | 보상 |
|------|------|---------|------|
| 장학재단 설립 | ₩500,000,000 일회성 | 마스터+ | F2 리그 프로필 재단명 표시, "사회공헌인" 칭호, 다음 시즌 첫 거래일 뉴스 딜레이 −5틱 |
| 사회적 기업 후원 | ₩10,000,000/시즌 Recurring | 에메랄드+ | XP +5/시즌 |
| 공익 캠페인 기부 | ₩1,000,000 ~ ₩50,000,000 일회성 (플레이어 입력) | 골드+ | XP: 기부금 ₩10M당 +1, 최대 +5/회 |

#### 카테고리 5: 대안 투자 (Alternative Investments)

**부동산 (임대 수익형)**

부동산은 `tangible_assets`로 분류되며 리그 랭킹 `account_total_value` 산정에서 제외된다.

| 부동산 종류 | 매입가 | 시즌 임대 수익(gross) | 유지비 (0.5%/시즌) | 순수익 | 해금 조건 |
|-----------|--------|-------------|------|------|---------|
| 소형 오피스텔 | ₩200,000,000 | ₩5,000,000 | ₩1,000,000 | ₩4,000,000 (2.0%) | 에메랄드+ |
| 강남 상가 | ₩1,000,000,000 | ₩30,000,000 | ₩5,000,000 | ₩25,000,000 (2.5%) | 마스터+ |
| 빌딩 | ₩5,000,000,000 | ₩200,000,000 | ₩25,000,000 | ₩175,000,000 (3.5%) | 그랜드마스터+ |

> **유지비**: 재산세 + 관리비 현실 반영. 매 시즌 오프시즌 정산 시 `cash_assets`에서 자동 차감 (F3 참조). 유지비율 `REAL_ESTATE_MAINTENANCE_RATE = 0.005 (0.5%/시즌)`.

**스타트업 엔젤 투자**

| 항목 | 값 |
|------|---|
| 투자금 범위 | ₩50,000,000 ~ ₩500,000,000 (플레이어 입력) |
| 해금 조건 | 에메랄드+ |
| 만기 | 투자 후 3~6시즌 (투자 시점 랜덤 결정) |
| 동시 보유 한도 | 최대 3건 (집중 투자 vs 분산의 선택 강제) |

엑싯 확률 분포 — **스타트업 등급에 따라 플레이어가 사전 선택** (W-20 플레이어 에이전시):

| 등급 | IPO | M&A 성사 | 폐업 | 배수 (IPO) | EV × 투자금 |
|------|-----|---------|------|------------|------------|
| A (검증형) | 10% | 70% | 20% | 1.5~2.5× | ~1.15× |
| B (성장형) | 20% | 50% | 30% | 2~5× | ~1.33× |
| C (도박형) | 15% | 15% | 70% | 5~10× | ~1.30× |

> **C등급 확률 조정 (현실화)**: 구 확률(IPO 30%/M&A 20%/폐업 50%)의 EV ≈ 2.45×는 지나치게 높아 C등급 도박형의 리스크·보상 구조가 실제 스타트업 실패율(한국 3년 내 폐업 약 60~70%)과 괴리됐다. 조정 후 EV ≈ 1.30× — 여전히 B등급(1.33×)과 유사하나 분산이 훨씬 크다. 폐업 70%는 한국 스타트업 현실에 부합한다.

> **등급 선택이 에이전시**: 투자 전 스타트업 소개 카드에 등급(A/B/C)이 표시된다.
> 등급은 산업 섹터와 창업자 이력으로 결정되며, 플레이어는 자신의 리스크 성향에 따라 선택한다.
> A등급은 안정 수익, C등급은 고분산 도박으로 분명히 구분되므로 결과가 "완전한 순운"이 아니다.
> 상세 EV 계산은 §F5 참조.

> **섹터 연계 (선택적 심화)**: 플레이어가 직전 시즌에 해당 스타트업 섹터에서
> 3회 이상 수익 거래를 한 경우, 해당 등급의 폐업 확률이 -5%p (보너스 적용 명시).

### 3-3. 라이프스타일 소비 화면 레이아웃

```
┌──────────────────────────────────────────────────────────────┐
│  [현재 거주지 배경 이미지 — 좌측 패널]  [소비 카테고리 탭 — 우측] │
│                                                              │
│  현재 현금 자산: ₩3,200,000,000                               │
│  소비 후 잔여: ₩2,800,000,000  ← 실시간 갱신                   │
│                               [다음 날 →] / [다음 시즌 시작 →]  │
└──────────────────────────────────────────────────────────────┘
```

카테고리 탭: 거주지 | 사치품 | 네트워크 | 사회공헌 | 대안투자

각 항목 카드: 품목명 + 가격 + 해금 상태(잠금/구매가능/보유중) + 구매 버튼.
해금 조건 미충족 항목은 회색 잠금 표시.

### 3-4. 거주지 업그레이드 연출 ("이사 날")

1. 구매 확정 → 2단계 확인 클릭 (대금 차감 규모가 크므로 의도적 마찰)
2. 화면 페이드 블랙 1~2초
3. 새 거주지 배경 풀스크린 페이드인 — UI 전부 제거. 배경 + 앰비언트 오디오만. 3초 정지
4. 타이틀 카드 페이드인: 거주지명 + 지불 금액 소자. 2초
5. F3 UI 레이어인 → 정상 화면으로 복귀
6. 뉴스 피드 이벤트 생성: "[플레이어명] 트레이더, [거주지명] 입주"

### 3-5. F3 화면 연동

- F3 화면 배경 = 현재 거주지 이미지
- 배경은 레이어드 구조: 기본 거주지 배경 + 사치품 오브젝트 레이어 (외제차, 명품시계 진열장 등)
- F3 하단: 현재 거주지명 + 대표 칭호 표시
- 라이프스타일 소비 화면 진입 버튼: F3 우상단 (장 마감 후 비거래 시간에만 활성)

#### 거주지 배경 에셋 현황

| 티어 | 거주지 | 파일 | 상태 |
|------|--------|------|------|
| 브론즈 | 쪽방/고시원 | `assets/art/housing/bronze_jjokbang.png` | ✅ 완료 |
| 실버 | 변두리 원룸 | `assets/art/housing/silver_oneroom.png` | ✅ 완료 |
| 골드 | 도심 오피스텔 | `assets/art/housing/gold_officetel.png` | ✅ 완료 |
| 플래티넘 | 강남 아파트 (중형) | `assets/art/housing/platinum_apartment.png` | ✅ 완료 |
| 에메랄드 | 도심 대형 아파트 | `assets/art/housing/emerald_large_apartment.png` | ✅ 완료 |
| 다이아 | 초고층 펜트하우스 | `assets/art/housing/diamond_penthouse.png` | ✅ 완료 |
| 마스터 | 교외 대저택 | `assets/art/housing/master_mansion.png` | ✅ 완료 |
| 그랜드마스터 | 개인 섬/별장 | `assets/art/housing/grandmaster_island_villa.png` | ✅ 완료 |
| 챌린저 | 스카이 레지던스 | `assets/art/housing/challenger_sky_residence.png` | ✅ 완료 |
| 레전드 | 영빈관급 저택 | `assets/art/housing/legend_official_residence.png` | ✅ 완료 |
| 거장 | (엔딩 이미지) | `assets/art/housing/grandmaster_ending.png` | ✅ 완료 |

### 3-6. 칭호 시스템

소비 마일스톤 달성 시 칭호 부여. F2 리그 프로필의 플레이어명 옆에 표시.

| 칭호 | 조건 |
|------|------|
| 건물주 | 부동산 1개 이상 보유 |
| 수입차 애호가 | 수입차 구매 |
| 컬렉터 | 명품 시계 구매 |
| 멤버스 온리 | 프라이빗 골프 클럽 가입 |
| 요트클럽 | 요트 계류권 구매 |
| 사회공헌인 | 장학재단 설립 또는 총 후원 ₩100M 이상 |
| 투자의 신사 | 전 카테고리 1개 이상 해금 |

복수 칭호 보유 시: F2에 대표 칭호 1개 표시 (플레이어 선택).

---

## 4. Formulas

### F1. 부동산 임대 수익

```
rental_income_per_season = property_purchase_price × property_rental_rate

property_rental_rate:
  소형 오피스텔: 0.025  (2.5%/시즌)
  강남 상가:     0.030  (3.0%/시즌)
  빌딩:          0.040  (4.0%/시즌)

예시: 강남 상가 ₩1,000,000,000 × 0.030 = ₩30,000,000/시즌
```

### F2. 총 자산

```
total_assets = cash_assets + account_total_value + Σ(tangible_asset_values)

account_total_value = sim_cash + portfolio_value    # 시즌 중
                    = 0                              # 시즌 시작 전 (예수금 입금 전)

tangible_asset_value = purchase_price
                     × (1 - DEPRECIATION_RATE) ^ seasons_held  # 고정 감가 (현재 0)
                     × price_modifier                           # 확률 변동 ± PROPERTY_PRICE_VARIANCE
```

### F3. 일일 현금 자산 자동 정산

```
cash_assets += Σ(rental_income_this_offseason)
cash_assets -= Σ(purchase_price × REAL_ESTATE_MAINTENANCE_RATE)   # 보유 부동산별 유지비
cash_assets -= Σ(recurring_costs_this_offseason)
cash_assets += Σ(startup_exit_proceeds_this_offseason)   # 만기 도달 시
```

> `REAL_ESTATE_MAINTENANCE_RATE = 0.005` (0.5%/시즌). 재산세·관리비 통합 비율.

### F4. 시즌 정산 후 예수금 → 현금 자산 전환

```
cash_assets += account_total_value   # 예수금 + 시즌 거래 P&L 전액
account_total_value = 0
```

(CurrencySystem.settle_to_cash() 호출 — 기존 구현)

### F5. 스타트업 엑싯 배수 (등급별 — W-20)

```
# 투자 시점에 플레이어가 선택한 grade ("A" / "B" / "C")
exit_multiplier:
  # A등급 (검증형)
  grade == "A":
    IPO (randf() < 0.10):          randf_range(1.5, 2.5)   # 10%
    M&A (randf() < 0.80):          randf_range(1.0, 1.3)   # 70% (=0.80-0.10)
    폐업 (그 외):                  0.0                      # 20%

  # B등급 (성장형) — 기존 기본값
  grade == "B":
    IPO (randf() < 0.20):          randf_range(2.0, 5.0)   # 20%
    M&A (randf() < 0.70):          randf_range(1.0, 1.5)   # 50% (=0.70-0.20)
    폐업 (그 외):                  0.0                      # 30%

  # C등급 (도박형) — 폐업률 현실화 (구: IPO 30%/M&A 20%/폐업 50%)
  grade == "C":
    IPO (randf() < 0.15):          randf_range(5.0, 10.0)  # 15%
    M&A (randf() < 0.30):          randf_range(0.8, 1.2)   # 15% (=0.30-0.15)
    폐업 (그 외):                  0.0                      # 70%

exit_proceeds = investment_amount × exit_multiplier

# 섹터 보너스: 직전 시즌 해당 섹터 수익 거래 >= STARTUP_SECTOR_BONUS_THRESHOLD(3)회 시 폐업 확률 -5%p
if sector_profitable_trades_last_season >= STARTUP_SECTOR_BONUS_THRESHOLD:
    ipo_threshold += 0.0   # IPO 확률 유지
    ma_threshold += 0.05   # M&A 임계값 +5%p → 폐업 구간 축소
```

**EV 계산 (투자금 1원 기준)**:
- A등급: 0.10×2.0 + 0.70×1.15 + 0.20×0 = 0.20 + 0.805 = **1.005× (분산 낮음)**
- B등급: 0.20×3.5 + 0.50×1.25 + 0.30×0 = 0.70 + 0.625 = **1.325× (분산 중간)**
- C등급: 0.15×7.5 + 0.15×1.0 + 0.70×0 = 1.125 + 0.15 = **1.275× ≈ 1.30× (분산 매우 높음)**

> A등급은 EV≈1로 거의 중립 투자. B/C등급은 장기 EV는 높지만 단기 폐업 위험이 크다.
> 등급 선택이 실질적 의미를 가짐으로써 결과가 완전한 순운이 되지 않도록 한다 (W-20).

---

## 5. Edge Cases

| 케이스 | 처리 |
|--------|------|
| 소비 후 잔여 자산 < ₩1,000,000 | 경고 표시: "소비 후 프리마켓으로 진입하게 됩니다". 확인 후 진행 가능 |
| 소비 후 잔여 자산 < ₩10,000 | LifestyleScreen에서 구매 자체는 허용. 시즌 시작 버튼 시점에 SeasonManager가 한강 엔딩 체크 (season-manager.md §3-1 ⑦ 참조). 라이프스타일 시스템이 한강 엔딩을 직접 트리거하지 않음 |
| 스타트업 엑싯 동시 2건 이상 | 순서대로 처리. 각각 별도 결과 카드 표시 |
| 부동산 매각 시 마이너스 수익 | 허용. 손실 확정 후 cash_assets 반영 |
| Recurring 비용 납부 불가 (잔액 부족) | 해당 비시즌에 cash_assets 음수 방지: 비용 차감 불가 → 경고 표시 후 해당 Recurring 항목 강제 해지. 칭호 유지, 환불 없음 |
| 비시즌 윈도우 스킵 (소비 없이 다음 시즌) | 허용. 비시즌 정산(자동)은 실행, 소비만 0 |
| 라이프스타일 소비 화면 중 앱 종료 | 화면 진입 시 즉시 세이브. 항목 구매 확정 시 즉시 세이브 |
| 거주지 업그레이드 건너뛰기 시도 | 불가. 현재 티어 +1 단계만 구매 가능. UI에서 상위 단계 잠금 표시 |
| 익스플로잇 — 소비 직전/후 세이브 반복 | 구매 확정 즉시 세이브 → 세이브 로드 반복으로 소비 취소 불가 |
| Recurring 비용 보유 중 해당 티어 미충족 시즌 | 해지 없음. Recurring은 해금 조건이 아닌 보유 조건이므로 유지 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `GameClock` | Hard ← | `on_market_close` 신호 → `process_market_close(day, week)` 트리거. 시즌 종료 판단도 GameClock 데이터로 자체 처리 |
| `SeasonManager` | Soft ← | 티어 배정 기준 조회 (`get_tier_name()`) — `process_offseason()` 의존 없음 |
| `CurrencySystem` | Hard ← | `cash_deduct(amount)` / `cash_add(amount)` — 신규 추가 필요 |
| `SaveSystem` | Hard ← | 라이프스타일 상태 직렬화 (보유 부동산, 스타트업, 구매 품목, 칭호, 거주지) |
| `GrowthScreen (F3)` | Hard ← | 현재 거주지 배경 이미지, 칭호 목록, 소비 화면 진입 버튼 |
| `LeagueUI (F2)` | Soft ← | 플레이어 칭호, 장학재단명 표시 |
| `NewsEventSystem` | Soft ← | 거주지 구매 등 대형 이벤트 시 뉴스 생성 |
| `AudioManager` | Soft ← | "이사 날" 연출 앰비언트 오디오 |
| `design/gdd/season-manager.md` | 준수 | 비시즌 윈도우 타이밍, 티어 배정 기준, 한강/거장 엔딩 조건 |
| `design/gdd/growth-screen.md` | 싱크 필요 | F3 배경 레이어드 구조 |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 | 범위 | 설명 |
|---------|--------|------|------|
| `OFFICETEL_RENTAL_RATE` | 0.025 | 0.01~0.04/시즌 | 소형 오피스텔 시즌당 임대 수익률 |
| `SANGGA_RENTAL_RATE` | 0.030 | 0.01~0.05/시즌 | 강남 상가 시즌당 임대 수익률 |
| `BUILDING_RENTAL_RATE` | 0.040 | 0.02~0.06/시즌 | 빌딩 시즌당 임대 수익률 |
| `STARTUP_IPO_PROB_A/B/C` | 0.10/0.20/0.30 | — | 등급별 IPO 확률 (W-20 등급 시스템으로 통합) |
| `STARTUP_MA_PROB_A/B/C` | 0.70/0.50/0.20 | — | 등급별 M&A 확률 (IPO 실패 중) |
| `STARTUP_FAIL_PROB_A/B/C` | 0.20/0.30/0.50 | — | 등급별 폐업 확률 |
| `STARTUP_SECTOR_BONUS_THRESHOLD` | 3 | 1~5 | 섹터 보너스 발동 최소 수익 거래 횟수 (직전 시즌) |
| `STARTUP_MAX_HOLDINGS` | 3 | 1~5 | 동시 보유 가능 스타트업 건수 |
| `STARTUP_MIN_SEASONS` | 3 | 2~4 | 스타트업 최소 만기 시즌 수 |
| `STARTUP_MAX_SEASONS` | 6 | 4~10 | 스타트업 최대 만기 시즌 수 |
| `PROPERTY_PRICE_VARIANCE` | 0.10 | 0~0.30 | 부동산 매각 시 가격 변동 범위 (±10%) |
| `DEPRECIATION_RATE` | 0.0 | 0.0~0.05/시즌 | 유형자산 감가상각률 (현재 없음) |
| `REAL_ESTATE_MAINTENANCE_RATE` | 0.005 (0.5%/시즌) | 0.002~0.01 | 부동산 유지비율. 재산세+관리비 통합. 낮을수록 부동산 투자 매력도 증가 |

> **DLC 확장 시**: `OFFICETEL_RENTAL_RATE`, `SANGGA_RENTAL_RATE`, `BUILDING_RENTAL_RATE`, `STARTUP_IPO_PROB`, `STARTUP_MA_PROB`, `STARTUP_FAIL_PROB`는 시장별 부동산·투자 문화에 따라 달라질 수 있다. US·JP DLC 구현 시 `market_us.json` / `market_jp.json`에 해당 파라미터를 추가하고 `MarketProfile.get_trading_param()`으로 로드한다. (ADR-021)

---

## 8. Acceptance Criteria

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 시즌 종료 후 자동 정산(임대 수익, 스타트업 엑싯, Recurring 비용)이 1회 처리된다 | 부동산 보유 상태로 시즌 종료 후 cash_assets 갱신 확인 |
| AC-02 | 라이프스타일 소비 화면에서 구매 시 cash_assets가 즉시 차감된다 | 구매 전후 잔액 비교 |
| AC-03 | "소비 후 잔여" 수치가 구매 선택에 따라 실시간 갱신된다 | 여러 항목 선택 중 수치 변화 확인 |
| AC-04 | 소비 후 잔여 자산이 시즌 종료 시 티어 배정 기준이 된다 | 의도적으로 티어 임계값 이하로 소비 후 티어 하락 확인 |
| AC-13 | 라이프스타일 소비 화면이 매일 장 마감 후 정산 리포트 확인 직후 표시된다 | 일반 평일에 장 마감 → 일일 정산 확인 → 소비 화면 표시 확인 |
| AC-14 | 소비 화면 버튼 텍스트가 컨텍스트에 따라 다르다: 일반일 "다음 날 →", 시즌 종료 "다음 시즌 시작 →" | 평일과 시즌 마지막 금요일에 각각 버튼 텍스트 확인 |
| AC-05 | 거주지 업그레이드 시 "이사 날" 풀스크린 페이드 연출이 재생된다 | 거주지 구매 후 페이드 블랙 → 새 배경 페이드인 → 타이틀 카드 확인 |
| AC-06 | F3 화면 배경이 현재 거주지 이미지로 표시된다 | 거주지 변경 후 F3 진입 확인 |
| AC-07 | 획득 칭호가 F2 리그 프로필에 표시된다 | 칭호 조건 충족 후 F2 확인 |
| AC-08 | 부동산 자산이 리그 랭킹 account_total_value에 포함되지 않는다 | 부동산 보유 상태에서 랭킹 계산 로직 검증 (tangible_assets 별도 집계) |
| AC-09 | 비시즌 윈도우 스킵 시 비시즌 정산은 자동 처리된다 | 소비 없이 "다음 시즌 시작" 클릭 후 임대 수익 반영 확인 |
| AC-10 | 소비 후 잔여 < ₩1,000,000이면 프리마켓 진입 경고가 표시된다 | 경고 확인 후 진행 가능, 경고 없이 진행 불가 |
| AC-11 | Recurring 비용 납부 불가 시 해당 항목 강제 해지, 환불 없음 | cash_assets 부족 상태로 시즌 종료 → 경고 + 해지 확인 |
| AC-12 | 구매 확정 즉시 세이브 → 리로드 후 소비 내역 유지 | 구매 → 앱 강제 종료 → 재시작 → 구매 내역 유지 확인 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

> **⚠️ Beta 스코프 시스템. Alpha 완료 전 구현 시작 금지.**

### 진입점
- **자동 정산**: `GameClock.on_market_close` → `LifestyleManager.process_market_close(day, week)` — 매일 호출, 내부에서 시즌 마지막 날 여부 자체 판단
- **소비 화면**: `SettlementReporter.settlement_confirmed` → `TradingScreen.spending_screen_requested` → `MainScreen` → `GameMain._show_lifestyle_screen()` → 소비 화면 닫기 → `GameClock.confirm_transition()`

### 호출 경로

**CurrencySystem 확장**
- [x] `currency_system.gd`: `cash_deduct(amount: int) -> bool` 추가 (잔액 부족 시 false 반환)
- [x] `currency_system.gd`: `cash_add(amount: int) -> void` 추가

**LifestyleManager (신규)**
- [x] `src/gameplay/lifestyle_manager.gd`: 신규 작성
- [x] `process_offseason()`: 임대 수익 입금, 스타트업 엑싯, Recurring 비용 순차 처리
- [x] `signal offseason_settled` 선언 + emit
- [x] 보유 부동산, 스타트업 투자, 구매 품목, 칭호, 거주지 상태 관리
- [x] `game_clock.gd`: `on_market_close` 시그널 → `LifestyleManager.process_market_close(day, week)` 연결 (내부에서 시즌 마지막 날 판단)

**LifestyleScreen (신규)**
- [x] `src/ui/lifestyle_screen.gd`: 신규 작성. 5개 카테고리 탭 + 잔여 자산 실시간 표시
- [x] 거주지 탭: 10개 거주지 카드, 해금/보유/구매 가능 상태
- [x] 사치품 탭: 4개 품목 카드
- [x] 네트워크 탭: 2개 항목
- [x] 사회공헌 탭: 3개 항목 (기부금 직접 입력 지원)
- [x] 대안투자 탭: 부동산 3종 + 스타트업 투자금 입력
- [x] "소비 후 잔여" 실시간 갱신
- [x] 소비 후 잔여 < ₩1M 경고 팝업
- [x] `game_main.gd`: `_show_lifestyle_screen()` — 매일 장 마감 후 호출 (TradingScreen 경유)
- [x] `lifestyle_screen.gd`: 버튼 텍스트 "다음 날 →" (일반일) / "다음 시즌 시작 →" (시즌 종료) 컨텍스트 분기

**거주지 업그레이드 연출**
- [x] `lifestyle_screen.gd`: 2단계 확인 → 페이드 블랙 → 새 배경 페이드인 → 타이틀 카드 → F3 복귀

**F3 연동**
- [x] `growth_screen.gd`: 배경 이미지 레이어드 구조 (거주지 레이어 + 사치품 오브젝트 레이어)
- [x] `growth_screen.gd`: 하단 거주지명 + 대표 칭호 표시
- [x] `growth_screen.gd`: 비시즌 기간 소비 화면 진입 버튼 추가

**세이브/로드**
- [x] `save_system.gd`: 라이프스타일 상태 직렬화 추가
  - 현재 거주지 티어
  - 보유 부동산 목록 (종류, 매입가, 보유 시즌 수)
  - 스타트업 투자 목록 (투자금, 만기 시즌, 엑싯 결과)
  - 구매한 사치품/네트워크/사회공헌 항목 목록
  - 보유 칭호 목록 + 대표 칭호

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_lifestyle_manager.gd` | `test_offseason_rental_income()` |
| AC-02 | `tests/unit/test_lifestyle_manager.gd` | `test_purchase_deducts_cash()` |
| AC-04 | `tests/unit/test_lifestyle_manager.gd` | `test_next_season_seed_after_spending()` |
| AC-08 | `tests/unit/test_lifestyle_manager.gd` | `test_property_excluded_from_ranking_assets()` |
| AC-11 | `tests/unit/test_lifestyle_manager.gd` | `test_recurring_force_cancel_on_insufficient_cash()` |
| AC-12 | `tests/unit/test_lifestyle_manager.gd` | `test_purchase_persists_after_reload()` |
| AC-05~07, AC-09~10, AC-13~14 | 수동 플레이테스트 | — |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 (B-12 구현 완료 2026-04-17)
