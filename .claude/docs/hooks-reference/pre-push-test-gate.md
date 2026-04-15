# Hook: pre-push-test-gate

## Trigger

`git push` 시 `main` 브랜치에 푸시하는 경우 실행.
구현 위치: `tools/hooks/pre-push` — 설치: `bash tools/hooks/install.sh`

## Purpose

공유 브랜치에 broken 상태가 진입하기 전 빌드·테스트 게이트를 강제한다.
코드가 다른 개발자에게 영향을 미치기 전 마지막 자동화 품질 관문.

## 프레임워크 원래 의도

팀 개발 환경에서는 아래 단계별 게이트를 운용한다:

```
develop 브랜치: 빌드 + 유닛 테스트 + 통합 테스트
main 브랜치:    빌드 + 유닛 + 통합 + 스모크 + 퍼포먼스 회귀
```

## 이 프로젝트의 구현

**현재 적용 범위**: `main` 브랜치 푸시 시 Step 1~2 실행.

```bash
# Step 1: 릴리즈 빌드 검증
# 클래스 캐시 깨짐, 스크립트 컴파일 오류 등 런타임 전 오류를 모두 잡는다.
"$GODOT_BIN" --headless \
    --export-release "Windows Desktop" "$BUILD_OUT" \
    --path "d:/Github/ta"

# Step 2: GUT 유닛 테스트 전체
# 존재하지 않는 메서드 호출, 로직 오류, 회귀 등을 잡는다.
"$GODOT_BIN" --headless \
    -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/unit/ \
    -gexit \
    --path "$(pwd)"
```

| 단계 | 상태 | 미적용 이유 |
|------|------|------------|
| 릴리즈 빌드 | **구현됨** | — |
| 유닛 테스트 (GUT) | **구현됨** | — |
| `develop` 브랜치 보호 | 미적용 | 솔로 개발, trunk-based, develop 브랜치 미운용 |
| 통합 테스트 | 미적용 | `tests/integration/` 미구현 — 구현 시 Step 3으로 추가 |
| 스모크 테스트 | 미적용 | 동일 |
| 퍼포먼스 회귀 | 미적용 | 베이스라인 미정의 — Polish 단계에서 추가 |

## 확장 시점

- `tests/integration/` 구현 시 → Step 3 추가
- `develop` 브랜치 도입 시 → `PROTECTED_BRANCHES="develop main"` 으로 복원
- Polish 단계 진입 시 → 퍼포먼스 회귀 검사 추가

## Agent Integration

훅 실패 시:
1. **빌드 실패** → 스크립트 컴파일 오류 또는 클래스 캐시 불일치 확인. `--headless --path . --import` 실행 후 재시도
2. **GUT 테스트 실패** → 실패 로그 확인 → GDD → 코드 → 테스트 순서로 판단 (`coding-standards.md` 테스트 수정 방향 참조)
3. **Godot 실행 파일 없음** → `GODOT_BIN` 경로 확인 또는 `tools/hooks/pre-push` 수정
