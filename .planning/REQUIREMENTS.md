# Requirements: Coder Production Scaffold

**Defined:** 2026-06-16
**Core Value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Server & Persistence

- [ ] **SRV-01**: Postgres data persists on a host-disk bind mount at a configurable path (`CODER_PG_DATA_DIR`, default `./data/postgres`), surviving container recreation
- [ ] **SRV-02**: Coder server image is pinned to a specific version (`ghcr.io/coder/coder:v2.33.8`), with the reference overridable via `CODER_REPO`/`CODER_VERSION`
- [ ] **SRV-03**: Both services declare a restart policy (`unless-stopped`) so they recover after host reboot
- [ ] **SRV-04**: Coder server has a healthcheck so `depends_on` and operators can detect readiness
- [ ] **SRV-05**: Operator can set Postgres bind-mount ownership to UID 999 (documented pre-`up` `chown` step) so the database initializes cleanly

### Configuration

- [ ] **CFG-01**: A committed `.env.example` documents every configuration variable with safe placeholder values
- [ ] **CFG-02**: A local `.env` (gitignored) supplies real configuration and secrets to compose
- [ ] **CFG-03**: `CODER_ACCESS_URL` is set from `.env` to the public-facing URL, disabling Coder's convenience dev tunnel
- [ ] **CFG-04**: `CODER_WILDCARD_ACCESS_URL` is set from `.env` so workspace apps resolve under a wildcard subdomain
- [ ] **CFG-05**: Database credentials (`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`) are sourced from `.env` and reflected in `CODER_PG_CONNECTION_URL`

### Operations & Documentation

- [ ] **OPS-01**: README documents the external reverse-proxy contract: HTTP `:7080`, wildcard TLS cert for `*.<apps-domain>`, preserved `Host` + WebSocket upgrade headers, no terminal-breaking buffering
- [ ] **OPS-02**: README documents first-admin bootstrap and the start-order caveat (DB-first / create-admin / start server)
- [ ] **OPS-03**: README documents the `chown 999:999` prerequisite and bring-up sequence

### Backup & Restore

- [ ] **BAK-01**: `scripts/backup.sh` produces a non-interactive custom-format dump (`pg_dump -Fc` via `docker compose exec -T`) written to a host path (default `./backups/`)
- [ ] **BAK-02**: `scripts/restore.sh` restores a chosen dump into the database safely (handles clean/recreate and role ownership), non-interactively
- [ ] **BAK-03**: Both scripts read configuration from `.env`, avoid interactive password prompts, and return meaningful exit codes so an external scheduler/backup tool can invoke them

### Workspace Template

- [ ] **TPL-01**: A Docker-based Terraform template (`templates/docker/`) provisions workspaces as containers on the host via the Docker socket
- [ ] **TPL-02**: Template exposes code-server (browser VSCode) as a workspace app via the `coder/code-server` module
- [ ] **TPL-03**: Template supports JetBrains Gateway (IntelliJ) connectivity via the `coder/jetbrains-gateway` module
- [ ] **TPL-04**: Workspace `/home` is a persistent volume that survives stop/start
- [ ] **TPL-05**: Template handles Docker socket access (documented `group_add` / GID) so workspace provisioning works
- [ ] **TPL-06**: Workspace agent reaches the Coder server access URL reliably (e.g. `host.docker.internal` handling) so workspaces connect

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### AI & MCP Integration

- **AI-01**: Coder Tasks wired directly via a `coder_ai_task` resource (independent of the `claude-code` module, since v5 dropped that wiring)
- **AI-02**: `claude-code` module installed in workspaces with `ANTHROPIC_API_KEY` sourced from `.env`
- **AI-03**: Coder's own MCP server exposed (`coder exp mcp server`) so external agents can drive the instance
- **AI-04**: In-workspace MCP servers (filesystem/git/fetch) preconfigured for the in-container agent

### Quality of Life

- **QOL-01**: Dotfiles module so developers bring personal shell/editor config into workspaces
- **QOL-02**: Backup retention/pruning policy in the backup script
- **QOL-03**: Workspace resource limits (CPU/memory) configurable in the template

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Bundled TLS / reverse proxy (Caddy/Traefik) | TLS terminated by an external proxy the operator runs separately; scaffold only documents the contract |
| Scheduled/automated backups (cron container, timers) | Backup scripts are built cron-friendly; the scheduler itself is deferred |
| Multi-host / Kubernetes deployment | Single Docker host only; workspaces run as containers via the mounted socket |
| Managed Postgres (RDS/Cloud SQL) | Self-hosted Postgres container is the target; external DB is a later option |
| OIDC / SSO | Built-in email/password admin is sufficient for the initial deployment |
| HTTP MCP transport (`mcp-server-http`) | Experimental in v2.33.x; design around stdio if/when AI lands in v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRV-01 | Phase 1 | Pending |
| SRV-02 | Phase 1 | Pending |
| SRV-03 | Phase 1 | Pending |
| SRV-04 | Phase 1 | Pending |
| SRV-05 | Phase 1 | Pending |
| CFG-01 | Phase 1 | Pending |
| CFG-02 | Phase 1 | Pending |
| CFG-03 | Phase 1 | Pending |
| CFG-04 | Phase 1 | Pending |
| CFG-05 | Phase 1 | Pending |
| OPS-01 | Phase 1 | Pending |
| OPS-02 | Phase 1 | Pending |
| OPS-03 | Phase 1 | Pending |
| BAK-01 | Phase 2 | Pending |
| BAK-02 | Phase 2 | Pending |
| BAK-03 | Phase 2 | Pending |
| TPL-01 | Phase 3 | Pending |
| TPL-02 | Phase 3 | Pending |
| TPL-03 | Phase 3 | Pending |
| TPL-04 | Phase 3 | Pending |
| TPL-05 | Phase 3 | Pending |
| TPL-06 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 22 total (SRV-01..05, CFG-01..05, OPS-01..03, BAK-01..03, TPL-01..06)
- Mapped to phases: 22
- Unmapped: 0 ✓

Note: Original file stated "23 total" — recount of explicit IDs yields 22. No orphans.

---
*Requirements defined: 2026-06-16*
*Last updated: 2026-06-16 after roadmap creation (traceability populated)*
