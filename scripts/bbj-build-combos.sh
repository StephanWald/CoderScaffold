#!/usr/bin/env bash
# scripts/bbj-build-combos.sh — Non-interactive per-combo BBjServices image pre-warm
#
# Reads the same combinations.json that templates/bbj-services/main.tf reads and
# builds one Docker image per combo, warming the BuildKit layer cache so subsequent
# in-template Terraform builds are near-instant cache hits.
#
# NOTE: This script CANNOT be run end-to-end in this repository — it requires:
#   - Real BBj installer jars in BBJ_ASSETS_PATH (e.g. BBj-25.12.jar, BBj-26.01.jar)
#   - A valid certificate.bls in BBJ_ASSETS_PATH
#   - A reachable BLS license server (BBJ_LICENSE_SERVER)
#   - Dockerfile + playback.properties copied into BBJ_ASSETS_PATH
# These are operator-supplied assets not present in this repo. Running bash -n on
# this script (syntax check) and shellcheck are the verifiable steps here.
# Full end-to-end verification is the operator's live-deploy step.
#
# Usage: ./scripts/bbj-build-combos.sh
#
# Exit codes:
#   0  — all combos built successfully
#   1  — one or more combos failed (missing jar or docker build failure)
#   2  — jq is not installed (required dependency)
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

# Apply defaults — BBJ_ASSETS_PATH and BBJ_LICENSE_SERVER are already defined in
# .env.example's BBjServices section; these are the fallbacks when .env is absent.
BBJ_ASSETS_PATH="${BBJ_ASSETS_PATH:-./bbj-assets}"
BBJ_LICENSE_SERVER="${BBJ_LICENSE_SERVER:-}"

# BASE_IMAGE and MAVEN_VERSION defaults match templates/bbj-services/main.tf so
# the build-args are identical between this script and the in-template Terraform build,
# maximising the BuildKit layer cache hit rate.
BASE_IMAGE="${BASE_IMAGE:-codercom/enterprise-base:ubuntu}"
MAVEN_VERSION="${MAVEN_VERSION:-3.9.16}"

# Resolve the build context to an absolute path so docker build works from any cwd.
# Portable across GNU and BSD/macOS — avoids `realpath -m` (the -m/--canonicalize-missing
# flag is GNU-only; macOS's BSD realpath rejects it). Relative paths resolve against
# PROJECT_ROOT; the folder must exist (it is the docker build context).
case "${BBJ_ASSETS_PATH}" in
  /*) : ;;                                            # already absolute
  *) BBJ_ASSETS_PATH="${PROJECT_ROOT}/${BBJ_ASSETS_PATH}" ;;
esac
if [[ ! -d "${BBJ_ASSETS_PATH}" ]]; then
  echo "ERROR: BBJ_ASSETS_PATH does not exist: ${BBJ_ASSETS_PATH}" >&2
  echo "  Create it and stage the BBj jar(s) + certificate.bls + combinations.json + Dockerfile + playback.properties." >&2
  exit 1
fi
BBJ_ASSETS_PATH="$(cd "${BBJ_ASSETS_PATH}" && pwd -P)"

# ---------------------------------------------------------------------------
# Require jq — the script cannot proceed without it
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found on PATH. Install it with:" >&2
  echo "  Ubuntu/Debian: apt-get install jq" >&2
  echo "  macOS:         brew install jq" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve combinations.json — prefer the operator's asset folder copy; fall back
# to the version-controlled example if absent (with a warning).
# ---------------------------------------------------------------------------
COMBOS_FILE="${BBJ_ASSETS_PATH}/combinations.json"
if [[ ! -f "${COMBOS_FILE}" ]]; then
  EXAMPLE_FILE="${PROJECT_ROOT}/templates/bbj-services/combinations.example.json"
  echo "WARN: ${COMBOS_FILE} not found; falling back to ${EXAMPLE_FILE}" >&2
  COMBOS_FILE="${EXAMPLE_FILE}"
fi

if [[ ! -f "${COMBOS_FILE}" ]]; then
  echo "ERROR: No combinations.json found (checked asset folder and example). Cannot proceed." >&2
  exit 1
fi

echo "Reading combos from: ${COMBOS_FILE}"
echo "Build context:       ${BBJ_ASSETS_PATH}"
echo "Base image:          ${BASE_IMAGE}"
echo "Maven version:       ${MAVEN_VERSION}"
echo ""

# ---------------------------------------------------------------------------
# Iterate and build one image per combo
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
FAIL_COMBOS=()

# Read combo count for progress display
COMBO_COUNT="$(jq 'length' "${COMBOS_FILE}")"
echo "Found ${COMBO_COUNT} combo(s) to build."
echo ""

while IFS= read -r combo; do
  ID="$(echo "${combo}" | jq -r '.id')"
  JAR="$(echo "${combo}" | jq -r '.jar')"
  JDK="$(echo "${combo}" | jq -r '.jdk')"

  echo "──────────────────────────────────────────────────────────"
  echo "Combo: ${ID}  (JDK: ${JDK}, JAR: ${JAR})"

  # Fail-fast: verify the jar exists in the asset folder before attempting a build.
  # A missing jar produces an unintelligible docker build error; this gives a clear message.
  JAR_PATH="${BBJ_ASSETS_PATH}/${JAR}"
  if [[ ! -f "${JAR_PATH}" ]]; then
    echo "FAIL [${ID}]: jar not found at ${JAR_PATH}" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_COMBOS+=("${ID} (missing jar: ${JAR})")
    continue
  fi

  IMAGE_TAG="bbj-services:${ID}"
  echo "Building image: ${IMAGE_TAG}"

  # Capture docker build exit status explicitly so one failure does not abort
  # the whole loop (allowing the summary to be complete).
  if docker build \
    --build-arg "JDK=${JDK}" \
    --build-arg "BBJ_JAR_NAME=${JAR}" \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "MAVEN_VERSION=${MAVEN_VERSION}" \
    --build-arg "LICENSE_SERVER=${BBJ_LICENSE_SERVER}" \
    -t "${IMAGE_TAG}" \
    "${BBJ_ASSETS_PATH}"; then
    echo "PASS [${ID}]: image built → ${IMAGE_TAG}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL [${ID}]: docker build failed for ${IMAGE_TAG}" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_COMBOS+=("${ID} (docker build failed)")
  fi
done < <(jq -c '.[]' "${COMBOS_FILE}")

# ---------------------------------------------------------------------------
# Per-combo summary
# ---------------------------------------------------------------------------
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Build summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
  echo ""
  echo "Failed combos:"
  for f in "${FAIL_COMBOS[@]}"; do
    echo "  FAIL  ${f}"
  done
  echo ""
  echo "ERROR: One or more combos failed to build. See output above." >&2
  exit 1
fi

echo "All combos built successfully."
exit 0
