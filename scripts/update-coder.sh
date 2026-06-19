#!/usr/bin/env bash
# scripts/update-coder.sh — Update the pinned Coder version and roll the running stack.
#
# Updating Coder is a version-pin bump + pull + recreate. Postgres data lives in a
# persistent volume and is NOT touched; Coder runs its DB migrations automatically
# on the new container's first start. This script makes that safe and repeatable:
#
#   1. Take a fresh DB backup first (scripts/backup.sh) — never upgrade without a
#      restore point. Aborts the upgrade if the backup fails.
#   2. Pin the target version in .env (CODER_VERSION=...), preserving the rest.
#   3. docker compose pull coder  +  docker compose up -d   (recreates coder only;
#      database is unchanged and keeps running).
#   4. Wait for the coder service healthcheck to go healthy, then report the version.
#
# Only the Coder control plane restarts (brief downtime). Running workspaces are
# separate containers and are unaffected.
#
# Usage:
#   ./scripts/update-coder.sh <version>     # e.g. ./scripts/update-coder.sh v2.33.9
#   ./scripts/update-coder.sh               # re-pull/recreate the currently pinned version
#   ./scripts/update-coder.sh --check       # show current + latest release, then exit
#   ./scripts/update-coder.sh <version> --push-templates   # also re-push templates after
#
# Flags:
#   --check            Print the current pinned version and the latest GitHub release; exit.
#   --no-backup        Skip the pre-update DB backup (NOT recommended).
#   --push-templates   After a healthy upgrade, run scripts/push-templates.sh.
#   --dry-run          Print the actions that would be taken; change nothing.
#   -h, --help         Show this help.
#
# Exit codes:
#   0  — update completed and coder is healthy (or --check / --help / --dry-run)
#   1  — bad usage, missing docker/compose, backup failed, pull failed, or coder
#        did not become healthy within the timeout
#
# ---------------------------------------------------------------------------
# LIVE VERIFICATION DEFERRED
#   The coder CLI / a running Coder stack are not available in the dev container
#   where this script was authored. Static checks (bash -n, shellcheck) were run.
#   The pull/recreate/health path is DEFERRED to a host with the stack running.
#   Per project memory: "Infra needs a live deploy gate."
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution — works when called via an absolute path from cron (cwd=/)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Defaults that mirror compose.yaml exactly (the ${VAR:-default} fallbacks).
DEFAULT_VERSION="v2.33.8"
DEFAULT_REPO="ghcr.io/coder/coder"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CHECK_ONLY=0
DO_BACKUP=1
PUSH_TEMPLATES=0
DRY_RUN=0
TARGET_VERSION=""

usage() { sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|check)     CHECK_ONLY=1 ;;
    --no-backup)       DO_BACKUP=0 ;;
    --push-templates)  PUSH_TEMPLATES=1 ;;
    --dry-run)         DRY_RUN=1 ;;
    -h|--help)         usage; exit 0 ;;
    -*)                echo "ERROR: unknown flag: $1" >&2; usage; exit 1 ;;
    *)
      if [[ -n "${TARGET_VERSION}" ]]; then
        echo "ERROR: unexpected extra argument: $1" >&2; exit 1
      fi
      TARGET_VERSION="$1"
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Source .env (canonical set -a pattern; safe on values with spaces or $)
# ---------------------------------------------------------------------------
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi
CODER_REPO="${CODER_REPO:-${DEFAULT_REPO}}"
CURRENT_VERSION="${CODER_VERSION:-${DEFAULT_VERSION}}"

# ---------------------------------------------------------------------------
# --check: report current pinned version and the latest published release
# ---------------------------------------------------------------------------
latest_release() {
  # Newest non-draft release tag from the GitHub API (empty on network failure).
  curl -fsSL --max-time 20 "https://api.github.com/repos/coder/coder/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  echo "Current pinned version : ${CURRENT_VERSION}  (repo: ${CODER_REPO})"
  LATEST="$(latest_release || true)"
  if [[ -n "${LATEST}" ]]; then
    echo "Latest GitHub release  : ${LATEST}"
  else
    echo "Latest GitHub release  : (could not reach api.github.com)"
  fi
  echo
  echo "Coder ships a 'stable' track (e.g. v2.33.x) and a 'mainline' track (e.g."
  echo "v2.34.x). Prefer stable in production. Browse releases:"
  echo "  https://github.com/coder/coder/releases"
  echo
  echo "To update: ./scripts/update-coder.sh <version>"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pre-flight: docker + compose available, compose.yaml present
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found on PATH." >&2; exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' (v2 plugin) not available." >&2; exit 1
fi
cd "${PROJECT_ROOT}"
if [[ ! -f compose.yaml ]]; then
  echo "ERROR: compose.yaml not found in ${PROJECT_ROOT}." >&2; exit 1
fi

# ---------------------------------------------------------------------------
# Resolve target version
#   - explicit arg  → validate and pin it in .env
#   - no arg        → re-pull/recreate the currently pinned version (no .env edit)
# ---------------------------------------------------------------------------
if [[ -n "${TARGET_VERSION}" ]]; then
  if [[ ! "${TARGET_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: version '${TARGET_VERSION}' is not of the form vX.Y.Z (e.g. v2.33.9)." >&2
    echo "       Never use ':latest' — pin an explicit version (see --check)." >&2
    exit 1
  fi
else
  TARGET_VERSION="${CURRENT_VERSION}"
  echo "No version given — re-pulling/recreating the currently pinned ${TARGET_VERSION}."
fi

echo "Updating Coder: ${CURRENT_VERSION} → ${TARGET_VERSION}  (repo: ${CODER_REPO})"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] would: backup DB$([[ ${DO_BACKUP} -eq 0 ]] && echo ' (skipped)') →"
  echo "[dry-run]        pin CODER_VERSION=${TARGET_VERSION} in .env →"
  echo "[dry-run]        docker compose pull coder → docker compose up -d →"
  echo "[dry-run]        wait for healthy$([[ ${PUSH_TEMPLATES} -eq 1 ]] && echo ' → push templates')"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: pre-update DB backup (safety gate). Abort the upgrade if it fails.
# Backup needs the database service running; skip with a warning if it is not.
# ---------------------------------------------------------------------------
if [[ "${DO_BACKUP}" -eq 1 ]]; then
  if [[ -n "$(docker compose ps -q database 2>/dev/null)" ]]; then
    echo "Step 1/4: backing up the database before upgrading..."
    if ! "${SCRIPT_DIR}/backup.sh"; then
      echo "ERROR: pre-update backup failed — aborting upgrade (no changes made)." >&2
      exit 1
    fi
  else
    echo "WARN: database service is not running; skipping pre-update backup." >&2
  fi
else
  echo "Step 1/4: pre-update backup SKIPPED (--no-backup)."
fi

# ---------------------------------------------------------------------------
# Step 2: pin CODER_VERSION in .env (preserve everything else)
# ---------------------------------------------------------------------------
echo "Step 2/4: pinning CODER_VERSION=${TARGET_VERSION} in .env..."
if [[ -f "${ENV_FILE}" ]]; then
  if grep -qE '^[[:space:]]*CODER_VERSION=' "${ENV_FILE}"; then
    tmp="$(mktemp)"
    sed -E "s|^[[:space:]]*CODER_VERSION=.*|CODER_VERSION=${TARGET_VERSION}|" "${ENV_FILE}" > "${tmp}"
    mv "${tmp}" "${ENV_FILE}"
  else
    printf '\nCODER_VERSION=%s\n' "${TARGET_VERSION}" >> "${ENV_FILE}"
  fi
else
  echo "WARN: ${ENV_FILE} not found; creating a minimal one (other settings use compose defaults)." >&2
  printf '# Created by update-coder.sh\nCODER_VERSION=%s\n' "${TARGET_VERSION}" > "${ENV_FILE}"
fi
export CODER_VERSION="${TARGET_VERSION}"

# ---------------------------------------------------------------------------
# Step 3: pull the new image and recreate the coder service
# ---------------------------------------------------------------------------
echo "Step 3/4: pulling ${CODER_REPO}:${TARGET_VERSION} and recreating coder..."
if ! docker compose pull coder; then
  echo "ERROR: 'docker compose pull coder' failed (bad tag or registry/network issue)." >&2
  echo "       .env was pinned to ${TARGET_VERSION}; revert it if this tag does not exist." >&2
  exit 1
fi
docker compose up -d

# ---------------------------------------------------------------------------
# Step 4: wait for the coder healthcheck to report healthy
# ---------------------------------------------------------------------------
echo "Step 4/4: waiting for coder to become healthy..."
CID="$(docker compose ps -q coder)"
if [[ -z "${CID}" ]]; then
  echo "ERROR: coder container not found after 'up -d'." >&2; exit 1
fi
TIMEOUT=180
ELAPSED=0
while :; do
  STATUS="$(docker inspect -f '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}{{ .State.Status }}{{ end }}' "${CID}" 2>/dev/null || echo unknown)"
  case "${STATUS}" in
    healthy) echo "coder is healthy."; break ;;
    exited|dead)
      echo "ERROR: coder container is '${STATUS}'. Recent logs:" >&2
      docker compose logs --tail 40 coder >&2 || true
      exit 1 ;;
  esac
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    echo "ERROR: coder did not become healthy within ${TIMEOUT}s (last status: ${STATUS})." >&2
    docker compose logs --tail 40 coder >&2 || true
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

# Report the running version (best-effort; the image tag is the source of truth).
RUNNING_VERSION="$(docker compose exec -T coder coder version 2>/dev/null | head -1 || true)"

# ---------------------------------------------------------------------------
# Optional: re-push templates after a successful upgrade
# ---------------------------------------------------------------------------
if [[ "${PUSH_TEMPLATES}" -eq 1 ]]; then
  echo "Re-pushing workspace templates..."
  "${SCRIPT_DIR}/push-templates.sh" || echo "WARN: template push reported a failure; see above." >&2
fi

# ---------------------------------------------------------------------------
# Summary — human-readable + parseable line for schedulers
# ---------------------------------------------------------------------------
echo ""
echo "Coder update complete."
echo "  Pinned version : ${TARGET_VERSION}"
[[ -n "${RUNNING_VERSION}" ]] && echo "  Reported       : ${RUNNING_VERSION}"
echo ""
echo "CODER_UPDATED_TO=${TARGET_VERSION} PREVIOUS=${CURRENT_VERSION}"
echo ""
echo "Rollback if needed: set CODER_VERSION=${CURRENT_VERSION} in .env, run"
echo "'docker compose up -d', and (if a migration ran) restore the pre-update"
echo "backup with scripts/restore.sh."
exit 0
