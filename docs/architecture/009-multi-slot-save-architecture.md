# ADR-009: 멀티슬롯 세이브 시스템 아키텍처

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-07 |
| **Decision Maker** | user + technical-director + gameplay-programmer |
| **Relates To** | design/gdd/save-load.md §3, src/core/save_system.gd |

## Context

Alpha 마일스톤에서 단일 슬롯 자동저장(`save_data.json`)으로 구현된 세이브 시스템을
멀티슬롯으로 확장해야 했다. 플레이어가 여러 캐릭터/진행상황을 병행 관리할 수 있게 하고,
세이브 선택 화면(StartScreen)에서 각 슬롯의 레벨·시즌·픽션날짜·평가금액을
**전체 데이터를 읽지 않고** 표시해야 했다.

핵심 제약:
1. 슬롯 목록 화면에서 빠른 메타데이터 표시 (전체 저장 데이터 로딩 없이)
2. v1 단일 슬롯(`save_data.json`) 사용자 자동 마이그레이션
3. 슬롯 삭제 후 ID 재사용 금지 (기존 파일 충돌 방지)

## Decision

**인덱스 파일 + 슬롯 파일 분리 패턴**을 채택한다.

### 파일 구조

```
user://
├── save_index.json          ← 메타데이터 캐시 (슬롯 목록 표시용)
├── save_slot_0.json         ← 슬롯 0 전체 데이터
├── save_slot_1.json         ← 슬롯 1 전체 데이터
└── ...
```

### save_index.json 포맷

```json
{
  "index_version": 1,
  "next_id": 2,
  "slots": [
    {
      "id": 0,
      "name": "슬롯 1",
      "level": 3,
      "season": 2,
      "fiction_date": "2026년 2월 3주차 수요일",
      "portfolio_value": 1850000,
      "saved_at": "2026-04-07T15:32:00"
    }
  ]
}
```

### 슬롯 ID 정책

- `next_id`는 단조 증가. 삭제된 슬롯 ID는 재사용하지 않는다.
- 슬롯 파일명: `save_slot_{id}.json`
- 슬롯 삭제 시: 파일 제거 + index의 slots 배열에서 제거. `next_id`는 유지.

### v1 마이그레이션

`SaveSystem._ready()`에서 `save_data.json` 감지 시 자동 실행:
1. `save_data.json` → `save_slot_0.json` 복사
2. `save_index.json` 생성 (id=0, next_id=1)
3. `save_data.json` 삭제

### SaveSystem 핵심 API

```gdscript
var active_slot_id: int = -1   ## -1 = 슬롯 미선택 (StartScreen 표시 중)
var _save_pending: bool = false

func get_slot_list() -> Array[Dictionary]   ## 인덱스만 읽음. O(1)
func create_slot(name: String) -> int       ## 신규 슬롯, active_slot_id 설정
func load_slot(id: int) -> bool             ## 전체 데이터 로드, active_slot_id 설정
func save_slot(id: int) -> bool             ## save_started/save_completed 시그널 emit
func delete_slot(id: int) -> void
func rename_slot(id: int, name: String) -> void  ## 인덱스만 수정
```

## Alternatives Considered

### A. 단일 파일 내 슬롯 배열

```json
{ "slots": [ { "id": 0, "data": {...전체데이터...} }, ... ] }
```

- **기각 이유**: 슬롯 목록 표시 시 전체 파일을 읽어야 함.
  슬롯 10개면 파싱 비용 10배. 슬롯 하나 손상 시 전체 파일 손상 위험.

### B. 슬롯별 디렉터리

```
user://saves/slot_0/game_data.json
user://saves/slot_0/meta.json
```

- **기각 이유**: Godot의 `user://` 경로에서 디렉터리 생성이 플랫폼별로 다르게
  동작할 수 있음. 파일 2개로 동일 효과 달성 가능.

### C. 메타데이터를 전체 슬롯 파일에서 매번 읽기

- **기각 이유**: StartScreen 진입 시마다 전체 슬롯 파일 N개를 파싱.
  슬롯이 많아질수록 로딩 시간 선형 증가. 인덱스 캐시가 명확히 우월.

## Consequences

### 긍정적

- 슬롯 목록 표시가 인덱스 1개 파일 읽기로 완결 (슬롯 수 무관 O(1))
- 슬롯 파일 손상이 다른 슬롯에 영향 없음 (파일 격리)
- rename/metadata 업데이트가 인덱스만 수정하므로 빠름

### 부정적

- 인덱스와 슬롯 파일 간 동기화 책임 발생 (save_slot() 내에서 `_update_slot_meta()` 필수)
- 슬롯 파일과 인덱스가 불일치할 경우 손상 슬롯으로 처리 (`is_slot_valid()` 체크)

### 리스크

- **인덱스-슬롯 불일치**: 저장 도중 앱 강제 종료 시 인덱스가 업데이트 안 될 수 있음.
  완화: `save_slot()` 내에서 파일 먼저 쓰고 인덱스 나중에 업데이트.
  `is_slot_valid(id)`에서 파일 존재 여부 확인으로 손상 감지.

## Validation Criteria

- **AC-01**: 슬롯 생성 → 플레이 → 자동저장 → 앱 재시작 → 슬롯 목록에 정보 표시 → 선택 → 상태 복원
- **AC-02**: v1 `save_data.json` 존재 시 앱 시작 시 자동 마이그레이션 후 slot_0으로 접근 가능
- **AC-03**: 슬롯 삭제 후 새 슬롯 생성 시 삭제된 ID 재사용 안 됨

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — 시그널 기반 통신 (save_started/save_completed)
- design/gdd/save-load.md §3 — 저장 포맷 상세
- ADR-011 — SavingOverlay가 save_started/save_completed 시그널 구독
