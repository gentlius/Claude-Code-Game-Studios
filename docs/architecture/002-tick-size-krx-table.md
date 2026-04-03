# ADR-002: Tick Size (호가 단위) — KRX 기반 테이블

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-01 |
| **Decision Maker** | user + game-designer |
| **Relates To** | price-engine.md (Rule 5-3), order-engine.md, chart-renderer.md |

## Context

주식 가격이 연속 실수가 아닌 이산 단위(호가)로 움직여야 현실감이 있다.
한국 거래소(KRX)는 가격대별 호가 단위를 규정하며, 이 게임은 한국 주식시장을
배경으로 하므로 KRX 호가 테이블을 기반으로 한다.

호가 단위는 세 시스템이 공유한다:
1. **가격 엔진**: 생성된 가격을 호가 단위로 반올림
2. **주문 엔진**: 지정가 주문의 가격을 호가 단위로 검증
3. **차트 렌더러**: Y축 그리드를 호가 단위에 정렬

## Decision

KRX 2023 호가 단위 테이블을 `PriceEngine.get_tick_size(price)` static 함수로
구현하여 **단일 소스(single source of truth)**로 사용한다.

| 가격대 | 호가 단위 |
|--------|----------|
| ~999원 | 1원 |
| 1,000~4,999원 | 5원 |
| 5,000~9,999원 | 10원 |
| 10,000~49,999원 | 50원 |
| 50,000~99,999원 | 100원 |
| 100,000~499,999원 | 500원 |
| 500,000원~ | 1,000원 |

`round_to_tick(raw_price)` 헬퍼가 float → int 변환과 호가 반올림을 동시에 처리한다.

### 공유 방식

`PriceEngine.get_tick_size()`와 `PriceEngine.round_to_tick()`을 static 함수로
정의하여 OrderEngine, ChartRenderer 등이 직접 호출한다. PriceEngine 인스턴스에
의존하지 않으므로 autoload 초기화 순서와 무관하다.

## Alternatives Considered

### A. 단일 고정 호가 (예: 모든 가격에 10원 단위)

- 장점: 구현 최소
- 단점: 저가주(1,000원 미만)에서 10원 단위는 1% 이상 변동폭 → 비현실적.
  고가주에서는 반대로 단위가 너무 촘촘해 무의미한 가격 변동 증가

### B. 별도 config 파일 (JSON/Resource)

- 장점: 데이터 분리 원칙 준수
- 단점: 호가 테이블은 KRX 규정이므로 게임 밸런스 튜닝 대상이 아님.
  static 함수로 충분하며, 외부 파일은 과도한 추상화

### C. 각 시스템이 자체 호가 로직 보유

- 장점: 시스템 간 결합도 제거
- 단점: 호가 로직 분산 → 불일치 위험. 가격 엔진은 50원 단위로 반올림하는데
  주문 엔진은 100원 단위로 검증하면 체결 불가 버그 발생

## Consequences

### 긍정적

- 호가 단위가 가격대별로 달라 저가~고가주 모두 현실적 가격 움직임
- 세 시스템이 동일 함수를 참조하므로 불일치 불가
- static 함수이므로 autoload 의존성 없음, 유닛 테스트 용이

### 부정적

- OrderEngine, ChartRenderer가 PriceEngine 클래스에 의존 (static이므로 약한 결합)
- KRX 규정이 변경되면 한 곳만 수정하면 되지만, 게임 밸런스와 무관한 외부 규정 변경은 고려 대상 아님
