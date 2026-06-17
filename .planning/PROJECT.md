# Coder Production Scaffold

## What This Is

A Docker Compose–based, production-ready scaffold for self-hosting [Coder](https://coder.com) (the self-hosted cloud development environment platform). It refines the upstream Docker install (https://coder.com/docs/install/docker) into a deployable environment with durable Postgres persistence, database backup/restore tooling, environment-driven configuration, and a starter workspace template that gives developers VSCode (code-server) and IntelliJ (JetBrains Gateway) dev containers. (AI agent + MCP integration is planned for v2.)

**Shipped: v1.0 MVP (2026-06-17)** — all 22 v1 requirements delivered across 3 phases. See `.planning/MILESTONES.md`.

## Core Value

A Coder server you can stand up, point at a real public URL, and trust with persistent data — the Postgres state survives container recreation and can be backed up/restored.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Postgres data persists across container recreation via a named volume by default (`coder_pgdata`, cross-platform); a host-disk bind mount is opt-in via `CODER_PG_DATA_DIR=./data/postgres` (Linux, requires `chown 999:999`) — Phase 1
- ✓ `.env.example` committed; local `.env` (gitignored) holds all configuration — Phase 1
- ✓ `CODER_ACCESS_URL` set from `.env` to the public-facing URL, which disables Coder's convenience dev tunnel — Phase 1
- ✓ `CODER_WILDCARD_ACCESS_URL` configured so workspace apps resolve under a wildcard subdomain — Phase 1
- ✓ Coder server image pinned to a specific version (not `:latest`) with restart policy and healthcheck — Phase 1
- ✓ Document the external-reverse-proxy contract: scaffold serves HTTP on `7080`; an upstream proxy terminates TLS and routes the wildcard apps subdomain — Phase 1
- ✓ `pg_dump` backup script writing dumps to host disk, parameterized and cron-friendly (clean exit codes, no interactive prompts) — Phase 2
- ✓ `pg_restore` restore script that restores a dump into the database — Phase 2
- ✓ Docker-based Terraform workspace template (`templates/docker/`) provisioning dev containers via the Docker socket — Phase 3
- ✓ Template wires code-server (embedded VSCode) into workspaces (`coder/code-server` 1.5.0) — Phase 3
- ✓ Template supports JetBrains Gateway (IntelliJ) connectivity (`coder/jetbrains-gateway` 1.2.6) — Phase 3
- ✓ Workspace `/home` persists across stop/start (per-workspace Docker volume); agent reaches the access URL via `host.docker.internal`/`host-gateway` — Phase 3

### Active

<!-- Current scope. Building toward these. Next milestone (v2) — not yet planned. -->

- (None — v1.0 shipped. Next milestone v2 candidates below; run `/gsd-new-milestone` to scope them.)
- [ ] (v2) AI/MCP integration — Coder Tasks, `claude-code` module with `ANTHROPIC_API_KEY`, Coder's MCP server, in-workspace MCP servers (AI-01..04)
- [ ] (v2) Quality of life — dotfiles module, backup retention/pruning, workspace CPU/memory limits (QOL-01..03)

> **Scope note (2026-06-16):** during requirements scoping the AI/MCP layer was deferred to v2 (see Out of Scope). v1 delivered the production server, persistence, backups, and the VSCode/IntelliJ workspace template.

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Bundled TLS / reverse proxy (Caddy/Traefik) — TLS is terminated by an external proxy the operator runs separately; scaffold only documents the contract
- Scheduled/automated backups (cron container, timers) — backup scripts are built cron-friendly so external scheduling can be added later, but the scheduler itself is deferred
- Multi-host / Kubernetes deployment — single Docker host only; workspaces run as containers via the mounted Docker socket
- Managed Postgres (RDS/Cloud SQL) — self-hosted Postgres container is the target; external DB is a later option
- AI/MCP integration (Coder Tasks + `ANTHROPIC_API_KEY`, `coder exp mcp` server, in-workspace MCP servers) — **deferred to v2**; v1 focuses on a solid production foundation first

## Context

- **Starting point**: this directory already contains the upstream `compose.yaml` from Coder's Docker install docs (Coder server + `postgres:17`, currently using named volumes and `:latest`). It is the refinement baseline.
- **Deployment model**: single Docker host. The Coder server mounts `/var/run/docker.sock` to provision workspaces as containers on the same host (consistent with the Docker template choice).
- **Public URL behavior**: setting `CODER_ACCESS_URL` to a reachable IP/domain disables the `*.try.coder.app` convenience tunnel Coder builds on startup. For non-Docker templates the access URL cannot be `localhost`/`127.0.0.1`.
- **AI toolchain**: agent integration defaults to Claude; provider is Anthropic (`ANTHROPIC_API_KEY`). Coder Tasks is the agent-agnostic framework so other agents (Goose, etc.) can be selected later.
- **Coder concepts**: workspaces are defined by Terraform *templates*; workspace apps (like code-server) are exposed under a wildcard subdomain, which is why the external proxy must route `*.<apps-domain>`.

## Constraints

- **Tech stack**: Docker Compose, `postgres` (≥13, upstream uses 17), Coder server image (`ghcr.io/coder/coder`), Terraform for the workspace template.
- **Compatibility**: keep the Coder image reference overridable (`CODER_REPO`/`CODER_VERSION`) — upstream docs/automations depend on a stable reference.
- **Security**: all secrets (DB password, `ANTHROPIC_API_KEY`) live in gitignored `.env`; only `.env.example` with placeholders is committed.
- **Operability**: backup/restore scripts must be non-interactive and return meaningful exit codes so external schedulers/backup tooling can call them.
- **Networking**: server binds `0.0.0.0:7080` (HTTP); TLS and the wildcard apps subdomain are an external-proxy responsibility.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Postgres data on named volume by default (`coder_pgdata`), host bind mount opt-in via `CODER_PG_DATA_DIR` | Revised in Phase 1 (01-01): bind-mounted PGDATA crash-loops Postgres on macOS/Windows Docker Desktop (VirtioFS denies chown). pg_dump backups run via `docker compose exec -T` and are transparent to the storage backend, so host-visible files aren't needed; named volume is cross-platform and drops the chown prerequisite. Bind mount stays available for operators who want host-visible files (Linux). | ✓ Phase 1 |
| TLS via external reverse proxy, not bundled | Operator already terminates TLS upstream; keeps scaffold simple and HTTP-only | ✓ Phase 1 — reverse-proxy contract documented in README (OPS-01); proxy itself out of scope |
| Backup = scripts only, cron-friendly (no scheduler) | Want backup primitives now; scheduling integrated later | ✓ Phase 2 — `scripts/backup.sh` + `scripts/restore.sh`, non-interactive with clean exit codes; round-trip UAT verified |
| Include Docker workspace template with VSCode + IntelliJ | Core developer experience goal for the instance | ✓ Phase 3 — `templates/docker/main.tf` with code-server 1.5.0 + jetbrains-gateway 1.2.6; UAT-confirmed on Docker Desktop |
| Coder Tasks (agent-agnostic), default Claude/Anthropic | Avoid locking to one agent while matching current toolchain | — Deferred to v2 |
| MCP both ways: Coder's MCP server + in-container MCP | Drive Coder from external agents and equip in-workspace agents | — Deferred to v2 |
| Pin Coder image version, keep reference overridable | Production reproducibility without breaking upstream automations | ✓ Phase 1 — default `v2.33.8`, overridable via `CODER_REPO`/`CODER_VERSION` |
| Workspace home volume keyed on workspace UUID with `ignore_changes = [name]` | Rename-safe persistence without freezing all attributes (code-review WR-02) | ✓ Phase 3 |
| Narrow agent init-script `host.docker.internal` rewrite to the access-URL host only | Avoid global loopback rewrite in the init script (code-review WR-01) | ✓ Phase 3 |

## Current State

**Shipped:** v1.0 MVP — 2026-06-17 (3 phases, 7 plans, 22/22 v1 requirements).

The scaffold delivers: a hardened `compose.yaml` (pinned Coder `v2.33.8` + `postgres:17`, restart policies, healthcheck, env-driven config, named-volume Postgres with opt-in host bind mount); non-interactive `pg_dump`/`pg_restore` backup tooling (`scripts/backup.sh`, `scripts/restore.sh`); a committed `.env.example` + operator README runbook (reverse-proxy contract, first-admin bootstrap, bring-up sequence); and a Docker workspace Terraform template (`templates/docker/main.tf`) wiring code-server (VS Code) + JetBrains Gateway (IntelliJ) with persistent `/home` and host-gateway connectivity.

**Codebase:** 8 source files — `compose.yaml`, `.env.example`, `README.md`, `CLAUDE.md`, `scripts/backup.sh`, `scripts/restore.sh`, `templates/docker/main.tf`, `.gitignore`. Stack: Docker Compose, Postgres 17, Coder `v2.33.8`, Terraform (kreuzwerker/docker ~> 4.4, coder/coder ~> 2.18).

**Known deferred at close (acknowledged, not blocking):** Phases 1 & 2 verification status is `human_needed` — functionally complete and in use, but formal UAT was not recorded (see STATE.md → Deferred Items). Phase 3 UAT passed (SC-1..SC-5).

**Next milestone (v2 — not yet planned):** AI/MCP integration (AI-01..04) and quality-of-life items (QOL-01..03). Run `/gsd-new-milestone` to scope.

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-17 after v1.0 milestone*
