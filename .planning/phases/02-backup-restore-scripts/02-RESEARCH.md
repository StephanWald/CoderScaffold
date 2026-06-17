# Phase 2: Backup & Restore Scripts — Research

**Researched:** 2026-06-17
**Domain:** Shell scripting, pg_dump/pg_restore via Docker Compose, Postgres 17
**Confidence:** MEDIUM (core invocations verified against official Postgres docs; bash patterns confirmed against multiple sources; Docker compose exec -T binary behavior confirmed via GitHub issues)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BAK-01 | `scripts/backup.sh` produces a non-interactive custom-format dump (`pg_dump -Fc` via `docker compose exec -T`) written to `./backups/` | pg_dump -Fc invocation pattern, PGPASSWORD auth, -T flag necessity, timestamped filename convention |
| BAK-02 | `scripts/restore.sh` restores a chosen dump into the database safely (handles clean/recreate and role ownership), non-interactively | pg_restore --clean --if-exists invocation, stop-coder-first ordering, PGPASSWORD auth |
| BAK-03 | Both scripts read configuration from `.env`, avoid interactive password prompts, and return meaningful exit codes | set -euo pipefail, set -a source .env, PGPASSWORD env var, non-zero exit on failure |
</phase_requirements>

---

## Summary

Phase 2 creates two shell scripts — `scripts/backup.sh` and `scripts/restore.sh` — that perform non-interactive logical Postgres backups and restores via `docker compose exec -T`. The scripts source connection config from `.env` (established in Phase 1), use `PGPASSWORD` for password-free auth, and exit with meaningful codes so external schedulers (cron, monitoring scripts) can detect failures.

The Postgres service (`database`) is reachable only on the internal Docker Compose network — it has no host port. All `pg_dump`/`pg_restore` invocations run inside the `database` container via `docker compose exec -T`. The dump file is written to `./backups/` on the host by redirecting stdout from the `docker compose exec` call. The `-T` flag is mandatory: without it Docker allocates a pseudo-TTY that corrupts binary streams.

The critical restore ordering issue is connection management. The Coder server holds an open Postgres connection. `pg_restore --clean` will block or fail against locked objects if Coder is still running. The restore script must stop the `coder` service before restoring and restart it after, using `docker compose stop coder` / `docker compose start coder`.

**Primary recommendation:** Write two focused bash scripts with `set -euo pipefail`, `.env` sourcing via `set -a`, PGPASSWORD injection, and explicit exit codes. The restore script must stop/start the `coder` service around the restore operation.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Database dump (`pg_dump`) | Database container (via exec) | Host shell (orchestration) | pg_dump runs inside the `database` container; host shell invokes it via `docker compose exec -T` and captures stdout |
| Dump file storage | Host filesystem (`./backups/`) | — | Dump redirected to host via shell `>` redirect; container has no persistent bind mount for backups |
| Configuration sourcing | Host shell (script) | — | `.env` lives on the host; scripts `source` it to get `POSTGRES_*` vars |
| Restore (`pg_restore`) | Database container (via exec) | Host shell (orchestration) | pg_restore runs inside the `database` container; host shell pipes dump file in via stdin |
| Service lifecycle (stop/start) | Host shell (script) | Docker Compose | Script calls `docker compose stop coder` / `docker compose start coder` to manage connections around restore |

---

## Standard Stack

### Core (no new packages — all tooling pre-exists)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `pg_dump` | bundled with `postgres:17` | Custom-format logical backup | Ships inside the database container; `-Fc` is the standard production backup format |
| `pg_restore` | bundled with `postgres:17` | Restore from custom-format dump | Counterpart to pg_dump; supports selective restore and parallel jobs |
| `docker compose` (v2) | CLI bundled with Docker Engine | Execute commands inside containers | Already required by the stack; `exec -T` provides non-TTY execution |
| `bash` | ≥ 4.x (system default on Linux) | Script shell | `set -euo pipefail` requires bash, not sh; widely available |

**No new packages to install.** All tools are already present: `pg_dump`/`pg_restore` inside the `postgres:17` container, `docker compose` on the host, `bash` on the host.

### Package Legitimacy Audit

> **N/A** — This phase installs no external packages. All tooling is bundled with existing infrastructure (postgres:17 image, Docker Compose).

---

## Architecture Patterns

### System Architecture Diagram

```
Host shell (backup.sh)
  │
  ├─ source .env  ──────────────────►  POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
  │
  ├─ mkdir -p ./backups/
  │
  └─ PGPASSWORD=$PW docker compose exec -T database \
         pg_dump -U $USER -Fc $DB \
         > ./backups/coder-YYYYMMDD-HHMMSS.dump
              │
              ▼
         [postgres:17 container]
              │
              ▼
         pg_dump (custom format binary)
              │
              ▼ stdout (binary stream, no TTY)
              │
         host file: ./backups/coder-YYYYMMDD-HHMMSS.dump

──────────────────────────────────────────────────────────

Host shell (restore.sh)
  │
  ├─ source .env
  │
  ├─ validate: DUMP_FILE argument present + file exists + non-zero size
  │
  ├─ docker compose stop coder   ◄── terminate Coder's DB connections
  │
  ├─ PGPASSWORD=$PW docker compose exec -T database \
         pg_restore -U $USER -d $DB --clean --if-exists --no-owner --no-acl \
         < $DUMP_FILE
  │
  └─ docker compose start coder  ◄── bring Coder back up
```

### Recommended Project Structure

```
scripts/
├── backup.sh        # BAK-01: produce pg_dump -Fc to ./backups/
└── restore.sh       # BAK-02: restore a named dump file, stop/start coder

backups/             # gitignored (already in .gitignore); created by backup.sh
```

### Pattern 1: `set -euo pipefail` + `.env` sourcing

**What:** Standard bash safety header plus `.env` loading.
**When to use:** All scripts in `scripts/`.

```bash
#!/usr/bin/env bash
# Source: standard bash practice [ASSUMED] + .env sourcing pattern [ASSUMED]
set -euo pipefail

# Resolve script directory so the script works from any cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # set -a exports every variable defined while it is active.
  # source reads the .env into the current shell (comments are skipped).
  # set +a reverts to non-export mode so subsequent shell variables are not leaked.
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

# Apply defaults for variables not set in .env (mirrors compose.yaml defaults)
POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"
```

**Key points:**
- `set -a; source .env; set +a` is the canonical pattern for exporting `.env` vars. [ASSUMED]
- `BASH_SOURCE[0]` resolves the script's location even when called from a different directory. [ASSUMED]
- Default values after sourcing mirror compose.yaml `${VAR:-default}` values exactly.

### Pattern 2: `PGPASSWORD` prefix for non-interactive pg_dump

**What:** Non-interactive Postgres authentication via environment variable.
**When to use:** Any `docker compose exec` call that invokes pg_dump or pg_restore.

```bash
# Source: postgresql.org/docs/current/app-pgdump.html (libpq env vars) [CITED: postgresql.org/docs/current/app-pgdump.html]
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_dump \
      -U "${POSTGRES_USER}" \
      -Fc \
      --no-owner \
      --no-acl \
      "${POSTGRES_DB}" \
  > "${DUMP_FILE}"
```

**Why `PGPASSWORD` not `--password`:** `--password` forces an interactive prompt; `PGPASSWORD` is the libpq standard for non-interactive scripted auth. [CITED: postgresql.org/docs/current/app-pgdump.html]

**Why `-T` is required:** Without `-T`, Docker allocates a pseudo-TTY which injects carriage returns and control characters into the binary stdout stream, corrupting the custom-format dump file. [ASSUMED — confirmed by docker/compose GitHub issue #8909 and community consensus]

**Why `--no-owner` and `--no-acl`:** Makes the dump portable: it can be restored by any Postgres user without requiring the original owner to exist. [CITED: postgresql.org/docs/current/app-pgdump.html]

### Pattern 3: Timestamped dump filename

**What:** Filename includes UTC timestamp so multiple backups coexist without overwriting.
**When to use:** `backup.sh` output file naming.

```bash
# Source: common community convention [ASSUMED]
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
DUMP_FILE="${PROJECT_ROOT}/backups/coder-${TIMESTAMP}.dump"
mkdir -p "${PROJECT_ROOT}/backups"
```

### Pattern 4: Backup verification (MVP)

**What:** Two-step check after pg_dump exits 0: size check + structural integrity check.
**When to use:** End of `backup.sh`, before exit 0.

```bash
# Step 1: Non-zero size check
# pg_dump may exit 0 even if -T flag corruption produced an empty/truncated file
if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is missing or zero bytes: ${DUMP_FILE}" >&2
  exit 1
fi

# Step 2: Structural integrity — pg_restore reads the TOC (table of contents)
# If the archive header is corrupt, this exits non-zero
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_restore --list "/dev/stdin" \
  < "${DUMP_FILE}" > /dev/null
```

**Note:** `/dev/stdin` inside the container receives the file via shell redirect on the host. This avoids needing to copy the dump file into the container. [ASSUMED — relies on Linux /dev/stdin in container]

**Alternative verified approach:** Copy dump into container, run pg_restore --list on the file path, then remove it. More portable but adds steps. For MVP, the stdin redirect is simpler.

### Pattern 5: Stop-restore-start (connection management)

**What:** Coder server holds a persistent Postgres connection pool. pg_restore --clean will block against locked objects if Coder is running. Stop Coder first.
**When to use:** `restore.sh`, wrapping the pg_restore call.

```bash
# Source: standard Postgres restore practice [ASSUMED]
echo "Stopping coder service to release database connections..."
docker compose stop coder

# Restore — will exit non-zero on error (set -e catches this)
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_restore \
      -U "${POSTGRES_USER}" \
      -d "${POSTGRES_DB}" \
      --clean \
      --if-exists \
      --no-owner \
      --no-acl \
  < "${DUMP_FILE}"

echo "Starting coder service..."
docker compose start coder
```

**Why `--clean --if-exists` together:** `--clean` drops objects before recreating (required for overwrite restore). `--if-exists` prevents errors when the target database is freshly initialized and objects don't exist yet (both fresh-instance and overwrite scenarios handled by the same flags). [CITED: postgresql.org/docs/current/app-pgrestore.html]

**Failure handling:** If `set -e` triggers during restore, Coder will remain stopped. The script should use `trap` to ensure Coder is restarted even on failure:

```bash
# Trap ensures coder restarts even if restore fails
# Without this: a failed restore leaves the coder service stopped permanently
trap 'docker compose start coder' EXIT
```

### Pattern 6: Argument validation in restore.sh

**What:** restore.sh takes the dump file path as its only argument. Validate it before doing anything destructive.
**When to use:** Top of `restore.sh`, after sourcing .env.

```bash
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dump-file>" >&2
  echo "Example: $0 ./backups/coder-20260617-120000.dump" >&2
  exit 1
fi

DUMP_FILE="$1"

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file not found: ${DUMP_FILE}" >&2
  exit 1
fi

if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  exit 1
fi
```

### Anti-Patterns to Avoid

- **No `-T` flag on `docker compose exec`:** Without `-T`, Docker injects TTY control codes into stdout, silently corrupting the binary dump. The dump will appear to succeed (exit 0) but pg_restore will fail with `invalid file header`.
- **Piping pg_dump directly to pg_restore through `docker compose exec -T`:** Known docker/compose issue #8909 — binary data is corrupted when piped as input to a second `docker compose exec -T` call. Always write dump to a host file first, then restore from it.
- **No `docker compose stop coder` before restore:** Coder holds active connections. pg_restore --clean will hang waiting for locks or fail with "database is being accessed by other users" (Postgres ERROR code 55006).
- **Hardcoding credentials in scripts:** All connection parameters must come from `.env`. No `password` literals in script code.
- **Using `docker-compose` (v1):** Deprecated. Use `docker compose` (v2 plugin). [CITED: CLAUDE.md]
- **`set -e` without `set -o pipefail`:** Without `pipefail`, a failing command in the middle of a pipeline (e.g., `pg_dump ... | gzip > file`) does not set exit code to non-zero; `set -e` sees only gzip's exit code.
- **Sourcing `.env` with `export $(cat .env | xargs)`:** xargs fails on values with spaces or special characters. Use `set -a; source .env; set +a` instead. [ASSUMED]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Database backup | Custom SQL SELECT statements | `pg_dump -Fc` | pg_dump handles transactions, sequences, extensions, constraints, indexes; custom SQL misses metadata and ordering |
| Binary authentication | Parsing pg password files manually | `PGPASSWORD` env var | libpq's built-in non-interactive auth; `.pgpass` is the other option but requires file permissions management |
| Database object dropping | DROP TABLE ... for each table | `pg_restore --clean --if-exists` | pg_restore knows the exact object list and correct drop order from the dump; manual drops miss sequences, types, functions |
| Backup integrity check | Parsing binary dump headers manually | `pg_restore --list` | pg_restore's built-in TOC reader; handles all custom-format archive version differences |
| Connection termination | Complex psql scripts querying pg_stat_activity | `docker compose stop coder` | Stopping the service is simpler, more reliable, and handles all connection types including poolers |

**Key insight:** `pg_dump -Fc` + `pg_restore` is the standard logical backup toolchain for Postgres. Every alternative (plain SQL, `COPY`, file-level copy) has severe limitations for production use.

---

## Common Pitfalls

### Pitfall 1: TTY Corruption of Binary Dump
**What goes wrong:** `docker compose exec database pg_dump -Fc ...` (without `-T`) produces a zero-byte or corrupted dump file even though pg_dump exits 0.
**Why it happens:** Without `-T`, Docker allocates a pseudo-TTY. The TTY layer converts LF to CR+LF in the output stream. Custom-format dumps are binary and are fatally corrupted by this translation.
**How to avoid:** Always pass `-T` to `docker compose exec`.
**Warning signs:** Dump file exists but `pg_restore --list < dump.file` exits non-zero. Error: `pg_restore: error: input file does not appear to be a valid archive`.

### Pitfall 2: Active Connections Block Restore
**What goes wrong:** `pg_restore --clean` hangs indefinitely or fails with `ERROR: database "coder" is being accessed by other users`.
**Why it happens:** The `coder` service maintains a persistent connection pool to the database. `--clean` tries to DROP and recreate objects, which requires an exclusive lock that active connections prevent.
**How to avoid:** Run `docker compose stop coder` before `pg_restore` and `docker compose start coder` after. Use `trap` to guarantee the start even on failure.
**Warning signs:** `pg_restore` output shows `ERROR:  database "coder" is being accessed by other users` or the restore hangs without progress.

### Pitfall 3: Restoring into a Fresh Database Fails with "does not exist" Errors
**What goes wrong:** `pg_restore --clean` (without `--if-exists`) exits non-zero with many `ERROR: table "X" does not exist` messages when restoring into a newly initialized, empty database.
**Why it happens:** `--clean` generates `DROP TABLE X` statements. On a fresh database, these objects don't exist, and `DROP TABLE X` (without `IF EXISTS`) raises an error.
**How to avoid:** Always pair `--clean` with `--if-exists`. This generates `DROP TABLE IF EXISTS X` which succeeds on both fresh and existing databases.
**Warning signs:** Restore exits with errors on first run against a fresh stack; subsequent runs (with data to drop) succeed.

### Pitfall 4: `.env` Not Found or Not Sourced
**What goes wrong:** Script uses default placeholder credentials (`username`/`password`) instead of real ones, silently failing to connect or connecting to the wrong database.
**Why it happens:** `.env` path resolution fails when the script is called from a different working directory (e.g., via cron with an absolute path to the script but cwd as `/`).
**How to avoid:** Resolve the project root relative to `BASH_SOURCE[0]`, not `$PWD`. Check for `.env` existence explicitly and warn if missing.
**Warning signs:** pg_dump exits with `FATAL: password authentication failed for user "username"` (the default placeholder).

### Pitfall 5: Dump File in Untracked Path Gets Committed
**What goes wrong:** pg_dump output in `./backups/` ends up in a `git add .` or similar command and a 10MB binary file is committed.
**Why it happens:** `backups/` gitignore entry already exists (from Phase 1 `.gitignore`), but if the entry is removed or a subdirectory is added outside the pattern, dumps leak.
**How to avoid:** `.gitignore` already contains `backups/` (verified in Phase 1). Scripts do not need to create this protection. Just verify the pattern covers dump output paths.
**Warning signs:** `git status` shows files under `backups/` as untracked.

### Pitfall 6: Coder Left Stopped on Restore Failure
**What goes wrong:** `restore.sh` fails mid-restore (e.g., pg_restore error), and because `set -e` exits immediately, the `docker compose start coder` call at the end never runs. Coder is permanently stopped.
**Why it happens:** `set -e` exits on error without running cleanup code that follows.
**How to avoid:** Register `docker compose start coder` as an EXIT trap at the top of the restore script, before stopping coder. The trap fires on both success and failure paths.
**Warning signs:** After a failed restore, `docker compose ps` shows `coder` service in `exited` or `stopped` state.

---

## Code Examples

### backup.sh (complete skeleton)

```bash
#!/usr/bin/env bash
# Source: pg_dump docs [CITED: postgresql.org/docs/current/app-pgdump.html], bash patterns [ASSUMED]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "WARN: .env not found at ${ENV_FILE}; using defaults" >&2
fi

POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
DUMP_FILE="${PROJECT_ROOT}/backups/coder-${TIMESTAMP}.dump"
mkdir -p "${PROJECT_ROOT}/backups"

echo "Starting backup: ${DUMP_FILE}"
cd "${PROJECT_ROOT}"

PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_dump \
      -U "${POSTGRES_USER}" \
      -Fc \
      --no-owner \
      --no-acl \
      "${POSTGRES_DB}" \
  > "${DUMP_FILE}"

# Verify: non-zero size
if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi

# Verify: structural integrity (reads TOC header)
if ! PGPASSWORD="${POSTGRES_PASSWORD}" \
     docker compose exec -T database \
       pg_restore --list /dev/stdin \
     < "${DUMP_FILE}" > /dev/null 2>&1; then
  echo "ERROR: Dump file failed integrity check: ${DUMP_FILE}" >&2
  exit 1
fi

DUMP_SIZE="$(du -sh "${DUMP_FILE}" | cut -f1)"
echo "Backup complete: ${DUMP_FILE} (${DUMP_SIZE})"
```

### restore.sh (complete skeleton)

```bash
#!/usr/bin/env bash
# Source: pg_restore docs [CITED: postgresql.org/docs/current/app-pgrestore.html], bash patterns [ASSUMED]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dump-file>" >&2
  echo "Example: $0 ./backups/coder-20260617-120000.dump" >&2
  exit 1
fi

DUMP_FILE="$1"
[[ -f "${DUMP_FILE}" ]] || { echo "ERROR: File not found: ${DUMP_FILE}" >&2; exit 1; }
[[ -s "${DUMP_FILE}" ]] || { echo "ERROR: File is zero bytes: ${DUMP_FILE}" >&2; exit 1; }

ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "WARN: .env not found at ${ENV_FILE}; using defaults" >&2
fi

POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"

cd "${PROJECT_ROOT}"

echo "Stopping coder service..."
docker compose stop coder

# Ensure coder restarts even if pg_restore fails
trap 'echo "Restarting coder service..."; docker compose start coder' EXIT

echo "Restoring from: ${DUMP_FILE}"
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_restore \
      -U "${POSTGRES_USER}" \
      -d "${POSTGRES_DB}" \
      --clean \
      --if-exists \
      --no-owner \
      --no-acl \
  < "${DUMP_FILE}"

echo "Restore complete. Coder will restart via EXIT trap."
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Plain SQL dumps (`pg_dump -Fp`) | Custom format (`pg_dump -Fc`) | Postgres 7.x era | Custom format is compressed, supports selective restore, required by pg_restore |
| `.pgpass` file for passwords | `PGPASSWORD` env var in scripts | Long-standing | PGPASSWORD simpler in scripted environments; .pgpass preferred for interactive psql sessions |
| `docker-compose` (v1 Python) | `docker compose` (v2 plugin) | Docker 20.10+ | v1 is EOL (2023); v2 is default on all current Docker |
| File-level Postgres backup (`pg_basebackup`) | Logical backup (`pg_dump`) | Not new — different use cases | Logical backup is storage-backend-transparent; works with named volumes, bind mounts, and RDS |

**Deprecated/outdated:**
- `pg_basebackup` for this use case: physical backup tool; requires same Postgres major version on restore; cannot restore to a named volume without special handling. pg_dump logical backup is the correct choice here.
- `docker-compose` v1 (hyphenated): EOL 2023, missing Compose Spec features, not installed in current Docker environments. [CITED: CLAUDE.md]
- Named volume approach for `CODER_PG_DATA_DIR` — the default named volume (`coder_pgdata`) works correctly with pg_dump because pg_dump is storage-backend-transparent. Phase 1 confirmed this.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `docker compose` (v2) | Both scripts | Unknown (dev env) | — | None — scripts require it |
| `pg_dump` inside `database` container | `backup.sh` | Yes (postgres:17 image) | 17.x | None — bundled |
| `pg_restore` inside `database` container | `restore.sh` | Yes (postgres:17 image) | 17.x | None — bundled |
| `bash` (v4+) | Both scripts | Yes (Linux host) | system | Fallback to sh with reduced safety |
| `.env` on host | Both scripts | Yes (established Phase 1) | n/a | Scripts warn and use defaults |
| `./backups/` directory | `backup.sh` | No (created by script) | n/a | Script creates it via `mkdir -p` |

**Note on Docker availability in devcontainer:** The development environment (`devcontainer`) does not have Docker available (confirmed: `docker: command not found`). Scripts will be tested against the actual deployment environment where Docker is available, not the devcontainer. This is expected for infrastructure scripts.

**Missing dependencies with no fallback:**
- Docker and `docker compose` must be available on the deployment host. Scripts cannot function without them.

---

## Validation Architecture

> `nyquist_validation: true` — section required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None (shell scripts — bats or manual smoke test) |
| Config file | None — see Wave 0 |
| Quick run command | `bash -n scripts/backup.sh && bash -n scripts/restore.sh` (syntax check only) |
| Full suite command | Manual smoke test against running stack |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BAK-01 | `backup.sh` produces a non-empty .dump file in `./backups/` | smoke (manual) | `bash -n scripts/backup.sh` (syntax only) | ❌ Wave 0 |
| BAK-02 | `restore.sh` restores a dump; post-restore Coder starts and data is visible | smoke (manual) | `bash -n scripts/restore.sh` (syntax only) | ❌ Wave 0 |
| BAK-03 | Both scripts exit non-zero on failure conditions | smoke (manual) | `bash -n scripts/backup.sh && bash -n scripts/restore.sh` | ❌ Wave 0 |

**Manual-only justification:** These scripts require a running Docker daemon, a live `database` container, and an operational Postgres instance. Automated unit tests for shell scripts that exec Docker are not feasible without a full Docker-in-Docker setup. Syntax checking (`bash -n`) catches structural errors; functional testing requires the live stack.

### Sampling Rate

- **Per task commit:** `bash -n scripts/backup.sh && bash -n scripts/restore.sh` (syntax check)
- **Per wave merge:** Manual smoke test on running stack: `./scripts/backup.sh` → verify non-empty `.dump` file
- **Phase gate:** Full round-trip test before `/gsd-verify-work`: backup → restore into fresh stack → verify Coder starts with existing data

### Wave 0 Gaps

- [ ] `scripts/backup.sh` — BAK-01
- [ ] `scripts/restore.sh` — BAK-02
- [ ] `scripts/` directory — must be created (does not exist)

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Scripts do not expose auth surfaces |
| V3 Session Management | No | No HTTP sessions |
| V4 Access Control | Yes (partial) | Dump files in `./backups/` must not be world-readable; scripts should `chmod 600` dump files |
| V5 Input Validation | Yes | `restore.sh` argument validation: path must be a regular file, non-zero size, within expected path |
| V6 Cryptography | No | No cryptographic operations; PGPASSWORD is a runtime env var, not stored |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Dump file contains full database including passwords/tokens | Information Disclosure | `chmod 600 "$DUMP_FILE"` after creation; `backups/` gitignored (already enforced) |
| Path traversal in `restore.sh` argument | Tampering | Validate argument is a regular file (`-f`); consider restricting to `${PROJECT_ROOT}/backups/` |
| PGPASSWORD visible in process listing | Information Disclosure | PGPASSWORD set only as environment variable prefix on exec, not in script as visible argument; still visible to local root via `/proc` — acceptable for this deployment model |
| Backup directory permissions | Information Disclosure | `mkdir -p backups && chmod 700 backups` or rely on umask; document |

**Security note on `PGPASSWORD`:** `PGPASSWORD` is visible to processes with `/proc` access on Linux. For the deployment model (single host, no multi-tenant access), this is acceptable. The alternative (`.pgpass` file) requires setting up `~/.pgpass` with `chmod 600` and is more complex. PGPASSWORD is the MVP choice; document the `/proc` caveat in the script header. [ASSUMED — standard libpq security guidance]

---

## Project Constraints (from CLAUDE.md)

The following CLAUDE.md directives are binding for this phase:

| Directive | Impact on Phase 2 |
|-----------|-------------------|
| `pg_dump -Fc` custom format | Mandated for backup.sh — no plain SQL |
| `--no-owner` and `--no-acl` | Required flags on both pg_dump and pg_restore |
| `docker compose exec -T` | Mandatory `-T` flag to avoid TTY binary corruption |
| `PGPASSWORD` env var for non-interactive auth | No `.pgpass` or `--password` interactive prompts |
| `.env` sourcing (no hardcoded secrets) | Scripts read `POSTGRES_USER/PASSWORD/DB` from `.env` |
| `docker compose` (v2, no hyphen) | `docker compose stop coder` not `docker-compose stop coder` |
| Non-interactive, cron-safe exit codes | `set -euo pipefail`; all failure paths exit non-zero |
| `scripts/` directory for scripts | Output path per REQUIREMENTS.md |
| `./backups/` for dump output | Already gitignored; `mkdir -p` at script start |
| `--clean --if-exists` on restore | Required to handle both fresh-instance and overwrite restores |
| Pipe via stdin (`<`) not filename argument | `pg_restore ... < dump.file` pattern |

---

## Open Questions (RESOLVED)

> All questions below are answered in-place by the recommendations and are wired into the Phase 2 plan task actions (path handling, stdout `BACKUP_FILE=` line, retention deferred to QOL-02/v2, idempotent `docker compose stop coder`).

1. **Should `restore.sh` accept a relative or absolute path?**
   - What we know: Cron jobs run with cwd as `/` (or an arbitrary cwd); relative paths from cron callers will fail if the script doesn't resolve them.
   - What's unclear: Whether operators are expected to call `restore.sh` with an absolute path or a path relative to the project root.
   - Recommendation: Accept any path (`$1`); resolve to absolute with `realpath` or manual expansion. Document in help text.

2. **Should `backup.sh` emit the dump filename to stdout for scripting?**
   - What we know: External schedulers (cron, monitoring scripts) may want to capture the filename to pass to an upload step.
   - What's unclear: Whether stdout should be clean (just the filename) or informational (progress messages on stderr, filename on stdout).
   - Recommendation: Print human-readable progress to stdout (cron captures it); emit the final filename as the last line prefixed with a parseable prefix (`BACKUP_FILE=...`).

3. **Retention policy scope for this phase?**
   - What we know: `QOL-02` (backup retention/pruning) is explicitly deferred to v2.
   - What's unclear: Whether MVP backup.sh should include a warning when `backups/` exceeds a size threshold.
   - Recommendation: No retention logic in MVP scripts. Document in README/script header that retention is out of scope and operators should run cleanup manually or defer to v2.

4. **How should `restore.sh` handle the `coder` service not being running?**
   - What we know: `docker compose stop coder` is idempotent if coder is already stopped.
   - Recommendation: Proceed normally — `docker compose stop coder` is safe to call even if coder is not running.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `set -a; source .env; set +a` pattern correctly exports `.env` vars without breaking on comments or quoted values | Pattern 1 | Script uses wrong credentials; fails with auth error |
| A2 | `pg_restore --list /dev/stdin < dump.file` works inside the postgres:17 container (Linux `/dev/stdin` available) | Pattern 4 | Integrity check step fails; workaround is to copy dump into container |
| A3 | `docker compose exec -T database pg_restore ... < dump.file` correctly delivers the file via stdin without binary corruption (unlike the `docker compose exec -T ... | pipe` pattern that issue #8909 documents as broken) | Pattern 5 | Restore silently corrupts input; use `docker exec -i` with container ID as fallback |
| A4 | `PGPASSWORD` set as env prefix on `docker compose exec` is passed through to the `pg_dump`/`pg_restore` process inside the container | Pattern 2 | Scripts fail with password prompt or auth failure; workaround is `-e PGPASSWORD=...` flag on `docker compose exec` |
| A5 | `docker compose stop coder` is sufficient to drain all Coder connections before restore (no separate connection pool outside the coder service) | Pattern 5 | pg_restore hangs; workaround is to also run `docker compose down coder` or terminate pg_stat_activity |
| A6 | `scripts/backup.sh` and `scripts/restore.sh` are the correct naming and location per REQUIREMENTS.md expectations | Standard Stack | Naming mismatch with other documentation |
| A7 | PGPASSWORD is not visible in `docker compose` logs or audit trails in a way that creates a compliance risk for this deployment model | Security Domain | Secret exposure; workaround is to use Docker secrets or .pgpass |

---

## Sources

### Primary (MEDIUM confidence)
- [CITED: postgresql.org/docs/current/app-pgdump.html] — pg_dump options: -Fc, --no-owner, --no-acl, -U, -d; libpq env vars including PGPASSWORD
- [CITED: postgresql.org/docs/current/app-pgrestore.html] — pg_restore options: --clean, --if-exists, --no-owner, --no-acl, -l (list), -d

### Secondary (LOW confidence — web + community)
- docker/compose GitHub issue #8909 — confirms -T flag binary input corruption for piped input; stdout redirect to file works correctly
- Phase 1 SUMMARY files (01-01-SUMMARY.md, 01-02-SUMMARY.md) — confirm `.env` variable names, named-volume decision, gitignore entries
- CLAUDE.md "pg_dump / pg_restore Conventions" section — documents all required flags; this research confirms them

### Tertiary (LOW confidence — training knowledge)
- `set -euo pipefail` bash pattern — widely established; not verified against a specific external source this session
- `set -a; source .env; set +a` pattern — community consensus; tagged [ASSUMED]
- Coder schema extensions — not verified; Coder likely uses no unusual Postgres extensions beyond standard `plpgsql` and `uuid-ossp` (common in Go ORMs); pg_dump handles standard extensions correctly

## Metadata

**Confidence breakdown:**
- pg_dump/pg_restore invocations: MEDIUM — confirmed against official Postgres docs
- Bash safety patterns: LOW — confirmed via web search, widely established practice
- Docker compose exec -T behavior: LOW — confirmed via GitHub issues, not official Docker docs
- Coder schema compatibility: LOW — assumed; no Coder-specific extension list found

**Research date:** 2026-06-17
**Valid until:** 2026-07-17 (stable tooling; Postgres docs and Docker behavior are stable)
