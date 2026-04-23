# 재무보고 시스템 (Financial Report System)

> **Status**: In Review (S10-05/07 구현 완료 — DLC Phase 2-3 및 빌드검증 잔여)
> **Sprint**: Sprint 10 (예정)
> **Owner**: game-designer + gameplay-programmer
> **Related**: [financial-statements.md](financial-statements.md) — A3 패널 표시 / [rumor-channel.md](rumor-channel.md) — 루머 연동 / [price-engine.md](price-engine.md) — 이벤트 압력
> **ADR**: [ADR-021](../../docs/architecture/021-market-profile-data-driven.md) — MarketProfile 데이터 기반 시장 규칙 분리

---

## 1. Overview

분기 실적 발표 시즌을 시뮬레이션하는 시스템. MarketProfile JSON이 시장별 규칙(보고서
주기, 잠정실적 여부 등)을 정의하며, 기본값은 한국 시장이다.

보고서 시즌마다 뉴스대상 종목(20–25%)은 **3단계 정보 공개** 구조로 실적을 발표한다:

1. **애널리스트 리포트** (시즌 중반) — 뉴스 피드에 방향 힌트, 공개 정보
2. **잠정실적 공시** (공식 발표 3일 전) — 방향+상회/하회 확인, 공식 신뢰도
3. **공식 실적 발표** (PRE_MARKET) — 실제 ROE 갱신, A3 동시 갱신, 루머 해소

서프라이즈/쇼크 판정은 **컨센서스(consensus_roe) 대비** 실제 결과로 판정한다.
컨센서스는 내부 변수로만 존재하며 플레이어에게 수치를 직접 노출하지 않는다.
이른 reporting_day 종목일수록 컨센서스 불확실성이 크고, 결과적으로 서프라이즈/쇼크
폭이 커지는 구조다.

뉴스 없는 종목은 시즌 시작 시 조용히 A3 데이터만 갱신된다.

**핵심 타이밍**: "소문에 사서, 뉴스에 팔아라" — 3단계 정보 공개를 읽고 포지션을 잡는다.

---

## 2. Player Fantasy

3일 전 — 잠정실적 공시가 떴다. "영업이익 전분기 대비 대폭 개선, 순이익 미확정."
LARGE 종목이니 잠정은 거의 믿을 수 있다. 지금 들어갈까?

전날 — 루머 카드가 추가로 뜬다. "컨센서스 상회 강력 전망."
잠정이 이미 좋다는 걸 알고 있는데 루머까지 같은 방향이다. 더 확신이 생긴다.
하지만 30%는 가짜 루머다. 이미 잠정 후 주가가 올라서 리스크도 커졌다.

발표 당일 장 전 — 어닝쇼크. 컨센서스는 ROE 0.18을 기대했는데 실제는 0.12.
잠정실적은 틀리지 않았다. 실제로 영업익은 개선됐다. 하지만 시장 기대치에 못 미쳤다.
잠정에 들어가서 공식 발표 전에 익절한 플레이어만 살아남았다.

---

## 3. Detailed Design

### 3-1. MarketProfile 기반 보고서 주기

모든 시장별 규칙은 `MarketProfile` JSON에서 로드한다. 하드코딩 금지.

```gdscript
## 시작 시 MarketProfile 로드
func _ready() -> void:
    var path: String = "res://assets/data/market_profiles/market_%s.json" % _active_market
    _profile = JSON.parse_string(FileAccess.get_file_as_string(path))

func is_report_season(season: int) -> bool:
    var cycle: int = _profile.report_cycle_seasons
    var start: int = _profile.fiscal_year_start_season
    return season >= (start + cycle) and ((season - start) % cycle == 0)

func get_report_type(season: int) -> String:
    if not is_report_season(season):
        return ""
    var cycle: int = _profile.report_cycle_seasons
    var start: int = _profile.fiscal_year_start_season
    var index: int = ((season - start) / cycle - 1) % _profile.report_type_sequence.size()
    return _profile.report_type_sequence[index]
```

**한국 시장 기본값** (`market_kr.json`):
- `report_cycle_seasons`: 3
- `fiscal_year_start_season`: 1
- `report_type_sequence`: ["Q1", "H1", "Q3", "Annual"]
- 결과: season 4→Q1, 7→H1, 10→Q3, 13→Annual, 16→Q1

### 3-2. 뉴스대상 종목 선정

보고서 시즌마다 전체 종목(약 40종) 중 20–25% (8–12종)를 **뉴스대상 종목**으로 선정한다.
ROE 변화량이 클수록, 이른 reporting_day에 배정될수록 컨센서스 불확실성이 크다.

```gdscript
func _select_newsworthy(all_stocks: Array[String], season: int) -> Array[String]:
    var candidates: Array[Dictionary] = []
    for stock_id in all_stocks:
        var delta: float = _compute_consensus_roe(stock_id, season) - StockData.get_roe(stock_id)
        if abs(delta) >= ROE_NEWS_THRESHOLD or _is_turnaround_expected(stock_id, season):
            candidates.append({"id": stock_id, "delta_abs": abs(delta)})
    candidates.sort_custom(func(a, b): return a.delta_abs > b.delta_abs)
    var count: int = clamp(candidates.size(), NEWS_STOCK_MIN, NEWS_STOCK_MAX)
    return candidates.slice(0, count).map(func(d): return d.id)
```

### 3-3. 컨센서스 및 ROE 갱신 모델

`consensus_roe`와 `new_roe`는 독립적으로 생성된다. 두 값의 괴리가 서프라이즈/쇼크를 결정한다.

```gdscript
func _compute_consensus_roe(stock_id: String, season: int) -> float:
    ## 시장이 예상하는 ROE — 플레이어에게 수치 미노출, 판정에만 사용
    var prev_roe: float = StockData.get_roe(stock_id)
    var theme: SeasonTheme = SeasonManager.get_season_theme(season)
    var theme_drift: float = theme.roe_drift * SectorBias.get(StockData.get_sector(stock_id), 1.0)
    var reporting_day: int = _pending_events[stock_id].reporting_day
    var uncertainty: float = CONSENSUS_UNCERTAINTY_MAX * exp(-reporting_day / float(UNCERTAINTY_DECAY))
    var consensus_noise: float = _consensus_rng.randf_range(-uncertainty, uncertainty)
    return clamp(prev_roe + theme_drift + consensus_noise, ROE_MIN, ROE_MAX)

func _compute_new_roe(stock_id: String, season: int) -> float:
    ## 실제 확정 ROE — PRE_MARKET 발표 시점에 생성
    var prev_roe: float = StockData.get_roe(stock_id)
    var theme: SeasonTheme = SeasonManager.get_season_theme(season)
    var theme_drift: float = theme.roe_drift * SectorBias.get(StockData.get_sector(stock_id), 1.0)
    var sector_noise: float = _rng.randf_range(-SECTOR_NOISE, SECTOR_NOISE)
    var stock_noise: float = _rng.randf_range(-STOCK_NOISE, STOCK_NOISE)
    return clamp(prev_roe + theme_drift + sector_noise + stock_noise, ROE_MIN, ROE_MAX)
```

### 3-4. PER/PBR 연동 갱신

ROE 변화 → 내재 EPS 변화 → PER 재계산. 공식 발표 PRE_MARKET에 원자적으로 갱신.

```gdscript
func _update_per_pbr(stock_id: String, new_roe: float) -> void:
    var bvps: float = StockData.get_book_value_per_share(stock_id)
    var eps: float = bvps * new_roe
    var price: float = PriceEngine.get_current_price(stock_id)
    var new_per: float = price / eps if eps > 0.0 else PER_NEGATIVE_SENTINEL
    var new_pbr: float = price / bvps if bvps > 0.0 else 0.0
    StockData.set_financials(stock_id, new_roe, new_per, new_pbr)
```

### 3-5. 이벤트 타입 분류

**TURNAROUND**: `prev_roe` 부호 변화 기준 (컨센서스 무관).  
**SURPRISE / SHOCK**: `actual_roe vs consensus_roe` 기준 (prev_roe 기준 아님).

| 우선순위 | 조건 | 타입 | 가격 방향 |
|---------|------|------|----------|
| 1 | prev_roe ≤ 0 AND new_roe > 0 | `TURNAROUND_PROFIT` (흑자전환) | LARGE + |
| 1 | prev_roe > 0 AND new_roe ≤ 0 | `TURNAROUND_LOSS` (적자전환) | LARGE - |
| 2 | new_roe - consensus_roe ≥ SURPRISE_THRESHOLD | `EARNINGS_SURPRISE` (어닝서프라이즈) | MEDIUM + |
| 2 | consensus_roe - new_roe ≥ SHOCK_THRESHOLD | `EARNINGS_SHOCK` (어닝쇼크) | MEDIUM - |

TURNAROUND를 먼저 체크. 해당 없으면 SURPRISE/SHOCK 체크. 둘 다 해당 없으면 뉴스 없음.

**뉴스 카드 텍스트**:
- `TURNAROUND_PROFIT`: "[종목] 흑자 전환 성공 — 시장 예상 크게 상회"
- `TURNAROUND_LOSS`: "[종목] 적자 전환 — 실적 대폭 악화"
- `EARNINGS_SURPRISE`: "[종목] 어닝서프라이즈 — 컨센서스 대비 대폭 상회"
- `EARNINGS_SHOCK`: "[종목] 어닝쇼크 — 컨센서스 크게 하회"

### 3-6. 3단계 이벤트 스케줄링

```gdscript
func schedule_quarterly_events(season: int) -> void:
    if not is_report_season(season):
        _do_quiet_update_all(season)
        return

    var newsworthy: Array[String] = _select_newsworthy(StockData.get_all_ids(), season)
    for stock_id in newsworthy:
        var reporting_day: int = _rng.randi_range(REPORT_DAY_MIN, REPORT_DAY_MAX)
        var event_sign: int = _get_event_sign(stock_id, season)  # +1 or -1
        var is_fake_rumor: bool = _rng.randf() < RUMOR_FAKE_RATE

        _pending_events[stock_id] = {
            # 1단계: 애널리스트 리포트 뉴스 (시즌 중반)
            "analyst_day": _rng.randi_range(ANALYST_DAY_MIN, ANALYST_DAY_MAX),
            "analyst_done": false,
            # 2단계: 잠정실적 (reporting_day - PRELIMINARY_DAY_OFFSET, MarketProfile)
            "preliminary_day": reporting_day - _profile.preliminary_earnings.day_offset,
            "preliminary_done": false,
            "has_preliminary": _roll_preliminary(stock_id),
            # 3단계: 루머 + 공식 발표
            "rumor_day": reporting_day - 1,
            "rumor_done": false,
            "reporting_day": reporting_day,
            "report_done": false,
            # 공통
            "event_sign": event_sign,
            "is_fake_rumor": is_fake_rumor,
            "season": season,
        }

    # 비대상 종목: 시즌 1일 PRE_MARKET 조용히 갱신
    for stock_id in StockData.get_all_ids():
        if not _pending_events.has(stock_id):
            _schedule_quiet_update(stock_id, season)

func _roll_preliminary(stock_id: String) -> bool:
    var profile_key: String = StockData.get_volatility_profile(stock_id)
    var prob: float = _profile.preliminary_earnings.probability_by_profile.get(profile_key, 0.0)
    return _rng.randf() < prob
```

### 3-7. 잠정실적 발행 (PRE_MARKET)

```gdscript
func _on_pre_market_preliminary(stock_id: String) -> void:
    var ev: Dictionary = _pending_events[stock_id]
    var is_bullish: bool = ev.event_sign > 0
    # 잠정실적 뉴스 카드 — 방향+정성, ROE 수치 미포함
    var text: String
    if is_bullish:
        text = "[%s] 잠정실적 — 영업이익 전분기 대비 개선, 컨센서스 상회 전망, 순이익 미확정" % stock_id
    else:
        text = "[%s] 잠정실적 — 매출 컨센서스 하회, 수익성 악화 우려, 순이익 미확정" % stock_id
    NewsEventSystem.fire_preliminary_news(stock_id, text)
    # 가격 압력 없음 — 뉴스 카드만 발행
```

### 3-8. 공식 발표 실행 (PRE_MARKET)

```gdscript
func _on_earnings_pre_market(stock_id: String) -> void:
    var new_roe: float = _compute_new_roe(stock_id, _pending_events[stock_id].season)
    _update_per_pbr(stock_id, new_roe)                      # A3 데이터 즉시 갱신
    PriceEngine.cancel_rumor_pressure(stock_id)             # 루머 압력 해소
    var event_type: String = _classify_event(stock_id, new_roe)
    NewsEventSystem.fire_earnings_event(stock_id, event_type)
    _pending_events.erase(stock_id)
```

**A3 갱신, 루머 해소, 뉴스 발행은 동일 PRE_MARKET 프레임에서 원자적으로 처리한다.**

### 3-9. 루머 발생 (장중)

루머는 `rumor_day` 장중 `RUMOR_FIRE_TICK_IN_DAY` 틱에 발생한다. `process_tick()`은
장 중에만 실행되므로 `_rumor_pressure`가 장 마감 후에도 자연 유지된다.

```gdscript
# 루머 텍스트 (강도 힌트 포함)
var rumor_direction: int = ev.event_sign * (-1 if ev.is_fake_rumor else 1)
if rumor_direction > 0:
    text = "[%s] 실적 발표 임박 — 컨센서스 상회 강력 전망" % stock_id
else:
    text = "[%s] 실적 발표 임박 — 컨센서스 하회 우려 고조" % stock_id
```

### 3-10. 애널리스트 리포트 뉴스 (장중, 시즌 중반)

뉴스 피드에 등장하는 공개 정보. 가격 압력 없음. 방향 힌트만 제공.

```gdscript
# 발행 타이밍: analyst_day 장중 임의 틱
var analyst_text: String
if ev.event_sign > 0:
    analyst_text = "[%s] OO증권, 목표주가 상향 — 분기 실적 기대감 반영" % stock_id
else:
    analyst_text = "[%s] XX증권, 목표주가 하향 — 원가 압박 지속 우려" % stock_id
NewsEventSystem.fire_analyst_report(stock_id, analyst_text)
```

---

## 4. Formulas

### F1. 실제 ROE (new_roe)

```
new_roe = clamp(prev_roe + theme_drift × sector_bias + sector_noise + stock_noise,
                ROE_MIN, ROE_MAX)
```

| 변수 | 정의 | 범위 |
|------|------|------|
| `prev_roe` | 직전 보고서 시즌 ROE | ROE_MIN ~ ROE_MAX |
| `theme_drift` | 시즌 테마 드리프트 (bull:+0.04, bear:-0.04, neutral:0.0) | -0.05 ~ +0.05 |
| `sector_bias` | 섹터별 테마 민감도 | 0.3 ~ 2.0 |
| `sector_noise` | 섹터 공통 노이즈 | ±SECTOR_NOISE |
| `stock_noise` | 종목 개별 노이즈 | ±STOCK_NOISE |

**예시**: prev_roe=0.08, bull(+0.04), sector_bias=1.2, sector_noise=+0.01, stock_noise=-0.005
→ `new_roe = 0.08 + 0.048 + 0.01 - 0.005 = 0.133`

### F2. 컨센서스 ROE (consensus_roe)

```
uncertainty = CONSENSUS_UNCERTAINTY_MAX × exp(-reporting_day / UNCERTAINTY_DECAY)
consensus_noise ~ uniform(-uncertainty, +uncertainty)
consensus_roe = clamp(prev_roe + theme_drift × sector_bias + consensus_noise, ROE_MIN, ROE_MAX)
```

| 변수 | 정의 | 범위 |
|------|------|------|
| `CONSENSUS_UNCERTAINTY_MAX` | 불확실성 최대값 (reporting_day=1 근방) | 0.08 |
| `UNCERTAINTY_DECAY` | 불확실성 감쇠 속도 (클수록 천천히 감소) | 8 |
| `consensus_noise` | `_consensus_rng`로 생성 (`_rng`와 독립) | ±uncertainty |

**예시**: reporting_day=2, UNCERTAINTY_MAX=0.08, DECAY=8
→ `uncertainty = 0.08 × exp(-2/8) = 0.08 × 0.779 = 0.062`
→ consensus_roe가 실제값과 최대 ±0.062 벗어날 수 있음 → 큰 서프라이즈/쇼크 가능

reporting_day=18 → `uncertainty = 0.08 × exp(-18/8) = 0.08 × 0.105 = 0.008`
→ 컨센서스가 거의 정확 → 서프라이즈/쇼크 폭 작음

### F3. 이벤트 분류 임계값

```
흑자전환: prev_roe ≤ 0.0 AND new_roe > 0.0           (consensus 무관)
적자전환: prev_roe > 0.0 AND new_roe ≤ 0.0           (consensus 무관)
어닝서프라이즈: new_roe - consensus_roe ≥ SURPRISE_THRESHOLD
어닝쇼크:      consensus_roe - new_roe ≥ SHOCK_THRESHOLD
```

### F4. PER/PBR

```
EPS = BVPS × new_roe
PER = current_price / EPS    (EPS > 0)
PER = PER_NEGATIVE_SENTINEL  (EPS ≤ 0, 표시: "N/A")
PBR = current_price / BVPS
```

### F5. 루머 압력 주입

```
rumor_direction = event_sign × (-1 if is_fake else +1)
delta_per_tick  = RUMOR_PRESSURE_STRENGTH × rumor_direction
ticks_remaining = RUMOR_DURATION_TICKS
```

→ `RumorChannel.inject_rumor_pressure()` 경유 PriceEngine `_rumor_pressure` 주입

---

## 5. Edge Cases

### E-01. VOLATILE 종목 / 잠정 미발행 (확률 미충족)

`has_preliminary == false`이면 잠정 이벤트 건너뜀. 루머 → 공식 발표만 진행.

### E-02. 잠정 방향과 공식 결과 불일치

잠정실속은 방향(영업익 개선/악화)만 공개한다. 영업익이 개선돼도 순이익이 나쁘거나
컨센서스 대비 부족하면 공식 발표에서 어닝쇼크가 가능하다. 정상 게임플레이.
플레이어가 "잠정에 들어갔다가 발표에 역습당하는" 경험이 의도된 리스크.

### E-03. 가짜 루머 + 잠정 방향 충돌

잠정은 bullish, 루머는 fake bearish. 플레이어 혼란이 의도된 정보 비대칭.
잠정(공식 공시) > 루머(30% 가짜)이므로 경험 많은 플레이어는 잠정을 우선 신뢰.

### E-04. reporting_day == 2 일 때 preliminary_day == -1

`PRELIMINARY_DAY_OFFSET = 3`이면 preliminary_day = -1 (이전 시즌). 불가.
`REPORT_DAY_MIN`을 `PRELIMINARY_DAY_OFFSET + 2` 이상으로 보장하면 발생 안 함.
현재 `REPORT_DAY_MIN = 5`로 설정하면 minimum preliminary_day = 2.

### E-05. 세이브/로드 — 3단계 catch-up

`_pending_events` 전체 직렬화. 로드 후 각 `done` 플래그 미체크 + current_day 초과 확인.

| 로드 시점 | catch-up 처리 |
|----------|-------------|
| 애널리스트 전 | analyst → preliminary → rumor 스킵 → report 순 실행 |
| 애널리스트 후, 잠정 전 | preliminary → rumor 스킵 → report |
| 잠정 후, 루머 전 | rumor 스킵 → report |
| 루머 후, 공식 전 | report만 실행 |

루머는 catch-up 시 항상 스킵한다 (장 중 이벤트, 장 마감 후 의미 없음).
잠정과 공식은 catch-up 시 정상 실행 (PRE_MARKET 이벤트).

### E-06. 동일 reporting_day 복수 종목

허용. overnight_buffer에서 순서대로 발행. PriceEngine은 각 종목 독립 처리.

### E-07. EPS ≤ 0 (적자 PER)

`PER_NEGATIVE_SENTINEL = -1`. A3 패널은 -1을 받으면 "N/A" 표시.

### E-08. 비보고서 시즌 A3 불변

`is_report_season() == false`이면 ROE/PER/PBR 갱신 없음. 직전 보고서 값 유지.

### E-09. 이른 reporting_day 종목의 업종 파급

reporting_day가 이른 LARGE 종목이 어닝쇼크를 맞으면 같은 섹터 종목들에 충격이
전파된다. ADR-022 EventSource 파이프라인으로 구현한다.

**구현 방법** (S10-05 Phase 1 포함):
```gdscript
# FinancialReportSystem._publish_earnings_event() 내부
if stock.volatility_profile == "LARGE" and is_earnings_shock:
    NewsEventSystem.inject_event({
        "event_source": "FinancialReportSystem",
        "scope": "SECTOR_RIPPLE",
        "target_sector": stock.sector,
        "origin_stock_id": stock.stock_id,
        "impact": shock_magnitude * SECTOR_RIPPLE_RATIO,
        "direction": -1 if is_negative_shock else 1,
        "visible_to_player": false,   # 개별 어닝 뉴스가 이미 표시됨
        "rumor_eligible": false
    })
```

- `SECTOR_RIPPLE_RATIO` 튜닝 상수 (기본 0.3): 어닝쇼크 크기의 30%를 섹터 파급으로 전달
- `origin_stock_id` 제외 처리: NewsEventSystem이 트리거 종목 자체는 이중 충격 방지로 건너뜀
- overnight_buffer 내 발행 종목과 같은 타이밍에 처리 (day_started 이벤트 핸들러)
- LARGE 종목만 해당 (MEDIUM/SMALL/VOLATILE은 섹터 파급 없음)

---

## 6. Dependencies

| 시스템 | 방향 | 설명 |
|--------|------|------|
| SeasonManager | Hard (→ FinancialReportSystem) | 시즌 시작 시 `schedule_quarterly_events()` 호출 |
| MarketProfile JSON | Hard | 보고서 주기, 잠정실적 확률 등 시장별 규칙 |
| StockData | Hard | ROE/PER/PBR 읽기/쓰기, 종목 목록, VolatilityProfile |
| NewsEventSystem | Hard | 애널리스트/잠정/어닝 이벤트 발행; SECTOR_RIPPLE inject_event() (ADR-022) |
| RumorChannel | Hard | 루머 압력 주입 `inject_rumor_pressure()` |
| PriceEngine | Hard | 루머 압력 해소 `cancel_rumor_pressure()` |
| GameClock | Hard | day/tick 기준 스케줄 실행 |
| SaveSystem | Hard | `_pending_events` 직렬화/역직렬화 |
| A3 financial-statements.md | Soft (표시) | StockData 경유 표시 — 직접 의존 없음 |

**역방향 등록 필요**:
- `season-manager.md` §6 — FinancialReportSystem 추가
- `rumor-channel.md` §6 — FinancialReportSystem(Hard, 소비자) 추가
- `price-engine.md` §6 — FinancialReportSystem(Hard) 추가

---

## 7. Tuning Knobs

### MarketProfile 경유 (시장별 차등, JSON 설정)

| 키 | KR 기본값 | 설명 |
|----|----------|------|
| `report_cycle_seasons` | 3 | 보고서 주기 (시즌 수) |
| `fiscal_year_start_season` | 1 | 회계연도 시작 시즌 |
| `report_type_sequence` | ["Q1","H1","Q3","Annual"] | 보고서 타입 순서 |
| `preliminary_earnings.enabled` | true | 잠정실적 기능 활성 여부 |
| `preliminary_earnings.day_offset` | 3 | 공식 발표 기준 잠정 발행 선행 일수 |
| `preliminary_earnings.probability_by_profile.LARGE` | 1.0 | 대형주 잠정 발행 확률 |
| `preliminary_earnings.probability_by_profile.MEDIUM` | 0.7 | 중형주 |
| `preliminary_earnings.probability_by_profile.SMALL` | 0.3 | 소형주 |
| `preliminary_earnings.probability_by_profile.VOLATILE` | 0.0 | 테마주 |

### 게임 로직 상수 (financial_report_config.json)

| 상수 | 기본값 | 범위 | 효과 |
|------|--------|------|------|
| `NEWS_STOCK_MIN` | 8 | 4–12 | 최소 뉴스 종목 수 |
| `NEWS_STOCK_MAX` | 12 | 8–20 | 최대 뉴스 종목 수 |
| `REPORT_DAY_MIN` | 5 | 5–8 | 최소 reporting_day (잠정 전날 확보) |
| `REPORT_DAY_MAX` | 18 | 10–19 | 최대 reporting_day |
| `ANALYST_DAY_MIN` | 3 | 2–6 | 애널리스트 리포트 최소 발행일 |
| `ANALYST_DAY_MAX` | 10 | 6–14 | 애널리스트 리포트 최대 발행일 |
| `RUMOR_FIRE_TICK_IN_DAY` | 40 | 20–60 | 루머 발생 틱 |
| `RUMOR_FAKE_RATE` | 0.30 | 0.10–0.50 | 가짜 루머 비율 |
| `ROE_NEWS_THRESHOLD` | 0.03 | 0.01–0.08 | 뉴스대상 최소 ROE 변화량 |
| `SURPRISE_THRESHOLD` | 0.05 | 0.03–0.10 | 어닝서프라이즈 임계값 (vs consensus) |
| `SHOCK_THRESHOLD` | 0.05 | 0.03–0.10 | 어닝쇼크 임계값 (vs consensus) |
| `CONSENSUS_UNCERTAINTY_MAX` | 0.08 | 0.04–0.15 | 이른 종목 컨센서스 최대 불확실성 |
| `UNCERTAINTY_DECAY` | 8 | 5–15 | 불확실성 감쇠 속도 (클수록 천천히) |
| `SECTOR_RIPPLE_RATIO` | 0.30 | 0.10–0.50 | LARGE 어닝쇼크 → 섹터 파급 비율 (E-09) |
| `SECTOR_NOISE` | 0.03 | 0.01–0.05 | 섹터 공통 ROE 노이즈 |
| `STOCK_NOISE` | 0.02 | 0.005–0.04 | 종목 개별 ROE 노이즈 |
| `ROE_MIN` | -0.30 | -0.50 ~ -0.10 | ROE 하한 |
| `ROE_MAX` | 0.50 | 0.30 ~ 1.00 | ROE 상한 |
| `PER_NEGATIVE_SENTINEL` | -1 | 고정 | 적자 PER sentinel |

---

## 8. Acceptance Criteria

| ID | 조건 | 판정 기준 |
|----|------|----------|
| AC-FR-01 | MarketProfile 기반 `is_report_season()` | KR: season 4,7,10,13 → true; 1,2,3,5,6 → false |
| AC-FR-02 | `get_report_type()` 순환 | KR: season 4→Q1, 7→H1, 10→Q3, 13→Annual, 16→Q1 |
| AC-FR-03 | 뉴스대상 종목 수 범위 | 보고서 시즌마다 8–12종목 |
| AC-FR-04 | ROE 갱신 전 종목 적용 | 보고서 시즌 시작 시 전 종목 ROE 변경 확인 |
| AC-FR-05 | 흑자전환 분류 | prev_roe=-0.05, new_roe=+0.03 → TURNAROUND_PROFIT (consensus 무관) |
| AC-FR-06 | 어닝서프라이즈 분류 | new_roe - consensus_roe = +0.06 ≥ 0.05 → EARNINGS_SURPRISE |
| AC-FR-07 | 어닝쇼크 — prev 대비 개선도 쇼크 가능 | prev_roe=0.10, new_roe=0.12, consensus_roe=0.18 → EARNINGS_SHOCK |
| AC-FR-08 | 3단계 타이밍 순서 | analyst_day < preliminary_day < rumor_day < reporting_day 보장 |
| AC-FR-09 | 가짜 루머 비율 | 100회 시뮬 시 25–35% 이벤트 반대 방향 루머 |
| AC-FR-10 | A3 데이터·뉴스 동시 갱신 | 공식 발표 PRE_MARKET 틱에 StockData.roe 갱신 완료 |
| AC-FR-11 | 루머 압력 해소 | 공식 발표 PRE_MARKET 시 `_rumor_pressure[stock_id]` 제거됨 |
| AC-FR-12 | 비보고서 시즌 A3 불변 | season 5에서 ROE/PER/PBR = season 4 보고서 값 |
| AC-FR-13 | 세이브/로드 catch-up (3단계) | 잠정 후 로드 시: 루머 스킵 → 공식 발표만 실행 |
| AC-FR-14 | PER 적자 sentinel | EPS ≤ 0 → PER == -1 |
| AC-FR-15 | 비대상 종목 조용한 갱신 | 뉴스카드 없이 A3만 갱신 |
| AC-FR-16 | 루머 교차 날짜 자연 지속 | 장 마감 후 `_rumor_pressure` 유지, 다음 PRE_MARKET까지 지속 |
| AC-FR-17 | 이른 reporting_day = 큰 불확실성 | reporting_day=5 uncertainty > reporting_day=15 uncertainty |
| AC-FR-18 | LARGE 종목 잠정 항상 발행 | LARGE VolatilityProfile 종목 → `has_preliminary == true` |
| AC-FR-19 | VOLATILE 종목 잠정 없음 | VOLATILE VolatilityProfile 종목 → `has_preliminary == false` |
| AC-FR-20 | MarketProfile 교체 시 주기 변경 | `report_cycle_seasons=6`이면 season 7부터 첫 보고서 |
| AC-FR-21 | E-09 섹터 파급 — LARGE 어닝쇼크 | LARGE 종목 EARNINGS_SHOCK 발행 시 동 섹터 다른 종목에 `inject_event(SECTOR_RIPPLE)` 1회 호출됨 |
| AC-FR-22 | E-09 섹터 파급 — 트리거 종목 제외 | `origin_stock_id` 종목 자신은 SECTOR_RIPPLE 적용 대상에서 제외됨 (이중 충격 없음) |
| AC-FR-23 | E-09 섹터 파급 — MEDIUM 이하 없음 | MEDIUM/SMALL/VOLATILE 어닝쇼크는 `inject_event(SECTOR_RIPPLE)` 미호출 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `SeasonManager._on_season_started()` → `FinancialReportSystem.schedule_quarterly_events(season)`
- `GameClock.pre_market_triggered(day)` → `FinancialReportSystem._on_pre_market(day)`
- `GameClock.tick_processed(tick)` → `FinancialReportSystem._on_tick(day, tick)`

### 파일 목록 (Sprint 10 — FinancialReportSystem 핵심)
- [x] `src/gameplay/financial_report_system.gd` — 신규 autoload
- [x] `project.godot` — FinancialReportSystem autoload 등록
- [x] `assets/data/financial_report_config.json` — 게임 로직 상수
- [x] `tests/unit/test_financial_report_system.gd` — 신규 테스트

### DLC 확장성 — MarketProfile 통합 (Sprint 10, Phase 1+2+3 전부)

> Phase 1~3 항목을 Sprint 10에서 전부 처리한다. market_kr.json이 모든 시스템의
> 단일 진입점이 되며, DLC 시장은 시장별 JSON 추가만으로 동작해야 한다.  
> 근거: [ADR-021](../../docs/architecture/021-market-profile-data-driven.md)

**Phase 1 — CRITICAL (다른 시스템과 동시 처리)**
- [ ] `assets/data/market_profiles/market_kr.json` 생성 — 아래 전 필드 포함:
  - `"trading_minutes": 390` (→ game-clock.md C-01)
  - `"tick_size_table": [...]` (→ price-engine.md C-02)
  - `"daily_limit_pct": 0.30` (→ price-engine.md C-03)
  - `"short_margin_rate": 1.40` (→ short-selling.md H-01)
  - `"short_margin_call_threshold": 0.20` (→ short-selling.md H-01)
  - `"borrow_pool_ratios": {...}` (→ short-selling.md H-02)
  - `"borrow_pool_enabled": true`
  - `"season_length_weeks": 4` (→ season-manager.md M-01)
  - `"ai_return_distribution": {...}` (→ ai-competitor.md M-02)
  - `"report_cycle_seasons": 3`
  - `"fiscal_year_start_season": 1`
  - `"report_type_sequence": ["Q1", "H1", "Q3", "Annual"]`
  - `"preliminary_earnings": { "enabled": true, "day_offset": 3, "probability_by_profile": {...} }`

**Phase 2 — HIGH (Sprint 10 내 처리)**
- [ ] `assets/data/market_profiles/market_us.json` 스텁 생성 (DLC 착수 전 설계 검증용)
  - `"trading_minutes": 390`, `"daily_limit_pct": null` (서킷브레이커 대체), `"borrow_pool_enabled": false`
  - `"report_type_sequence": ["Q1", "Q2", "Q3", "Q4"]`

**Phase 3 — LOW (Sprint 10 내 처리, 전부 확정)**
- [ ] `FormatUtils.format_currency(amount: int, market_id: String) -> String` 신규 추가
  - `"KR"` → 쉼표 포맷 원화 문자열
  - `"US"` 슬롯 확보 (실제 구현은 US DLC 시)
- [ ] 모든 UI 금액 표시를 `FormatUtils.format_currency()` 단일 메서드로 통일
  - 분산된 금액 포맷 문자열 grep 후 전수 교체 (`grep -r "원\"" src/ui/`)
- [ ] 엔딩 트리거 임계값 MarketProfile화 → endings-achievements.md §9 DLC 섹션 참조
- [ ] 이벤트 풀 `market_id` 필터 인프라 → news-events.md §9 DLC 섹션 참조
- [ ] 종목 데이터 시장별 분리 (`stocks_kr.json`) → stock-database.md §9 DLC 섹션 참조
- [ ] 테스트: `test_financial_report_system.gd` — `test_market_profile_full_schema_kr()` 추가 (market_kr.json 전 필드 존재 확인)

### 호출 경로
- [x] `SeasonManager.on_season_started` → `FinancialReportSystem._on_season_started()` → `schedule_quarterly_events(_current_season)`
- [x] `GameClock.on_market_state_changed(PRE_MARKET)` → `_on_pre_market(day)` → analyst/preliminary/report 처리 (E-05 catch-up 포함)
- [x] `GameClock.on_tick(tick, day, week)` → `_on_tick()` → 루머 발생 체크 (tick==RUMOR_FIRE_TICK_IN_DAY=40)
- [x] `_fire_official_report()` → `_apply_roe_update()` 원자적 + `NewsEventSystem.fire_stock_news()` 연동
- [x] `_fire_rumor()` → `NewsEventSystem.fire_stock_news()` + `NewsEventSystem.inject_event("RUMOR_FINANCIAL")` (ADR-022)
- [x] `SaveSystem.save_slot()` → `FinancialReportSystem.get_save_data()` (`_pending_events` 포함)
- [x] `SaveSystem.load_slot()` → `FinancialReportSystem.load_save_data()` + 자동 catch-up (`_on_pre_market` 재호출)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-FR-01 | `test_financial_report_system.gd` | `test_is_report_season_returns_true_on_cycle_boundary()` |
| AC-FR-02 | `test_financial_report_system.gd` | `test_get_report_type_follows_sequence()` |
| AC-FR-03 | `test_financial_report_system.gd` | — (S10-07 E2E 시나리오로 처리) |
| AC-FR-04 | `test_financial_report_system.gd` | `test_compute_new_roe_is_clamped_within_bounds()` |
| AC-FR-05 | `test_financial_report_system.gd` | `test_classify_event_turnaround_profit()` |
| AC-FR-06 | `test_financial_report_system.gd` | `test_classify_event_earnings_surprise()` |
| AC-FR-07 | `test_financial_report_system.gd` | `test_classify_event_earnings_shock()` |
| AC-FR-08 | `test_financial_report_system.gd` | — (E2E: `_build_event_entry` 검증 S10-07) |
| AC-FR-09 | `test_financial_report_system.gd` | — (통계적 검증 S10-07 E2E) |
| AC-FR-10 | `test_financial_report_system.gd` | — (E2E 시나리오 S10-07) |
| AC-FR-11 | `test_financial_report_system.gd` | — (phase 2) |
| AC-FR-12 | `test_financial_report_system.gd` | — (E2E 시나리오 S10-07) |
| AC-FR-13 | `test_financial_report_system.gd` | `test_save_load_round_trip_preserves_state()` |
| AC-FR-14 | `test_financial_report_system.gd` | `test_apply_roe_update_sets_per_sentinel_when_roe_negative()` |
| AC-FR-15 | `test_financial_report_system.gd` | `test_compute_new_roe_returns_zero_for_missing_stock()` |
| AC-FR-16 | `test_financial_report_system.gd` | — (phase 2) |
| AC-FR-17 | `test_financial_report_system.gd` | — (S10-07 E2E) |
| AC-FR-18 | `test_financial_report_system.gd` | `test_roll_preliminary_low_profile_almost_always_true()` |
| AC-FR-19 | `test_financial_report_system.gd` | `test_roll_preliminary_disabled_for_extreme_profile()` |
| AC-FR-20 | `test_financial_report_system.gd` | — (S10-07 MarketProfile 통합 후) |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
