# ADR-027 — Price Kernel Unification

**Status**: Accepted  
**Supersedes**: ADR-024 (C++ = stateless batch generator → stateful full kernel)  
**Date**: 2026-04-23

---

## 1. 문제

가격에 영향을 주는 연산이 GDScript 4개 시스템에 분산되어 있다.

| 시스템 | 가격 영향 로직 (현재 GDScript) |
|--------|-------------------------------|
| PriceEngine | Markov + drift + event 적용 + sensitivity + player + rumor |
| NewsEventSystem | 이벤트 풀 선택 · 타겟 · impact 계산 |
| EtfManager | 섹터 수익률 · 로테이션 판정 · 이벤트 생성 |
| FinancialReportSystem | 보고서 시즌 · ROE · 어닝 판정 · 이벤트 스케줄 |

결과:
- 프리히스토리 생성은 Markov + drift만 (이벤트 없음) → 라이브와 텍스처 다름
- 프리히스토리를 라이브처럼 만들려면 위 4개 시스템을 동일하게 돌려야 하는데, GDScript Autoload는 백그라운드 스레드에서 실행 불가
- 고칠수록 코드 경로가 늘어나는 구조적 문제

---

## 2. 결정

**가격에 영향을 주는 커널을 C++ 단일 구현으로 통합한다.**

4개 시스템 각각의 "가격 영향 로직"을 C++로 이전. GDScript에는 UI · 시그널 · 세이브/로드만 남긴다.

```
┌─────────────────────────────────────────────────┐
│                   C++ PriceKernel               │
│                                                 │
│  MarkovEngine   EventEngine   EtfEngine         │
│  (가격 계산)    (이벤트 생성·적용)  (섹터 ETF)     │
│                                                 │
│              ReportEngine                       │
│           (실적 발표 스케줄)                      │
└─────────────────────────────────────────────────┘
         ↑ set_config()          ↓ process_all_ticks()
┌─────────────────────────────────────────────────┐
│              GDScript (UI Layer)                │
│  뉴스카드 표시  ETF UI  A3화면  세이브/로드  스킬트리│
└─────────────────────────────────────────────────┘
```

---

## 3. 시스템 경계

### C++로 이전하는 것 (커널)

**PriceEngine**
- Markov 상태머신 + 전이 행렬 (아키타입별)
- drift (mean reversion + macro trend)
- event 적용 (instant shock / gradual shift + decay)
- macro/sector sensitivity 가중치
- rumor pressure 소모
- volume 계산 (energy correlation)
- 상하한가 clamp, VI 판정 결과 반환

**NewsEventSystem**
- 이벤트 풀 슬롯 선택 (scope 가중치, impact 선택)
- 쿨다운 · mutex 그룹 추적
- 시즌 태그 필터
- 타겟 종목 선택 (vol_profile 가중치)
- impact 계산 → 내부 event queue push

**EtfManager**
- 섹터 수익률 계산 (`_get_sector_return`)
- 로테이션 모멘텀 판정 (`momentum > threshold`)
- 로테이션 이벤트 생성 + 가격 적용
- ETF 구성종목 가중평균 → ETF 가격 계산

**FinancialReportSystem**
- 보고서 시즌 판정 (`is_report_season`)
- 뉴스워시 종목 선택 (`_select_newsworthy`)
- 이벤트 스케줄 빌드 (`_build_event_entry`)
- ROE 계산 (`_compute_new_roe`, `_compute_consensus_roe`)
- 어닝 분류 (`_classify_event`)
- 루머 · 잠정 · 공식 발표 이벤트 → 가격 적용
- quiet update (A3 데이터 갱신)

### GDScript에 남는 것 (UI)

| 시스템 | 남는 것 |
|--------|---------|
| PriceEngine | `on_price_updated` 시그널, `round_to_tick()` 공개 API, 세이브/로드 |
| NewsEventSystem | `on_news_display` 시그널 → NewsFeedUI 뉴스카드 렌더링 |
| EtfManager | ETF 가격 UI 반영 (`inject_price()` 위임받아 처리) |
| FinancialReportSystem | A3 화면 데이터 갱신, 뉴스카드 표시 |
| 공통 | 시그널 라우팅, 세이브/로드 직렬화, 스킬트리 연동 |

**player_pressure**: 플레이어 주문 체결 → GDScript에서 C++에 전달. 히스토리 시뮬레이션 중에는 전달하지 않음 (kernel 내부 값 0).

**VI/CB**: 히스토리 시뮬레이션 중에도 완전히 동일하게 시뮬한다. VI 발동 → N tick 가격 동결, CB 발동 → 잔여 거래일 동결. 예외 없음. 라이브와 동일 커널 코드 경로.

---

## 4. C++ 내부 구조

단일 GDExtension 클래스 `PriceKernel` 하나를 노출. 내부는 4개 엔진으로 분리.

```
PriceKernel (GDExtension 노출)
├── MarkovEngine      — per-stock Markov 상태 + 가격 계산
├── EventEngine       — 이벤트 풀 · 쿨다운 · 타겟 선택 · 적용
├── EtfEngine         — 섹터 수익률 · 로테이션 · ETF 가격
└── ReportEngine      — 보고서 시즌 · ROE · 이벤트 스케줄
```

### per-stock 상태 (MarkovEngine)

```cpp
struct StockState {
    // Markov
    int    markov_state;       // 0–6
    int    state_duration;
    int    macro_state;        // ADR-026
    // Price
    int    base_price;         // 기준가 (시즌간 불변, config에서 초기화)
    int    current_price;
    int    prev_day_close;
    // Sensitivity
    int    vol_profile;
    float  macro_sensitivity;
    float  sector_sensitivity;
    String sector;
    String archetype;
    // Event queues
    vector<GradualEvent> gradual_events;  // 진행 중인 gradual shift 목록
    float  player_pressure;              // 0.0 for historical
    float  rumor_delta_per_tick;
    int    rumor_ticks_remaining;
    // Fundamentals (ReportEngine 소유)
    float  roe;
    float  per;
    float  pbr;
    // VI/CB 상태
    int    vi_halt_remaining;   // 0 = 정상, >0 = VI halt 잔여 tick 수
    bool   cb_halted;           // true = circuit breaker 발동, 당일 종가 동결
    // RNG (세이브 시 복원 안 함 — ADR-018 세션 엔트로피 격리)
    Pcg32  rng;
};
```

### 시즌 공유 상태 (PriceKernel 소유 — EventEngine · EtfEngine 양쪽이 읽음)

```cpp
struct SeasonState {
    int     season_number;
    // EventEngine: scope별 가중치 (season_themes의 *_weight_scale 필드)
    float   macro_weight_scale;
    float   sector_weight_scale;
    float   individual_weight_scale;
    // EventEngine: 활성 시즌 태그 (이벤트 풀 필터링)
    vector<string> active_season_tags;
    // EventEngine + EtfEngine 공유: 섹터별 bias 배율
    unordered_map<string, float> sector_bias;
};
// 주의: hint_revealed_at_day, hint_text는 UI 전용 → GDScript가 보유, C++에 전달 안 함.
```

### UI 이벤트 반환 (tick마다 GDScript로)

`process_all_ticks()`는 가격 결과 외에 **UI 이벤트 목록**을 함께 반환한다.  
GDScript는 이를 받아 뉴스카드 · ETF UI · A3 화면을 업데이트한다.

```cpp
// 반환 Dictionary 구조
{
  "prices":    {stock_id: new_price, ...},
  "volumes":   {stock_id: volume, ...},
  "vi_hits":   [{stock_id, is_upper}, ...],   // VI 발동 목록
  "ui_events": [
    {
      "type":        "NEWS",     // NEWS | ROTATION | REPORT | RUMOR
      "template_id": "...",      // GDScript가 event_pool.json에서 headline/body lookup
      "stock_id":    "...",      // null 허용 (MACRO/SECTOR 이벤트)
      "sector":      "...",
      "direction":   1,
      "impact_tier": "MEDIUM",
      "fire_tick":   42,         // C++가 이벤트 발화한 tick_in_day
                                 // 뉴스 표시 지연은 GDScript가 fire_tick + DELAY로 계산
    },
    ...
  ],
  "a3_updates": [                // ROE/PER/PBR 변경된 종목
    {stock_id, new_roe, new_per, new_pbr},
    ...
  ],
  "etf_prices": {etf_id: price, ...},
}
```

**헤드라인 · body 텍스트는 C++에 없다.** C++는 `template_id`만 반환. GDScript가 `event_pool.json`에서 O(1) lookup 후 렌더링. 로컬라이제이션도 GDScript 담당.

**히스토리 시뮬 중 반환값**: `process_all_ticks()` 내부 호출 결과는 버리고 M1/D1 버퍼에만 기록. ui_events · a3_updates 수집 안 함 (UI 없음). 최종 상태(final_price, final_roe 등)는 시뮬 완료 후 별도 반환.

---

## 5. API 설계

### 5-1. 초기화

```cpp
// 전체 config 한 번에 로드 (기존 set_config 확장)
// price_engine_config + event_pool + season_themes +
// etf_config + financial_report_config + market_profile
void set_config(Dictionary unified_cfg);

// 종목 등록
void init_stock(String stock_id, Dictionary stock_data);
// stock_data: base_price, vol_profile, sector, archetype,
//             macro_sensitivity, sector_sensitivity, current_price,
//             prev_day_close, roe, per, pbr

// 리셋 (새 게임 / 세이브 로드 후)
void reset();
```

### 5-2. 시즌 경계

```cpp
// 시즌 시작: SeasonState 갱신 + ReportEngine 분기 스케줄 초기화
void start_season(int season_number, Dictionary season_theme);
// season_theme 필수 필드:
//   sector_bias:              {sector_id: float, ...}  — EventEngine + EtfEngine 공유
//   active_season_tags:       Array[String]            — EventEngine 이벤트 필터
//   macro_weight_scale:       float                    — MACRO scope 가중치 배율
//   sector_weight_scale:      float                    — SECTOR scope 가중치 배율
//   individual_weight_scale:  float                    — INDIVIDUAL scope 가중치 배율
// UI 전용 필드(hint_revealed_at_day, hint_text)는 전달하지 않음

// 일 경계:
//   - 전 종목 prev_day_close = current_price
//   - 매크로 상태 전이 (ADR-026 _roll_macro_states)
//   - 전 종목 player_pressure = 0.0 리셋
//   - VI/CB 상태 초기화 (vi_halt_remaining = 0, cb_halted = false)
void start_day(int day_number);
```

### 5-3. 라이브 tick 처리

```cpp
// tick당 1회. 전 종목 처리 → UI 이벤트 포함 결과 반환.
Dictionary process_all_ticks(int tick_in_day);

// 플레이어 주문 체결 → 다음 tick에 반영
void add_player_pressure(String stock_id, float delta);

// 플레이어 루머 구매 → per-tick 가격 압력 등록 (현재 _on_rumor_hint() 경로)
// GDScript가 is_fake 여부를 판단 후 진짜 루머만 전달.
// delta_per_tick = direction × rumorPressureStrength × tier_mult
// ticks_remaining = SkillTree.RUMOR_LEAD_MINUTES × GameClock.TICKS_PER_MINUTE
void set_rumor(String stock_id, float delta_per_tick, int ticks_remaining);

// 스킬트리 / 외부 트리거로 즉발 이벤트 주입 (현재 NewsEventSystem.inject_event() 역할)
// EtfEngine·ReportEngine이 내부 생성하는 이벤트와 달리,
// 플레이어 액션에서 발원하는 이벤트는 GDScript가 판단 후 여기로 전달.
// event_entry: { template_id, target_stock_id, impact_override, direction, event_type }
// impact_override가 0이면 EventEngine이 template의 impact_min/max에서 랜덤 선택.
void inject_event(Dictionary event_entry);
```

### 5-4. 히스토리 시뮬레이션 (백그라운드 스레드)

```cpp
// 인트로 시작 시 백그라운드에서 호출.
// process_all_ticks()와 동일 커널을 n_seasons × days_per_season × ticks_per_day 루핑.
// player_pressure는 전달하지 않으므로 항상 0. 나머지 커널 코드 완전 동일.
//
// theme_sequence: GDScript가 라이브와 동일한 로직으로 사전 생성한 시즌 테마 배열.
//   Array[Dictionary], len = n_seasons.
//   이유: 테마 선택 로직을 C++에 복제하지 않음 (로직 단일 소유 원칙).
//   GDScript: for i in n_seasons: themes.append(SeasonManager.pick_theme(seed, i))
//
// seed: 종목별 RNG 시드 (stock_id별 XOR 파생).
//
// 내부 버퍼: 종목당 rolling M1(m1_cache_bars 크기) + rolling D1(d1_cache_bars 크기).
//   크기는 set_config()의 "m1_cache_bars"(기본 7800), "d1_cache_bars"(기본 5200) 사용.
//   시뮬 전체가 아닌 마지막 N 바만 유지 → 메모리 O(종목수 × 캐시크기).
//
// VI/CB: 라이브와 동일하게 시뮬. 예외 없음.
Dictionary run_historical_simulation(
    int    n_seasons,
    int    days_per_season,
    int    ticks_per_day,
    Array  theme_sequence,   // Array[Dictionary], len = n_seasons
    int64_t seed
);
// 반환: {
//   stock_id: {
//     "m1_ohlc": PackedFloat32Array,   // [o,h,l,c] × m1_cache_bars (최신순)
//     "m1_vol":  PackedInt32Array,     // volume × m1_cache_bars
//     "d1_ohlc": PackedFloat32Array,   // [o,h,l,c] × d1_cache_bars (최신순)
//     "d1_vol":  PackedInt32Array,     // volume × d1_cache_bars
//     "final_price": int,
//     "final_roe":   float,
//     "final_per":   float,
//     "final_pbr":   float,
//     "final_markov_state": int,
//     "final_macro_state":  int,
//   },
//   ...
// }
```

`run_historical_simulation()`은 `start_season()` → `start_day()` → `process_all_ticks()` 루프를 내부에서 돌린다. 별도 코드 경로 없음.

### 5-5. 세이브/로드

```cpp
// 세이브: 전 종목 런타임 상태 직렬화 (GDScript가 파일로 기록)
Dictionary get_all_stock_states();
// 반환: {
//   stock_id: {
//     markov_state, state_duration, macro_state,
//     current_price, prev_day_close,
//     gradual_events: [{type, remaining_ticks, delta_per_tick}, ...],
//     rumor_delta_per_tick, rumor_ticks_remaining,
//     roe, per, pbr
//   }, ...
// }
// RNG 상태는 포함하지 않음 — 로드 후 새 세션 키로 재시드 (ADR-018 세션 엔트로피 격리 유지)

// 로드: reset() → set_config() → init_stock() × N 후 호출
// init_stock()의 초기값 위에 저장된 런타임 상태를 덮어씀
void restore_stock_state(String stock_id, Dictionary saved_state);
```

### 5-6. 진행도 (히스토리 시뮬 중 UI 갱신용)

```cpp
// Thread 실행 중 GDScript가 Timer로 폴링 (500ms 권장)
// 반환 범위: 0–1000 (permille). 내부 atomic<int> — 스레드 안전.
int get_simulation_progress();
// GDScript 예시:
//   $Timer.timeout.connect(func():
//       var p = PriceKernel.get_simulation_progress()
//       $ProgressBar.value = p / 10.0   # 0.0–100.0%
//       if p >= 1000: $Timer.stop()
//   )
```

---

## 6. 데이터 플로우

### 라이브

```
[인트로 완료 후]
GDScript → PriceKernel.set_config(unified_cfg)
GDScript → PriceKernel.init_stock(id, data) × N종목
GDScript → PriceKernel.start_season(1, theme)

[매 tick]
GameClock.on_tick(tick, day, week)
  → PriceEngine.process_tick()
      result = PriceKernel.process_all_ticks(tick_in_day)
      // 가격 적용
      for (id, price) in result["prices"]:
          _stock_states[id]["current_price"] = price
      // VI 시그널
      for vi in result["vi_hits"]:
          on_vi_triggered.emit(...)
      // UI 이벤트 → 각 GDScript 시스템으로 라우팅
      for ev in result["ui_events"]:
          match ev["type"]:
              "NEWS":    NewsFeedUI.show_card(ev)
              "REPORT":  FinancialReportUI.show_card(ev)
              "ROTATION": NewsFeedUI.show_card(ev)
      // A3 갱신
      for upd in result["a3_updates"]:
          StockDatabase.update_fundamentals(upd)
      // ETF 가격
      for (id, price) in result["etf_prices"]:
          _stock_states[id]["current_price"] = price
      on_price_updated.emit(tick)

[플레이어 주문 체결]
OrderEngine → PriceKernel.add_player_pressure(stock_id, delta)
```

### 히스토리 (인트로 백그라운드)

```
[인트로 시작 — GDScript 메인 스레드]
// 1. 테마 시퀀스 사전 생성 (라이브와 동일 로직 — C++ 복제 없음)
var theme_sequence = []
for i in range(n_seasons):
    theme_sequence.append(SeasonManager.pick_theme(seed, i))

// 2. 커널 초기화
PriceKernel.set_config(unified_cfg)
PriceKernel.init_stock(id, data) × N종목   // 초기 종목 데이터

// 3. 백그라운드 시작 + 진행도 폴링
Thread.start(PriceKernel.run_historical_simulation,
             n_seasons, 20, 1560, theme_sequence, seed)
$ProgressTimer.start(0.5)   // 500ms 간격 폴링

[C++ 내부 루프 — 백그라운드 스레드]
_progress.store(0)                                    // atomic 리셋
for season in range(n_seasons):
    start_season(season, theme_sequence[season])
    for day in range(days_per_season):
        start_day(day)
        for tick in range(ticks_per_day):
            process_all_ticks(tick)                   // 동일 커널 (VI/CB 포함)
            append_to_rolling_buffer()                // M1/D1 rolling 버퍼
    _progress.store((season + 1) * 1000 / n_seasons) // 진행도 갱신

[완료 — GDScript 메인 스레드]
result = Thread.wait_to_finish()
$ProgressTimer.stop()
M1CacheManager.load_from_simulation(result)           // M1/D1 캐시 적재
// result의 final_price, final_roe 등 → 라이브 init_stock() 재호출 시 사용
PriceKernel.reset()                                   // 상태 초기화
// 실제 게임 시작 (시즌 1부터)
```

**라이브와 히스토리의 유일한 차이**: `add_player_pressure()` / `set_rumor()` / `inject_event()` 호출 없음. 커널 코드 완전히 동일. VI/CB 포함.

---

## 7. Config 통합

현재 각 시스템이 별도 JSON을 로드한다. C++ `set_config()`는 GDScript가 미리 머지한 단일 Dictionary를 받는다.

```gdscript
# GDScript에서 머지 후 전달
var unified = {}
unified.merge(load_json("price_engine_config.json"))
unified["event_pool"] = load_json("event_pool.json")["templates"]
unified["season_themes"] = load_json("season_themes.json")["themes"]
unified["etf_config"] = load_json("etf_config.json")
unified["report_config"] = load_json("financial_report_config.json")
unified["market_profile"] = MarketProfile.get_active_profile()
# 히스토리 시뮬 rolling 버퍼 크기 (M1CacheManager 상수와 동기화 필수)
unified["m1_cache_bars"] = M1CacheManager.M1_CACHE_SIZE   # 7800
unified["d1_cache_bars"] = M1CacheManager.D1_CACHE_SIZE   # 5200
PriceKernel.set_config(unified)
```

**이벤트 풀 분리**: C++는 가격 영향 필드만 사용.  
`template_id, scope, impact_min, impact_max, direction, event_type, decay_minutes, weight_base, cooldown_minutes, season_tags, mutex_group, event_tags`  
헤드라인 · body · variables는 GDScript가 보유 (UI 렌더링용).

**시즌 테마 분리**: C++는 `sector_bias, active_season_tags, macro_weight_scale, sector_weight_scale, individual_weight_scale`만 사용.  
`hint_revealed_at_day, hint_text`는 GDScript UI 전용 — C++에 전달 안 함.

---

## 8. 마이그레이션 순서

단계별로 DLL 재빌드 1회씩. 각 단계 완료 후 기존 테스트 전부 통과 확인.

### Phase A — MarkovEngine 라이브 통합
`process_all_ticks()` 구현. GDScript `_process_stock_tick()` → C++ 위임.  
이벤트는 아직 GDScript가 push. 검증: 라이브 가격 동작 이상 없음.

### Phase B — EventEngine 통합
이벤트 풀 선택 · 타겟 · impact 계산 C++로. GDScript `NewsEventSystem`에서 이벤트 생성 제거.  
`process_all_ticks()` 반환에 `ui_events` 추가. GDScript UI 라우팅 연결.

### Phase C — EtfEngine 통합
섹터 수익률 · 로테이션 · ETF 가격 C++로. `EtfManager.process_tick()` GDScript 로직 제거.  
반환에 `etf_prices` 추가.

### Phase D — ReportEngine 통합
보고서 시즌 · ROE · 어닝 판정 C++로. `FinancialReportSystem` GDScript 커널 제거.  
반환에 `a3_updates` 추가.

### Phase E — 히스토리 시뮬레이션
`run_historical_simulation()` 구현. 인트로 백그라운드 호출로 교체.  
기존 `generate_stock_m1()` deprecated.  
`M1CacheManager.CACHE_VERSION` 6 → **7** 범프 (알고리즘 교체로 기존 캐시 무효화).  
`get_simulation_progress()` 구현 + GDScript 진행도 UI 연결.

---

## 9. 리스크

| 리스크 | 내용 | 대응 |
|--------|------|------|
| GDScript ↔ C++ 반환 Dictionary 크기 | tick당 prices + ui_events + a3_updates | 이벤트 없는 tick은 빈 배열. 평균 이벤트 수 낮음 (4~8/일). 필요 시 PackedArray로 교체. |
| 히스토리 시뮬 속도 | 9.36M tick × 커널 비용 | UI/시그널 없음, 순수 연산. VI/CB 시뮬은 tick skip이므로 오히려 더 빠름. Phase E 완료 후 실측. |
| 히스토리 VI 빈도 | 역사 시뮬 중 VI가 자주 발동하면 D1 품질 하락 | VI는 라이브와 동일 조건(±10% 이내봉). 과도하면 아키타입 행렬 조정으로 해결 — 커널 예외 추가 안 함. |
| 세이브/로드 RNG 비연속 | 로드 후 RNG 재시드 → 가격 경로 비결정론적 | 의도된 동작 (ADR-018). 가격 연속성은 current_price 복원으로 보장. |
| 세이브 중 gradual_events | 진행 중인 이벤트 직렬화 필요 | `get_all_stock_states()`가 gradual_events queue 포함. |
| CACHE_VERSION 범프 | Phase E 완료 시 기존 캐시 전부 무효 | CACHE_VERSION 8→9. 인트로에서 자동 재생성. 기존 세이브 파일은 영향 없음 (캐시는 별도). |
| 헤드라인 lookup | C++가 template_id만 반환 → GDScript lookup | event_pool.json GDScript 사본 유지. O(1) Dictionary lookup. |
| theme_sequence 길이 불일치 | GDScript 생성 배열 길이 ≠ n_seasons | C++가 범위 초과 시 마지막 테마 반복 사용 + 경고. GDScript에서 assert로 사전 검증. |
| Phase 간 중간 상태 | Phase A 완료 후 B 전: 이벤트 GDScript, 가격 C++ | Phase마다 통합 테스트. 중간 상태도 정상 동작 설계. |

---

## 10. 검증 기준

- [ ] Phase A: 라이브 가격 분포 기존 대비 통계적 동등 (100시즌 mean/std ±5%)
- [ ] Phase B: 뉴스카드 발화 빈도 · 내용 기존 대비 동등
- [ ] Phase C: ETF 가격 추적 오차 없음
- [ ] Phase D: 실적 발표 뉴스 시즌 게이팅 정상
- [x] Phase E: run_historical_simulation() C++ 구현 (bc7b742)
- [ ] Phase E: 프리히스토리-라이브 경계 육안 차이 없음 (VI 발동 포함) — 플레이테스트 필요
- [x] Phase E: CACHE_VERSION = 9, 구버전 캐시 자동 무효화
- [ ] Phase E: 히스토리 시뮬 완료 시간 인트로 허용 범위 이내 (실측 필요)
- [x] Phase E: get_simulation_progress() 0→1000 구현 완료 (실측은 플레이테스트)
- [ ] 전 Phase: 기존 GUT 테스트 전부 통과
- [ ] 세이브 → get_all_stock_states() → restore_stock_state() 후 가격 연속성 유지
- [ ] 로드 후 RNG 재시드 — price scout 재현 불가 (ADR-018 유지 확인)
