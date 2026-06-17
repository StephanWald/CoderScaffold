#!/usr/bin/env bash
# scripts/restore.sh — Non-interactive pg_restore from a backup.sh dump into the database
#
# Usage: ./scripts/restore.sh <dump-file>
# Example: ./scripts/restore.sh ./backups/coder-20260617-120000.dump
#
# DESTRUCTIVE: --clean drops all existing objects in the target database before
# recreating them from the dump. Verify you are targeting the correct stack/DB
# before running — data that is not in the dump will be permanently lost.
#
# Reads connection config from .env (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB).
# Falls back to compose.yaml defaults (username/password/coder) if .env is absent.
#
# Security note: PGPASSWORD is passed as an inline env prefix on the docker compose exec
# call. It is visible to local root via /proc on Linux. For this single-host deployment
# model this is acceptable — consistent with backup.sh (T-02-07).
#
# Exit codes:
#   0  — restore completed successfully; coder service restarted
#   1  — invalid argument, file not found/empty, or pg_restore failed; coder service
#         restarted via EXIT trap even on failure
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution — works correctly when called via an absolute path from cron
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Argument validation — must happen BEFORE sourcing .env or stopping services
# Mitigates T-02-05: unvalidated dump-file argument (ASVS V5 input validation)
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dump-file>" >&2
  echo "Example: $0 ./backups/coder-20260617-120000.dump" >&2
  exit 1
fi

DUMP_FILE="$1"

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file not found or is not a regular file: ${DUMP_FILE}" >&2
  exit 1
fi

if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Source .env — canonical set -a pattern (safe on values with spaces or $)
# Do NOT use: export $(cat .env | xargs)
# ---------------------------------------------------------------------------
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "WARN: .env not found at ${ENV_FILE}; using defaults" >&2
fi

# Apply defaults that mirror compose.yaml exactly (lines 47-49)
POSTGRES_USER="${POSTGRES_USER:-username}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-password}"
POSTGRES_DB="${POSTGRES_DB:-coder}"

# Change to project root so docker compose finds compose.yaml
cd "${PROJECT_ROOT}"

# ---------------------------------------------------------------------------
# Stop Coder to release its connection pool before pg_restore --clean
# (Pitfall 2: active connections block --clean; RESEARCH.md Pattern 5)
# ---------------------------------------------------------------------------
echo "Stopping coder service to release database connections..."
docker compose stop coder

# ---------------------------------------------------------------------------
# EXIT trap: restart coder even if pg_restore fails under set -e (Pitfall 6)
# Registered immediately after stop so any failure path still restarts coder.
# ---------------------------------------------------------------------------
trap 'echo "Restarting coder service..."; docker compose start coder' EXIT

# ---------------------------------------------------------------------------
# Run pg_restore
# --clean --if-exists: drop existing objects before recreating (handles both
#   fresh-DB and overwrite scenarios — Pitfall 3; both flags required together)
# --no-owner --no-acl: makes restore portable across DB users (CLAUDE.md)
# -T: mandatory — without it Docker allocates a pseudo-TTY that corrupts
#     the binary stdin stream (same issue as pg_dump -T)
# Restore reads the dump from stdin (< "${DUMP_FILE}"), NOT as a pg_restore
# filename argument — avoids the broken docker/compose exec pipe pattern (#8909)
# PGPASSWORD: non-interactive auth via libpq env var (never use the interactive prompt flag)
# Service name: "database" for exec; "coder" for stop/start (compose.yaml)
# ---------------------------------------------------------------------------
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
