#!/usr/bin/env bash
# Read-only guard for codex-delegate. Never invokes codex; just answers
# "is it safe to hand this directory to codex exec right now?"
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "NO_CODEX_ON_PATH"
  exit 127
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "NOT_A_GIT_REPO"
  exit 3
fi

STATUS="$(git status --porcelain)"
if [[ -n "$STATUS" ]]; then
  echo "DIRTY"
  echo "$STATUS"
  exit 2
fi

echo "CLEAN"
exit 0
