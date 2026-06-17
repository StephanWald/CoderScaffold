---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Portable Claude Code Setup
status: complete
stopped_at: Completed 04-02-PLAN.md (README Claude Code operator runbook)
last_updated: "2026-06-17T18:12:00Z"
last_activity: 2026-06-17 -- Phase 04 fully complete
progress:
  total_phases: 1
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-17)

**Core value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.
**Current focus:** Phase 04 — portable-claude-config

## Current Position

Phase: 04 (portable-claude-config) — COMPLETE
Plan: 2 of 2 (all complete)
Status: Phase complete; milestone v1.1 complete
Last activity: 2026-06-17 -- Phase 04 plan 02 complete

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
| Phase 04-portable-claude-config P01 | 28 | 3 tasks | 1 files |
| Phase 04-portable-claude-config P02 | 1min | 1 tasks | 1 files |

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
- [Phase 04 — pre-planning OPEN]: CLAUDE_CONFIG_DIR (env var, simpler) vs neutral-mount+symlinks (reliable, no undocumented behavior) — must be resolved empirically before coding; default recommendation is symlinks (Option B)
- [Phase 04-01]: Neutral-mount + symlink approach locked (D-01) — CLAUDE_CONFIG_DIR rejected (undocumented, issue #25762 open, #3833 closed not planned)
- [Phase 04-01]: Volume name coder-${owner-uuid}-claude keyed on owner UUID not username — rename-safe (D-03)
- [Phase 04-01]: prevent_destroy=true on claude_config_volume — workspace deletion never destroys shared auth (D-03)
- [Phase 04-01]: anthropic_api_key variable defaults to "" — OAuth first-run login is default path, API key is inert override (D-07)
- [Phase 04-01]: claude_code_version intentionally unpinned — latest-on-start (D-06, deliberate exception to pin-everything ethos)
- [Phase 04-01]: [REUSABLE] drop-in snippet shipped inline in main.tf — no separate example file (D-08)
- [Phase 04-01]: terraform/tofu not in env — grep assertions served as authoritative validation gate for this plan

### Pending Todos

None. All planned work for milestone v1.1 is complete.

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

Last session: 2026-06-17T18:12:00Z
Stopped at: Completed 04-02-PLAN.md (README Claude Code operator runbook)
Resume file: None

## Operator Next Steps

Milestone v1.1 (Portable Claude Code Setup) is complete. All 2 plans executed.
Next: push templates/docker to Coder server and validate live behavior.
