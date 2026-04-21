#!/bin/bash
# Claude Code PreToolUse hook: Validates git commit commands
# Receives JSON on stdin with tool_input.command
# Exit 0 = allow, Exit 2 = block (stderr shown to Claude)
#
# Input schema (PreToolUse for Bash):
# { "tool_name": "Bash", "tool_input": { "command": "git commit -m ..." } }

INPUT=$(cat)

# Parse command -- use jq if available, fall back to grep
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
else
    COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Only process git commit commands
if ! echo "$COMMAND" | grep -qE '^git[[:space:]]+commit'; then
    exit 0
fi

# Get staged files
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED" ]; then
    exit 0
fi

WARNINGS=""

# Check design documents for required sections + incomplete Implementation Checklist
DESIGN_FILES=$(echo "$STAGED" | grep -E '^design/gdd/' | grep -v 'systems-index\.md')
if [ -n "$DESIGN_FILES" ]; then
    while IFS= read -r file; do
        if [[ "$file" == *.md ]] && [ -f "$file" ]; then
            # Required sections check
            for section in "Overview" "Player Fantasy" "Detailed" "Formulas" "Edge Cases" "Dependencies" "Tuning Knobs" "Acceptance Criteria" "Implementation Checklist"; do
                if ! grep -qi "$section" "$file"; then
                    WARNINGS="$WARNINGS\nDESIGN: $file missing required section: $section"
                fi
            done

            # Implementation Checklist 미완 항목 블록 -- Approved GDD에만 적용
            # 구현 완료 커밋에 GDD를 포함했으나 체크리스트를 갱신하지 않은 경우를 잡는다
            STATUS=$(grep -i '^\*\*Status\*\*:\|^> \*\*Status\*\*:' "$file" 2>/dev/null | head -1 | grep -oi 'Approved' || true)
            if [ "$STATUS" = "Approved" ] && grep -q "Implementation Checklist" "$file" 2>/dev/null; then
                UNCHECKED=$(awk '/Implementation Checklist/,/^---$/' "$file" | grep "^- \[ \]" | wc -l)
                if [ "$UNCHECKED" -gt 0 ]; then
                    echo "BLOCKED: $file — Implementation Checklist에 미완 항목 ${UNCHECKED}개 남음." >&2
                    echo "  DoD 체크 전 GDD Implementation Checklist를 전부 [x]로 갱신하라." >&2
                    exit 2
                fi
            fi
        fi
    done <<< "$DESIGN_FILES"
fi

# ── Check D: src/ 커밋 시 Approved GDD 체크리스트 동기화 강제 ─────────────────
# src/ 파일이 staged될 때 모든 Approved GDD를 스캔해 [ ] 항목이 있으면 차단.
# GDD Status가 Approved인데 미완 항목이 있다는 것은 구현 완료 후 체크를 빠뜨렸다는 뜻.
# 해결: 해당 항목 [x]로 체크하거나, 아직 미구현이면 GDD Status를 In Review로 내릴 것.
SRC_STAGED=$(echo "$STAGED" | grep -E '^src/')
if [ -n "$SRC_STAGED" ]; then
    while IFS= read -r gdd; do
        [ -f "$gdd" ] || continue
        STATUS=$(grep -i '^\*\*Status\*\*:\|^> \*\*Status\*\*:' "$gdd" 2>/dev/null | head -1 | grep -oi 'Approved' || true)
        if [ "$STATUS" = "Approved" ] && grep -q "Implementation Checklist" "$gdd" 2>/dev/null; then
            UNCHECKED=$(awk '/Implementation Checklist/,/^---$/' "$gdd" | grep "^- \[ \]" | wc -l)
            if [ "$UNCHECKED" -gt 0 ]; then
                echo "BLOCKED [D] $gdd — Approved GDD에 미완 항목 ${UNCHECKED}개." >&2
                echo "  구현 완료 항목은 [x]로 체크, 미구현 항목은 GDD Status를 In Review로 내릴 것." >&2
                exit 2
            fi
        fi
    done <<< "$(find design/gdd -name '*.md' ! -name 'systems-index.md' 2>/dev/null)"
fi

# Validate JSON data files -- block invalid JSON
DATA_FILES=$(echo "$STAGED" | grep -E '^assets/data/.*\.json$')
if [ -n "$DATA_FILES" ]; then
    # Find a working Python command
    PYTHON_CMD=""
    for cmd in python python3 py; do
        if command -v "$cmd" >/dev/null 2>&1; then
            PYTHON_CMD="$cmd"
            break
        fi
    done

    while IFS= read -r file; do
        if [ -f "$file" ]; then
            if [ -n "$PYTHON_CMD" ]; then
                if ! "$PYTHON_CMD" -m json.tool "$file" > /dev/null 2>&1; then
                    echo "BLOCKED: $file is not valid JSON" >&2
                    exit 2
                fi
            else
                echo "WARNING: Cannot validate JSON (python not found): $file" >&2
            fi
        fi
    done <<< "$DATA_FILES"
fi

# Check for hardcoded gameplay values in gameplay code
# Uses grep -E (POSIX extended) instead of grep -P (Perl) for cross-platform compatibility
CODE_FILES=$(echo "$STAGED" | grep -E '^src/gameplay/')
if [ -n "$CODE_FILES" ]; then
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            if grep -nE '(damage|health|speed|rate|chance|cost|duration)[[:space:]]*[:=][[:space:]]*[0-9]+' "$file" 2>/dev/null; then
                WARNINGS="$WARNINGS\nCODE: $file may contain hardcoded gameplay values. Use data files."
            fi
        fi
    done <<< "$CODE_FILES"
fi

# Check for TODO/FIXME without assignee -- uses grep -E instead of grep -P
SRC_FILES=$(echo "$STAGED" | grep -E '^src/')
if [ -n "$SRC_FILES" ]; then
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            if grep -nE '(TODO|FIXME|HACK)[^(]' "$file" 2>/dev/null; then
                WARNINGS="$WARNINGS\nSTYLE: $file has TODO/FIXME without owner tag. Use TODO(name) format."
            fi
        fi
    done <<< "$SRC_FILES"
fi

# Print warnings (non-blocking) and allow commit
if [ -n "$WARNINGS" ]; then
    echo -e "=== Commit Validation Warnings ===$WARNINGS\n================================" >&2
fi

# ── Check A: API Contracts 완전성 ─────────────────────────────────────────────
# src/gameplay/ 또는 src/core/에 새로 추가된 public func이 test_api_contracts.gd에 없으면 차단.
# "public" = 언더스코어로 시작하지 않는 func
CONTRACTS_FILE="tests/unit/test_api_contracts.gd"
GAMEPLAY_CORE_FILES=$(echo "$STAGED" | grep -E '^src/(gameplay|core)/.*\.gd$')
if [ -n "$GAMEPLAY_CORE_FILES" ] && [ -f "$CONTRACTS_FILE" ]; then
    MISSING_CONTRACTS=""
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        # 이 커밋에서 새로 추가된 public func 라인만 추출
        NEW_FUNCS=$(git diff --cached "$file" 2>/dev/null \
            | grep '^+func ' \
            | grep -v '^+func _' \
            | grep -oE 'func [a-z][a-z0-9_]+' \
            | awk '{print $2}')
        while IFS= read -r fn; do
            [ -z "$fn" ] && continue
            if ! grep -q "\"$fn\"" "$CONTRACTS_FILE" 2>/dev/null; then
                MISSING_CONTRACTS="$MISSING_CONTRACTS\n  - $fn  ($file)"
            fi
        done <<< "$NEW_FUNCS"
    done <<< "$GAMEPLAY_CORE_FILES"

    if [ -n "$MISSING_CONTRACTS" ]; then
        echo "BLOCKED [A] API Contracts 누락 — 다음 public 메서드가 test_api_contracts.gd에 없습니다:" >&2
        echo -e "$MISSING_CONTRACTS" >&2
        echo "  → tests/unit/test_api_contracts.gd에 has_method() 테스트를 추가한 뒤 다시 커밋하세요." >&2
        exit 2
    fi
fi

# ── Check B: Godot 클래스 캐시 일관성 ────────────────────────────────────────
# src/ 의 class_name 선언이 .godot/global_script_class_cache.cfg에 없으면 차단.
# 없으면 에디터에서 해당 노드를 찾지 못해 빈 화면 등의 런타임 오류 발생.
CACHE_FILE=".godot/global_script_class_cache.cfg"
if [ -f "$CACHE_FILE" ]; then
    MISSING_CLASSES=""
    while IFS= read -r classname; do
        [ -z "$classname" ] && continue
        if ! grep -q "\"class\": &\"$classname\"" "$CACHE_FILE" 2>/dev/null; then
            MISSING_CLASSES="$MISSING_CLASSES\n  - $classname"
        fi
    done <<< "$(grep -rh '^class_name ' src/ --include='*.gd' 2>/dev/null | awk '{print $2}')"

    if [ -n "$MISSING_CLASSES" ]; then
        echo "BLOCKED [B] 클래스 캐시 불일치 — 다음 class_name이 Godot 캐시에 없습니다:" >&2
        echo -e "$MISSING_CLASSES" >&2
        echo "  → 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe --headless --path . --import'" >&2
        echo "    실행 후 다시 커밋하세요." >&2
        exit 2
    fi
fi

# ── Check C: 테스트 파일의 has_method 참조 존재 확인 ─────────────────────────
# has_method("X") 로 테스트하는 메서드 X가 src/ 에 실제로 존재하지 않으면 차단.
# 존재하지 않는 함수를 상상으로 테스트하는 실수를 방지한다.
TEST_FILES_STAGED=$(echo "$STAGED" | grep -E '^tests/.*\.gd$')
if [ -n "$TEST_FILES_STAGED" ]; then
    PHANTOM_METHODS=""
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        TESTED=$(grep -oE 'has_method\("[a-z][a-z0-9_]+"\)' "$file" 2>/dev/null \
            | grep -oE '"[a-z][a-z0-9_]+"' | tr -d '"')
        while IFS= read -r method; do
            [ -z "$method" ] && continue
            if ! grep -rqE "^(static )?func $method\b" src/ --include='*.gd' 2>/dev/null; then
                PHANTOM_METHODS="$PHANTOM_METHODS\n  - $method  (in $file)"
            fi
        done <<< "$TESTED"
    done <<< "$TEST_FILES_STAGED"

    if [ -n "$PHANTOM_METHODS" ]; then
        echo "BLOCKED [C] 유령 메서드 — 테스트가 src/에 없는 메서드를 참조합니다:" >&2
        echo -e "$PHANTOM_METHODS" >&2
        echo "  → 실제 메서드명을 확인하거나, 소스 파일에 해당 메서드를 추가하세요." >&2
        exit 2
    fi
fi

exit 0
