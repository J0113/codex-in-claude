---
name: codex-in-claude
description: Delegate work to the OpenAI Codex CLI (`codex`, confirmed installed and authenticated on this machine) from within a Claude Code session. Two workflows -- codex-review (read-only critique of a plan, an uncommitted diff, a specific commit, or arbitrary text) and codex-delegate (Codex actually writes files / runs commands in the current directory). Use codex-review proactively right after presenting a plan in plan mode, before the user approves it, by offering "want Codex's take on this first?" -- and more generally whenever a second opinion from a different model would help before committing to an approach or before trusting a large diff. Use codex-delegate when the user might want a second AI agent to actually execute a task rather than Claude doing it directly. Always ask the user for explicit yes/no before running either workflow, every single time -- never invoke `codex exec` on your own judgment alone.
---

# Codex in Claude

Two ways to bring OpenAI's Codex CLI into a Claude Code session, as a second
opinion or a second pair of hands. They are deliberately kept separate:
**codex-review never writes anything**, **codex-delegate writes for real**.

## The one rule that applies to both

You (Claude) may *propose* either workflow whenever it seems useful. You may
never *run* it without the user's explicit yes for that specific invocation.
Proposing once and getting a yes does not cover the next one -- ask again
each time, even in the same conversation. This is intentional friction:
Codex will consume the user's Codex quota/credits and, for codex-delegate,
touch real files, so the decision to spend that stays with the user.

When you propose, state what you'd run: which workflow, what it's reviewing
or doing, and the model + effort you'd use (see "Picking a model" below).
The user's yes can come with a correction to any of those -- treat "yes but
use terra" as an approval with an override, not a new round-trip.

## Picking a model and effort

Never hardcode a model. Ask the user each time, but come with a
recommendation based on the task so it's a quick confirm rather than an
open question:

| Model | When | Typical effort |
|---|---|---|
| `gpt-5.6-sol` | Reviewing a plan or diff, or delegating anything nontrivial. Most capable, the right default for almost everything. | `high`, or `xhigh` for something you really want scrutinized |
| `gpt-5.6-terra` | Delegating an easier, well-scoped coding task | `medium` |
| `gpt-5.6-luna` | Pure search/lookup, "how does this work" clarification, or reviewing something small and low-stakes | `low` |

These are this machine's currently-cached models -- if the user's Codex
setup changes, `~/.codex/models_cache.json` and the `model` line in
`~/.codex/config.toml` are the sources of truth, not this table.

## Workflow 1: codex-review (read-only)

Codex critiques something without touching disk. Four cases, one script:
[scripts/codex-review.sh](scripts/codex-review.sh). It forces the sandbox
to read-only via `-c sandbox_mode="read-only"` on every call -- **not**
`-s read-only`, because `codex exec review` has no `-s/--sandbox` flag at
all (confirmed: it hard-errors on `-s`). The config-key override is the
only way to force it, and forcing it matters: Codex persists a per-project
`trust_level` in `~/.codex/config.toml`, and a directory that was previously
used for codex-delegate can otherwise silently default review to
workspace-write instead of read-only.

The script also always passes `--skip-git-repo-check`, so review works even
when the current directory isn't a git repo (harmless for read-only work --
verified live in a non-git scratch dir).

**Case A -- reviewing a plan (the primary use case).** When you've just
presented a plan via plan mode and are about to ask the user to approve it,
that plan text exists only in your own context -- it was never written to
disk. Before asking Codex about it, persist it:

```bash
PLAN_FILE=$(mktemp -t claude-plan)
cat > "$PLAN_FILE" <<'EOF'
<the exact plan text you just presented>
EOF
```

Use `mktemp`, not a path inside the repo -- there's nothing here to
gitignore or clean up later. Then, once the user says yes:

```bash
scripts/codex-review.sh --mode custom --file "$PLAN_FILE" \
  --model gpt-5.6-sol --effort high
```

The script pipes the file to Codex via stdin (`codex exec review -`) rather
than passing it as a shell argument -- a plan can be long markdown with
quotes, backticks, and code fences, all of which mangle badly as a literal
CLI arg. `--mode custom` is also how you'd review any other arbitrary text
(a spec, an email, a design doc) -- write it to a temp file the same way.

**Case B -- reviewing uncommitted changes.** Codex can read git state
itself here, no temp file needed:

```bash
scripts/codex-review.sh --mode uncommitted --model gpt-5.6-sol --effort high
```

**Case C/D -- reviewing a base-branch diff or a specific commit.** Same
idea, Codex reads git directly:

```bash
scripts/codex-review.sh --mode base --base main --model gpt-5.6-sol --effort high
scripts/codex-review.sh --mode commit --commit HEAD~1 --model gpt-5.6-sol --effort high
```

All four modes print Codex's clean final response to stdout (read via
`-o/--output-last-message` to a temp file internally, then `cat`), not the
raw streamed transcript -- so just read the script's stdout directly,
you don't need a separate file read.

## Workflow 2: codex-delegate (writes for real)

Codex actually executes: writes files, runs shell commands, in the current
working directory. No git worktree isolation -- same directory as this
session, by design, so treat the permission step accordingly.

**Step 1 -- guard, before even asking permission.** Run
[scripts/codex-delegate-precheck.sh](scripts/codex-delegate-precheck.sh).
It exits `0`/prints `CLEAN` only when `codex` is on PATH, the cwd is inside
a git repo, and `git status --porcelain` is empty. If it prints `DIRTY`,
stop and show the user the listed changes -- don't propose delegating yet.
The reason is practical, not paranoid: once Codex's edits land on top of
the user's in-progress edits, there's no clean way to tell whose change is
whose in the resulting diff.

If it prints `NOT_A_GIT_REPO`: don't try to route around this with
`--skip-git-repo-check`. codex-delegate's whole safety model -- the dirty
check, and showing a diff afterward -- depends on git existing. Tell the
user to `git init` (or confirm they're fine skipping that safety net
entirely) before proceeding.

If it prints `NO_CODEX_ON_PATH`: tell the user Codex isn't installed or
isn't on PATH and stop -- don't try to guess an install path or fall back
to another tool.

**Step 2 -- ask.** Only after `CLEAN`, propose the specific task, model,
and effort, and wait for an explicit yes.

**Step 3 -- run.** Write the task instructions to a temp file for the same
reason as the plan case above (avoids shell-escaping and length limits),
then:

```bash
TASK_FILE=$(mktemp -t claude-delegate-task)
cat > "$TASK_FILE" <<'EOF'
<the task you and the user agreed on>
EOF
scripts/codex-delegate-run.sh --file "$TASK_FILE" \
  --model gpt-5.6-sol --effort high
```

[scripts/codex-delegate-run.sh](scripts/codex-delegate-run.sh) re-runs the
precheck immediately before invoking Codex (defense in depth, in case
something changed between the user's yes and this call), then runs
`codex exec -s workspace-write` -- **not** `danger-full-access`. Codex's
non-interactive `exec` mode has no interactive-approval flag to configure
in the first place (confirmed: `codex exec --help` has no `-a`); it always
runs with approval effectively `never` since there's no human to prompt,
so the sandbox mode alone is what keeps it bounded to the workspace (plus
`/tmp`). Verified live: it wrote a file autonomously under
`workspace-write` with no hang and no elevated flags.

**Step 4 -- show the result.** The script prints, in order: Codex's final
message, `git status --short`, and a `git diff --stat` summary, then saves
the full diff to a temp file and prints its path. Show the user the
message + stat summary; only pull in the full diff file (via Read) if they
ask to see everything. Note the stat/full-diff step marks new untracked
files intent-to-add (`git add -N`) so they actually appear in the diff --
plain `git diff` silently omits brand-new files -- then resets the index
back to how it was, so nothing gets left staged.

**Long-running tasks.** `codex exec` can take a while for a nontrivial
task. Use your judgment on how to run it: for something you expect to
finish in a couple minutes, run the script in the foreground and wait; for
something open-ended (a broad refactor, "fix all the failing tests"), run
it via Bash with `run_in_background: true` so the conversation isn't
blocked, and let the completion notification tell you when to read the
result back.

## Working directory and `--add-dir`

Both scripts assume they're invoked from the directory you want Codex
operating in -- they don't take a `-C`/cwd override. If the task needs
Codex to touch a directory outside the current workspace root,
`codex-delegate-run.sh` accepts `--add-dir <path>`, which maps to Codex's
own `--add-dir` (adds another writable root without loosening the sandbox
mode itself).
