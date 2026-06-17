#!/usr/bin/env bash
# scripts/backup.sh — Non-interactive pg_dump -Fc backup to ./backups/
#
# Usage: ./scripts/backup.sh
#
# Reads connection config from .env (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB).
# Falls back to compose.yaml defaults (username/password/coder) if .env is absent.
#
# Security note: PGPASSWORD is passed as an inline env prefix on the docker compose exec
# call. It is visible to local root via /proc on Linux. For this single-host deployment
# model this is acceptable — documented here per RESEARCH.md Security Domain guidance.
# Retention/pruning of old backups is out of scope (QOL-02, deferred to v2).
#
# Exit codes:
#   0  — backup completed successfully, dump file integrity verified
#   1  — dump is zero bytes, fails integrity check, or pg_dump itself fails
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution — works correctly when called via an absolute path from cron
# (cron runs with cwd=/; $PWD-relative resolution would fail)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# ---------------------------------------------------------------------------
# Build output path — UTC timestamp ensures multiple backups coexist
# ---------------------------------------------------------------------------
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
DUMP_FILE="${PROJECT_ROOT}/backups/coder-${TIMESTAMP}.dump"
mkdir -p "${PROJECT_ROOT}/backups"

# Change to project root so docker compose finds compose.yaml
cd "${PROJECT_ROOT}"

echo "Starting backup: ${DUMP_FILE}"

# ---------------------------------------------------------------------------
# Run pg_dump
# -T: mandatory — without it Docker allocates a pseudo-TTY that corrupts
#     the binary stream (carriage returns injected into binary data)
# -Fc: custom format (compressed, supports selective restore, required by pg_restore)
# --no-owner --no-acl: makes dump portable across DB users (CLAUDE.md)
# PGPASSWORD: non-interactive auth via libpq env var (never use the interactive prompt flag)
# Service name: "database" (not "db" or "postgres") per compose.yaml
# ---------------------------------------------------------------------------
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
    pg_dump \
      -U "${POSTGRES_USER}" \
      -Fc \
      --no-owner \
      --no-acl \
      "${POSTGRES_DB}" \
  > "${DUMP_FILE}"

# ---------------------------------------------------------------------------
# Security: restrict dump file — contains all user/workspace data and secrets
# (ASVS V4 / RESEARCH.md Security Domain)
# ---------------------------------------------------------------------------
chmod 600 "${DUMP_FILE}"

# ---------------------------------------------------------------------------
# Integrity verification step 1: non-zero size
# pg_dump may exit 0 even if -T was omitted and TTY corruption produced an
# empty or truncated file
# ---------------------------------------------------------------------------
if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Integrity verification step 2: structural check via pg_restore --list
# Reads the TOC (table of contents) from the archive header; exits non-zero
# if the archive is corrupt or not a valid custom-format dump
# ---------------------------------------------------------------------------
if ! PGPASSWORD="${POSTGRES_PASSWORD}" \
     docker compose exec -T database \
       pg_restore --list /dev/stdin \
     < "${DUMP_FILE}" > /dev/null 2>&1; then
  echo "ERROR: Dump file failed integrity check: ${DUMP_FILE}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Success — print human-readable summary and a parseable line for schedulers
# ---------------------------------------------------------------------------
DUMP_SIZE="$(du -sh "${DUMP_FILE}" | cut -f1)"
echo "Backup complete: ${DUMP_FILE} (${DUMP_SIZE})"
echo "BACKUP_FILE=${DUMP_FILE}"
