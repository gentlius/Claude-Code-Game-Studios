#!/bin/bash
# Claude Code PreCompact hook: Dump session state before context compression
# This output appears in the conversation right before compaction, ensuring
# critical state survives the summarization process.

echo "=== SESSION STATE BEFORE COMPACTION ==="
echo "Timestamp: $(date)"

# --- Active session state file ---
STATE_FILE="production/session-state/active.md"
if [ -f "$STATE_FILE" ]; then
    STATUS_LINE=$(grep "^## STATUS:" "$STATE_FILE" 2>/dev/null | head -1)
    if echo "$STATUS_LINE" | grep -q "IN PROGRESS"; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  ⚠️  AUTO-RESUME REQUIRED — INCOMPLETE TASK DETECTED     ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Claude: 컴팩션 후 즉시 아래 작업을 재개하라. 사용자 재지시를 기다리지 말 것."
        echo "다음 사용자 메시지와 무관하게, 응답 시작 시 REMAINING 항목부터 실행한다."
        echo ""
        STATE_LINES=$(wc -l < "$STATE_FILE" 2>/dev/null | tr -d ' ')
        if [ "$STATE_LINES" -gt 100 ] 2>/dev/null; then
            head -n 100 "$STATE_FILE"
            echo "... (truncated — $STATE_LINES total lines)"
        else
            cat "$STATE_FILE"
        fi
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  END AUTO-RESUME BLOCK                                   ║"
        echo "╚══════════════════════════════════════════════════════════╝"
    else
        echo ""
        echo "## Active Session State (from $STATE_FILE)"
        cat "$STATE_FILE"
    fi
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  WARNING: active.md 없음                             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Claude: 진행 중인 멀티스텝 작업이 있으면 이 컴팩션으로 상태가 소실된다."
    echo "컴팩션 직후 첫 응답에서: (1) 아래 수정 파일 목록으로 작업 상태 파악,"
    echo "(2) production/session-state/active.md 즉시 작성, (3) 미완 작업 재개."
fi

# --- Files modified this session (unstaged + staged + untracked) ---
echo ""
echo "## Files Modified (git working tree)"

CHANGED=$(git diff --name-only 2>/dev/null)
STAGED=$(git diff --staged --name-only 2>/dev/null)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null)

if [ -n "$CHANGED" ]; then
    echo "Unstaged changes:"
    echo "$CHANGED" | while read -r f; do echo "  - $f"; done
fi
if [ -n "$STAGED" ]; then
    echo "Staged changes:"
    echo "$STAGED" | while read -r f; do echo "  - $f"; done
fi
if [ -n "$UNTRACKED" ]; then
    echo "New untracked files:"
    echo "$UNTRACKED" | while read -r f; do echo "  - $f"; done
fi
if [ -z "$CHANGED" ] && [ -z "$STAGED" ] && [ -z "$UNTRACKED" ]; then
    echo "  (no uncommitted changes)"
fi

# --- Work-in-progress design docs ---
echo ""
echo "## Design Docs — Work In Progress"

WIP_FOUND=false
for f in design/gdd/*.md; do
    [ -f "$f" ] || continue
    INCOMPLETE=$(grep -n -E "TODO|WIP|PLACEHOLDER|\[TO BE|\[TBD\]" "$f" 2>/dev/null)
    if [ -n "$INCOMPLETE" ]; then
        WIP_FOUND=true
        echo "  $f:"
        echo "$INCOMPLETE" | while read -r line; do echo "    $line"; done
    fi
done

if [ "$WIP_FOUND" = false ]; then
    echo "  (no WIP markers found in design docs)"
fi

# --- Log compaction event ---
SESSION_LOG_DIR="production/session-logs"
mkdir -p "$SESSION_LOG_DIR" 2>/dev/null
echo "Context compaction occurred at $(date)." \
    >> "$SESSION_LOG_DIR/compaction-log.txt" 2>/dev/null

echo ""
echo "=== END SESSION STATE ==="

exit 0
