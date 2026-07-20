#!/usr/bin/env bash
# Actually invokes codex exec to write files / run commands in the current
# directory. Only call this AFTER the user has said yes to the specific
# task, model, and effort level -- this script does not ask permission
# itself, it just executes.
set -euo pipefail

FILE=""
MODEL=""
EFFORT=""
ADD_DIR=""

usage() {
  cat <<'EOF'
Usage: codex-delegate-run.sh --file <prompt-file> --model <m> --effort <e> [--add-dir <dir>]

Re-runs the git-status guard before touching anything. Prints codex's final
message, then a git status/diff summary, then the path to a temp file
holding the full diff (read it if the user wants to see everything).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|--model|--effort|--add-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
      case "$1" in
        --file) FILE="$2" ;;
        --model) MODEL="$2" ;;
        --effort) EFFORT="$2" ;;
        --add-dir) ADD_DIR="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$FILE" ]] || { echo "ERROR: prompt file not found: $FILE" >&2; exit 1; }
[[ -z "$MODEL" ]] && { echo "ERROR: --model is required" >&2; exit 1; }
[[ -z "$EFFORT" ]] && { echo "ERROR: --effort is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defense in depth: re-verify clean trees right before running, in case
# something changed between the user's yes and this call.
if [[ -n "$ADD_DIR" ]]; then
  PRECHECK_OUT="$("$SCRIPT_DIR/codex-delegate-precheck.sh" --add-dir "$ADD_DIR")" || {
    echo "ERROR: precondition check failed, aborting before touching codex."
    echo "$PRECHECK_OUT"
    exit 1
  }
else
  PRECHECK_OUT="$("$SCRIPT_DIR/codex-delegate-precheck.sh")" || {
    echo "ERROR: precondition check failed, aborting before touching codex."
    echo "$PRECHECK_OUT"
    exit 1
  }
fi

WORKSPACE_ROOT="$(git rev-parse --show-toplevel)"
ADD_ROOT=""
if [[ -n "$ADD_DIR" ]]; then
  ADD_DIR="$(cd "$ADD_DIR" && pwd -P)"
  ADD_ROOT="$(git -C "$ADD_DIR" rev-parse --show-toplevel)"
fi

OUT="$(mktemp -t codex-delegate-out)"
DIFF_FILE="$(mktemp -t codex-delegate-diff)"
TEMP_INDEX=""
trap 'rm -f "$OUT" "$TEMP_INDEX"' EXIT

ARGS=(exec -s workspace-write -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -o "$OUT")
[[ -n "$ADD_DIR" ]] && ARGS+=(--add-dir "$ADD_DIR")
ARGS+=(-)

# Codex's raw session transcript -> stderr, visible for debugging; stdout
# stays clean for the final summary below.
codex "${ARGS[@]}" < "$FILE" >&2

echo "=== Codex final message ==="
cat "$OUT"
echo

# Build a complete patch against HEAD in a temporary index. This captures
# staged, unstaged, deleted, and untracked files without changing the real
# index. Starting from a clean tree means the patch contains only this run.
capture_repo() {
  local repo_root="$1"
  local label="$2"

  echo "=== $label: git status --short ==="
  git -C "$repo_root" status --short
  echo

  TEMP_INDEX="$(mktemp -t codex-delegate-index)"
  rm -f "$TEMP_INDEX"
  if git -C "$repo_root" rev-parse --verify HEAD >/dev/null 2>&1; then
    GIT_INDEX_FILE="$TEMP_INDEX" git -C "$repo_root" read-tree HEAD
  else
    GIT_INDEX_FILE="$TEMP_INDEX" git -C "$repo_root" read-tree --empty
  fi
  GIT_INDEX_FILE="$TEMP_INDEX" git -C "$repo_root" add -A

  echo "=== $label: git diff --stat ==="
  GIT_INDEX_FILE="$TEMP_INDEX" git -C "$repo_root" diff --cached --stat
  {
    printf '### %s (%s)\n' "$label" "$repo_root"
    GIT_INDEX_FILE="$TEMP_INDEX" git -C "$repo_root" diff --cached --binary
    printf '\n'
  } >> "$DIFF_FILE"
  rm -f "$TEMP_INDEX"
  TEMP_INDEX=""
  echo
}

capture_repo "$WORKSPACE_ROOT" "WORKSPACE"
if [[ -n "$ADD_ROOT" && "$ADD_ROOT" != "$WORKSPACE_ROOT" ]]; then
  capture_repo "$ADD_ROOT" "ADD_DIR"
fi

echo
echo "Full diff saved to: $DIFF_FILE"
