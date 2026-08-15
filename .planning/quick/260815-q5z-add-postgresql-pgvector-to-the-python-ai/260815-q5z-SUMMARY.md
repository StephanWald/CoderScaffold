---
phase: quick-260815-q5z
plan: 01
subsystem: infra
tags: [postgresql, pgvector, coder, terraform, docker, python-ai]

# Dependency graph
requires:
  - phase: quick-260815-epv
    provides: templates/python-ai/ workspace template (Dockerfile, main.tf, README.md)
provides:
  - PostgreSQL 18.x + pgvector baked into templates/python-ai/Dockerfile (postgresql, postgresql-contrib, postgresql-<major>-pgvector)
  - Idempotent, warn-and-continue Postgres startup block in templates/python-ai/main.tf (initdb/pg_ctl/createdb/CREATE EXTENSION vector) with PGDATA on persistent /home/coder
  - PGDATA + DATABASE_URL exported in agent env and /etc/profile.d/20-postgres.sh
  - README PostgreSQL + pgvector section + 4 new deferred live-verification checklist items
affects: [python-ai template consumers, future AI/RAG work needing a local vector store]

# Tech tracking
tech-stack:
  added: ["postgresql (Ubuntu default, currently 18.x)", "postgresql-contrib", "postgresql-<major>-pgvector"]
  patterns:
    - "Version-agnostic apt install: derive PG_MAJOR from /usr/lib/postgresql instead of hardcoding a major version"
    - "PGDATA on the persistent home volume, not the Debian-managed cluster (which is dropped at build time) — required because docker_container is ephemeral"
    - "Warn-and-continue (WR-03) guard pattern applied consistently to every new startup_script step"

key-files:
  created: []
  modified:
    - templates/python-ai/Dockerfile
    - templates/python-ai/main.tf
    - templates/python-ai/README.md

key-decisions:
  - "PGDATA=/home/coder/.pgdata (not the Debian cluster) — the docker_container is recreated on every stop/start; only /home/coder persists"
  - "Debian auto-created cluster dropped immediately at build time (pg_dropcluster) so it can never be mistaken for the live database"
  - "coder OS user is the Postgres superuser (initdb -U coder) — single-tenant workspace, no separate postgres role or sudo needed for DB operations"
  - "PG_MAJOR derived dynamically at both build time and startup_script runtime — never hardcoded — so a base-image Postgres bump requires no template change"
  - "Generic coder database name (not project-specific) per plan design constraint"
  - "No port published, listen_addresses left at initdb default (localhost) — server reachable only from inside the workspace container"

patterns-established:
  - "Offline container smoke test as a pre-implementation proof step for infra changes that can't be easily unit tested"

requirements-completed: [PGV-01, PGV-02, PGV-03]

# Metrics
duration: 25min
completed: 2026-08-15
---

# Quick Task 260815-q5z: Add PostgreSQL + pgvector to python-ai Summary

**Baked PostgreSQL 18.x + pgvector into the python-ai Coder workspace image with an idempotent, warn-and-continue agent startup block that persists the database cluster on the workspace's home volume.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-15T16:35:00Z
- **Completed:** 2026-08-15T17:00:52Z
- **Tasks:** 3 completed
- **Files modified:** 3

## Accomplishments
- `templates/python-ai/Dockerfile` installs postgresql + postgresql-contrib + the version-matched pgvector package, drops the unused Debian cluster, hands `/var/run/postgresql` to the `coder` user, and ships `/etc/profile.d/20-postgres.sh`
- Offline container smoke test (`codercom/enterprise-base:ubuntu`, `--user root`) proved the full runtime sequence end to end: apt install -> PG_MAJOR derivation -> pg_dropcluster -> socket dir chown -> initdb-as-coder -> pg_ctl start -> createdb -> `CREATE EXTENSION vector` -> `extversion` printed (`0.6.0` on this arm64 test image; the live-probed amd64 target resolves to PG 18 / pgvector 0.8.1 — confirms why the major is derived, not hardcoded)
- `templates/python-ai/main.tf` starts Postgres from `coder_agent.main.startup_script` as the `coder` user with `PGDATA=/home/coder/.pgdata`, creates the generic `coder` database, enables `vector`, and is idempotent + non-fatal on every start
- `PGDATA` and `DATABASE_URL` exported in both `coder_agent.main.env` and the Dockerfile's `/etc/profile.d/20-postgres.sh`
- `templates/python-ai/README.md` documents what ships, connection facts, the Docker-in-Docker impossibility, the persistence model and its limits, ops one-liners, and 4 new deferred live-verification checklist items

## Task Commits

Each task was committed atomically:

1. **Task 1: Bake PostgreSQL + pgvector into the workspace image** - `44edab5` (feat)
2. **Task 2: Start Postgres idempotently from the agent** - `8746eff` (feat)
3. **Task 3: Document the database and extend the live-verification checklist** - `7868477` (docs)

_Note: docs/state commits (SUMMARY.md, STATE.md) are handled by the orchestrator, not this executor._

## Files Created/Modified
- `templates/python-ai/Dockerfile` - New RUN block installs postgresql/postgresql-contrib/postgresql-$PG_MAJOR-pgvector, drops the default Debian cluster, chowns the socket dir to `coder`, writes `/etc/profile.d/20-postgres.sh`
- `templates/python-ai/main.tf` - New guarded startup_script block (initdb/pg_ctl/createdb/CREATE EXTENSION), two new agent env entries (PGDATA, DATABASE_URL)
- `templates/python-ai/README.md` - New `## PostgreSQL + pgvector` section, "What it provides" bullet, 4 new checklist items

## Decisions Made
See `key-decisions` in frontmatter. Summary: data lives on `/home/coder/.pgdata` (not the Debian cluster, which is deliberately dropped) because the workspace container is ephemeral; `coder` is the DB superuser by construction; the Postgres major version is derived at both build and runtime rather than hardcoded, since the offline smoke test itself resolved a different major (16 on this arm64 test host) than the live-probed amd64 target (18) — directly validating the design constraint.

## Deviations from Plan

None - plan executed exactly as written. The offline smoke test's Postgres major (16, arm64 local test image) differed from the plan's live-probed ground truth (18, amd64 target), but this was expected and anticipated by the plan's own design constraint (never hardcode the major) rather than a deviation from it — no fallback locale or workaround was needed, and the plan's exact runtime sequence worked unmodified.

## Issues Encountered
None. `terraform fmt -check -diff` and `terraform validate` both passed cleanly on the first run; the `.terraform/` provider cache was removed after validation per the plan's requirement.

Note: the plan's brace-expansion verification heuristic (`grep -c '[^$]\${[A-Za-z_]'` over the startup_script heredoc) reports 2 matches, but both are the pre-existing `${local.project_folder}` and `${local.repo_url}` Terraform interpolations already present in the file before this plan touched it (legitimate Terraform value injection, not shell brace expansion). Verified in isolation that the new Postgres block introduces zero such matches, satisfying the actual intent of design constraint 2 (bare `$VAR` shell forms only in the new code).

## User Setup Required

None - no external service configuration required. LIVE verification (workspace start, `psql -d coder`, pgvector extversion, cross-restart persistence, idempotence) is deferred per project practice — no running Coder server in this environment. Checklist items added to `templates/python-ai/README.md` under "DEFERRED LIVE-VERIFICATION CHECKLIST".

## Next Phase Readiness
- `templates/python-ai/` is ready for `coder templates push python-ai` and live verification on a real Coder host.
- No blockers. The next operator action is running the 4 new README checklist items against a live workspace after push.

---
*Phase: quick-260815-q5z*
*Completed: 2026-08-15*

## Self-Check: PASSED

- FOUND: templates/python-ai/Dockerfile
- FOUND: templates/python-ai/main.tf
- FOUND: templates/python-ai/README.md
- FOUND: .planning/quick/260815-q5z-add-postgresql-pgvector-to-the-python-ai/260815-q5z-SUMMARY.md
- FOUND: 44edab5 (Task 1 commit)
- FOUND: 8746eff (Task 2 commit)
- FOUND: 7868477 (Task 3 commit)
