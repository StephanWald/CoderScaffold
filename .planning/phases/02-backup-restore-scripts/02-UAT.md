---
status: testing
phase: 02-backup-restore-scripts
source: [02-VERIFICATION.md]
started: "2026-06-17"
updated: "2026-06-17"
---

## Current Test

number: 1
name: Full backup→restore round-trip on a host with Docker and the stack running
expected: |
  Backup produces a non-empty mode-600 custom-format dump and exits 0 (the SC-1
  integrity-check blocker is now fixed via Plan 02-03 — confirm `Backup complete` prints
  and the script exits 0); restoring it into a freshly-wiped DB exits 0, Coder restarts,
  and the user/workspace created pre-backup are visible in the UI (SC-2).
awaiting: user response

## Tests

### 1. Full backup→restore round-trip on a host with Docker and the stack running
expected: Backup produces a non-empty mode-600 custom-format dump and exits 0; restoring it into a freshly-wiped DB exits 0, Coder restarts, and the user/workspace created pre-backup are visible in the UI (SC-2). Failure paths (missing dump arg/file, stack down) exit non-zero with a stderr message, and a pre-stop validation failure leaves `coder` running.
result: pending
note: "Prior blocker (integrity check exited 1 on every run) was diagnosed and fixed by gap-closure Plan 02-03 (commit 8b5be56 — `docker compose cp` seekable check). Re-run the round-trip against a live Docker stack to confirm SC-1 (exit 0 / 'Backup complete') and SC-2 (restore + UI visibility)."

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps

- truth: "Running scripts/backup.sh produces a custom-format dump in ./backups/ and exits 0 with a verified backup (SC-1, BAK-01)"
  status: resolved
  resolution: "Fixed by gap-closure Plan 02-03 (commit 8b5be56). The integrity check now `docker compose cp`s the dump into the container as a seekable regular file, runs `pg_restore --list` against it, removes it on all branches, and surfaces real stderr on failure — replacing the broken `pg_restore --list /dev/stdin` stdin-pipe pattern. Re-verification (02-VERIFICATION.md) scored 8/8 must-haves; live round-trip re-test tracked as pending Test 1 above."
  reason: "User reported: backup.sh wrote a non-empty dump but the integrity-check step (pg_restore --list /dev/stdin via `docker compose exec -T database` with the dump piped as stdin) failed, so the script exits 1 on every run. The dump file itself appears valid; the verification method (binary file as stdin into `docker compose exec`) is the suspected fault — a risk RESEARCH.md flagged as Open Question 1 / assumption A2."
  severity: blocker
  test: 1
  artifacts:
    - path: "scripts/backup.sh"
      issue: "Integrity check (lines 98-101): `pg_restore --list /dev/stdin < dump` via `docker compose exec -T database`. `pg_restore --list` requires a SEEKABLE regular file (Postgres 17 docs) — /dev/stdin is a non-seekable stream, so it fails for EVERY valid custom-format dump. Compounded by docker/compose #8909 (binary stdin into `exec -T` is unreliable, esp. macOS Docker Desktop). `> /dev/null 2>&1` also swallows pg_restore's real error."
  missing:
    - "Integrity check must give pg_restore a seekable regular file AND avoid `docker compose exec` stdin: `docker compose cp` the dump into the container (e.g. /tmp), run `pg_restore --list <in-container-path>`, then rm it. Cron-safe, no host postgres tooling, stays container-only per design."
    - "Stop swallowing pg_restore stderr on the failure path so future failures are self-explaining (drop the `2>&1`/`>/dev/null` on the error branch or surface captured output)."
  root_cause: "`pg_restore --list /dev/stdin` cannot succeed: --list on a custom-format archive requires a seekable regular file, but the dump is fed as non-seekable stdin across the `docker compose exec -T` boundary (overlapping with docker/compose #8909 binary-stdin corruption). The dump WRITE path (stdout redirect out of exec) is correct, so the dump on disk is valid; only the verification is broken. Scope fix to backup.sh only — restore.sh's single forward-pass pg_restore is unaffected."
  debug_session: .planning/debug/backup-integrity-check-fails.md
