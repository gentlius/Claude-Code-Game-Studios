# ADR-018: Anti-Price-Scout — 세션 RNG 엔트로피 격리

| 항목 | 내용 |
|------|------|
| **Status** | Proposed |
| **Date** | 2026-04-14 |
| **Deciders** | technical-director, lead-programmer, qa-lead |
| **관련 GDD** | design/gdd/save-load.md, design/gdd/price-engine.md |

---

## 문제 정의

PriceEngine의 `season_bias`와 일간 Markov state가 세이브 파일에 저장된다.
플레이어가 다음 패턴으로 정보 우위를 얻는 것이 이론상 가능하다:

1. Day N 장 시작 직전에 저장
2. Day N을 플레이 → 종목별 가격 움직임(방향, 폭) 관찰
3. 저장 시점으로 로드
4. 관찰한 정보로 포지션 구성 후 Day N 재플레이

이를 **가격 정찰(price scouting)** 익스플로잇이라 한다.
유저 지시(2026-04-14): "반드시 막아."

---

## 분석: 익스플로잇이 가능한 이유

Godot 4의 전역 `randf()`는 엔진 초기화 시 자동 시드(`randomize()`)된다.
세이브/로드 후 RNG 상태는 **저장되지 않으므로** 인트라데이 가격 노이즈는 세션마다 다르다.

그러나 저장되는 정보가 있다:

| 저장 항목 | 익스플로잇 기여도 |
|-----------|----------------|
| `season_bias` (BULL/NEUTRAL/BEAR) | **높음** — 반복 로드 시 해당 종목이 통계적으로 상승/하락하는 경향 파악 가능 |
| `markov_state` (SIDEWAYS/UPTREND 등) | **중간** — 당일 장 시작 방향 추정에 활용 가능 |
| 전일 종가 (`prev_close`) | 낮음 — 합법적 공개 정보 |

플레이어가 동일 저장 파일을 5-10회 반복 로드하면 `season_bias`를 높은 확률로 추론할 수 있다.
이는 정확한 가격 예측은 아니지만 유의미한 방향성 정보를 제공한다.

---

## 결정

**PriceEngine에 전용 `RandomNumberGenerator` 인스턴스를 도입하고,
세션 시작 시(게임 실행 또는 세이브 로드 모두 포함) 현재 시간 기반으로 재시드한다.**

구체적으로:

```gdscript
# price_engine.gd
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
    _reseed_session()

func load_save_data(data: Dictionary) -> void:
    # ... 기존 복원 로직 ...
    _reseed_session()  # 로드 시에도 재시드

func _reseed_session() -> void:
    _rng.seed = Time.get_ticks_usec()

# 기존 randf() 호출을 _rng.randf()로 교체 (PriceEngine 내부 전용)
```

`_rng`의 상태는 `get_save_data()` 에 포함하지 않는다.

---

## 결과

### 보장되는 것
- **세션마다 다른 인트라데이 가격**: 동일 저장 파일을 두 번 로드해도, 특정 거래일의
  틱별 가격 경로가 달라진다.
- **시즌 전체 트렌드 일관성 유지**: `season_bias`와 일간 Markov state는 여전히 저장/복원되므로
  한 세션 내에서 시즌의 전반적 흐름은 일관성 있게 유지된다.

### 남아있는 잔여 리스크 (수용됨)
- 플레이어가 20회 이상 반복 로드하면 `season_bias`를 통계적으로 추론 가능하다.
- 이 시간 투자(1x 속도 기준 약 100분+)는 정상 플레이 20일치보다 크므로 실질적 위협이 아니다.
- 수용 근거: "완벽한 차단"보다 "경제적으로 무의미하게 만들기"가 UX 훼손 없이 달성 가능한 목표.

### 변경 파일
| 파일 | 변경 내용 |
|------|-----------|
| `src/gameplay/price_engine.gd` | `_rng: RandomNumberGenerator` 추가, `_reseed_session()` 추가, `randf()` → `_rng.randf()` 교체, `load_save_data()` 에 `_reseed_session()` 호출 추가 |
| `design/gdd/price-engine.md` | Edge Cases에 EC-xx(세션 재시드) 추가 |
| `tests/unit/test_price_engine.gd` | 테스트 환경에서는 `_rng.seed = TEST_SEED`로 고정 (결정론적 테스트 보장) |

---

## 대안 검토

| 대안 | 장점 | 거부 이유 |
|------|------|-----------|
| 시즌 경계에서만 저장 허용 | 완전 차단 | UX 훼손 심각 — 30분 진행 분실 위험 |
| 로드 횟수를 세이브 파일에 기록하고 패널티 부과 | 익스플로잇 억제 | 징벌적 UX, 일반 플레이어에게도 불쾌감 |
| `season_bias` 저장 제거 | 강력한 차단 | 로드 후 시즌 트렌드가 급변하여 게임이 불공평하게 느껴짐 |
| 현재 방식 유지 (전역 `randf()`) | 변경 없음 | 세션 RNG가 게임 엔진 내 다른 시스템과 혼재 → 디버그 어려움. ADR 제정 계기로 격리 강제 |

---

## 테스트 요건

- **결정론성 테스트**: `_rng.seed = FIXED`로 설정 시 동일 틱 시퀀스 재현 가능 (테스트 전용)
- **비결정론성 확인**: 두 세션 간 가격 시퀀스가 다름을 확인 (통계적 검증)
- **`load_save_data()` 후 재시드 확인**: 로드 직후 `_rng.seed != 0` AND 이전 세션 seed와 다름
