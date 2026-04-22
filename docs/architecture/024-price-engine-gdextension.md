# ADR-024: PriceEngine GDExtension 마이그레이션 — M1-first 배치 생성 + C++ 연산 핵심

**Status**: Accepted  
**Date**: 2026-04-21  
**Author**: technical-director + lead-programmer  
**Supersedes**: 일부 ADR-023 (M1 생성 방식 변경)

---

## 컨텍스트

ADR-023에서 가격 생성 규칙의 단일 소유권을 PriceEngine으로 확정했다.
그러나 `OhlcvHistory._generate_pre_history()`가 `PriceEngine.generate_synthetic_d1()`을
호출하는 D1-first 방식은 두 가지 문제를 남겼다:

1. **D1→M1 확장 품질**: `_expand_d1_to_m1()`의 단순 랜덤 워크가 D1 엔벨로프 안에서
   너무 매끄러운 직선을 만들어 1분봉이 비현실적으로 표시됨.
2. **생성 성능**: 전 종목(46개) 프리히스토리를 인트로 시간 안에 생성하려면
   GDScript 단일 스레드로는 36~72초가 필요 — 허용 불가.

---

## 결정

### 1. M1-first 생성 (D1→M1 확장 폐기)

모든 타임프레임 데이터의 단일 소스를 M1 Markov 직접 생성으로 변경한다.

```
Before: Markov → D1 → _expand_d1_to_m1() → M1
After:  Markov → M1 (스트리밍) → D1 누적기 → M1 캐시 + D1 캐시
```

`_expand_d1_to_m1()` 알고리즘 삭제. `M1_VOLATILITY` 상수 폐기.

### 2. 2-tier 캐시 (M1 + D1)

| 캐시 | 크기 | 서빙 타임프레임 | 집계 |
|------|------|----------------|------|
| M1 | 7,800 bars (1시즌) | M1 직접 / M5·M15 런타임 집계 | 없음 / on-read |
| D1 | 5,200 bars (260시즌) | D1 직접 / W1·MN 런타임 집계 | 없음 / on-read |

저장: 260KB/종목. 46종목 × 3슬롯 = ~36MB. 512MB 예산 내.

### 3. PriceEngine 배치 API

```gdscript
# Phase 1 (GDScript), Phase 3 (C++ MarkovGenerator로 위임)
func generate_all_stocks_m1(
    stocks: Array[StockData],
    history_seed: int
) -> void:
    # 백그라운드 스레드에서 호출
    # 종목당: history_seasons × 20 × 390 M1 바 Markov 생성
    # 마지막 7,800 M1 + 마지막 5,200 D1 → M1CacheManager 캐시
    # 진행 시 batch_progress(done, total) emit
```

### 4. 3단계 마이그레이션

**Phase 1 — GDScript M1-first 검증**
- `M1CacheManager` 완전 재작성: 배치 생성 + 2-tier 캐시
- `OhlcvHistory` 의존성 역전: D1 누적을 M1CacheManager로 이전
- `chart_renderer.gd` 업데이트: 새 캐시 API 소비
- 목표: 알고리즘 정확성 검증 (M1 집계 D1 vs 직접 D1 비교)

**Phase 2 — 상수 JSON 추출**
- `STATE_PARAMS`, `TRANSITION_MATRIX`, `VOL_PATTERN_SCALE`, `BASE_VOLUME_RANGE`
  → `assets/data/price_engine_config.json` (이미 일부 존재)
- GDScript와 C++ 양쪽이 동일 JSON에서 로드 → 상수 이중관리 없음

**Phase 3 — C++ GDExtension**
- `gdextension/src/markov_generator.cpp` — stateless 연산 핵심
- `PriceEngine.gd`의 배치 생성 + 실시간 틱 루프가 C++로 위임

### 5. 아키텍처 경계

```
C++ MarkovGenerator (RefCounted, stateless):
    generate_all_stocks_m1(cfg_array, seeds) -> Dictionary  # M1+D1 PackedArrays
    step_tick(state, params, rng_state)      -> Dictionary  # new_price, new_state

GDScript PriceEngine (autoload, 유지):
    var _markov: MarkovGenerator             # C++ 인스턴스
    시그널 / 이벤트 레이어 / VI·CB / 세이브·로드
```

C++로 이동하지 않는 것: 이벤트 레이어, 주문북 업데이트, VI/서킷브레이커.
이들은 GDScript 오브젝트(MarketEvent, StockData)와 강하게 결합되어
C++ 경계를 넘기면 오히려 복잡도가 증가한다.

### 6. PRNG

Godot `RandomNumberGenerator` (PCG32)를 가격 생성에서 제거.
C++ `MarkovGenerator`가 동일한 PCG32 알고리즘을 자체 구현.
시드 = `history_seed XOR hash(stock_id)`.

**세이브 호환성**: Phase 1→3 마이그레이션은 캐시 무효화를 유발한다.
`cache_version` 필드를 캐시 헤더에 추가하여 버전 불일치 시 자동 재생성.

### 7. 플랫폼

| 플랫폼 | 지원 | 비고 |
|--------|------|------|
| Windows 64bit | ✅ | 우선 타겟 |
| Android ARM64 | ✅ | NDK 추후 추가 |
| iOS ARM64 | ✅ | Xcode static lib 추후 추가 |
| Web (Emscripten) | ❌ | 포기 — GDExtension + Thread 불안정 |

---

## 기각된 대안

**대안 A: M1_VOLATILITY 튜닝만 적용**
빠르지만 D1→M1 확장 방식의 근본 문제(직선 형태)를 해결하지 못함.

**대안 B: 6-타임프레임 전부 캐시**
저장 공간 절약 미미, 런타임 집계 로직 제거 이점 없음.
M1 → D1 범위 불일치 문제가 더 복잡해짐.

**대안 C: 전체 PriceEngine C++ 이전**
이벤트 레이어, 시그널, GDScript 오브젝트 경계 문제로 복잡도 폭증.
핫패스만 C++로 이동하는 것이 정확한 분리.

---

## 결과

- 모든 타임프레임이 동일한 M1 Markov에서 파생 → 크로스 타임프레임 일관성
- 1분봉이 실제 Markov 패턴을 반영 → 차트 품질 개선
- Phase 3 완료 시 배치 생성 ~1-3초 (현행 36-72초 대비)
- GDScript PriceEngine API 표면 불변 → 호출부 수정 없음

---

## 구현 파일

| 파일 | 변경 |
|------|------|
| `src/gameplay/m1_cache_manager.gd` | 완전 재작성 |
| `src/gameplay/ohlcv_history.gd` | D1 누적 제거, M1CacheManager 위임 |
| `src/gameplay/price_engine.gd` | `generate_all_stocks_m1()` 추가, `_expand_d1_to_m1()` 삭제 |
| `src/ui/chart_renderer.gd` | 새 캐시 API 소비 |
| `assets/data/price_engine_config.json` | Phase 2: 상수 추가 |
| `gdextension/src/markov_generator.cpp` | Phase 3: 신규 |
| `gdextension/src/markov_generator.h` | Phase 3: 신규 |
| `gdextension/src/register_types.cpp` | Phase 3: 신규 |
| `gdextension/markov_generator.gdextension` | Phase 3: 신규 |
| `tests/unit/test_api_contracts.gd` | 새 API 등록 |
