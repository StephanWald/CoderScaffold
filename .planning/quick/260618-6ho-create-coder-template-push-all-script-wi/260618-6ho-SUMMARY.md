---
status: complete
quick_id: 260618-6ho
date: 2026-06-18
---

# Quick Task 260618-6ho — Summary

**Task:** Create a shell script that uses the `coder` CLI to push (propagate) all workspace templates at once, checking login state and logging in if needed.

## Delivered

`scripts/push-templates.sh` (executable) — a login-aware bulk template pusher that mirrors the `backup.sh` / `restore.sh` conventions (`#!/usr/bin/env bash`, `set -euo pipefail`, cron-safe `SCRIPT_DIR`/`PROJECT_ROOT` resolution, `set -a` `.env` sourcing, heavy comments, parseable summary line, meaningful exit codes).

Behavior:
1. Fails fast (`exit 1`) if the `coder` binary is not on PATH.
2. Auth gate via `coder whoami` — skips login when a session already exists; otherwise runs `coder login` with `CODER_ACCESS_URL` (positional) and optional `--token "$CODER_SESSION_TOKEN"` for unattended runs. Without a token it warns that interactive login needs a TTY.
3. Iterates every `templates/*/` subdirectory containing a `.tf` file and runs `coder templates push <name> --directory <dir> --yes`. A single failure does not abort the loop; the script exits 1 at the end naming every failed template, or exits 0 cleanly when no template dirs are found.
4. Emits a parseable `TEMPLATES_PUSHED=<n> TEMPLATES_FAILED=<n>` line for schedulers/CI.

## Commits

- `b9c10ef` feat(scripts): add push-templates.sh for bulk coder template push (executor, worktree)
- glob-fix commit: `fix(scripts): unquote templates glob so push-templates.sh actually discovers templates`

## Verification

- `bash -n` clean (syntax).
- **Bug caught in review:** the executor's loop quoted the whole glob — `for dir in "${PROJECT_ROOT}/templates/*/"` — which suppresses pathname expansion, so it iterated one literal non-existent path, skipped it, and always reported "no templates found" (pushing nothing). `bash -n` cannot catch this. Fixed by quoting only the variable and leaving the glob unquoted, then proving discovery + push wiring against a stubbed `coder` CLI:
  ```
  Pushing template: docker (from /workspaces/coder/templates/docker)
    coder templates push docker --directory /workspaces/coder/templates/docker --yes
  TEMPLATES_PUSHED=1 TEMPLATES_FAILED=0
  ```
- **Live verification deferred** (per project memory "infra needs a live deploy gate"): the `coder` CLI is not installed here and no Coder server is reachable, so the real auth flow + actual template push against a running server still need to be exercised in a deployed environment. The script header documents this.

## Follow-up

- Run `./scripts/push-templates.sh` once against a live Coder server (with `CODER_ACCESS_URL` set, and `CODER_SESSION_TOKEN` for the non-interactive path) to confirm the auth flow and push succeed end-to-end.
