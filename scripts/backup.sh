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
# if the archive is corrupt or not a valid custom-format dump.
#
# WHY docker compose cp + in-container file (not /dev/stdin):
#   pg_restore --list on a custom-format (-Fc) archive requires a SEEKABLE
#   regular file — pg_restore seeks block offsets in the TOC header (Postgres
#   17 docs: "input must be a regular file or directory, not a pipe or stdin").
#   Feeding the dump via `< DUMP_FILE` into docker compose exec produces a
#   non-seekable stream inside the container, so --list fails for EVERY valid
#   dump.  Additionally, docker/compose #8909 corrupts binary data piped into
#   exec stdin (especially on macOS Docker Desktop), making the stdin path
#   doubly unreliable.
#
#   Fix: docker compose cp copies the dump to the container as a real seekable
#   file. pg_restore --list reads it directly. No stdin crossing; no seek issue.
#
# Security (T-02-03-01): temp file is removed on ALL exit paths (success,
#   failure, or unexpected abort under set -e) via explicit branch removal.
#   rm -f suppresses errors in case cp itself failed (|| true guards below).
#
# Uniqueness (T-02-03-03): PID ($$) in the name prevents concurrent runs from
#   colliding on the same temp path.
#
# Auth: PGPASSWORD is NOT needed for pg_restore --list (reads archive header
#   only; makes no database connection). Do not add it here.
# ---------------------------------------------------------------------------
CONTAINER_DUMP="/tmp/coder-verify-$$-$(basename "${DUMP_FILE}")"

# Copy the dump into the container as a real seekable regular file.
# docker compose cp does not use the corrupted exec-stdin path (#8909).
docker compose cp "${DUMP_FILE}" "database:${CONTAINER_DUMP}"

# Run structural check; pg_restore stderr flows to this script's stderr so
# the caller sees the real diagnostic on failure.  Stdout (the TOC listing)
# is noise for a health check so it is suppressed with >/dev/null.
# The || prevents set -e from aborting; PGRESTORE_EXIT captures the real code.
PGRESTORE_EXIT=0
if ! docker compose exec -T database pg_restore --list "${CONTAINER_DUMP}" >/dev/null; then
  PGRESTORE_EXIT=1
fi

# Remove the in-container temp file unconditionally (|| true: rm must not mask
# the real exit code, and the file may not exist if cp itself failed).
docker compose exec -T database rm -f "${CONTAINER_DUMP}" || true

if [[ "${PGRESTORE_EXIT}" -ne 0 ]]; then
  echo "ERROR: Dump file failed integrity check: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Success — print human-readable summary and a parseable line for schedulers
# ---------------------------------------------------------------------------
DUMP_SIZE="$(du -sh "${DUMP_FILE}" | cut -f1)"
echo "Backup complete: ${DUMP_FILE} (${DUMP_SIZE})"
echo "BACKUP_FILE=${DUMP_FILE}"
