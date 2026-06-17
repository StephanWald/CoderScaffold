---
phase: 01-compose-hardening-configuration
plan: "02"
subsystem: infra
tags: [docker-compose, env-config, documentation, operator-runbook, postgres, coder]

# Dependency graph
requires:
  - phase: 01-01
    provides: Hardened compose.yaml with all ${VAR} references, .gitignore protecting .env and data/
provides:
  - .env.example documenting every compose variable with safe placeholders (CFG-01)
  - README.md operator runbook covering bring-up, chown/bind-mount, first-admin bootstrap, and the 9-point reverse-proxy contract (OPS-01, OPS-02, OPS-03)
affects:
  - phase-02 (backup scripts reference .env variable names established here)
  - phase-03 (workspace template operators follow the same .env convention for CODER_ACCESS_URL / CODER_WILDCARD_ACCESS_URL)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "env-example contract: every ${VAR} in compose.yaml has a corresponding entry in .env.example with a safe placeholder and inline comment"
    - "named-volume default / bind-mount opt-in: CODER_PG_DATA_DIR is commented out in .env.example so cp .env.example .env does not re-enable bind mount"
    - "operator runbook: README documents the stack top-to-bottom in clone→configure→up→verify order with failure symptoms co-located with each prerequisite"

key-files:
  created:
    - .env.example
    - README.md
  modified: []

key-decisions:
  - "CODER_PG_DATA_DIR is a commented-out opt-in line in .env.example (not an active default) so copying the example to .env does not trigger the bind-mount path that crash-loops Postgres on macOS/Windows VirtioFS"
  - "README quick-start defaults to named-volume bring-up (no chown required); host bind-mount chown instructions are scoped to an opt-in subsection"
  - "Added a dedicated 'Postgres storage: named volume vs host bind mount' section explaining the default, the trade-offs, and the migration path"

patterns-established:
  - "Pattern 4: env-example opt-in comments — variables that change the default storage backend are present but commented out, with inline explanation of when to uncomment"
  - "Pattern 5: co-located failure symptoms — each prerequisite in the README states the exact error message the operator will see if the step is skipped"

requirements-completed: [CFG-01, OPS-01, OPS-02, OPS-03]

# Metrics
duration: ~45min
completed: 2026-06-17
---

# Phase 01 Plan 02: Configuration Contract + Operator Runbook Summary

**.env.example documenting all compose variables with safe placeholders, and README.md operator runbook covering bring-up sequence, host bind-mount opt-in with chown prerequisite, first-admin bootstrap, and the 9-point reverse-proxy contract — scoped to the named-volume default established in Plan 01-01.**

## Performance

- **Duration:** ~45 min (including checkpoint verification round-trip)
- **Started:** 2026-06-16T19:45:00Z
- **Completed:** 2026-06-17
- **Tasks:** 2 auto tasks + 1 human-verify checkpoint (all complete, checkpoint approved)
- **Files modified:** 2 (.env.example, README.md)

## Accomplishments

- Created `.env.example` with 6 active variables (CODER_ACCESS_URL, CODER_WILDCARD_ACCESS_URL, CODER_VERSION, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB) plus CODER_PG_DATA_DIR as a commented opt-in line; every compose ${VAR} is now documented with an inline explanation and a safe placeholder (CFG-01)
- Created `README.md` as a complete operator runbook: clone → configure → bring up → verify sequence; chown prerequisite with failure symptom scoped to the bind-mount opt-in subsection; first-admin bootstrap via the Coder UI (no env-var autocreate); the 9-point reverse-proxy contract (OPS-01)
- Human-verify checkpoint passed: reviewer confirmed .env.example is complete and README lets a stranger stand up the stack without prior Coder knowledge

## Task Commits

Each task was committed atomically:

1. **Task 1: Create .env.example** - `cd16542` (feat)
2. **Task 2: Write README.md** - `2bc3e03` (feat)

## Files Created/Modified

- `.env.example` — 6 active variables in two grouped sections (Coder Server, PostgreSQL); CODER_PG_DATA_DIR present as a commented opt-in with explanation; CODER_TELEMETRY_ENABLE and CODER_FIRST_USER_* absent per plan exclusions (D-10, D-01); POSTGRES_PASSWORD uses the obviously-fake placeholder `change-me-in-production`; not gitignored
- `README.md` — operator runbook in 8 sections: title/overview, prerequisites, quick start (named-volume path, no chown required by default), Postgres storage section (named volume vs bind mount trade-offs + opt-in instructions including chown with failure symptom), first-admin bootstrap, reverse-proxy contract (9-point D-06 checklist), upgrade-from-quickstart note, common operations + coder_home note

## Decisions Made

1. **CODER_PG_DATA_DIR as commented opt-in in .env.example:** An active `CODER_PG_DATA_DIR=./data/postgres` line in .env.example, when copied to .env without editing, re-enables the bind-mount path that crash-loops Postgres on macOS/Windows Docker Desktop (VirtioFS denies chown). The variable is retained as a commented line with a clear explanation of when to uncomment it.

2. **README quick-start uses named volume (no chown by default):** The primary bring-up sequence in README reflects the Plan 01-01 named-volume default. A dedicated "Postgres storage" subsection covers the host bind-mount opt-in path, including the `sudo chown -R 999:999` prerequisite and the exact failure symptom (`chown: changing ownership ... Permission denied`).

3. **"Postgres storage: named volume vs host bind mount" section added:** This section was not in the original plan spec but was required to explain the Plan 01-01 storage deviation to operators. It documents the default rationale (cross-platform, pg_dump is storage-transparent), the opt-in path, and the one-shot volume migration command for operators upgrading from the quickstart.

## Deviations from Plan

### Plan Instructions Superseded by Plan 01-01 Storage Deviation

The following plan acceptance criteria and instructions were written before the Plan 01-01 approved deviation (Postgres default changed from host bind mount to named volume). They are intentionally superseded — the implementation reflects the approved storage architecture, not the original plan text.

**1. [Superseded — Storage Decision] CODER_PG_DATA_DIR active variable count**
- **Plan said:** `.env.example` must have exactly 7 active (uncommented) variables, including `^CODER_PG_DATA_DIR=./data/postgres` as an active line
- **What was built:** 6 active variables; CODER_PG_DATA_DIR is a commented opt-in line
- **Rationale:** An active `CODER_PG_DATA_DIR=./data/postgres` in .env.example triggers the bind-mount path when operators `cp .env.example .env` without reading every line. This would crash-loop Postgres on macOS/Windows (VirtioFS denies chown). Keeping it commented avoids the footgun while keeping the variable discoverable with full documentation.
- **Requirements impact:** CFG-01 is still fully satisfied — every compose `${VAR}` is documented. The difference is the active vs. commented state of one variable.

**2. [Superseded — Storage Decision] chown step placement in the main bring-up sequence**
- **Plan said:** `sudo chown -R 999:999 ./data/postgres` must appear in the MAIN bring-up block, before `docker compose up`
- **What was built:** The main quick-start bring-up block has no chown step (the default named-volume path requires no chown). The chown prerequisite and its failure symptom appear in the "Postgres storage: named volume vs host bind mount → Option B: host bind mount" subsection, scoped to the operators who have opted into the bind-mount path
- **Rationale:** Putting a chown step for a non-existent `./data/postgres` directory into the default bring-up sequence would confuse and block operators using the named-volume default. OPS-03 substance is preserved — the chown prerequisite is documented with the failure symptom, just in the correct scope
- **Requirements impact:** OPS-03 satisfied — the prerequisite is impossible to miss for operators who opt into the bind-mount path, and it includes the exact failure symptom (`chown: changing ownership ... Permission denied`, `database` service exits immediately)

---

**Total deviations:** 2 superseded plan criteria (no auto-fix needed; intentional architectural scoping)
**Impact on plan:** All CFG-01, OPS-01, OPS-02, OPS-03 substance is preserved and correctly scoped to the named-volume-default architecture approved in Plan 01-01.

## Issues Encountered

None — both tasks executed cleanly. The human-verify checkpoint was approved without reported gaps.

## User Setup Required

None — no external service configuration required for the documentation plan. Operators must edit `.env` values (CODER_ACCESS_URL, POSTGRES_PASSWORD) before production use, as documented in README.md.

## Next Phase Readiness

- Phase 1 implementation complete: compose.yaml hardened (01-01), .env.example + README.md delivered (01-02)
- Phase 2 (backup scripts) can proceed: pg_dump backup strategy is storage-backend-transparent; .env variable names for Postgres credentials are established
- Phase 3 (workspace template) can proceed: CODER_ACCESS_URL and CODER_WILDCARD_ACCESS_URL configuration pattern is documented for operators

Remaining blocker for Phase 3: Docker socket GID varies by host distro (TPL-05, logged in STATE.md).

---
*Phase: 01-compose-hardening-configuration*
*Completed: 2026-06-17*

## Self-Check: PASSED

- `.env.example` exists: FOUND
- `README.md` exists: FOUND
- Commit cd16542 (.env.example): FOUND
- Commit 2bc3e03 (README.md): FOUND
- Human-verify checkpoint: APPROVED
