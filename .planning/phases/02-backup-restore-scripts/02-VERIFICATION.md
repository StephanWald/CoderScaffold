---
phase: 02-backup-restore-scripts
verified: 2026-06-17T08:00:00Z
status: human_needed
score: 7/8 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Full backup→restore round-trip on a host with Docker and the stack running"
    expected: |
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
         - `./scripts/restore.sh /nonexistent.dump` — must exit non-zero with an ERROR on stderr; `docker compose ps` shows `coder` still running (EXIT trap must NOT fire for pre-stop validation failures)
         - `./scripts/backup.sh` with the stack down — must exit non-zero with a meaningful stderr message
    why_human: "Requires a live Docker daemon, a running Postgres container, and a running Coder server to execute the pg_dump/pg_restore round-trip and verify data is visible in the Coder UI. Docker is unavailable in this devcontainer environment."
---

# Phase 2: Backup & Restore Scripts Verification Report

**Phase Goal:** An operator can take a verified backup of the Coder database and restore it into a fresh instance without interactive prompts
**Verified:** 2026-06-17T08:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Running `scripts/backup.sh` produces a custom-format dump (`pg_dump -Fc`) in `./backups/` and exits `0`; reads all connection config from `.env` and requires no interactive input | VERIFIED | Script exists (111 lines, executable). `bash -n` passes. Contains: `pg_dump -Fc`, `--no-owner --no-acl`, `docker compose exec -T database`, `PGPASSWORD=` inline prefix, `set -a; source .env; set +a`, compose.yaml-mirroring defaults. `mkdir -p backups` creates the output directory. Zero-byte guard + `pg_restore --list /dev/stdin` integrity check + `chmod 600` all confirmed present. Cannot execute live (no Docker). |
| SC-2 | A backup produced by `backup.sh` restores cleanly into a freshly initialized database via `scripts/restore.sh` — post-restore, the Coder server starts and existing workspaces and users are visible | UNCERTAIN | `restore.sh` contains all required flags (`--clean --if-exists --no-owner --no-acl`, stdin redirect, stop/start lifecycle, EXIT trap). Static analysis passes. Cannot confirm data is visible in the UI without a live round-trip — this is the functional proof required by the SC. Routed to human verification. |
| SC-3 | Both scripts return non-zero exit codes on failure, making them safe for use with external schedulers | VERIFIED | `backup.sh`: `set -euo pipefail` + explicit `exit 1` on zero-byte dump and failed `pg_restore --list` check + `rm -f` of empty dump. `restore.sh`: `exit 1` on missing arg (`$# -lt 1`), missing file (`! -f`), zero-byte file (`! -s`); `set -euo pipefail` propagates `pg_restore` failures as non-zero. EXIT trap guarantees `docker compose start coder` on any exit. |

**Score:** 7/8 must-haves verified (1 truth routes to human for live round-trip; all static checks pass)

---

### Must-Have Truths (Plan Frontmatter — Combined)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `scripts/backup.sh` produces a custom-format dump in `./backups/` and exits 0 | VERIFIED | `pg_dump -Fc` → `${PROJECT_ROOT}/backups/coder-${TIMESTAMP}.dump`; `mkdir -p` ensures directory. `bash -n` exits 0. |
| 2 | `backup.sh` reads POSTGRES_USER/PASSWORD/DB from .env with no interactive input | VERIFIED | `set -a; source "${ENV_FILE}"; set +a` with `[[ -f ]]` guard. No `--password` flag present. `PGPASSWORD=` inline prefix on exec. |
| 3 | `backup.sh` exits non-zero when dump is empty or fails integrity check | VERIFIED | Zero-byte guard: `[[ ! -s "${DUMP_FILE}" ]]` → `rm -f "${DUMP_FILE}"; exit 1`. Integrity guard: `pg_restore --list /dev/stdin` failure → `exit 1`. `set -euo pipefail` catches unguarded failures. |
| 4 | Dump file is mode 600 | VERIFIED | `chmod 600 "${DUMP_FILE}"` executed immediately after `pg_dump` redirect completes (line 80). |
| 5 | `scripts/restore.sh` restores a backup.sh dump and exits 0 | UNCERTAIN | All flags and wiring confirmed statically. Live execution against a running Postgres container cannot be done here. Routed to human. |
| 6 | `restore.sh` stops the coder service before restoring and restarts it even if the restore fails | VERIFIED | `docker compose stop coder` (line 79), then `trap 'echo "Restarting coder service..."; docker compose start coder' EXIT` registered immediately after (line 85). Trap fires on any exit including `set -e` failures. |
| 7 | `restore.sh` validates its dump-file argument before doing anything destructive | VERIFIED | Argument validation (count, `-f`, `-s`) is at lines 34-50, which is BEFORE `.env` sourcing (line 57) and BEFORE `docker compose stop coder` (line 79). No service is touched on invalid input. |
| 8 | README documents the backup/restore operational workflow | VERIFIED | `## Backup & restore` section confirmed at line 240 of README.md. Contains: `scripts/backup.sh`, `scripts/restore.sh`, DESTRUCTIVE callout with `--clean` mention, cron example with absolute path, QOL-02 retention deferral note. Existing `## Upgrading from the quickstart` migration snippet untouched. |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/backup.sh` | Non-interactive `pg_dump -Fc` backup to `./backups/` | VERIFIED | Exists, 111 lines, executable (`-rwxr-xr-x`). `bash -n` exits 0. All mandatory flags confirmed. |
| `scripts/restore.sh` | Non-interactive `pg_restore --clean --if-exists` with stop/start coder + EXIT trap | VERIFIED | Exists, 111 lines, executable (`-rwxr-xr-x`). `bash -n` exits 0. All mandatory flags confirmed. |
| `README.md` | Operational Backup & restore section referencing `scripts/backup.sh` | VERIFIED | `## Backup & restore` section at line 240 with all required content confirmed. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/backup.sh` | `.env` | `set -a; source "${ENV_FILE}"; set +a` | WIRED | Confirmed at lines 31-38; guarded by `[[ -f "${ENV_FILE}" ]]`; `# shellcheck disable=SC1090` present. |
| `scripts/backup.sh` | `database` container | `docker compose exec -T database pg_dump -Fc` | WIRED | Confirmed at lines 66-74; `-T` flag present; `PGPASSWORD=` inline prefix; service name `database`. |
| `scripts/restore.sh` | `database` container | `docker compose exec -T database pg_restore --clean --if-exists` | WIRED | Confirmed at lines 100-109; all flags present; stdin redirect `< "${DUMP_FILE}"` at line 109. |
| `scripts/restore.sh` | coder service lifecycle | `docker compose stop coder` + `trap ... docker compose start coder EXIT` | WIRED | Stop at line 79; trap at line 85 immediately after stop (correct ordering per key-decisions). |
| `scripts/restore.sh` | dump produced by `scripts/backup.sh` | stdin redirect `< "${DUMP_FILE}"` | WIRED | Confirmed at line 109; NOT passed as a pg_restore filename argument (avoids #8909 pattern). |

---

### Data-Flow Trace (Level 4)

Not applicable. These are shell scripts, not components rendering dynamic data. All data flow is through shell variables and process substitution, verified at Level 3.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `backup.sh` has no syntax errors | `bash -n scripts/backup.sh` | exit 0 | PASS |
| `restore.sh` has no syntax errors | `bash -n scripts/restore.sh` | exit 0 | PASS |
| All backup.sh mandatory patterns present | `grep` for 21 patterns | 21/21 PASS | PASS |
| All restore.sh mandatory patterns present | `grep` for 23 patterns | 23/23 PASS | PASS |
| Live backup→restore round-trip | Requires Docker daemon | Not runnable in devcontainer | SKIP (human_verification) |

---

### Probe Execution

No probes declared in PLAN frontmatter. No `scripts/*/tests/probe-*.sh` files found. No probes to run.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BAK-01 | 02-01-PLAN.md | `scripts/backup.sh` produces a non-interactive custom-format dump (`pg_dump -Fc` via `docker compose exec -T`) written to a host path (`./backups/`) | SATISFIED | Script confirmed present with all required flags. `chmod 600` applied. Exit codes on failure confirmed. |
| BAK-02 | 02-02-PLAN.md | `scripts/restore.sh` restores a chosen dump safely (handles clean/recreate and role ownership), non-interactively | SATISFIED (static) | Script confirmed present with `--clean --if-exists --no-owner --no-acl`. EXIT trap confirmed. Functional data-visible-in-UI check is the human_verification item. |
| BAK-03 | 02-01-PLAN.md, 02-02-PLAN.md | Both scripts read configuration from `.env`, avoid interactive password prompts, and return meaningful exit codes | SATISFIED | Both scripts: `set -a; source .env; set +a`, `PGPASSWORD=` inline prefix, no `--password`, `set -euo pipefail`, explicit `exit 1` guards with stderr messages. |

All three requirement IDs declared in PLAN frontmatter are accounted for. REQUIREMENTS.md traceability table marks BAK-01, BAK-02, BAK-03 all as "Complete" under Phase 2. No orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/backup.sh` | — | No TBD/FIXME/XXX/TODO/PLACEHOLDER found | — | Clean |
| `scripts/restore.sh` | — | No TBD/FIXME/XXX/TODO/PLACEHOLDER found | — | Clean |

No debt markers, no placeholder text, no stub patterns, no hardcoded empty values. Both scripts are complete operational implementations.

---

### Human Verification Required

#### 1. Backup→Restore Round-Trip (Functional Proof of SC-2)

**Test:** On a host with Docker and the stack running:

1. `docker compose up -d` — wait for `docker compose ps` to show `database (healthy)` and `coder (healthy)`
2. Create recognizable state in the Coder UI at http://localhost:7080 (note the admin user and any workspace)
3. `./scripts/backup.sh` — confirm a non-empty `backups/coder-YYYYMMDD-HHMMSS.dump` exists, `echo $?` is `0`, and `ls -l backups/` shows mode `-rw-------` (600)
4. Wipe DB: `docker compose down && docker volume rm coder_coder_pgdata && docker compose up -d`; wait for `database (healthy)`
5. `./scripts/restore.sh ./backups/coder-YYYYMMDD-HHMMSS.dump` (real filename from step 3) — confirm `echo $?` is `0`
6. `docker compose ps` shows `coder` running; Coder UI shows the user/workspace from step 2

**Failure paths to verify:**

- `./scripts/restore.sh /nonexistent.dump` — must exit non-zero with an ERROR on stderr; `docker compose ps` must show `coder` still running (EXIT trap must NOT fire before `docker compose stop coder` runs — confirmed by argument-validation-first ordering in the script)
- `./scripts/backup.sh` with the stack down — must exit non-zero with a meaningful stderr message

**Expected:** All steps pass; post-restore Coder UI shows pre-backup data (users, workspaces visible)

**Why human:** Requires a live Docker daemon, a running Postgres container, and a reachable Coder UI to confirm data is visible after restore. Docker is unavailable in this devcontainer environment. This check cannot be fabricated.

---

### Gaps Summary

No gaps found. All statically verifiable must-haves pass. The single human_verification item (live round-trip) is the expected deployment-host check per the PLAN itself (02-02-PLAN.md Task 3 explicitly defers to `/gsd-verify-work` when Docker is unavailable). All three requirement IDs (BAK-01, BAK-02, BAK-03) are satisfied by the implementation evidence.

Status is `human_needed` because SC-2 (data visible in UI after restore) cannot be confirmed without a live stack. All automated checks pass at 7/8 scored truths, with truth 5 (restore exits 0 on a valid dump) being the live-execution item.

---

_Verified: 2026-06-17T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
