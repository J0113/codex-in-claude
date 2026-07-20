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
    --file) FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --add-dir) ADD_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$FILE" ]] || { echo "ERROR: prompt file not found: $FILE" >&2; exit 1; }
[[ -z "$MODEL" ]] && { echo "ERROR: --model is required" >&2; exit 1; }
[[ -z "$EFFORT" ]] && { echo "ERROR: --effort is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defense in depth: re-verify clean tree right before running, in case
# something changed between the user's yes and this call.
PRECHECK_OUT="$("$SCRIPT_DIR/codex-delegate-precheck.sh")" || {
  echo "ERROR: precondition check failed, aborting before touching codex."
  echo "$PRECHECK_OUT"
  exit 1
}

OUT="$(mktemp -t codex-delegate-out)"
DIFF_FILE="$(mktemp -t codex-delegate-diff)"
trap 'rm -f "$OUT"' EXIT

ARGS=(exec -s workspace-write -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -o "$OUT")
[[ -n "$ADD_DIR" ]] && ARGS+=(--add-dir "$ADD_DIR")
ARGS+=(-)

# Codex's raw session transcript -> stderr, visible for debugging; stdout
# stays clean for the final summary below.
codex "${ARGS[@]}" < "$FILE" >&2

echo "=== Codex final message ==="
cat "$OUT"
echo
echo "=== git status --short ==="
git status --short
echo

# `git diff` alone skips brand-new untracked files. Mark them
# intent-to-add (no content actually staged) so they show up in the
# stat/diff below, then reset the index back to how it was.
git add -N . >/dev/null 2>&1 || true
echo "=== git diff --stat ==="
git diff --stat
git diff > "$DIFF_FILE"
git reset >/dev/null 2>&1 || true
echo
echo "Full diff saved to: $DIFF_FILE"
