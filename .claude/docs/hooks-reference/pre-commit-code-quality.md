# Hook: pre-commit-code-quality

## Trigger

`git commit` 시 `src/` 또는 `tests/` 파일이 staged에 포함된 경우 실행.
구현 위치: `tools/hooks/pre-commit` — 설치: `bash tools/hooks/install.sh`

## Purpose

코드가 버전 관리에 들어가기 전 세 가지 품질 게이트를 강제한다:
- **[A]** API contracts 누락 — public 메서드가 계약 테스트에 등록됐는가
- **[B]** Godot 클래스 캐시 불일치 — 에디터 런타임 오류 예방
- **[C]** 유령 메서드 — 테스트가 존재하지 않는 메서드를 참조하는가

## Implementation

```bash
# src/, tests/ 파일 커밋 시 실행되는 섹션 (tools/hooks/pre-commit 내부)
STAGED=$(git diff --cached --name-only 2>/dev/null)

# ── [A] API Contracts 완전성 ──────────────────────────────────────────────────
CONTRACTS_FILE="tests/unit/test_api_contracts.gd"
GAMEPLAY_CORE=$(echo "$STAGED" | grep -E '^src/(gameplay|core)/.*\.gd$')
if [ -n "$GAMEPLAY_CORE" ] && [ -f "$CONTRACTS_FILE" ]; then
    MISSING=""
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        NEW_FUNCS=$(git diff --cached "$file" 2>/dev/null \
            | grep '^+func ' | grep -v '^+func _' \
            | grep -oE 'func [a-z][a-z0-9_]+' | awk '{print $2}')
        while IFS= read -r fn; do
            [ -z "$fn" ] && continue
            if ! grep -q "\"$fn\"" "$CONTRACTS_FILE" 2>/dev/null; then
                MISSING="$MISSING\n  - $fn  ($file)"
            fi
        done <<< "$NEW_FUNCS"
    done <<< "$GAMEPLAY_CORE"
    if [ -n "$MISSING" ]; then
        echo "BLOCKED [A] API Contracts 누락:" >&2
        echo -e "$MISSING" >&2
        echo "  → tests/unit/test_api_contracts.gd에 has_method() 테스트를 추가하세요." >&2
        exit 2
    fi
fi

# ── [B] Godot 클래스 캐시 일관성 ─────────────────────────────────────────────
CACHE_FILE=".godot/global_script_class_cache.cfg"
if [ -f "$CACHE_FILE" ]; then
    MISSING_CLASSES=""
    while IFS= read -r classname; do
        [ -z "$classname" ] && continue
        if ! grep -q "\"class\": &\"$classname\"" "$CACHE_FILE" 2>/dev/null; then
            MISSING_CLASSES="$MISSING_CLASSES\n  - $classname"
        fi
    done <<< "$(grep -rh 'class_name ' src/ --include='*.gd' 2>/dev/null | awk '{print $2}')"
    if [ -n "$MISSING_CLASSES" ]; then
        echo "BLOCKED [B] 클래스 캐시 불일치:" >&2
        echo -e "$MISSING_CLASSES" >&2
        echo "  → 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe --headless --path . --import' 실행 후 재커밋" >&2
        exit 2
    fi
fi

# ── [C] 유령 메서드 참조 ──────────────────────────────────────────────────────
TEST_FILES=$(echo "$STAGED" | grep -E '^tests/.*\.gd$')
if [ -n "$TEST_FILES" ]; then
    PHANTOM=""
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        TESTED=$(grep -oE 'has_method\("[a-z][a-z0-9_]+"\)' "$file" 2>/dev/null \
            | grep -oE '"[a-z][a-z0-9_]+"' | tr -d '"')
        while IFS= read -r method; do
            [ -z "$method" ] && continue
            if ! grep -rq "^func $method\b" src/ --include='*.gd' 2>/dev/null; then
                PHANTOM="$PHANTOM\n  - $method  ($file)"
            fi
        done <<< "$TESTED"
    done <<< "$TEST_FILES"
    if [ -n "$PHANTOM" ]; then
        echo "BLOCKED [C] 유령 메서드 — 테스트가 src/에 없는 메서드를 참조합니다:" >&2
        echo -e "$PHANTOM" >&2
        echo "  → 실제 메서드명을 확인하거나, 소스에 해당 메서드를 추가하세요." >&2
        exit 2
    fi
fi
```

## Agent Integration

훅 실패 시:
1. **[A] API Contracts 누락** → `tests/unit/test_api_contracts.gd`에 `has_method("누락함수명")` 테스트 추가 후 재커밋
2. **[B] 클래스 캐시 불일치** → `D:/Godot4/Godot_v4.6.2-stable_win64_console.exe --headless --path . --import` 실행 → `.godot/global_script_class_cache.cfg` stage → 재커밋
3. **[C] 유령 메서드** → `src/`에서 실제 메서드명을 grep으로 확인 후 테스트 수정
