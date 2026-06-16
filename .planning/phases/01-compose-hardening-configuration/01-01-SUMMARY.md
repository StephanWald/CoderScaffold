---
phase: 01-compose-hardening-configuration
plan: "01"
subsystem: infra
tags: [docker-compose, postgres, coder, named-volume, healthcheck, gitignore, env-config]

# Dependency graph
requires: []
provides:
  - Hardened compose.yaml with pinned Coder image v2.33.8, restart policies, /healthz healthcheck, env-sourced credentials and URLs
  - Named-volume Postgres persistence (coder_pgdata) with opt-in host bind mount via CODER_PG_DATA_DIR
  - .gitignore protecting .env, data/, and backups/ from version control
affects:
  - 01-02 (operator docs depend on the compose.yaml structure established here)
  - phase-02 (backup scripts depend on the compose stack layout; pg_dump is storage-backend-transparent)
  - phase-03 (workspace template requires a working access URL and wildcard URL config)

# Tech tracking
tech-stack:
  added:
    - "ghcr.io/coder/coder:v2.33.8 (pinned stable image)"
    - "postgres:17 (named volume coder_pgdata; bind-mount opt-in via CODER_PG_DATA_DIR)"
  patterns:
    - "env-sourced config: all secrets and URLs via ${VAR:-default} with no hardcoded values in compose.yaml"
    - "healthcheck-gated depends_on: coder service waits for database service_healthy before starting"
    - "named volume default / bind mount opt-in: cross-platform default, power-user override"
    - "Requirement ID comment tags (# SRV-01, # CFG-03, etc.) inline for traceability"

key-files:
  created:
    - .gitignore
  modified:
    - compose.yaml

key-decisions:
  - "Pin Coder image to v2.33.8 (stable track) via CODER_VERSION variable; CODER_REPO keeps registry overridable"
  - "Default Postgres storage to named volume coder_pgdata (cross-platform, no chown required); host bind mount opt-in via CODER_PG_DATA_DIR=./data/postgres"
  - "CODER_ACCESS_URL defaults to http://127.0.0.1:7080 (full URL form required by Coder; setting real URL in .env disables dev tunnel)"
  - "CODER_WILDCARD_ACCESS_URL defaults empty (wildcard apps disabled in quickstart; set in .env for production)"
  - "Do not expose Postgres on a host port; Coder reaches it by Docker service name database:5432 only"

patterns-established:
  - "Pattern 1: env-sourced compose config — every operator-tunable value uses ${VAR:-default} so the stack works zero-setup but is fully overridable from .env"
  - "Pattern 2: healthcheck-gated startup — Coder only starts after postgres passes pg_isready; Coder /healthz gates anything depending on Coder"
  - "Pattern 3: named volume default with bind-mount opt-in — avoids VirtioFS chown issues on macOS/Windows by default; operators wanting host-visible data set CODER_PG_DATA_DIR"

requirements-completed: [SRV-01, SRV-02, SRV-03, SRV-04, SRV-05, CFG-02, CFG-03, CFG-04, CFG-05]

# Metrics
duration: ~90min
completed: 2026-06-16
---

# Phase 01 Plan 01: Compose Hardening — Walking Skeleton Summary

**Hardened compose.yaml with pinned v2.33.8 image, dual restart policies, /healthz healthcheck, env-sourced config, and named-volume Postgres — verified healthy on macOS Docker Desktop (both services Up/healthy, /healthz returns OK, Coder UI loads).**

## Performance

- **Duration:** ~90 min (including checkpoint verification round-trip)
- **Started:** 2026-06-16T12:51:25Z
- **Completed:** 2026-06-16T19:40:00Z
- **Tasks:** 2 auto tasks + 1 human-verify checkpoint (all complete)
- **Files modified:** 2 (compose.yaml, .gitignore)

## Accomplishments

- Transformed the upstream proof-of-concept compose.yaml into a production-grade stack: pinned image, restart policies, healthcheck-gated startup ordering, env-driven secrets and URLs, no secrets hardcoded
- Established the named-volume Postgres persistence default (coder_pgdata) with host bind-mount opt-in via CODER_PG_DATA_DIR — cross-platform and requires no chown prerequisite by default
- Created .gitignore protecting .env (secrets), data/ (bind-mount dir), and backups/ (Phase 2 dump output) from version control, while keeping .env.example committable
- Verified the walking skeleton end-to-end on macOS Docker Desktop: both services reach (healthy), /healthz returns OK, Coder UI loads at http://127.0.0.1:7080

## Task Commits

Each task was committed atomically:

1. **Task 1: Harden compose.yaml** - `670bc81` (feat)
2. **Task 2: Create .gitignore** - `faa11a5` (feat)
3. **Deviation fix: Default Postgres to named volume** - `19abadd` (fix) — applied during Task 3 checkpoint after bind-mount chown failed on macOS VirtioFS

## Files Created/Modified

- `compose.yaml` — hardened two-service stack: pinned Coder image v2.33.8, restart: unless-stopped on both services, Coder /healthz healthcheck (30s start_period covering DB migrations), env-sourced CODER_ACCESS_URL/CODER_WILDCARD_ACCESS_URL/CODER_PG_CONNECTION_URL, named-volume Postgres persistence with bind-mount opt-in, canonical image comment and commented Postgres ports block preserved verbatim
- `.gitignore` — ignores .env (secrets), data/ (Postgres data dir), backups/ (Phase 2 dumps); .env.example remains trackable

## Decisions Made

1. **Pin Coder to v2.33.8 (stable track):** Avoids silent drift that `:latest` introduces; upgrades are explicit via CODER_VERSION in .env. CODER_REPO keeps the registry overridable (upstream documentation stability requirement).

2. **Named volume default / bind-mount opt-in:** Postgres defaults to `coder_pgdata` named volume (works cross-platform, no chown required). Operators who want host-visible data set `CODER_PG_DATA_DIR=./data/postgres` in .env and pre-create the directory. See Deviations below for full rationale.

3. **Empty CODER_WILDCARD_ACCESS_URL default:** Empty = unset from Coder's perspective (Research-confirmed). Quickstart works without a wildcard subdomain; production operators add `*.coder.example.com` in .env.

4. **Postgres not exposed on host port:** The `#ports:` block is kept commented out. Coder reaches the database by Docker network service name (database:5432); exposing it on the host is an unnecessary attack surface (T-01-02).

## Deviations from Plan

### Architectural Revision (Approved by User)

**[Approved Deviation - Storage Strategy] Default Postgres storage changed from host bind mount to named volume**

- **Found during:** Task 3 checkpoint (human verification on macOS Docker Desktop)
- **Issue:** The plan specified a host bind mount (`${CODER_PG_DATA_DIR:-./data/postgres}`) as the Postgres data directory (SRV-01, locked roadmap decision). During Task 3 verification, Postgres crash-looped immediately. Root cause: Docker Desktop uses VirtioFS for bind mounts on macOS and Windows, which denies `chown`/`chmod` on the PGDATA directory during init. The `sudo chown -R 999:999` prerequisite documented in OPS-03 has no effect on VirtioFS mounts — the error occurs inside the container at PGDATA initialization, not on the host.
- **Original decision rationale:** "Host-visible files for backups" — the assumption was that backup scripts needed direct file system access to the Postgres data directory. This assumption was incorrect: the project's backup strategy uses `pg_dump` (logical backup via `docker compose exec -T`), which is completely transparent to the storage backend.
- **Approved fix:** Default to named volume `coder_pgdata` (requires no chown, works cross-platform). Preserve the bind-mount opt-in: operators set `CODER_PG_DATA_DIR=./data/postgres` in `.env` (and must pre-create + chown the directory). The CODER_PG_DATA_DIR variable is preserved in compose.yaml; when set, it overrides the named volume default.
- **Impact on requirements:** SRV-01 ("Postgres data survives container recreation") is still fully satisfied — named volumes persist across `docker compose down && docker compose up -d`. The OPS-03 chown prerequisite is no longer on the default path (only needed when operator opts into bind mount).
- **Files modified:** `compose.yaml`
- **Verification:** Stack brought up healthy on macOS Docker Desktop after the change; both services show (healthy) in `docker compose ps`; /healthz returns OK; Coder UI loads.
- **Commit:** `19abadd`

## Known Stubs

None — compose.yaml uses env-interpolated defaults that work in the quickstart context. Plan 02 will document and template all variables in .env.example.

## Threat Flags

No new security surface beyond what the plan's threat model covers. All mitigations applied:

| Threat | Status |
|--------|--------|
| T-01-01 (.env secrets in git) | Mitigated: .gitignore blocks .env; credentials sourced via ${POSTGRES_PASSWORD:-...}, no literal secrets in compose.yaml |
| T-01-02 (Postgres on host network) | Mitigated: #ports block kept commented; Coder reaches DB by service name only |
| T-01-03 (image drift via :latest) | Mitigated: default pinned to v2.33.8; CODER_VERSION makes upgrades explicit |
| T-01-04 (dev tunnel in production) | Mitigated: CODER_ACCESS_URL interpolated from .env; setting a real URL disables the *.try.coder.app tunnel |
| T-01-05 (Postgres data permissions) | Mitigated: named volume default is not world-readable; bind-mount opt-in users need chown 999:999 (documented) |

## Self-Check: PASSED

- `compose.yaml` exists: FOUND
- `.gitignore` exists: FOUND
- Commit 670bc81 (harden compose.yaml): FOUND
- Commit faa11a5 (.gitignore): FOUND
- Commit 19abadd (named volume fix): FOUND
- Stack verified healthy (macOS Docker Desktop): both services (healthy), /healthz OK, UI loads
