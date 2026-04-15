# Hook: pre-commit-design-check

## Trigger

`git commit` 시 `design/gdd/` 파일이 staged에 포함된 경우 실행.
구현 위치: `tools/hooks/pre-commit` — 설치: `bash tools/hooks/install.sh`

## Purpose

GDD가 커밋 시점에 필수 섹션 9개를 모두 갖추고 있는지, Implementation Checklist가
완전히 체크됐는지 강제한다. GDD 스테일 고질병의 1선 방어.

## Implementation

```bash
# design/gdd/ 파일 커밋 시 실행되는 섹션 (tools/hooks/pre-commit 내부)

DESIGN_FILES=$(git diff --cached --name-only | grep -E '^design/gdd/[^/]+\.md$')

if [ -n "$DESIGN_FILES" ]; then
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        # 필수 9개 섹션 검증
        for section in "Overview" "Player Fantasy" "Detailed" "Formulas" \
                        "Edge Cases" "Dependencies" "Tuning Knobs" \
                        "Acceptance Criteria" "Implementation Checklist"; do
            if ! grep -qi "$section" "$file" 2>/dev/null; then
                echo "BLOCKED [GDD]: $file — 필수 섹션 누락: $section" >&2
                exit 2
            fi
        done
        # Implementation Checklist 미완 항목 차단
        if grep -q "Implementation Checklist" "$file" 2>/dev/null; then
            UNCHECKED=$(awk '/Implementation Checklist/,0' "$file" \
                | grep -c "^- \[ \]" 2>/dev/null || echo 0)
            if [ "$UNCHECKED" -gt 0 ]; then
                echo "BLOCKED [GDD]: $file — Implementation Checklist 미완 항목 ${UNCHECKED}개" >&2
                exit 2
            fi
        fi
    done <<< "$DESIGN_FILES"
fi
```

## Agent Integration

훅 실패 시:
1. **필수 섹션 누락** → `game-designer` 에이전트에게 해당 섹션 작성 요청, 또는 `/design-system` 스킬로 섹션 추가
2. **Implementation Checklist 미완** → 해당 항목이 실제로 구현됐는지 확인 후 `[x]`로 갱신. 미구현이면 구현 완료 후 커밋

## 3중 방어선에서의 위치

- **1선 (이 훅)**: `tools/hooks/pre-commit` — 누가 커밋해도 실행
- **2선**: `.claude/hooks/validate-commit.sh` — Claude가 커밋할 때 동일 검사
- **3선**: `coding-standards.md` Code Review Checklist "GDD 동기화" 섹션 — Lead Programmer 하드 게이트
