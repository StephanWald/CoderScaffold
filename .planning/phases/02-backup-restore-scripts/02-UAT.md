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
  Requires a live Docker daemon + running stack (not available in this devcontainer).
  1. `docker compose up -d`; confirm `database (healthy)` and `coder (healthy)` via `docker compose ps`
  2. Create recognizable state in the Coder UI at http://localhost:7080 (note the admin user and any workspace)
  3. `./scripts/backup.sh` — confirm:
     - `backups/coder-YYYYMMDD-HHMMSS.dump` exists and is non-empty
     - `echo $?` returns `0`
     - `ls -l backups/` shows mode `-rw-------` (600)
  4. Wipe DB: `docker compose down && docker volume rm coder_coder_pgdata && docker compose up -d`; wait for `database (healthy)`
  5. `./scripts/restore.sh ./backups/coder-YYYYMMDD-HHMMSS.dump` — confirm `echo $?` is `0`
  6. `docker compose ps` shows `coder` running; Coder UI shows the user/workspace from step 2 (data restored — SC-2)
  7. Failure paths:
     - `./scripts/restore.sh /nonexistent.dump` — must exit non-zero with an ERROR on stderr; `docker compose ps` shows `coder` still running (EXIT trap must NOT leave coder stopped for pre-stop validation failures)
     - `./scripts/backup.sh` with the stack down — must exit non-zero with a meaningful stderr message
awaiting: user response

## Tests

### 1. Full backup→restore round-trip on a host with Docker and the stack running
expected: Backup produces a non-empty mode-600 custom-format dump and exits 0; restoring it into a freshly-wiped DB exits 0, Coder restarts, and the user/workspace created pre-backup are visible in the UI (SC-2). Failure paths (missing dump arg/file, stack down) exit non-zero with a stderr message, and a pre-stop validation failure leaves `coder` running.
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
