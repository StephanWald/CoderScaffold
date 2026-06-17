---
phase: 02-backup-restore-scripts
plan: 01
subsystem: infra
tags: [bash, pg_dump, postgres, docker-compose, backup, cron]

requires:
  - phase: 01-compose-hardening-configuration
    provides: compose.yaml with service name "database", POSTGRES_* env var names and defaults, .gitignore with backups/ entry, .env.example contract

provides:
  - scripts/backup.sh: non-interactive pg_dump -Fc backup to ./backups/ with integrity verification and mode 600 output

affects:
  - 02-02-restore (restore.sh consumes dump files produced by backup.sh)
  - operators running cron-scheduled backups

tech-stack:
  added: []
  patterns:
    - "BASH_SOURCE[0] path resolution for cron-safe script invocation"
    - "set -a; source .env; set +a for env file loading without xargs"
    - "PGPASSWORD inline env prefix on docker compose exec (not export, not --password)"
    - "docker compose exec -T for binary stream correctness"
    - "Two-step dump verification: size guard + pg_restore --list structural check"
    - "chmod 600 immediately after write for dump file security"

key-files:
  created:
    - scripts/backup.sh
  modified: []

key-decisions:
  - "chmod 600 applied to dump file immediately after write (ASVS V4 — dump contains user/workspace data including tokens)"
  - "pg_restore --list /dev/stdin integrity check via stdin redirect — avoids copying dump into container"
  - "PGPASSWORD as inline env prefix (not exported) — limits variable lifetime to the single exec call"
  - "BACKUP_FILE= parseable stdout line for scheduler capture alongside human-readable progress"
  - "zero-byte guard + rm -f on empty dump before exit 1 — catches -T-omission TTY corruption"

patterns-established:
  - "Pattern: BASH_SOURCE[0] in all scripts/ files for cwd-independent path resolution"
  - "Pattern: set -a; source; set +a for .env loading (no cat .env | xargs)"
  - "Pattern: PGPASSWORD prefix on every docker compose exec that invokes pg_dump/pg_restore"

requirements-completed: [BAK-01, BAK-03]

duration: 4min
completed: 2026-06-17
---

# Phase 02 Plan 01: Backup Script Summary

**Non-interactive pg_dump -Fc backup script with PGPASSWORD auth, timestamped ./backups/ output, chmod 600 hardening, zero-byte guard, and pg_restore --list structural integrity check**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-17T07:01:20Z
- **Completed:** 2026-06-17T07:04:02Z
- **Tasks:** 2 (combined into single commit — both tasks targeted the same file)
- **Files modified:** 1

## Accomplishments

- Created `scripts/` directory (first shell scripts in this repo)
- `scripts/backup.sh` (executable, 111 lines): sources `.env` via `set -a; source; set +a`, applies compose.yaml-mirroring defaults, runs `PGPASSWORD`-prefixed `docker compose exec -T database pg_dump -Fc --no-owner --no-acl` to a timestamped `./backups/coder-YYYYMMDD-HHMMSS.dump`
- Security hardening: `chmod 600` applied immediately after write (dump contains all user data, tokens, workspace metadata)
- Two-step integrity verification: zero-byte size guard (exits 1, rm -f dump) + `pg_restore --list /dev/stdin` structural check (exits 1 on corrupt archive)
- Cron-safe path resolution via `BASH_SOURCE[0]` — works when called from absolute path with cwd=/
- Human-readable stdout progress + `BACKUP_FILE=` parseable line for scheduler capture

## Task Commits

Both tasks targeted the same `scripts/backup.sh` file and were committed atomically:

1. **Task 1 + Task 2: scripts/backup.sh** - `4e2dfdd` (feat)

**Plan metadata commit:** `9702710` (docs)

## Files Created/Modified

- `scripts/backup.sh` — Non-interactive pg_dump -Fc backup; env-sourced config; PGPASSWORD auth; two-step dump verification; chmod 600 output; set -euo pipefail

## Decisions Made

- **chmod 600 placement:** Applied immediately after `pg_dump` redirect completes, before size/integrity checks — ensures dump is never world-readable even if subsequent checks fail
- **pg_restore --list via stdin:** Used `/dev/stdin` redirect inside the container rather than copying the dump file in — simpler, no cleanup required
- **PGPASSWORD inline prefix (not export):** Limits the variable's process-environment lifetime to the single `docker compose exec` call
- **BACKUP_FILE= line format:** Parseable prefix allows `grep -oP 'BACKUP_FILE=\K.*'` in calling scripts; human-readable progress goes to stdout (not stderr) so cron logs capture context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed `--password` from comment to satisfy acceptance criterion grep**
- **Found during:** Post-write verification
- **Issue:** Comment `# no --password (interactive)` caused `! grep -q '\-\-password'` acceptance check to fail because the pattern matched the comment text
- **Fix:** Rewrote comment to `# PGPASSWORD: non-interactive auth via libpq env var (never use the interactive prompt flag)` — preserves documentation intent without literal `--password` text
- **Files modified:** scripts/backup.sh
- **Verification:** `! /bin/grep -q '\-\-password' scripts/backup.sh` passes
- **Committed in:** 4e2dfdd (same task commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — comment text triggered negative grep pattern)
**Impact on plan:** Minimal — comment rewording only, no logic change.

## Issues Encountered

- `grep` in this devcontainer is aliased to `ugrep` which treated `-s` in the pattern `-s "${DUMP_FILE}"` as a flag rather than a literal string. Switched to `/bin/grep` for all verification commands — `/bin/grep -q -- '-s "${DUMP_FILE}"'` returns exit 0 correctly.

## Known Stubs

None — `scripts/backup.sh` is a complete operational script. No hardcoded empty values or placeholder data.

## Threat Flags

No new threat surface beyond the threat model in the plan. The only security-relevant surface is the dump file at rest in `./backups/` — mitigated via `chmod 600` (T-02-01) and gitignore (pre-existing). PGPASSWORD /proc visibility is documented and accepted (T-02-02).

## User Setup Required

None — no external service configuration required. Operators run `./scripts/backup.sh` against the live stack; Docker and the stack must be running on the deployment host.

**Manual verification (deployment host only — Docker unavailable in devcontainer):**
```bash
./scripts/backup.sh
# Expect: backups/coder-YYYYMMDD-HHMMSS.dump created, exit 0
ls -l backups/coder-*.dump
# Expect: -rw------- (mode 600)
```

## Next Phase Readiness

- `scripts/backup.sh` is complete; produces a verified, mode-600 custom-format dump in `./backups/`
- Plan 02-02 (`scripts/restore.sh`) can immediately consume dumps from this script
- No blockers for Plan 02-02

## Self-Check: PASSED

- [x] `scripts/backup.sh` exists: confirmed (created by Write tool, 111 lines, mode 755)
- [x] Commit 4e2dfdd exists: confirmed by git log
- [x] Commit 9702710 (docs) exists: confirmed by git log
- [x] All acceptance criteria satisfied: bash -n passes, all mandated flags/patterns present, no --password, no docker-compose (hyphenated)

---
*Phase: 02-backup-restore-scripts*
*Completed: 2026-06-17*
