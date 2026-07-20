#!/usr/bin/env bash
# Read-only Codex review. Never writes to the filesystem: sandbox is forced
# to read-only regardless of any per-project trust state Codex may have
# persisted in ~/.codex/config.toml (confirmed by testing that trust_level
# can silently upgrade the default sandbox to workspace-write).
set -euo pipefail

MODE=""
FILE=""
BASE=""
COMMIT=""
MODEL=""
EFFORT=""
TITLE=""

usage() {
  cat <<'EOF'
Usage:
  codex-review.sh --mode custom     --file <path>  --model <m> --effort <e> [--title <t>]
  codex-review.sh --mode uncommitted                --model <m> --effort <e> [--title <t>]
  codex-review.sh --mode base       --base <branch> --model <m> --effort <e> [--title <t>]
  codex-review.sh --mode commit     --commit <sha>  --model <m> --effort <e> [--title <t>]

--mode custom reads review instructions from --file via stdin (handles a
persisted plan, a pasted diff, or arbitrary text) so nothing is passed as a
raw shell argument.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --commit) COMMIT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found on PATH. Install/authenticate it first." >&2
  exit 127
fi

[[ -z "$MODEL" ]] && { echo "ERROR: --model is required" >&2; exit 1; }
[[ -z "$EFFORT" ]] && { echo "ERROR: --effort is required" >&2; exit 1; }

OUT="$(mktemp -t codex-review-out)"
trap 'rm -f "$OUT"' EXIT

# `codex exec review` has no -s/--sandbox flag (confirmed: it errors with
# "unexpected argument '-s'"). Force read-only via the underlying config
# key instead -- this matters because Codex persists a per-project
# trust_level in ~/.codex/config.toml that can otherwise silently upgrade
# review's default sandbox to workspace-write on a directory that was
# previously used with codex-delegate.
ARGS=(exec review -c 'sandbox_mode="read-only"' --skip-git-repo-check -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -o "$OUT")
[[ -n "$TITLE" ]] && ARGS+=(--title "$TITLE")

case "$MODE" in
  custom)
    [[ -z "$FILE" ]] && { echo "ERROR: --mode custom requires --file" >&2; exit 1; }
    [[ -f "$FILE" ]] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
    ARGS+=(-)
    codex "${ARGS[@]}" < "$FILE" >&2
    ;;
  uncommitted)
    ARGS+=(--uncommitted)
    codex "${ARGS[@]}" >&2
    ;;
  base)
    [[ -z "$BASE" ]] && { echo "ERROR: --mode base requires --base <branch>" >&2; exit 1; }
    ARGS+=(--base "$BASE")
    codex "${ARGS[@]}" >&2
    ;;
  commit)
    [[ -z "$COMMIT" ]] && { echo "ERROR: --mode commit requires --commit <sha>" >&2; exit 1; }
    ARGS+=(--commit "$COMMIT")
    codex "${ARGS[@]}" >&2
    ;;
  *)
    echo "ERROR: --mode must be one of: custom, uncommitted, base, commit" >&2
    usage
    exit 1
    ;;
esac

# Codex's raw session transcript goes to stderr (visible above for
# debugging); the clean final message is the only thing on stdout.
cat "$OUT"
