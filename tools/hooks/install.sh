#!/bin/bash
# Seed Money — Git Hooks 설치 스크립트
# 실행: bash tools/hooks/install.sh

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo "ERROR: git 저장소 루트를 찾을 수 없습니다." >&2
    exit 1
fi

HOOKS_DIR="$REPO_ROOT/.git/hooks"
SRC_DIR="$REPO_ROOT/tools/hooks"

for hook in pre-commit pre-push; do
    src="$SRC_DIR/$hook"
    dst="$HOOKS_DIR/$hook"
    if [ ! -f "$src" ]; then
        echo "WARN: $src 를 찾을 수 없습니다. 건너뜁니다."
        continue
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "설치됨: $dst"
done

echo ""
echo "완료. 커밋/푸시 시 hooks가 자동으로 실행됩니다."
echo "새 팀원 온보딩 시 'bash tools/hooks/install.sh' 를 실행하게 안내하세요."
