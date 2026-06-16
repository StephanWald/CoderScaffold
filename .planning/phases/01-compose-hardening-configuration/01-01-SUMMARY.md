---
phase: 01-compose-hardening-configuration
plan: "01"
subsystem: infra
tags: [docker-compose, postgres, coder, bind-mount, healthcheck, gitignore]

# Dependency graph
requires: []
provides:
  - Hardened compose.yaml with bind-mount persistence, pinned image, restart policies, and /healthz healthcheck
  - .gitignore protecting .env secrets and data/backups directories from git
affects:
  - 01-02 (operator docs depend on the compose.yaml structure established here)
  - phase-02 (backup scripts depend on data/ and backups/ bind-mount conventions)
  - phase-03 (workspace template depends on stable Coder image and access URL config)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Host bind mount for Postgres data at ${CODER_PG_DATA_DIR:-./data/postgres} with chown 999:999 pre-create requirement"
    - "Two-service depends_on: condition: service_healthy gate for DB-first ordering"
    - "Coder /healthz healthcheck with 30s start_period for DB migration window"
    - "${VAR:-default} interpolation for every overridable config value"

key-files:
  created:
    - .gitignore
  modified:
    - compose.yaml

key-decisions:
  - "Pin Coder image default to v2.33.8 (stable track) via ${CODER_VERSION:-v2.33.8}; keep CODER_REPO overridable"
  - "CODER_ACCESS_URL default is http://127.0.0.1:7080 (enables quickstart); setting real URL in .env disables dev tunnel"
  - "CODER_WILDCARD_ACCESS_URL defaults empty (wildcard apps disabled in quickstart; enable in .env for production)"
  - "CODER_TELEMETRY_ENABLE not set — left at Coder default (D-10)"
  - "Postgres exposed only via Docker service name 'database'; host port 5432 remains commented out"
  - "coder_data named volume removed; replaced by host bind mount for direct backup access"

patterns-established:
  - "Pattern 1: ${VAR:-default} interpolation for all compose environment variables"
  - "Pattern 2: restart: unless-stopped on both services with # SRV-0N comment tags"
  - "Pattern 3: Coder healthcheck uses CMD (not CMD-SHELL) with curl -f http://localhost:7080/healthz"
  - "Pattern 4: Requirement ID comment tags (# SRV-01, # CFG-03, etc.) for traceability"

requirements-completed: [SRV-01, SRV-02, SRV-03, SRV-04, CFG-02, CFG-03, CFG-04, CFG-05]

# Metrics
duration: 2min (Tasks 1-2 complete; Task 3 awaiting human checkpoint)
completed: 2026-06-16
---

# Phase 01 Plan 01: Compose Hardening & Configuration Summary

**Hardened two-service compose.yaml with Postgres bind-mount persistence, v2.33.8 pinned image, dual restart policies, /healthz healthcheck, and env-sourced config; plus .gitignore protecting secrets**

## Performance

- **Duration:** ~2 min (Tasks 1-2 complete; paused at Task 3 checkpoint)
- **Started:** 2026-06-16T12:51:25Z
- **Completed:** 2026-06-16T12:52:55Z (Tasks 1-2)
- **Tasks:** 2 of 3 complete (Task 3 is checkpoint:human-verify)
- **Files modified:** 2

## Accomplishments
- Hardened compose.yaml: pinned Coder image to v2.33.8, added restart policies on both services, replaced named Postgres volume with host bind mount, added Coder /healthz healthcheck with 30s start_period, interpolated all URLs and credentials from .env
- Created .gitignore with three entries: .env (secrets), data/ (bind-mount), backups/ (Phase 2 dump output)
- Threat mitigations applied: T-01-01 (.env gitignored), T-01-02 (Postgres port kept commented), T-01-03 (image pinned), T-01-04 (access URL env-sourced), T-01-05 (bind-mount ownership documented via OPS-03 comment)

## Task Commits

Each task was committed atomically:

1. **Task 1: Harden compose.yaml** - `670bc81` (feat)
2. **Task 2: Create .gitignore** - `faa11a5` (feat)
3. **Task 3: Human checkpoint** - awaiting verification

## Files Created/Modified
- `compose.yaml` - Hardened stack: bind-mount persistence, pinned image, restart policies, /healthz healthcheck, env-sourced config
- `.gitignore` - Excludes .env, data/, backups/ from git; leaves .env.example trackable

## Decisions Made
- Coder image pinned to v2.33.8 (stable track); CODER_VERSION/CODER_REPO keep upgrades explicit
- CODER_ACCESS_URL default set to full URL form `http://127.0.0.1:7080` (required for Coder — bare IPs without protocol are rejected)
- CODER_WILDCARD_ACCESS_URL defaults empty (correct behavior: unset = wildcard apps disabled)
- CODER_TELEMETRY_ENABLE omitted per D-10 (left at Coder default; not a production safety concern)
- coder_data named volume removed entirely; host bind mount at ${CODER_PG_DATA_DIR:-./data/postgres} gives direct backup access

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria verified via grep-based checks (docker not available in dev container environment, so `docker compose config -q` could not be run; all structural requirements confirmed by direct file inspection).

## Issues Encountered

Docker CLI not available in the dev container environment — `docker compose config -q` could not be executed for YAML parse verification. YAML structure was validated by:
- Confirming all required stanzas present via grep
- Checking indentation and structure visually
- All acceptance criteria greps passed

The human checkpoint (Task 3) will confirm end-to-end stack functionality.

## Threat Scan

No new threat surface beyond what the plan's threat model covers. All T-01-xx mitigations applied:
- T-01-01: .gitignore blocks .env (Task 2); no literal password in compose.yaml
- T-01-02: Postgres #ports:5432 block preserved commented out
- T-01-03: Image pinned to v2.33.8
- T-01-04: CODER_ACCESS_URL interpolated from .env
- T-01-05: Bind-mount ownership documented via OPS-03 comment in volume line

## Next Phase Readiness
- compose.yaml is the architectural backbone for Plan 02 (operator docs: .env.example, README)
- Bind-mount convention (data/, backups/) established for Phase 2 backup scripts
- Human checkpoint (Task 3) must pass before Phase 01 is marked complete

## Self-Check

Files exist:
- compose.yaml: FOUND
- .gitignore: FOUND

Commits exist:
- 670bc81 (Task 1): FOUND
- faa11a5 (Task 2): FOUND

## Self-Check: PASSED

---
*Phase: 01-compose-hardening-configuration*
*Completed: 2026-06-16 (Tasks 1-2; Task 3 checkpoint pending)*
