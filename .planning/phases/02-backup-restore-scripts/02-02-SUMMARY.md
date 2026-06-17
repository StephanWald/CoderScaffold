---
phase: 02-backup-restore-scripts
plan: 02
subsystem: infra
tags: [bash, pg_restore, postgres, docker-compose, restore, backup]

requires:
  - phase: 02-01
    provides: scripts/backup.sh producing ./backups/coder-YYYYMMDD-HHMMSS.dump (custom format, mode 600)

provides:
  - scripts/restore.sh: non-interactive pg_restore --clean --if-exists with stop/start coder + EXIT trap
  - README.md ## Backup & restore: operational section documenting both scripts with DESTRUCTIVE warning and cron note

affects:
  - operators running restore from backup.sh dumps
  - phase gate: backup→restore round-trip functional verification (deferred to /gsd-verify-work)

tech-stack:
  added: []
  patterns:
    - "EXIT trap: docker compose start coder registered immediately after stop — guarantees restart even under set -e failure"
    - "Argument validation before any destructive action: -f regular file + -s non-zero size (ASVS V5, T-02-05)"
    - "pg_restore --clean --if-exists via stdin redirect (never filename arg to pg_restore, never pipe between exec calls)"
    - "docker compose stop coder before restore to release connection pool (Pitfall 2)"

key-files:
  created:
    - scripts/restore.sh
  modified:
    - README.md

key-decisions:
  - "EXIT trap registered immediately after docker compose stop coder (not at top of script) — ensures coder is only restarted when it was actually stopped; prevents false restart on argument-validation failures that exit before stop"
  - "Argument validation (count + -f + -s) placed BEFORE sourcing .env and BEFORE touching any service — no destructive action on invalid input (T-02-05)"
  - "Restore reads dump via stdin redirect (< ${DUMP_FILE}) not as pg_restore filename argument — avoids docker/compose exec binary corruption pattern (#8909)"
  - "--clean --if-exists paired: handles fresh-instance (no objects to drop) and overwrite (existing objects present) in one invocation"
  - "README DESTRUCTIVE warning added as a callout block — T-02-06 mitigation; operator must consciously acknowledge before running"

metrics:
  duration: 2min
  completed: 2026-06-17
---

# Phase 02 Plan 02: Restore Script + README Summary

**Non-interactive pg_restore --clean --if-exists with stop/start coder lifecycle management via EXIT trap, argument validation (ASVS V5), and README operational documentation covering both backup/restore scripts with DESTRUCTIVE warning and cron-safety note**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-17T07:08:00Z
- **Completed:** 2026-06-17T07:10:00Z
- **Tasks:** 3 (Task 1: restore.sh, Task 2: README.md, Task 3: round-trip recording — no code change)
- **Files modified:** 2

## Accomplishments

- `scripts/restore.sh` (executable, 111 lines): validates the dump-file argument before any destructive action, sources `.env` via `set -a`, stops `coder` service, registers EXIT trap (guarantees `docker compose start coder` even on `pg_restore` failure under `set -e`), runs `PGPASSWORD`-prefixed `docker compose exec -T database pg_restore --clean --if-exists --no-owner --no-acl` from stdin redirect
- All critical flags present: `-T`, `PGPASSWORD=`, `--clean`, `--if-exists`, `--no-owner`, `--no-acl`, `< "${DUMP_FILE}"` stdin redirect, `set -euo pipefail`, `set -a; source .env; set +a`
- `README.md` `## Backup & restore` section: documents backup command, restore command, DESTRUCTIVE `--clean` warning, cron example with absolute path, retention/pruning deferral note (QOL-02)
- Existing `## Upgrading from the quickstart` migration snippet left unchanged

## Task Commits

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | scripts/restore.sh | `90dd904` | scripts/restore.sh (created, 111 lines, mode 755) |
| 2 | README.md Backup & restore | `414c389` | README.md (54 lines added) |
| 3 | Round-trip recording | no code change | Recorded in SUMMARY (Docker unavailable — see below) |

## Files Created/Modified

- `scripts/restore.sh` — Non-interactive pg_restore; argument validation; stop/start coder lifecycle; EXIT trap; PGPASSWORD auth; stdin redirect; set -euo pipefail
- `README.md` — Added `## Backup & restore` section (~54 lines) near `## Common operations`

## Decisions Made

- **EXIT trap placement:** Registered immediately after `docker compose stop coder` (not at the top of the script) — this ensures the restart trap only fires when the service was actually stopped; argument-validation failures that exit before the stop do not attempt a spurious `docker compose start coder`
- **Argument validation order:** Count check → `-f` file check → `-s` size check all happen BEFORE `.env` sourcing and BEFORE any `docker compose` call — no destructive action can trigger on bad input
- **Stdin redirect:** `< "${DUMP_FILE}"` on the host shell, not a filename argument to `pg_restore` — avoids the documented binary-corruption pattern when piping between two `docker compose exec` calls (#8909)
- **README placement:** New `## Backup & restore` section added after `## Common operations` / `### coder_home volume` — consistent with existing H2 section ordering

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria for Tasks 1 and 2 verified green. Task 3 is a recording-only task with the expected outcome documented below.

## End-of-Phase Round-Trip Verification (Task 3)

**Status: DEFERRED to `/gsd-verify-work`**

Docker daemon is not available in the devcontainer environment (confirmed in RESEARCH.md "Environment Availability" and the execution environment note). The functional round-trip cannot be executed here — no fabricated pass.

**Operator steps to verify (when Docker stack is available):**

1. `docker compose up -d` — wait for `docker compose ps` to show `database (healthy)` and `coder (healthy)`
2. Create recognizable state in the Coder UI at http://localhost:7080 (note admin user and any workspace)
3. `./scripts/backup.sh` — confirm:
   - `backups/coder-YYYYMMDD-HHMMSS.dump` exists and is non-empty
   - `echo $?` returns `0`
   - `ls -l backups/` shows mode `-rw-------` (600)
4. Wipe DB: `docker compose down && docker volume rm coder_coder_pgdata && docker compose up -d` — wait for `database (healthy)`
5. `./scripts/restore.sh ./backups/coder-YYYYMMDD-HHMMSS.dump` (use the real filename from step 3) — confirm `echo $?` is `0`
6. `docker compose ps` shows `coder` running; Coder UI shows the user/workspace from step 2 (data restored)
7. Failure paths:
   - `./scripts/restore.sh /nonexistent.dump` — must exit non-zero with an stderr ERROR; `docker compose ps` shows `coder` still running (EXIT trap does NOT fire for pre-stop validation failures)
   - `./scripts/backup.sh` with stack down — must exit non-zero with a meaningful stderr message

## Known Stubs

None — `scripts/restore.sh` is a complete operational script. No hardcoded empty values or placeholder data. `README.md` documents the actual scripts with their real flags and behavior.

## Threat Flags

No new threat surface beyond the plan's threat model. All T-02-05/06/07/08 mitigations are implemented:
- T-02-05 (unvalidated dump-file arg): `-f` + `-s` checks before destructive action — MITIGATED
- T-02-06 (--clean against wrong/running DB): `docker compose stop coder` + EXIT trap + README DESTRUCTIVE warning — MITIGATED
- T-02-07 (PGPASSWORD in /proc): inline prefix only, documented in script header — ACCEPTED (single-host model)
- T-02-08 (binary stream corruption): mandatory `-T` + stdin redirect (not filename arg) — MITIGATED

## Self-Check: PASSED

- [x] `scripts/restore.sh` exists: confirmed (Write tool, 111 lines, mode 755 via chmod +x)
- [x] `bash -n scripts/restore.sh` exits 0: PASS
- [x] All mandatory flags present: `set -euo pipefail`, `docker compose stop coder`, `trap ... EXIT`, `docker compose start coder`, `pg_restore`, `--clean`, `--if-exists`, `--no-owner`, `--no-acl`, `-T`, `PGPASSWORD=`, `< "${DUMP_FILE}"`, `set -a; source .env; set +a`
- [x] No `--password` in script: PASS
- [x] No `docker-compose` (hyphenated) in script: PASS
- [x] Commit 90dd904 exists: confirmed by git log
- [x] `README.md` contains `## Backup` heading, `scripts/backup.sh`, `scripts/restore.sh`, `--clean` warning: all PASS
- [x] Commit 414c389 exists: confirmed by git log
- [x] Existing `## Upgrading from the quickstart` migration snippet unchanged: PASS

---
*Phase: 02-backup-restore-scripts*
*Completed: 2026-06-17*
