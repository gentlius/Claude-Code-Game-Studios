# Hook: pre-commit-design-check

## Trigger

Runs before any commit that modifies files in `design/`, `assets/data/`, or `src/`.

## Purpose

두 가지 방향으로 GDD-코드 동기화를 강제한다:
1. **GDD 커밋 시**: 필수 섹션 존재 여부, Status 필드 유효성 검증
2. **코드 커밋 시**: 관련 GDD가 함께 staged 되지 않으면 경고 출력

> **핵심 원칙**: 코드가 바뀌면 GDD도 같은 커밋에서 업데이트된다.
> 이것이 "GDD 문서 스테일" 고질병의 근본 해결책이다.

## Implementation

```bash
#!/bin/bash
# Pre-commit hook: Design document and game data validation
# Place in .git/hooks/pre-commit or configure via your hook manager

STAGED=$(git diff --cached --name-only --diff-filter=ACM)
DESIGN_FILES=$(echo "$STAGED" | grep -E '^design/')
DATA_FILES=$(echo "$STAGED" | grep -E '^assets/data/')
SRC_FILES=$(echo "$STAGED" | grep -E '^src/')

EXIT_CODE=0

# ── 1. GDD 필수 섹션 검증 (design/ 파일 커밋 시) ──
if [ -n "$DESIGN_FILES" ]; then
    for file in $DESIGN_FILES; do
        if [[ "$file" == *.md && "$file" == design/gdd/* ]]; then
            # 필수 섹션 체크
            for section in "Overview" "Detailed" "Edge Cases" "Dependencies" "Acceptance Criteria" "Implementation Checklist"; do
                if ! grep -qi "$section" "$file"; then
                    echo "ERROR: $file — 필수 섹션 누락: $section"
                    EXIT_CODE=1
                fi
            done
            # Status 필드 체크
            if ! grep -qi "^> \*\*Status\*\*:" "$file"; then
                echo "ERROR: $file — Status 필드 없음 (> **Status**: Draft|In Review|Approved 형식 필요)"
                EXIT_CODE=1
            fi
        fi
    done
fi

# ── 2. JSON 데이터 파일 유효성 검증 (assets/data/ 파일 커밋 시) ──
if [ -n "$DATA_FILES" ]; then
    for file in $DATA_FILES; do
        if [[ "$file" == *.json ]]; then
            PYTHON_CMD=""
            for cmd in python python3 py; do
                if command -v "$cmd" >/dev/null 2>&1; then
                    PYTHON_CMD="$cmd"
                    break
                fi
            done
            if [ -n "$PYTHON_CMD" ] && ! "$PYTHON_CMD" -m json.tool "$file" > /dev/null 2>&1; then
                echo "ERROR: $file — 유효하지 않은 JSON"
                EXIT_CODE=1
            fi
        fi
    done
fi

# ── 3. 코드 커밋 시 GDD 동기화 경고 (src/ 파일 커밋 시) ──
# 블록(EXIT_CODE=1)이 아닌 경고(WARN)만 출력. 의도적으로 코드만 커밋하는 경우도 있음.
# Code Review Checklist의 "GDD 동기화" 항목이 실질적 하드 게이트.
if [ -n "$SRC_FILES" ] && [ -z "$DESIGN_FILES" ]; then
    echo ""
    echo "⚠️  WARN: src/ 파일이 변경됐으나 design/gdd/ 파일은 staged 되지 않았습니다."
    echo "   관련 GDD의 Implementation Checklist와 Status를 업데이트했는지 확인하세요."
    echo "   의도적으로 GDD 업데이트가 불필요한 경우 이 경고를 무시하세요."
    echo ""
fi

exit $EXIT_CODE
```

## Agent Integration

훅 실패 또는 경고 발생 시:
1. **GDD 섹션 누락**: `game-designer` 에이전트에게 해당 섹션 작성 요청
2. **Status 필드 없음**: GDD 상단에 `> **Status**: Draft` 추가
3. **JSON 오류**: 수동 수정 또는 `tools-programmer` 에이전트 호출
4. **src/ 경고 (GDD 미동기화)**: Code Review Checklist의 "GDD 동기화" 4개 항목 확인 후
   관련 GDD 업데이트를 동일 커밋에 포함

## 설계 철학

고질병 근본 원인: "코드를 커밋할 때 GDD 업데이트를 강제하는 장치가 없었다."

3중 방어선:
- **1선 (커밋 시)**: 이 훅 — src/ 변경 시 GDD 동기화 경고
- **2선 (리뷰 시)**: `coding-standards.md` Code Review Checklist "GDD 동기화" 섹션 — Lead Programmer 하드 게이트
- **3선 (스프린트 종료 시)**: Sprint DoD "구현된 시스템 GDD Status = Approved" 항목
