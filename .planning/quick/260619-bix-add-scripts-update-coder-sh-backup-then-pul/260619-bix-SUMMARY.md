---
quick_id: 260619-bix
title: update-coder.sh + Updating Coder docs
date: 2026-06-19
status: complete
commit: f66b9f8
---

# Quick Task 260619-bix — Summary

Added `scripts/update-coder.sh` and a README "Updating Coder" section.

## How updating works
The Coder server is a pinned prebuilt image. Updating = bump `CODER_VERSION` →
`docker compose pull coder` → `docker compose up -d`. Postgres data persists in
the `coder_pgdata` volume; the new server runs DB migrations automatically. Only
the control plane restarts briefly; running workspaces are unaffected.

## scripts/update-coder.sh
- `--check`: prints current pinned version vs latest GitHub release + stable/
  mainline guidance.
- `<version>`: validates `vX.Y.Z` (rejects `:latest`); **backs up the DB first**
  via backup.sh and aborts the upgrade if the backup fails; pins CODER_VERSION in
  .env (preserving the rest); `pull` + `up -d`; waits for the coder healthcheck;
  reports the running version.
- No-arg: re-pull/recreate the currently pinned version.
- Flags: `--no-backup`, `--push-templates` (re-push via push-templates.sh),
  `--dry-run`, `-h/--help`.
- Non-interactive; exit 0 success / 1 on bad usage, failed backup, failed pull,
  or unhealthy server. Matches backup.sh / push-templates.sh conventions
  (set -euo pipefail, .env via set -a, parseable summary line, cron-safe paths).

## README
New "Updating Coder" section: stable-vs-mainline note, script usage, manual
steps, how to bump the committed default (compose.yaml + .env.example), and
rollback (revert CODER_VERSION + restore.sh the pre-update dump).

## Verification
- `bash -n` and `shellcheck` clean.
- `--help`, `--check` (correctly shows v2.33.8 → latest v2.33.9), `--dry-run`
  (shows v2.33.8 → v2.33.9, no changes), and bad-version rejection all exercised.
- `restore.sh <dump-file>` interface confirmed to match the documented rollback.
- LIVE pull/recreate/health deferred to a host with a running stack + coder CLI
  (per "infra needs a live deploy gate"); the apply path is unverified here.

## Note for the user
Latest stable is **v2.33.9** (patch bump on the same 2.33.x track as the pinned
v2.33.8) — a low-risk update: `./scripts/update-coder.sh v2.33.9`.
