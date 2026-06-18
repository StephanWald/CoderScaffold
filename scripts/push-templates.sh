#!/usr/bin/env bash
# scripts/push-templates.sh — Login-aware bulk push of all workspace templates under templates/
#
# Usage: ./scripts/push-templates.sh
#
# Reads CODER_ACCESS_URL and CODER_SESSION_TOKEN from .env (if present).
# If an active Coder session is already detected via `coder whoami`, login is skipped.
# If not authenticated, the script runs `coder login` using CODER_ACCESS_URL (url, optional)
# and CODER_SESSION_TOKEN (--token, optional). When no token is set, login requires a TTY
# (interactive browser/token prompt); schedulers should always set CODER_SESSION_TOKEN.
#
# Pushes every subdirectory of templates/ that contains at least one *.tf file via
# `coder templates push <name> --directory <dir> --yes`. A failure on one template does
# NOT abort the rest — the loop continues and the script exits 1 at the end, naming every
# failed template.
#
# LIVE VERIFICATION DEFERRED — see note below.
#
# Exit codes:
#   0  — all found templates pushed successfully (or no template dirs found — clean skip)
#   1  — coder binary missing on PATH; OR one or more template pushes failed
set -euo pipefail

# ---------------------------------------------------------------------------
# LIVE VERIFICATION DEFERRED
#
# The coder CLI is NOT installed in this dev environment and there is no running
# Coder server reachable from here. Static checks (bash -n, shellcheck) have been
# performed. LIVE verification (auth flow + actual template push against a real Coder
# server) is DEFERRED to an environment that has the coder CLI installed and a running
# Coder server. Per project memory: "Infra needs a live deploy gate."
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Path resolution — works correctly when called via an absolute path from cron
# (cron runs with cwd=/; $PWD-relative resolution would fail)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Source .env — canonical set -a pattern (safe on values with spaces or $)
# Do NOT use: export $(cat .env | xargs)
# Only CODER_ACCESS_URL and CODER_SESSION_TOKEN are relevant here; Postgres vars
# are intentionally not given defaults — this script does not touch the database.
# ---------------------------------------------------------------------------
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "WARN: .env not found at ${ENV_FILE}; continuing without it" >&2
fi

# Change to project root so templates/<dir> relative paths resolve consistently
cd "${PROJECT_ROOT}"

# ---------------------------------------------------------------------------
# Binary check — fail fast with a clear message if coder is not on PATH
# ---------------------------------------------------------------------------
if ! command -v coder >/dev/null 2>&1; then
  echo "ERROR: coder CLI not found on PATH; install it from https://coder.com/docs/install" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Authentication step
#
# coder whoami exits non-zero when not authenticated (no active session).
# If authenticated, skip login — avoids unnecessary re-authentication.
# ---------------------------------------------------------------------------
if coder whoami >/dev/null 2>&1; then
  echo "Existing Coder session detected (coder whoami succeeded); skipping login."
else
  echo "No active Coder session found; running coder login..."

  # Build login args as a bash array — never word-split into flags via a string.
  # coder login <url> [--token <token>]
  #   url positional: CODER_ACCESS_URL if set (required for non-interactive token path)
  #   --token: CODER_SESSION_TOKEN if set (enables fully non-interactive auth for schedulers)
  login_args=()

  if [[ -n "${CODER_ACCESS_URL:-}" ]]; then
    login_args+=("${CODER_ACCESS_URL}")
  fi

  if [[ -n "${CODER_SESSION_TOKEN:-}" ]]; then
    login_args+=("--token" "${CODER_SESSION_TOKEN}")
  else
    # No token: coder login will launch an interactive browser/token prompt.
    # NOTE: this requires a TTY and will hang or fail in non-interactive environments
    # (cron, CI). Set CODER_SESSION_TOKEN in .env for unattended/scheduled use.
    echo "NOTE: CODER_SESSION_TOKEN not set — interactive coder login requires a TTY." >&2
  fi

  if ! coder login "${login_args[@]}"; then
    echo "ERROR: coder login failed; cannot push templates." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Discover and push all templates
#
# Loop over immediate subdirectories of templates/.
# Use compgen to test for .tf files — nullglob-safe and avoids modifying
# global shell options (shopt -s nullglob would affect the whole script).
# compgen -G returns exit 0 if any match is found, non-zero if none.
# ---------------------------------------------------------------------------
failed=()   # names of templates that failed to push
pushed=()   # names of templates successfully pushed
found_any=0 # becomes 1 when at least one subdir with a .tf file is found

for dir in "${PROJECT_ROOT}/templates/*/"; do
  # Guard: skip if dir does not exist (handles the no-match literal-glob case)
  [[ -d "${dir}" ]] || continue

  # Strip trailing slash; get basename for the template name
  name="$(basename "${dir%/}")"

  # Skip the directory if it contains no *.tf files
  # compgen -G prints matching paths and exits 0 on any match; >/dev/null suppresses output
  if ! compgen -G "${dir}*.tf" >/dev/null 2>&1; then
    echo "Skipping ${name}: no .tf files found in ${dir}"
    continue
  fi

  found_any=1
  echo "Pushing template: ${name} (from ${dir%/})"

  # Push this template non-interactively.
  # --yes: skips the interactive confirmation prompt (required for scripted use).
  # --directory: must be the path to the template directory (no trailing slash).
  # Do NOT abort the loop on failure (set -e is active; wrap in if/else).
  if coder templates push "${name}" --directory "${dir%/}" --yes; then
    pushed+=("${name}")
  else
    echo "WARN: Failed to push template: ${name}" >&2
    failed+=("${name}")
  fi
done

# ---------------------------------------------------------------------------
# Handle no-template case — clean exit, not an error
# ---------------------------------------------------------------------------
if [[ "${found_any}" -eq 0 ]]; then
  echo "No template directories with .tf files found under ${PROJECT_ROOT}/templates/; nothing to push."
  exit 0
fi

# ---------------------------------------------------------------------------
# Summary — human-readable + parseable line for schedulers (mirrors backup.sh)
# ---------------------------------------------------------------------------
echo ""
echo "Template push complete."
echo "  Pushed (${#pushed[@]}): ${pushed[*]:-none}"
echo "  Failed (${#failed[@]}): ${failed[*]:-none}"
echo ""
# Parseable summary line (readable by external schedulers or CI output parsers)
echo "TEMPLATES_PUSHED=${#pushed[@]} TEMPLATES_FAILED=${#failed[@]}"

if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "ERROR: failed templates: ${failed[*]}" >&2
  exit 1
fi

exit 0
