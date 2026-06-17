---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Awaiting next milestone
stopped_at: "Completed Phase 03 Plan 02 (README ## Workspace Template section)"
last_updated: "2026-06-17T15:32:27.595Z"
last_activity: 2026-06-17 — Milestone v1.0 completed and archived
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-16)

**Core value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.
**Current focus:** Phase 03 — docker-workspace-template

## Current Position

Phase: Milestone v1.0 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-06-17 — Milestone v1.0 completed and archived

## Performance Metrics

**Velocity:**

- Total plans completed: 6
- Average duration: ~90 min
- Total execution time: ~1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-compose-hardening-configuration | 2 | ~135min | ~67min |
| 02 | 3 | - | - |
| 03 | 2 | - | - |

**Recent Trend:**

- Last 5 plans: 01-01 (~90min, 2 tasks, 2 files), 01-02 (~45min, 2 tasks, 2 files)
- Trend: —

*Updated after each plan completion*

| Phase 01-compose-hardening-configuration P01 | 90min | 2 tasks + 1 checkpoint | 2 files |
| Phase 01-compose-hardening-configuration P02 | 45min | 2 tasks + 1 checkpoint | 2 files |
| Phase 02-backup-restore-scripts P01 | 4min | 2 tasks | 1 files |
| Phase 02-backup-restore-scripts P02 | 2min | 3 tasks | 2 files |
| Phase 03-docker-workspace-template P01 | 2min | 2 tasks | 1 files |
| Phase 03 P02 | 1min | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-roadmap: TLS via external reverse proxy — scaffold is HTTP-only on :7080
- Pre-roadmap: Backup = scripts only, cron-friendly — no scheduler in v1
- Pre-roadmap: AI/MCP deferred to v2 — v1 focuses on production foundation
- [Phase 01-01]: Pin Coder image default to v2.33.8 (stable track) via CODER_VERSION variable; keep CODER_REPO overridable
- [Phase 01-01 REVISED]: Default Postgres storage to named volume coder_pgdata (cross-platform, no chown required); host bind mount opt-in via CODER_PG_DATA_DIR=./data/postgres. Replaces locked "host bind mount" roadmap decision. Rationale: VirtioFS on macOS/Windows Docker Desktop denies chown on bind-mounted PGDATA; pg_dump logical backups are storage-backend-transparent so bind mount was never required for backups.
- [Phase 01-01]: CODER_ACCESS_URL defaults to http://127.0.0.1:7080 (full URL with protocol required by Coder; real URL in .env disables dev tunnel)
- [Phase 01-01]: CODER_WILDCARD_ACCESS_URL defaults empty (wildcard apps disabled in quickstart; set in .env for production)
- [Phase 01-02]: CODER_PG_DATA_DIR is commented opt-in in .env.example (not active) — prevents bind-mount crash-loop when operator copies .env.example to .env on macOS/Windows without editing the path
- [Phase 01-02]: README quick-start uses named-volume path (no chown required by default); chown + failure symptom scoped to the "Optional: host bind mount" subsection
- [Phase 02-backup-restore-scripts]: chmod 600 applied to dump file immediately after write (ASVS V4 — dump contains user/workspace data including tokens)
- [Phase 02-backup-restore-scripts]: PGPASSWORD as inline env prefix on docker compose exec — limits variable lifetime to single exec call, not exported
- [Phase 02-backup-restore-scripts]: Two-step dump verification: zero-byte size guard + pg_restore --list structural check (catches TTY corruption where pg_dump exits 0 but produces corrupt/empty output)
- [Phase 02-backup-restore-scripts P02]: EXIT trap registered immediately after docker compose stop coder — coder restarted even if pg_restore fails under set -e (Pitfall 6)
- [Phase 02-backup-restore-scripts P02]: Argument validation (-f regular file + -s non-zero size) placed before sourcing .env and before any service stop — no destructive action on invalid input (ASVS V5, T-02-05)
- [Phase 02-backup-restore-scripts P02]: Restore reads dump via stdin redirect (< ${DUMP_FILE}), not as pg_restore filename arg — avoids docker/compose exec binary corruption pattern (#8909)
- [Phase ?]: Display name / description / icon documented as post-push step via coder templates edit — not Terraform-managed (RESEARCH.md Pitfall 6)

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3: Docker socket GID varies by host distro — RESOLVED in templates/docker/main.tf commented block (TPL-05/D-08)
- Phase 3: `host.docker.internal` handling for workspace agent — RESOLVED via host.docker.internal/host-gateway + replace() entrypoint in templates/docker/main.tf (TPL-06/D-09)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| AI/MCP | Coder Tasks + claude-code + MCP servers (AI-01..04) | v2 | 2026-06-16 |
| QoL | Dotfiles module, backup retention, workspace resource limits (QOL-01..03) | v2 | 2026-06-16 |
| verification | Phase 01 — 01-VERIFICATION.md status human_needed (functional; formal UAT not recorded) | acknowledged at v1.0 close | 2026-06-17 |
| verification | Phase 02 — 02-VERIFICATION.md status human_needed (functional; formal UAT not recorded) | acknowledged at v1.0 close | 2026-06-17 |

## Session Continuity

Last session: 2026-06-17T14:19:33.099Z
Stopped at: Completed Phase 03 Plan 02 (README ## Workspace Template section)
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
