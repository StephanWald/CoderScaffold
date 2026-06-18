# Roadmap: Coder Production Scaffold

## Milestones

- ✅ **v1.0 MVP** — Phases 1–3 (shipped 2026-06-17) — see [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 Portable Claude Code Setup** — Phase 4 (shipped 2026-06-18) — see [`milestones/v1.1-ROADMAP.md`](milestones/v1.1-ROADMAP.md)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1–3) — SHIPPED 2026-06-17</summary>

- [x] Phase 1: Compose Hardening & Configuration (2/2 plans) — completed 2026-06-17
- [x] Phase 2: Backup & Restore Scripts (3/3 plans) — completed 2026-06-17
- [x] Phase 3: Docker Workspace Template (2/2 plans) — completed 2026-06-17

Full details: [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v1.1 Portable Claude Code Setup (Phase 4) — SHIPPED 2026-06-18</summary>

- [x] Phase 4: Portable Claude Config (3/3 plans) — completed 2026-06-18

Wire claude-code module v5.2.0 + per-owner shared Claude config volume into the Docker template (neutral-mount + symlink approach); ship operator runbook. UAT 4/5 passed live (auth persistence A→B, upgrade-path data-loss guards CR-01/WR-01, idempotency); owner-isolation accepted as an acknowledged gate. Two deploy blockers (G1 module args, G2 volume prevent_destroy) found & fixed live.

Full details: [`milestones/v1.1-ROADMAP.md`](milestones/v1.1-ROADMAP.md)

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Compose Hardening & Configuration | v1.0 | 2/2 | Complete | 2026-06-17 |
| 2. Backup & Restore Scripts | v1.0 | 3/3 | Complete | 2026-06-17 |
| 3. Docker Workspace Template | v1.0 | 2/2 | Complete | 2026-06-17 |
| 4. Portable Claude Config | v1.1 | 3/3 | Complete | 2026-06-18 |
