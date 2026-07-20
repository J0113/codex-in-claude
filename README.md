# Codex in Claude

A Claude Code skill that brings the OpenAI Codex CLI in as a second opinion
or a second pair of hands.

## Workflows

- **`codex-review`** critiques a plan, arbitrary text, uncommitted changes, a
  base-branch diff, or a commit. It cannot change workspace files and uses an
  ephemeral Codex session.
- **`codex-delegate`** lets Codex implement an approved task in the current
  workspace with the `workspace-write` sandbox.

Claude must receive explicit approval for every Codex invocation, including
the task or review target, model, and reasoning effort.

## Requirements

- Claude Code
- An installed and authenticated `codex` CLI on `PATH`
- A clean Git repository for delegation

## Safety model

Review runs read-only. Delegation first verifies that every writable
repository is clean, then reports status and a complete diff afterward.
Additional writable directories passed with `--add-dir` must also belong to
clean Git repositories and are included in the resulting audit.

No worktree isolation is used: delegation intentionally operates in the same
working directory as the active Claude Code session.

## Files

- [`SKILL.md`](SKILL.md) — Claude Code instructions and workflow
- [`scripts/codex-review.sh`](scripts/codex-review.sh) — read-only reviews
- [`scripts/codex-delegate-precheck.sh`](scripts/codex-delegate-precheck.sh) — delegation guard
- [`scripts/codex-delegate-run.sh`](scripts/codex-delegate-run.sh) — approved write-capable delegation
- [`evals/evals.json`](evals/evals.json) — behavioral evaluations
- [`evals/fixtures`](evals/fixtures) — reproducible evaluation repositories

## Typical use

Ask Claude naturally, for example:

> Get Codex to review this plan with gpt-5.6-sol at high effort.

or:

> Have Codex implement this TODO with gpt-5.6-terra at medium effort.

Claude will apply the appropriate safety checks and ask for any missing
approval before invoking Codex.
