# Phase 2: Backup & Restore Scripts — Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 4 (2 new scripts + 1 new directory + 1 existing file to update)
**Analogs found:** 0 in-repo script analogs (net-new shell scripting layer) / 4 total files
**Convention anchors found:** compose.yaml, .gitignore, README.md (provide env var names, service names, command shapes, and documentation section style)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/backup.sh` | utility (backup) | batch / file-I/O | None — no existing shell scripts | no analog |
| `scripts/restore.sh` | utility (restore) | batch / file-I/O | None — no existing shell scripts | no analog |
| `backups/` (directory) | storage | file-I/O | `.gitignore` line 9: `backups/` already present | convention anchor |
| `README.md` (update) | documentation | n/a | `README.md` §"Upgrading from the quickstart" (lines 158–200) | section-style anchor |

**Note:** This repo contains no existing shell scripts. `scripts/backup.sh` and `scripts/restore.sh` are the first scripts in the repository. The planner must rely on RESEARCH.md patterns (already verified against official Postgres docs) rather than in-repo analogs for the script bodies. Where convention anchors exist (env var names, service names, command shapes, documentation section style), they are documented below with concrete excerpts.

---

## Pattern Assignments

### `scripts/backup.sh` (utility, batch/file-I/O)

**Analog:** No in-repo analog. Use RESEARCH.md `## Code Examples` > `backup.sh (complete skeleton)`.

**Convention anchor — env var names** (`compose.yaml` lines 10, 47–49):
```yaml
# Service name used in docker compose exec calls:
#   docker compose exec -T database ...
# (service name is "database", not "db" or "postgres")

environment:
  POSTGRES_USER: ${POSTGRES_USER:-username}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
  POSTGRES_DB: ${POSTGRES_DB:-coder}
```
Copy these exact variable names and defaults into the script's fallback lines:
```bash
POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"
```

**Convention anchor — docker compose v2 command shape** (`README.md` lines 169–171):
```bash
docker compose exec -T database \
  pg_dump -U "${POSTGRES_USER:-coder}" -Fc "${POSTGRES_DB:-coder}" > coder-migrate.dump
```
This is the only existing usage of `docker compose exec -T database` in the codebase. Mirror this shape exactly (v2 plugin syntax, `-T` flag, service name `database`).

**Convention anchor — gitignore** (`.gitignore` lines 8–9):
```
# Backup files (Phase 2 scripts will write here)
backups/
```
The `backups/` directory is already gitignored. `backup.sh` must write dumps to `./backups/` (relative to project root). The directory does not pre-exist — `backup.sh` must `mkdir -p` it.

**Core pattern** (from RESEARCH.md Pattern 1 + Pattern 2 + Pattern 3, confirmed against CLAUDE.md):
```bash
#!/usr/bin/env bash
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
```

**Verification pattern** (RESEARCH.md Pattern 4 — no in-repo analog):
```bash
if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi

if ! PGPASSWORD="${POSTGRES_PASSWORD}" \
     docker compose exec -T database \
       pg_restore --list /dev/stdin \
     < "${DUMP_FILE}" > /dev/null 2>&1; then
  echo "ERROR: Dump file failed integrity check: ${DUMP_FILE}" >&2
  exit 1
fi
```

**Security pattern** (RESEARCH.md Security Domain — ASVS V4):
```bash
chmod 600 "${DUMP_FILE}"
```
Apply immediately after the dump is written, before the size check.

---

### `scripts/restore.sh` (utility, batch/file-I/O)

**Analog:** No in-repo analog. Use RESEARCH.md `## Code Examples` > `restore.sh (complete skeleton)`.

**Convention anchor — service lifecycle commands** (`README.md` lines 222–228):
```bash
# Stop the stack (data volumes are preserved)
docker compose down

# Reset the Postgres database (destructive — wipes all workspaces, users, templates)
docker compose down
docker volume rm coder_coder_pgdata
```
The README uses `docker compose` (v2, no hyphen) throughout. `restore.sh` must use the same. For stop/start of a single service:
```bash
docker compose stop coder
docker compose start coder
```
Service name is `coder` (not `app`, `server`, or `coder-server`).

**Convention anchor — restore command shape** (`README.md` lines 175–178):
```bash
docker compose exec -T database \
  pg_restore -U "${POSTGRES_USER:-coder}" -d "${POSTGRES_DB:-coder}" \
  --clean --if-exists < coder-migrate.dump
```
The script must mirror this shape, adding `--no-owner --no-acl` (required by CLAUDE.md).

**Argument validation pattern** (RESEARCH.md Pattern 6 — no in-repo analog):
```bash
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dump-file>" >&2
  echo "Example: $0 ./backups/coder-20260617-120000.dump" >&2
  exit 1
fi

DUMP_FILE="$1"
[[ -f "${DUMP_FILE}" ]] || { echo "ERROR: File not found: ${DUMP_FILE}" >&2; exit 1; }
[[ -s "${DUMP_FILE}" ]] || { echo "ERROR: File is zero bytes: ${DUMP_FILE}" >&2; exit 1; }
```

**Stop-restore-start with EXIT trap pattern** (RESEARCH.md Pattern 5 — no in-repo analog):
```bash
cd "${PROJECT_ROOT}"

echo "Stopping coder service to release database connections..."
docker compose stop coder

# Trap ensures coder restarts even if pg_restore fails (set -e exits immediately on error)
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

### `backups/` directory

**No file to create** — the directory is created at runtime by `backup.sh` via `mkdir -p "${PROJECT_ROOT}/backups"`. The `.gitignore` entry already covers it (`.gitignore` line 9: `backups/`).

**Planner action:** Verify `.gitignore` line 9 is present (confirmed: it is). No file changes needed for gitignore.

---

### `README.md` (documentation update)

**Analog:** Existing README.md — mirror section structure and command block style.

**Convention anchor — section heading style** (`README.md` lines 1–236):
- H2 (`##`) for top-level sections
- H3 (`###`) for sub-sections
- Fenced bash code blocks for all commands
- Inline variable references use `\`` backtick-wrapped `` `VARIABLE_NAME` `` not angle brackets
- Tables use pipe syntax with a header separator row

**Convention anchor — existing backup command inline reference** (`README.md` lines 168–178):
```bash
# 1. While the OLD quickstart stack is still running, dump logically:
docker compose exec -T database \
  pg_dump -U "${POSTGRES_USER:-coder}" -Fc "${POSTGRES_DB:-coder}" > coder-migrate.dump
```
The new `## Backup & restore` section should document `scripts/backup.sh` and `scripts/restore.sh` using the same code block style. The existing inline `docker compose exec -T database pg_dump` snippet in §"Upgrading from the quickstart" should be left as-is (it's a one-off migration, not the backup script). Add a new top-level `##` section for operational backup/restore.

---

## Shared Patterns

### Bash safety header
**Apply to:** `scripts/backup.sh`, `scripts/restore.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
```
`set -euo pipefail` is mandatory — without `pipefail`, a failing `pg_dump` in a pipeline does not propagate a non-zero exit code. Without `-u`, unset `$POSTGRES_PASSWORD` silently becomes empty, causing auth failures with no useful error.

### .env sourcing
**Apply to:** `scripts/backup.sh`, `scripts/restore.sh`
```bash
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
```
`BASH_SOURCE[0]` resolves correctly when the script is called via an absolute path from cron. `$PWD`-relative resolution fails when cwd is `/` (default cron cwd). Do not use `export $(cat .env | xargs)` — breaks on values containing spaces or `$` characters.

### PGPASSWORD auth
**Apply to:** Every `docker compose exec` call that invokes `pg_dump` or `pg_restore`
```bash
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_dump ...
```
`PGPASSWORD` as an inline env prefix (not `export PGPASSWORD=...`) limits exposure to the single `exec` call. `-T` is mandatory on every `docker compose exec` that produces or consumes binary streams — omitting it corrupts the binary dump format.

### docker compose v2 command form
**Apply to:** All `docker compose` invocations in scripts
```bash
docker compose stop coder     # not: docker-compose stop coder
docker compose start coder    # not: docker-compose start coder
docker compose exec -T ...    # not: docker-compose exec -T ...
```
Source: CLAUDE.md "What NOT to Use" — `docker-compose` (v1, hyphenated) is EOL. `README.md` uses v2 syntax throughout.

### Variable defaults mirroring compose.yaml
**Apply to:** `scripts/backup.sh`, `scripts/restore.sh`

After sourcing `.env`, apply defaults that exactly match `compose.yaml` lines 47–49:
```bash
POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"
```
These mirror the `${VAR:-default}` fallbacks in `compose.yaml` exactly. Diverging defaults would cause scripts to connect to a different database than the live stack.

---

## No Analog Found

All script files in this phase are net-new with no in-repo analog:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/backup.sh` | utility | batch/file-I/O | No shell scripts exist in this repo; first script |
| `scripts/restore.sh` | utility | batch/file-I/O | No shell scripts exist in this repo; first script |

**For both scripts:** Use RESEARCH.md `## Code Examples` complete skeletons as the primary pattern source. They are verified against official Postgres documentation and CLAUDE.md conventions. The convention anchors above (env var names, service names, command shape) are extracted from the live codebase and take precedence over any discrepancy in RESEARCH.md.

---

## Critical Flag Checklist

Every `docker compose exec` in these scripts must pass this checklist before merging:

| Flag / Convention | `backup.sh` | `restore.sh` |
|-------------------|-------------|--------------|
| `-T` on `docker compose exec` | required | required |
| `PGPASSWORD=` prefix (not `--password`) | required | required |
| `-Fc` on `pg_dump` | required | n/a |
| `--no-owner --no-acl` | required | required |
| `--clean --if-exists` on `pg_restore` | n/a | required |
| Stdin redirect `< dump.file` (not filename arg) | n/a | required |
| `docker compose stop coder` before restore | n/a | required |
| `trap ... EXIT` for coder restart | n/a | required |
| `chmod 600 "$DUMP_FILE"` after write | required | n/a |
| `set -euo pipefail` | required | required |
| `set -a; source .env; set +a` | required | required |

---

## Metadata

**Convention anchor scope:** `/workspaces/coder/compose.yaml`, `/workspaces/coder/.gitignore`, `/workspaces/coder/README.md`
**Files scanned:** 4 (compose.yaml, .gitignore, README.md, RESEARCH.md)
**In-repo shell script analogs found:** 0
**Pattern extraction date:** 2026-06-17
