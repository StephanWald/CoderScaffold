# Walking Skeleton — Coder Production Scaffold

**Phase:** 1
**Generated:** 2026-06-16

## Capability Proven End-to-End

An operator runs `docker compose up -d` and reaches the Coder UI at the configured `CODER_ACCESS_URL`, where Coder is connected to Postgres whose data lives on a host bind mount that survives container recreation.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Orchestration | Docker Compose v2 (single host, two services: `coder` + `database`) | Single-host deployment; no Swarm/K8s. `docker compose` plugin, never the deprecated `docker-compose` v1. |
| Coder image | `ghcr.io/coder/coder:v2.33.8`, overridable via `${CODER_REPO}`/`${CODER_VERSION}` | Stable track per CLAUDE.md; pinned (never `:latest`) for reproducibility and rollback; reference kept overridable because upstream docs/automations depend on it. |
| Data layer | `postgres:17`, reached by service name `database` (no host port) | Coder's current default and minimum-supported track; service-name DSN avoids exposing Postgres on the host network. |
| Data persistence | Host bind mount `${CODER_PG_DATA_DIR:-./data/postgres}` (NOT a named volume) | Data is directly visible on the host for the Phase 2 backup scripts and survives container recreation. Requires a `chown -R 999:999` pre-step (UID 999 = postgres). |
| Health signaling | Docker healthcheck `curl -f http://localhost:7080/healthz` on coder; `pg_isready` on database; `depends_on: condition: service_healthy` gates startup ordering | `/healthz` is unauthenticated and returns `OK`; gates DB-first ordering on `docker compose up` (D-02). `start_period: 30s` covers Coder's DB-migration window. |
| Restart policy | `restart: unless-stopped` on both services | Recover after crash/OOM/host reboot; on reboot Coder retries the DB connection until Postgres is ready. |
| TLS / ingress | External reverse proxy (operator-run); scaffold is HTTP-only on `0.0.0.0:7080` | Explicitly out of scope to bundle a proxy; README documents the contract (wildcard TLS, Host verbatim, WebSocket + DERP passthrough, no buffering). |
| Configuration | `.env` (gitignored, real secrets) + `.env.example` (committed placeholders) + compose `${VAR:-default}` fallbacks | Secrets never in git; defaults preserve the zero-setup quickstart. |
| First admin | Built-in UI first-run (no `CODER_FIRST_USER_*` env vars) | D-01: avoids storing an admin password on disk. |
| Telemetry | Left at Coder's default (unset) | D-10: do not force-disable; operators opt out in `.env` if desired. |
| Directory layout | Flat repo root: `compose.yaml`, `.env.example`, `.gitignore`, `README.md`, `data/postgres/` (bind mount, gitignored), `backups/` (Phase 2, gitignored) | Matches RESEARCH recommended structure; scripts (Phase 2) under `scripts/`, template (Phase 3) under `templates/docker/`. |

## Stack Touched in Phase 1

- [x] Project scaffold — hardened `compose.yaml` two-service stack + `.gitignore` (Plan 01)
- [x] Routing — Coder server reachable on host port `7080` (HTTP) at `CODER_ACCESS_URL`
- [x] Database — real write + persist: Postgres initializes on the host bind mount and data survives `docker compose down && up` (Plan 01, SRV-01)
- [x] UI interaction — operator opens `CODER_ACCESS_URL` and completes the first-run admin creation (Plan 01 checkpoint; documented in Plan 02 README)
- [x] Deployment — documented local full-stack run command: `mkdir -p ./data/postgres && sudo chown -R 999:999 ./data/postgres && docker compose up -d` (Plan 02 README)

## Out of Scope (Deferred to Later Slices)

- Backup / restore scripts (`scripts/backup.sh`, `scripts/restore.sh`) — Phase 2 (BAK-01..03)
- Docker workspace Terraform template (`templates/docker/`), code-server, JetBrains Gateway, persistent `/home`, socket GID handling — Phase 3 (TPL-01..06)
- Bundled TLS / reverse-proxy config files — out of scope (documented as a contract only, D-05)
- Env-var admin autocreate (`CODER_FIRST_USER_*`) — rejected (D-01)
- Telemetry default-off posture — left at Coder default (D-10)
- AI/MCP integration, dotfiles, backup retention, workspace resource limits — v2

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **Phase 2:** Operator can take a verified `pg_dump -Fc` backup of the Coder DB and restore it non-interactively — built on Phase 1's host bind-mount layout and `.env` config contract.
- **Phase 3:** Developer can create a workspace from `templates/docker/` with code-server and JetBrains Gateway and a persistent `/home` — built on Phase 1's working access and wildcard URLs.
