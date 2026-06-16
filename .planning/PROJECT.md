# Coder Production Scaffold

## What This Is

A Docker Compose–based, production-ready scaffold for self-hosting [Coder](https://coder.com) (the self-hosted cloud development environment platform). It refines the upstream Docker install (https://coder.com/docs/install/docker) into a deployable environment with durable Postgres persistence on host disk, database backup/restore tooling, environment-driven configuration, and a starter workspace template that gives developers VSCode (code-server) and IntelliJ (JetBrains Gateway) dev containers with AI agent + MCP integration.

## Core Value

A Coder server you can stand up, point at a real public URL, and trust with persistent data — the Postgres state survives container recreation and can be backed up/restored.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Postgres data persists across container recreation via a named volume by default (`coder_pgdata`, cross-platform); a host-disk bind mount is opt-in via `CODER_PG_DATA_DIR=./data/postgres` (Linux, requires `chown 999:999`)
- [ ] `pg_dump` backup script writing dumps to host disk, parameterized and cron-friendly (clean exit codes, no interactive prompts)
- [ ] `pg_restore` restore script that restores a dump into the database
- [ ] `.env.example` committed; local `.env` (gitignored) holds all configuration
- [ ] `CODER_ACCESS_URL` set from `.env` to the public-facing URL, which disables Coder's convenience dev tunnel
- [ ] `CODER_WILDCARD_ACCESS_URL` configured so workspace apps resolve under a wildcard subdomain
- [ ] Coder server image pinned to a specific version (not `:latest`) with restart policy and healthcheck
- [ ] Document the external-reverse-proxy contract: scaffold serves HTTP on `7080`; an upstream proxy terminates TLS and routes the wildcard apps subdomain
- [ ] Docker-based Terraform workspace template provisioning dev containers
- [ ] Template wires code-server (embedded VSCode) into workspaces
- [ ] Template supports JetBrains Gateway (IntelliJ) connectivity into workspaces
- [ ] Workspace `/home` persists across stop/start; workspace agent reaches the access URL

> **Scope note (2026-06-16):** during requirements scoping the AI/MCP layer was deferred to v2 (see Out of Scope). v1 delivers the production server, persistence, backups, and the VSCode/IntelliJ workspace template.

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
| TLS via external reverse proxy, not bundled | Operator already terminates TLS upstream; keeps scaffold simple and HTTP-only | — Pending |
| Backup = scripts only, cron-friendly (no scheduler) | Want backup primitives now; scheduling integrated later | — Pending |
| Include Docker workspace template with VSCode + IntelliJ | Core developer experience goal for the instance | — Pending |
| Coder Tasks (agent-agnostic), default Claude/Anthropic | Avoid locking to one agent while matching current toolchain | — Pending |
| MCP both ways: Coder's MCP server + in-container MCP | Drive Coder from external agents and equip in-workspace agents | — Pending |
| Pin Coder image version, keep reference overridable | Production reproducibility without breaking upstream automations | — Pending |

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
*Last updated: 2026-06-16 after initialization*
