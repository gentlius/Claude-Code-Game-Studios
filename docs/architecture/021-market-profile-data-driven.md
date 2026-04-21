# ADR-021: MarketProfile 데이터 기반 시장 규칙 분리

> **Status**: Accepted (개정 2026-04-20 — 섹터/ETF/아키타입/로테이션/로컬라이제이션 범위 확장)
> **Date**: 2026-04-20
> **Deciders**: Technical Director, Game Designer, Lead Programmer, Localization Lead
> **Context**: FinancialReportSystem 설계 + EtfManager 섹터 로테이션 + DLC 시장 확장 검토

---

## 배경

두 가지 계기로 MarketProfile 범위가 확장됐다.

**1차 (FinancialReportSystem)**: 한국 시장 회계 규칙(분기 주기, 잠정실적 확률 등)을 코드에
하드코딩하면 DLC 시장 추가마다 조건 분기가 누적된다.

**2차 (EtfManager 섹터 로테이션)**: 섹터 아키타입, 라이벌 가중치, 로테이션 파라미터,
헤드라인 문자열 키가 시장마다 다르다. KR의 "성장_기술 vs 방어_가치" 구도가 US/JP에서는
다른 구조를 갖는다. 이 모든 것이 코드에 박히면 DLC 추가가 불가능해진다.

---

## 결정

**시장별 규칙 전체를 `MarketProfile` JSON 파일로 분리한다.**

```
assets/data/market_profiles/
├── market_kr.json    # 한국 시장 (기본)
├── market_us.json    # 미국 시장 (DLC)
└── market_jp.json    # 일본 시장 (DLC)
```

### 핵심 원칙

1. **코드는 `MarketProfile.get_active()`만 안다** — `if market == "KR"` 분기 금지
2. **시즌 단위 단일 시장** — 동시 멀티마켓 없음. 시즌 시작 시 전체 재초기화
3. **헤드라인은 키만, 문자열은 Godot `.po`** — MarketProfile이 언어 문자열을 직접 담지 않는다

---

## MarketProfile 스키마 (전체)

```json
{
  "market_id": "KR",
  "display_name_ko": "한국 코스피",
  "display_name_en": "Korea KOSPI",

  "trading": {
    "commission": 0.00015,
    "sell_tax": 0.002,
    "capital_gains_rate": 0.0,
    "margin_rate_min": 1.20
  },

  "calendar": {
    "ticks_per_day": 390,
    "days_per_season": 20,
    "fiscal_year_start_season": 1,
    "report_cycle_seasons": 3,
    "report_type_sequence": ["Q1", "H1", "Q3", "Annual"],
    "preliminary_earnings": {
      "enabled": true,
      "day_offset": 3,
      "probability_by_profile": {
        "LARGE": 1.0, "MEDIUM": 0.7, "SMALL": 0.3, "VOLATILE": 0.0
      }
    }
  },

  "sectors": [
    "반도체", "2차전지", "바이오", "자동차",
    "에너지", "금융", "게임", "엔터", "건설", "유통", "통신"
  ],

  "etfs": {
    "ETF_반도체": { "sector": "반도체", "base_price": 50000 },
    "ETF_2차전지": { "sector": "2차전지", "base_price": 50000 },
    "ETF_바이오":  { "sector": "바이오",  "base_price": 50000 },
    "ETF_자동차":  { "sector": "자동차",  "base_price": 50000 },
    "ETF_에너지":  { "sector": "에너지",  "base_price": 50000 },
    "ETF_금융":    { "sector": "금융",    "base_price": 50000 },
    "ETF_게임":    { "sector": "게임",    "base_price": 50000 },
    "ETF_엔터":    { "sector": "엔터",    "base_price": 50000 },
    "ETF_건설":    { "sector": "건설",    "base_price": 50000 },
    "ETF_유통":    { "sector": "유통",    "base_price": 50000 },
    "ETF_통신":    { "sector": "통신",    "base_price": 50000 }
  },

  "sector_archetypes": {
    "GROWTH_TECH": ["반도체", "바이오", "게임"],
    "THEMATIC":    ["2차전지", "에너지", "엔터"],
    "CYCLICAL":    ["자동차", "건설"],
    "DEFENSIVE":   ["금융", "통신", "유통"]
  },

  "rivalry_weights": {
    "GROWTH_TECH": { "DEFENSIVE": 0.6, "CYCLICAL": 0.3, "THEMATIC": 0.1 },
    "THEMATIC":    { "DEFENSIVE": 0.5, "GROWTH_TECH": 0.3, "CYCLICAL": 0.2 },
    "CYCLICAL":    { "GROWTH_TECH": 0.5, "DEFENSIVE": 0.3, "THEMATIC": 0.2 },
    "DEFENSIVE":   { "GROWTH_TECH": 0.5, "THEMATIC": 0.3, "CYCLICAL": 0.2 }
  },

  "rotation_params": {
    "flow_sensitivity": 0.5,
    "flow_decay": 0.1,
    "threshold": 0.03,
    "cooldown_ticks": 5,
    "inflow_impact": [0.04, 0.07],
    "outflow_impact": [0.02, 0.03]
  },

  "rotation_headline_keys": {
    "inflow":  ["ROTATION_KR_INFLOW_0", "ROTATION_KR_INFLOW_1", "ROTATION_KR_INFLOW_2"],
    "outflow": ["ROTATION_KR_OUTFLOW_0", "ROTATION_KR_OUTFLOW_1"]
  },

  "source_locale": "ko",

  "endings": {
    "bankruptcy": {
      "threshold": 10000,
      "name_key":  "ENDING_KR_BANKRUPTCY_NAME",
      "body_key":  "ENDING_KR_BANKRUPTCY_BODY",
      "visual":    "res://assets/endings/kr_hangang.png"
    },
    "leverage_crash": {
      "name_key":  "ENDING_KR_LEVERAGE_NAME",
      "body_key":  "ENDING_KR_LEVERAGE_BODY",
      "visual":    "res://assets/endings/kr_loansharks.png"
    },
    "win": {
      "threshold": 100000000000,
      "name_key":  "ENDING_KR_WIN_NAME",
      "body_key":  "ENDING_KR_WIN_BODY"
    }
  },

  "achievements": []
}
```

### 헤드라인 로컬라이제이션 계층

MarketProfile은 문자열 **키**만 담는다. 실제 문자열은 Godot `.po` 파이프라인이 관리한다.

```
# locale/ko.po (한국어)
msgid "ROTATION_KR_INFLOW_0"
msgstr "{sector} 섹터 수급 개선 — 기관 비중 확대"

msgid "ROTATION_KR_INFLOW_1"
msgstr "{sector} 업종 강세 전환, 외국인 순매수"

# locale/en.po (영어 — DLC 글로벌 출시 시 추가)
msgid "ROTATION_KR_INFLOW_0"
msgstr "{sector} sector sees institutional inflows"
```

런타임 사용:
```gdscript
var key = MarketProfile.get_rotation_headline("inflow")
var headline = tr(key).format({"sector": sector_display_name})
```

**키 네이밍 규칙**: `ROTATION_{MARKET_ID}_{DIRECTION}_{INDEX}`
→ 시장 간 키 충돌 없음. DLC 시장 헤드라인은 새 키 추가만으로 확장.

---

## 핵심 API (MarketProfile autoload)

```gdscript
# 시즌 시작 시 활성 시장 로드
func load_market(market_id: String) -> void

# 데이터 접근
func get_active() -> Dictionary           # 전체 프로파일
func get_sectors() -> Array[String]
func get_etfs() -> Dictionary
func get_archetype(sector: String) -> String
func get_sectors_in_archetype(archetype: String) -> Array[String]
func get_rivalry_weights(archetype: String) -> Dictionary
func get_rotation_params() -> Dictionary
func get_rotation_headline(direction: String) -> String  # 랜덤 키 반환
func get_trading_param(key: String) -> Variant
func get_calendar_param(key: String) -> Variant
func get_ending_param(ending_id: String, field: String) -> Variant  # endings 블록 조회
func get_dlc_achievements() -> Array  # DLC 전용 업적 목록 (기본값 빈 배열)

# 런타임 조정 (매크로 이벤트 시 rivalry_weights 임시 보정)
func apply_macro_context(context_id: String) -> void
func reset_macro_context() -> void
```

---

## FinancialReportSystem 핵심 함수 (변경 없음)

```gdscript
func is_report_season(season: int) -> bool:
    var cycle: int = MarketProfile.get_calendar_param("report_cycle_seasons")
    var start: int = MarketProfile.get_calendar_param("fiscal_year_start_season")
    return season >= (start + cycle) and ((season - start) % cycle == 0)

func get_report_type(season: int) -> String:
    var seq: Array = MarketProfile.get_calendar_param("report_type_sequence")
    var cycle: int = MarketProfile.get_calendar_param("report_cycle_seasons")
    var start: int = MarketProfile.get_calendar_param("fiscal_year_start_season")
    var index: int = ((season - start) / cycle - 1) % seq.size()
    return seq[index]
```

---

## DLC 추가 시 필요한 작업

1. `assets/data/market_profiles/market_XX.json` 파일 추가
2. `locale/ko.po` / `locale/en.po`에 `ROTATION_XX_*` 키 추가
3. `FinancialReportSystem`, `EtfManager`, 기타 시스템 — **코드 변경 없음**
4. 시즌 선택 UI에 새 시장 옵션 노출 (UI 작업만)

---

## 기각한 대안

### 대안 A: 시장별 서브클래스
`FinancialReportSystemKR` 등 상속 분기. Godot autoload 단일 인스턴스 제약 + 공통 로직 중복. 기각.

### 대안 B: `if market == "KR"` 분기
시장 수 증가에 따라 분기 누적. 3번째 시장부터 스파게티화. 기각.

### 대안 C: 동시 멀티마켓
PriceEngine/OrderEngine/Portfolio 전면 재설계 필요. 게임 필라("판단이 곧 실력") 충돌.
인지 부하 2배. 기각. **시즌 단위 단일 시장으로 확정.**

### 대안 D: 헤드라인 문자열 MarketProfile에 직접 포함
번역가가 JSON 파라미터 파일을 수정해야 함. Godot `.po` 도구체인과 충돌. 기각.

### 대안 E: 별도 locale 계층 (locale/ko/market_kr.json)
Godot 기본 i18n 우회하는 자체 시스템. 유지 비용 최대. 기각.

---

## 결과 및 영향

### 시스템별 전환 대상

| 시스템 | 전환 내용 |
|--------|---------|
| FinancialReportSystem | 회계 캘린더, 보고서 주기, 잠정실적 확률 → `get_calendar_param()` |
| EtfManager | ETF 목록, 기준가, sector_archetypes, rivalry_weights, rotation_params → `get_*()` |
| OrderEngine (수수료) | commission, sell_tax, capital_gains_rate → `get_trading_param()` |
| ShortSelling | margin_rate_min → `get_trading_param()` |
| SeasonManager | days_per_season → `get_calendar_param()` |
| AiCompetitor | (시장별 AI 파라미터 필요 시) |
| NewsEventSystem | SECTOR_ROTATION 헤드라인 키 → `get_rotation_headline()` + `tr()` |
| SeasonManager / LeverageManager | 엔딩 임계값, 서사 키, 비주얼 경로 → `get_ending_param()` |
| SteamManager | DLC 전용 업적 → `get_dlc_achievements()` |

### 주의사항

- MarketProfile은 **시장 규칙**만 담는다. 게임 로직 튜닝 상수(SURPRISE_THRESHOLD 등)는 별도 config 파일.
- `rotation_params`의 `inflow_impact` 범위는 news-events.md의 MEDIUM 등급(0.04~0.08) 이내로 유지.
- `rivalry_weights`의 합이 반드시 1.0이어야 한다 (MarketProfile 로드 시 검증).
- `source_locale` 필드: KR = `"ko"`, US DLC = `"en"`, JP DLC = `"ja"`. 번역 추출 스크립트가 이 값으로 원본/번역 방향을 결정한다. DLC 추가 시 반드시 명시.
- 엔딩 서사 문자열은 `locale/ko_endings.po` (+ `en_endings.po`) 분리 파일로 관리. KR 엔딩 키 영어 번역 시 Cultural Note 주석 필수 ("Han River = Korean cultural idiom for financial ruin/despair").

---

## 관련 문서

- [financial-report-system.md](../../design/gdd/financial-report-system.md) §3-1, §7
- [sector-etf.md](../../design/gdd/sector-etf.md) §3-7, §6
- [ADR-022](022-event-source-pipeline.md) — EventSource → NewsEventSystem 파이프라인
- [ADR-018](018-anti-price-scout-rng-entropy.md) — RNG 분리 패턴 (동일 원칙)
