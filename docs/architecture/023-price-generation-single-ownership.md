# ADR-023: 가격 생성 규칙 단일 소유 — PriceEngine.generate_synthetic_d1()

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-21 |
| **Deciders** | technical-director, lead-programmer |
| **Triggered By** | M1/D1 차트 가격 불일치 버그 (M1 ~59K vs D1 ~210K, 동일 종목) |

## 컨텍스트

프리히스토리 가격 생성 로직이 세 시스템에 분산되어 있었다:

| 시스템 | 생성 대상 | 알고리즘 |
|--------|----------|---------|
| PriceEngine | 현재 시즌 tick-by-tick | 3-레이어 Markov (GDD price-engine.md) |
| OhlcvHistory | 프리히스토리 D1 바 | 자체 단순 랜덤 워크 (VOL_BY_PROFILE + mean reversion) |
| M1CacheManager | 프리히스토리 M1 바 | D1 OHLC 엔벨로프 내 bias+noise 보간 |

이로 인해 발생한 문제:
1. **가격 불일치**: OhlcvHistory의 D1과 M1CacheManager의 M1이 서로 다른 알고리즘으로 생성 → 같은 종목 D1/M1 차트 가격대 불일치
2. **패턴 부재**: OhlcvHistory의 단순 랜덤 워크는 PriceEngine의 Markov 체인 패턴(추세·박스권·브레이크아웃)이 없어 프리히스토리 차트에서 패턴 분석이 불가
3. **상수 중복**: VOL_BY_PROFILE, MEAN_REVERSION_STRENGTH 등이 OhlcvHistory에 독자적으로 정의되어 PriceEngine GDD와 독립적으로 발산 가능
4. **세이브 슬롯 미분리**: M1 캐시가 `user://m1_cache/` 전역 경로에 저장 → 슬롯 간 캐시 오염

## 결정

### 1. 가격 생성 규칙 — PriceEngine 단일 소유

`PriceEngine.generate_synthetic_d1(stock_id, n_days, seed)` 정적 메서드를 추가한다.
OhlcvHistory의 `_generate_pre_history()`는 이 메서드 호출로 대체한다.
OhlcvHistory의 자체 가격 생성 상수(VOL_BY_PROFILE 등)는 삭제한다.

### 2. 축약 Markov 시뮬레이션 (일별 단위)

Tick-by-tick(1560 tick/일) 시뮬레이션은 100시즌 × 46종목 시 비현실적이다.
대신 **일 단위 축약 Markov**를 사용한다:

```
for each day:
    # 상태 전이: 하루에 최대 3회 체크
    for each segment (3 segments per day):
        roll transition matrix → update state
    
    # 일별 가격 변동 계산
    daily_return = state.bias × TICKS_PER_DAY
                 + uniform(mag_min, mag_max) × TICKS_PER_DAY × 0.3
                 + normal(0, noise_std × sqrt(TICKS_PER_DAY))
    
    # 드리프트 레이어 (PriceEngine §2와 동일)
    drift = (base_price - current_price) / current_price × DRIFT_STRENGTH
    
    # 변동성 프로필 스케일링 (PriceEngine §1-4와 동일 파라미터)
    daily_return *= vol_scale[volatility_profile]
    
    # D1 OHLC 생성
    close = current_price × (1 + daily_return + drift)
    high  = current_price × (1 + max(daily_return, 0) + |noise| × 0.5)
    low   = current_price × (1 + min(daily_return, 0) - |noise| × 0.5)
    open  = current_price  # 전일 종가
```

### 3. 시스템별 역할 재정의

| 시스템 | 변경 전 역할 | 변경 후 역할 |
|--------|------------|------------|
| **PriceEngine** | 현재 시즌 가격 생성 | **가격 생성 규칙 단일 소유** (현재 시즌 + 프리히스토리 D1 생성 API 제공) |
| **OhlcvHistory** | D1 바 생성 + 저장/조회 | **저장/조회/집계만** (생성은 PriceEngine에 위임) |
| **M1CacheManager** | M1 바 생성 + 캐시 관리 | 역할 유지 (D1→M1 확장 보간은 합리적 타협) |

### 4. 세이브 슬롯별 M1 캐시 분리

```
# 변경 전
user://m1_cache/{stock_id}_{season_idx:04d}.bin

# 변경 후
user://m1_cache/slot_{slot_id}/{stock_id}_{season_idx:04d}.bin
```

- `M1CacheManager._cache_dir()` 메서드: `"user://m1_cache/slot_%d/" % SaveSystem.get_active_slot_id()`
- `SaveSystem.delete_slot()` 시 해당 슬롯 캐시 디렉토리 삭제
- 슬롯 로드 시 `M1CacheManager`에 슬롯 ID 변경 통보 → 캐시 초기화

## 대안 검토

| 옵션 | 설명 | 기각 이유 |
|------|------|---------|
| **A (채택)** | PriceEngine에 generate_synthetic_d1() 추가 | — |
| B | OhlcvHistory에 PriceEngine 상수 참조만 추가 | 알고리즘 로직이 여전히 두 곳에 존재. 동기화 책임 분산. |
| C | PriceEngine.process_tick() fast-forward | 1.4억 틱 시뮬레이션 → 게임 시작 수 분 소요. 비현실적. |

## 영향 범위

- `src/gameplay/price_engine.gd` — `generate_synthetic_d1()` 추가
- `src/gameplay/ohlcv_history.gd` — `_generate_pre_history()` 교체, 자체 상수 삭제
- `src/gameplay/m1_cache_manager.gd` — 캐시 경로 슬롯별 분리
- `src/core/save_system.gd` — 슬롯 삭제 시 M1 캐시 디렉토리 삭제
- `design/gdd/price-engine.md` — §generate_synthetic_d1 섹션 추가
- `docs/architecture/023-price-generation-single-ownership.md` — 이 문서

## 결과

- 프리히스토리 D1/M1 차트가 현재 시즌 차트와 동일한 Markov 패턴 성격을 가짐
- 가격 생성 파라미터 변경 시 한 곳(PriceEngine)만 수정하면 전체 반영
- 세이브 슬롯 간 캐시 오염 제거
