#!/usr/bin/env bash
# Create the exact repository state required by one eval case.
set -euo pipefail

CASE="${1:-}"
TARGET="${2:-}"
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$CASE" || -z "$TARGET" ]]; then
  echo "Usage: setup-eval.sh <plan-review|uncommitted-review|delegate-dirty-guard|delegate-clean-tree> <empty-target-dir>" >&2
  exit 1
fi

if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  echo "ERROR: target exists and is not a directory: $TARGET" >&2
  exit 1
fi

mkdir -p "$TARGET"
if [[ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "ERROR: target directory must be empty: $TARGET" >&2
  exit 1
fi

git -C "$TARGET" init -q
git -C "$TARGET" config user.name "Skill Eval"
git -C "$TARGET" config user.email "skill-eval@example.invalid"

case "$CASE" in
  plan-review)
    cp "$FIXTURE_DIR/auth.py" "$TARGET/auth.py"
    ;;
  uncommitted-review|delegate-dirty-guard|delegate-clean-tree)
    cp "$FIXTURE_DIR/utils-base.py" "$TARGET/utils.py"
    ;;
  *)
    echo "ERROR: unknown eval case: $CASE" >&2
    exit 1
    ;;
esac

git -C "$TARGET" add .
git -C "$TARGET" commit -qm "eval baseline"

case "$CASE" in
  uncommitted-review)
    cp "$FIXTURE_DIR/utils-uncommitted.py" "$TARGET/utils.py"
    ;;
  delegate-dirty-guard)
    cp "$FIXTURE_DIR/scratch_notes.txt" "$TARGET/scratch_notes.txt"
    cp "$FIXTURE_DIR/README_notes.txt" "$TARGET/README_notes.txt"
    ;;
esac

printf 'READY %s %s\n' "$CASE" "$(cd "$TARGET" && pwd -P)"
