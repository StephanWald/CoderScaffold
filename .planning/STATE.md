---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: "Plan 02-01 complete: scripts/backup.sh created. Ready for Plan 02-02: restore.sh"
last_updated: "2026-06-17T07:06:17.644Z"
last_activity: 2026-06-17 -- Phase 02 execution started
progress:
  total_phases: 3
  completed_phases: 1
  total_plans: 4
  completed_plans: 3
  percent: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-16)

**Core value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.
**Current focus:** Phase 02 — backup-restore-scripts

## Current Position

Phase: 02 (backup-restore-scripts) — EXECUTING
Plan: 2 of 2
Status: Ready to execute
Last activity: 2026-06-17 -- Phase 02 execution started

Progress: [##░░░░░░░░] 25%

## Performance Metrics

**Velocity:**

- Total plans completed: 1
- Average duration: ~90 min
- Total execution time: ~1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-compose-hardening-configuration | 2 | ~135min | ~67min |

**Recent Trend:**

- Last 5 plans: 01-01 (~90min, 2 tasks, 2 files), 01-02 (~45min, 2 tasks, 2 files)
- Trend: —

*Updated after each plan completion*

| Phase 01-compose-hardening-configuration P01 | 90min | 2 tasks + 1 checkpoint | 2 files |
| Phase 01-compose-hardening-configuration P02 | 45min | 2 tasks + 1 checkpoint | 2 files |
| Phase 02-backup-restore-scripts P01 | 4min | 2 tasks | 1 files |

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3: Docker socket GID varies by host distro — document as operator-resolved, not hardcoded (TPL-05)
- Phase 3: `host.docker.internal` handling for workspace agent → access URL connectivity (TPL-06) — may need Terraform `extra_hosts` entry on Linux hosts

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| AI/MCP | Coder Tasks + claude-code + MCP servers (AI-01..04) | v2 | 2026-06-16 |
| QoL | Dotfiles module, backup retention, workspace resource limits (QOL-01..03) | v2 | 2026-06-16 |

## Session Continuity

Last session: 2026-06-17T07:06:17.632Z
Stopped at: Plan 02-01 complete: scripts/backup.sh created. Ready for Plan 02-02: restore.sh
Resume file: .planning/phases/ (Phase 02 plans TBD — run /gsd:plan-phase 02 to generate plans)
