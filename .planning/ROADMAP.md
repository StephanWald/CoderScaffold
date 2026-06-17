# Roadmap: Coder Production Scaffold

## Milestones

- ✅ **v1.0 MVP** — Phases 1–3 (shipped 2026-06-17) — see [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)
- 🚧 **v1.1 Portable Claude Code Setup** — Phase 4 (in progress — verification found gaps, gap closure planned)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1–3) — SHIPPED 2026-06-17</summary>

- [x] Phase 1: Compose Hardening & Configuration (2/2 plans) — completed 2026-06-17
- [x] Phase 2: Backup & Restore Scripts (3/3 plans) — completed 2026-06-17
- [x] Phase 3: Docker Workspace Template (2/2 plans) — completed 2026-06-17

Full details: [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)

</details>

### v1.1 Portable Claude Code Setup

- [ ] **Phase 4: Portable Claude Config** - Wire claude-code module + per-owner shared volume into the Docker template; ship operator runbook — verification found gaps (CR-01), gap closure plan 04-03 created

## Phase Details

### Phase 4: Portable Claude Config

**Goal**: A developer authenticates with Claude Code once and finds their credentials, settings, skills, and MCP servers waiting in every subsequent workspace — including newly created ones.
**Depends on**: Phase 3 (Docker workspace template)
**Requirements**: CLAUDE-01, CLAUDE-02, CLAUDE-03, CLAUDE-04, CLAUDE-05, CLAUDE-06, CLAUDE-07
**Success Criteria** (what must be TRUE):

  1. Operator runs `claude` in a fresh workspace; after authenticating once, a second workspace for the same owner starts already authenticated with no login prompt
  2. Two of the same owner's workspaces share one authenticated Claude session — `~/.claude/.credentials.json` and `~/.claude.json` (or their volume equivalents) are on a single per-owner Docker volume, not duplicated per workspace
  3. Owner's global settings, personal skills, and user-scoped MCP servers (stored in `~/.claude/`) carry into a newly created workspace without any manual copy step
  4. A different owner's workspaces are isolated — their Claude config volume is distinct and inaccessible to the first owner
  5. The README contains an operator runbook section covering: first-run login steps, what is shared across workspaces, and the concurrent-workspace write caveat

**Plans**: 3 plans

**Wave 1**

- [x] 04-01-PLAN.md — main.tf: anthropic_api_key variable, per-owner claude_config_volume, .claude-shared mount, startup_script symlinks, claude-code module, inline [REUSABLE] snippet (CLAUDE-01..06)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 04-02-PLAN.md — README operator runbook: first-run login, what is shared, seeding, concurrent-write caveat, manual volume cleanup (CLAUDE-07)
- [ ] 04-03-PLAN.md — gap closure: guard startup_script symlinks against pre-existing real ~/.claude dir + ~/.claude.json (CR-01, WR-01); correct README cleanup blast-radius wording (WR-03) (CLAUDE-03, CLAUDE-04, CLAUDE-07)

**Planning consideration**: The open architecture decision (CLAUDE_CONFIG_DIR vs neutral-mount+symlinks) was resolved in planning — locked to the neutral-mount + symlink approach per CONTEXT.md D-01 (ARCHITECTURE.md HIGH-confidence recommendation; CLAUDE_CONFIG_DIR rejected as undocumented/unimplemented).

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Compose Hardening & Configuration | v1.0 | 2/2 | Complete | 2026-06-17 |
| 2. Backup & Restore Scripts | v1.0 | 3/3 | Complete | 2026-06-17 |
| 3. Docker Workspace Template | v1.0 | 2/2 | Complete | 2026-06-17 |
| 4. Portable Claude Config | v1.1 | 2/3 | Gap Closure Planned | — |
