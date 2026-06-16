# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-16)

**Core value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.
**Current focus:** Phase 1 — Compose Hardening & Configuration

## Current Position

Phase: 1 of 3 (Compose Hardening & Configuration)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-06-16 — Roadmap created; 22 v1 requirements mapped across 3 phases

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-roadmap: Postgres data on host bind mount (not named volume) — data survives container recreation and is visible for backups
- Pre-roadmap: TLS via external reverse proxy — scaffold is HTTP-only on :7080
- Pre-roadmap: Backup = scripts only, cron-friendly — no scheduler in v1
- Pre-roadmap: AI/MCP deferred to v2 — v1 focuses on production foundation

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: `sudo chown -R 999:999 ./data/postgres` is a required pre-`up` step — must be clearly documented in README (OPS-03) to avoid DB crash on first start
- Phase 3: Docker socket GID varies by host distro — document as operator-resolved, not hardcoded (TPL-05)
- Phase 3: `host.docker.internal` handling for workspace agent → access URL connectivity (TPL-06) — may need Terraform `extra_hosts` entry on Linux hosts

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| AI/MCP | Coder Tasks + claude-code + MCP servers (AI-01..04) | v2 | 2026-06-16 |
| QoL | Dotfiles module, backup retention, workspace resource limits (QOL-01..03) | v2 | 2026-06-16 |

## Session Continuity

Last session: 2026-06-16
Stopped at: Roadmap created, REQUIREMENTS.md traceability updated, ready to plan Phase 1
Resume file: None
