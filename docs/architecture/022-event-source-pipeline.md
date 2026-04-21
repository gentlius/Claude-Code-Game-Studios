# ADR-022: EventSource → NewsEventSystem → PriceEngine 단방향 파이프라인

> **Status**: Accepted
> **Date**: 2026-04-20
> **Deciders**: Technical Director, Game Designer, Lead Programmer, Narrative Director
> **Context**: EtfManager 섹터 로테이션 설계 + FinancialReportSystem 선행 사례 일반화

---

## 배경

FinancialReportSystem은 분기 보고 이벤트를 `NewsEventSystem.inject_event()`로 주입해
PriceEngine에 간접적으로 영향을 준다. EtfManager의 섹터 로테이션 이벤트를 설계하면서
이 패턴이 **어떤 시스템이든 시장에 영향을 줄 수 있는 일반화된 메커니즘**임을 확인했다.

PriceEngine을 직접 조작하는 것과의 차이:

| 직접 조작 | EventSource 패턴 |
|---------|----------------|
| 가격에 즉시 반영, 플레이어에게 보이지 않음 | 뉴스 피드에 헤드라인 표시 가능 |
| 이벤트 이력 없음 | 이벤트 로그 잔존 (S3 루머 연동 가능) |
| 시스템 간 결합도 높음 | NewsEventSystem을 경유하여 결합 해소 |
| 새 시스템 추가 시 PriceEngine 수정 필요 | PriceEngine 수정 없이 확장 가능 |

---

## 결정

**모든 시스템은 PriceEngine을 직접 조작하지 않는다.
시장에 영향을 주려면 반드시 `NewsEventSystem.inject_event()`를 경유한다.**

```
[EventSource 시스템]
        │
        │ inject_event(event_data)
        ▼
[NewsEventSystem]
        │
        ├─► PriceEngine   (가격 영향 적용)
        ├─► NewsFeedUI    (플레이어에게 헤드라인 표시, 선택적)
        └─► RumorChannel  (S3 해금 시 루머로 변형, 선택적)
```

---

## EventSource 규약

GDScript에는 인터페이스가 없으므로 규약을 문서로 명시한다.

### EventSource가 지켜야 할 규칙

1. **`inject_event()` 단일 진입점** — `NewsEventSystem.inject_event(event_data)` 외의 경로로 가격 조작 금지
2. **이벤트 데이터 스키마 준수** — `news-events.md §3` EventData 구조체를 따른다
3. **트리거 조건 명시** — 언제 이벤트를 발화할지 GDD에 명확히 정의 (임계값, 쿨다운 등)
4. **과잉 발화 방지** — 쿨다운 또는 임계값으로 스팸 방지. 매 틱 무조건 발화 금지

### EventSource 등록부 (현재)

| 시스템 | 이벤트 유형 | 트리거 | 선행 사례 |
|--------|-----------|--------|--------|
| FinancialReportSystem | FINANCIAL_REPORT | 분기 스케줄 | ✅ 1호 |
| EtfManager | SECTOR_ROTATION | sector_flow_delta 임계값 + 쿨다운 | ✅ 2호 |
| SeasonManager | *(향후)* SEASON_TRANSITION | 시즌 경계 | 미구현 |
| LifestyleManager | *(향후)* ECONOMIC_SIGNAL | 소비 지표 임계값 | 미구현 |

> 새 시스템이 EventSource로 추가될 때마다 이 표에 등록한다.

---

## SECTOR_ROTATION 이벤트 스키마

`NewsEventSystem.inject_event()`에 전달되는 데이터 구조:

```gdscript
{
    "event_source": "EtfManager",       # 발화 시스템 식별
    "scope": "SECTOR_ROTATION",          # news-events.md에 추가된 신규 scope
    "sector_in": "반도체",              # 유입 섹터 (inflow 이벤트)
    "sector_out": "금융",               # 소외 섹터 (outflow 이벤트, 별도 inject)
    "impact": 0.055,                     # inflow_impact 범위 내 랜덤값
    "direction": 1,                      # +1 (inflow) / -1 (outflow)
    "headline_key": "ROTATION_KR_INFLOW_1",  # tr() 키
    "visible_to_player": true,           # NewsFeedUI 표시 여부
    "rumor_eligible": true               # S3 루머 채널 연동 가능 여부
}
```

---

## NewsEventSystem 처리 규칙 (SECTOR_ROTATION)

`scope == "SECTOR_ROTATION"` 수신 시:

```gdscript
func _process_sector_rotation(event: Dictionary) -> void:
    # 1. 해당 섹터 구성 종목 전체에 impact 분배 (종목별 sector_sensitivity 가중)
    var stocks = StockDatabase.get_sector_stocks(event["sector_in"])
    for stock_id in stocks:
        var sensitivity = StockDatabase.get_sector_sensitivity(stock_id)
        var stock_impact = event["impact"] * sensitivity
        PriceEngine.apply_event_impact(stock_id, stock_impact, event["direction"])

    # 2. NewsFeedUI 헤드라인 (visible_to_player == true)
    if event["visible_to_player"]:
        var headline = tr(event["headline_key"]).format({"sector": event["sector_in"]})
        NewsFeedUI.push_headline(headline, impact_tier(event["impact"]))

    # 3. S3 루머 연동 (rumor_eligible == true, S3 해금 시)
    if event["rumor_eligible"] and SkillTree.is_unlocked("S3"):
        RumorChannel.maybe_generate_rumor(event)
```

---

## 기각한 대안

### 대안 A: PriceEngine.apply_sector_rotation() 직접 추가
PriceEngine에 섹터 로테이션 로직을 직접 넣는 방식.
**기각**: PriceEngine이 "섹터 아키타입"과 "라이벌 가중치"를 알아야 하는 책임 과부하.
뉴스 피드·루머 연동이 불가능해진다.

### 대안 B: EtfManager → PriceEngine 직접 호출
EtfManager가 PriceEngine 가격을 직접 조작.
**기각**: 플레이어에게 invisible. 뉴스 피드 표시 불가. S3 루머 연동 불가.
새 EventSource 추가마다 PriceEngine 인터페이스 변경 필요.

### 대안 C: 전용 SectorRotationManager 별도 생성
섹터 로테이션 전용 autoload 생성.
**기각**: EtfManager가 이미 sector_flow 상태를 소유하므로 책임 분리가 어색하다.
단일 책임 원칙 관점에서 EtfManager가 flow 계산 + 이벤트 발화를 모두 소유하는 게 맞다.

---

## 결과 및 영향

### 현재 스프린트 영향 (Sprint 10)

- `NewsEventSystem`에 `SECTOR_ROTATION` scope 처리 로직 추가 (`news-events.md §3-8` 참조)
- `EtfManager`가 `inject_event()` 호출 — PriceEngine 직접 조작 코드 작성 금지
- 기존 `FinancialReportSystem`의 `inject_event()` 호출 패턴이 이 ADR의 1호 사례로 소급 문서화됨

### 미래 확장

새 시스템이 시장에 영향을 주고 싶을 때:
1. `inject_event(event_data)` 호출 코드 작성
2. 이 ADR의 EventSource 등록부에 추가
3. PriceEngine, NewsFeedUI, RumorChannel — 변경 없음

---

## 관련 문서

- [news-events.md](../../design/gdd/news-events.md) §3-8 — SECTOR_ROTATION 이벤트 타입
- [sector-etf.md](../../design/gdd/sector-etf.md) §3-7 — EtfManager EventSource 구현
- [financial-report-system.md](../../design/gdd/financial-report-system.md) — EventSource 1호 사례
- [ADR-021](021-market-profile-data-driven.md) — MarketProfile (rotation_headline_keys 포함)
