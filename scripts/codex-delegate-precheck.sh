#!/usr/bin/env bash
# Read-only guard for codex-delegate. Never invokes codex; just answers
# "is it safe to hand this directory to codex exec right now?"
set -euo pipefail

ADD_DIR=""

usage() {
  echo "Usage: codex-delegate-precheck.sh [--add-dir <dir>]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --add-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --add-dir requires a value" >&2; exit 1; }
      ADD_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v codex >/dev/null 2>&1; then
  echo "NO_CODEX_ON_PATH"
  exit 127
fi

if ! WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "NOT_A_GIT_REPO"
  exit 3
fi

check_clean() {
  local repo_root="$1"
  local label="$2"
  local status

  status="$(git -C "$repo_root" status --porcelain)"
  if [[ -n "$status" ]]; then
    echo "DIRTY"
    printf '%s: %s\n' "$label" "$repo_root"
    echo "$status"
    exit 2
  fi
}

check_clean "$WORKSPACE_ROOT" "WORKSPACE"

if [[ -n "$ADD_DIR" ]]; then
  if [[ ! -d "$ADD_DIR" ]]; then
    echo "ADD_DIR_NOT_A_DIRECTORY"
    printf '%s\n' "$ADD_DIR"
    exit 4
  fi

  ADD_DIR="$(cd "$ADD_DIR" && pwd -P)"
  if ! ADD_ROOT="$(git -C "$ADD_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "ADD_DIR_NOT_A_GIT_REPO"
    printf '%s\n' "$ADD_DIR"
    exit 5
  fi

  if [[ "$ADD_ROOT" != "$WORKSPACE_ROOT" ]]; then
    check_clean "$ADD_ROOT" "ADD_DIR"
  fi
fi

echo "CLEAN"
exit 0
