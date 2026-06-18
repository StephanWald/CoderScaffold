# Architecture Research

**Domain:** Self-hosted Coder production scaffold (Docker Compose, single host)
**Researched:** 2026-06-16
**Confidence:** HIGH (authoritative Coder docs, upstream compose.yaml, verified CLI reference)

---

## Standard Architecture

### System Overview

```
                         INTERNET
                             |
              ┌──────────────▼──────────────────┐
              │      External Reverse Proxy       │
              │  (Nginx / Caddy / Traefik / etc.) │
              │  Terminates TLS (443 → 7080 HTTP) │
              │  Routes coder.example.com         │
              │  Routes *.apps.example.com        │
              └──────────────┬──────────────────-─┘
                             │ HTTP (plain)
                             │ Host: coder.example.com OR *.apps.example.com
                             │ X-Forwarded-For / X-Forwarded-Proto preserved
                             ▼
              ┌──────────────────────────────────┐
              │         Docker host              │
              │                                  │
              │  ┌──────────────────────────┐    │
              │  │    coder (container)     │    │
              │  │  ghcr.io/coder/coder:X   │    │
              │  │  0.0.0.0:7080            │◄───┼── :7080 published
              │  │                          │    │
              │  │  ┌─────────────────┐     │    │
              │  │  │  coderd process │     │    │
              │  │  │  (control plane)│     │    │
              │  │  └────────┬────────┘     │    │
              │  └───────────┼──────────────┘    │
              │              │ DSN / TCP          │
              │  ┌───────────▼──────────────┐    │
              │  │   database (container)   │    │
              │  │   postgres:17            │    │
              │  │   (no published port)    │    │
              │  │   ./data/postgres →      │    │
              │  │   /var/lib/postgresql/data│   │
              │  └──────────────────────────┘    │
              │                                  │
              │  /var/run/docker.sock ────────────┼─► coder container
              │                                  │   (workspace provisioning)
              │                                  │
              │  ┌──────────────────────────┐    │
              │  │  workspace containers    │    │
              │  │  (created on-demand by   │    │
              │  │   Terraform Docker prov) │    │
              │  │                          │    │
              │  │  ┌──────────────────┐   │    │
              │  │  │  coder-agent     │   │    │
              │  │  │  (startup script)│   │    │
              │  │  │  code-server     │   │    │
              │  │  │  JetBrains GW    │   │    │
              │  │  │  Claude Code CLI │   │    │
              │  │  │  MCP servers     │   │    │
              │  │  └──────────────────┘   │    │
              │  └──────────────────────────┘    │
              └──────────────────────────────────┘
```

---

## Component Boundaries

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| External reverse proxy | TLS termination; routes both the primary domain and `*.apps` wildcard to `:7080`; preserves `Host`, `X-Forwarded-For`, `X-Forwarded-Proto`, `Upgrade` (WebSocket) headers | Operator-managed (Nginx/Caddy/Traefik); out of scope to build |
| `coder` container (coderd) | Entire Coder control plane: web UI, API, workspace lifecycle, template registry, agent relay, MCP server endpoint | `ghcr.io/coder/coder:<version>`, pinned, `restart: unless-stopped` |
| `database` container | Authoritative state store for all Coder data (users, workspaces, templates, audit log) | `postgres:17`, bind-mounted to `./data/postgres` |
| Docker socket | IPC channel through which coderd's Terraform provisioner creates/destroys workspace containers on the same host | `/var/run/docker.sock` bind-mounted into the coder container |
| Workspace container | Isolated developer environment; runs the coder-agent process plus IDE tooling | Provisioned by the Docker Terraform template; one container per workspace |
| coder-agent | Long-running process inside workspace container; connects back to coderd over WireGuard tunnel; enables terminal, port-forward, IDE, and app access | Injected via `entrypoint` in the Docker template's `docker_container` resource |
| Terraform template | Declarative definition of a workspace (providers, container config, volumes, agent, apps) stored in `templates/docker/` | Pushed to coderd via `coder templates push`; executed by the built-in Terraform provisioner |
| scripts/backup.sh | Non-interactive `pg_dump` wrapper; writes timestamped dumps to `./backups/`; cron-friendly (meaningful exit codes) | Shell script; no Docker dependency beyond `docker exec` on the database container |
| scripts/restore.sh | Non-interactive `pg_restore`/`psql` wrapper; restores a named dump file | Shell script; same interface contract as backup.sh |

---

## Data Flow

### Request Flow: Web UI / API

```
Browser → External proxy (TLS) → :7080 (HTTP)
    → coderd (coder container)
        → Postgres (state read/write)
    ← HTTP response
← Browser
```

### Request Flow: Workspace App (code-server, JetBrains)

```
Browser → External proxy (TLS)
    Host: <workspace-slug>--<app-slug>.apps.example.com
    → :7080 (HTTP)
    → coderd (wildcard routing: parses subdomain to identify workspace + app)
    → coder-agent (WireGuard tunnel, port-forward to app port inside container)
    ← streamed response / WebSocket
← Browser
```

The wildcard subdomain (`CODER_WILDCARD_ACCESS_URL=*.apps.example.com`) is what enables per-workspace, per-app URL isolation. Each workspace app gets a unique subdomain encoding the workspace and app slug. Without this, workspace apps cannot be served via the dashboard and `coder_app` resources have no routing surface. The external proxy must:
- Hold a wildcard TLS cert for `*.apps.example.com` (or use on-demand TLS)
- Forward ALL hostnames matching `*.apps.example.com` to `:7080` with the original `Host` header intact
- Forward WebSocket upgrade headers (`Connection: Upgrade`, `Upgrade: websocket`)

### Request Flow: Workspace SSH / Terminal

```
Developer CLI (coder ssh) / Web terminal
    → coderd relay (WireGuard)
    → coder-agent (inside workspace container)
    → shell / process
```

### Terraform Provisioning Flow

```
`coder templates push` (from local CLI or CI)
    → coderd API (template version stored in Postgres)

User creates workspace (web UI or CLI)
    → coderd calls built-in Terraform provisioner
    → Terraform evaluates templates/docker/main.tf
        → Docker provider via /var/run/docker.sock
            → docker pull (if needed)
            → docker volume create (home persistence)
            → docker container create/start
                env CODER_AGENT_TOKEN=<token>
                entrypoint: /tmp/coder-agent start
    → coder-agent dials coderd (CODER_AGENT_TOKEN auth)
    → Workspace status: "Running"
```

### Database Backup Flow

```
scripts/backup.sh (cron or manual)
    → docker exec database pg_dump
    → ./backups/coder_YYYYMMDD_HHMMSS.dump
    exit 0 (success) / exit 1 (failure)

scripts/restore.sh <dump-file>
    → docker exec database pg_restore / psql
    exit 0 (success) / exit 1 (failure)
```

### External Proxy Contract (Out-of-Scope Component, Documented)

| Aspect | Requirement |
|--------|-------------|
| Inbound | Port 443 (HTTPS) |
| Upstream | `http://localhost:7080` (or `http://coder:7080` if proxy runs in same Docker network) |
| TLS cert (primary) | `coder.example.com` |
| TLS cert (apps) | `*.apps.example.com` — wildcard cert required (DNS challenge) OR on-demand TLS per subdomain |
| Hostnames to route | `coder.example.com` AND `*.apps.example.com` both go to `:7080` |
| Headers to forward | `Host` (original, not rewritten), `X-Forwarded-For`, `X-Forwarded-Proto: https`, `Upgrade`, `Connection` |
| WebSocket | Must be proxied without buffering (WS upgrade must pass through) |
| Access URL env var | `CODER_ACCESS_URL=https://coder.example.com` |
| Wildcard env var | `CODER_WILDCARD_ACCESS_URL=*.apps.example.com` |

---

## Recommended Scaffold Layout

```
.                               # repo root
├── compose.yaml                # production Docker Compose (refined from upstream)
├── .env.example                # committed; all vars documented with placeholders
├── .env                        # gitignored; operator fills this in
├── .gitignore                  # ignores .env, data/, backups/
│
├── templates/
│   └── docker/                 # Terraform workspace template
│       ├── main.tf             # core: providers, coder_agent, docker_container, coder_app
│       ├── variables.tf        # optional params exposed to workspace users
│       └── .terraform.lock.hcl # pinned provider versions
│
├── scripts/
│   ├── backup.sh               # pg_dump wrapper → ./backups/
│   └── restore.sh              # pg_restore/psql wrapper ← ./backups/<file>
│
├── data/
│   └── postgres/               # Postgres bind-mount target (gitignored)
│       └── .gitkeep            # ensures dir exists in repo
│
└── backups/                    # dump output dir (gitignored)
    └── .gitkeep
```

### Structure Rationale

- **compose.yaml at root:** Standard Docker Compose convention; single file is sufficient at this scale.
- **templates/docker/:** Terraform workspace template is a first-class project artifact, not a script. Subfolder allows multiple templates later (e.g., `templates/docker-gpu/`).
- **scripts/:** Operational tooling separate from template Terraform. Scripts are shell, not Terraform — no provider init needed.
- **data/postgres/:** Bind mount (not named volume) so Postgres WAL files are visible on host disk and directly accessible by backup scripts without `docker cp`. `.gitkeep` ensures dir pre-exists before `docker compose up`.
- **backups/:** Separate from `data/` to allow distinct backup rotation policies; on same host disk so `pg_dump` output is immediate without network transfer. gitignored.
- **.env.example:** Committed reference of every variable with safe placeholder values. `.env` is the operator's secret store, gitignored.

---

## Architectural Patterns

### Pattern 1: Postgres Healthcheck Gate

**What:** `database` service declares a `pg_isready` healthcheck. `coder` service has `depends_on: database: condition: service_healthy`. Compose will not start the coder container until Postgres accepts connections.

**When to use:** Always — coderd will crash-loop if it reaches the DB DSN before Postgres is ready.

**Trade-offs:** Adds a few seconds to cold-start. Eliminates a class of startup race conditions.

```yaml
database:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
    interval: 5s
    timeout: 5s
    retries: 5

coder:
  depends_on:
    database:
      condition: service_healthy
```

### Pattern 2: Host Bind Mount for Postgres Data

**What:** Postgres data directory mapped to a host path (`./data/postgres`) instead of a Docker named volume.

**When to use:** Any deployment where backup scripts run on the host or dumps must be accessible without `docker cp`.

**Trade-offs:** Named volume is more portable across hosts; bind mount requires the host path to exist before first start. The trade-off is intentional: operability over portability.

```yaml
database:
  volumes:
    - ./data/postgres:/var/lib/postgresql/data
```

### Pattern 3: Template Decoupled from Server Lifecycle

**What:** The Terraform template (`templates/docker/`) is a separate artifact pushed to the server via `coder templates push`. It is not embedded in the compose file.

**When to use:** Always with Coder — this is the intended model.

**Trade-offs:** Template push is a manual bootstrap step (or CI step) that happens after server start, not as part of `docker compose up`. This is documented in the bootstrap order below and is expected.

### Pattern 4: coder-agent Token Injection

**What:** Coderd generates a unique `CODER_AGENT_TOKEN` per workspace provisioning run. The Terraform Docker template injects it as an environment variable into the workspace container. The agent process reads it at startup to authenticate back to coderd.

**When to use:** This is the mandatory pattern for all Coder workspace templates — agent connectivity requires it.

```hcl
resource "docker_container" "workspace" {
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
}
```

### Pattern 5: Workspace App Routing via coder_app

**What:** Each tool exposed in a workspace (code-server, JetBrains Gateway button, Claude Code status) is declared as a `coder_app` resource in Terraform. Coderd uses these declarations to render dashboard app buttons and route subdomain requests.

**When to use:** Any tool that should be accessible from the Coder dashboard or via the wildcard subdomain.

```hcl
resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337"
  icon         = "/icon/code.svg"
  subdomain    = true   # serves under wildcard apps domain
  share        = "owner"
}
```

### Pattern 6: coder_ai_task for Coder Tasks

**What:** A workspace template becomes task-capable by including a `coder_ai_task` resource (Coder provider ≥ 2.13) that references the Claude Code module's `task_app_id`. The control plane uses this to label and track AI-driven task workspaces separately from interactive workspaces.

**When to use:** Any template intended to support `coder tasks run`.

```hcl
module "claude_code" {
  source                = "registry.coder.com/coder/claude-code/coder"
  agent_id              = coder_agent.main.id
  folder                = "/home/coder"
  anthropic_api_key     = var.anthropic_api_key
  experiment_report_tasks = true
}

resource "coder_ai_task" "main" {
  sidebar_app_id = module.claude_code.task_app_id
}
```

---

## Bootstrap / Build Order

Dependencies are strict — each step depends on the prior completing successfully.

```
Step 1: docker compose up -d database
        Wait for: service_healthy (pg_isready)
        Produces: Running Postgres accepting connections

        ↓

Step 2: docker compose up -d coder
        Wait for: coder healthcheck (HTTP GET /healthz → 200)
        Produces: coderd API available at :7080
        Note: depends_on in compose.yaml handles DB gate automatically

        ↓ (manual or scripted, runs outside compose)

Step 3: First admin user
        Method A (recommended, headless): coder server create-admin-user
          --postgres-url "$CODER_PG_CONNECTION_URL"
          --username admin --email admin@example.com --password ...
          (runs against DB directly; coder server must NOT be running, OR)
        Method B (while server is running): visit https://coder.example.com
          in browser; first user to sign up gets admin role automatically
        Produces: Admin credentials for CLI login

        ↓

Step 4: coder login https://coder.example.com
        (authenticates CLI session using admin credentials from Step 3)
        Produces: ~/.config/coderv2/session token

        ↓

Step 5: coder templates push docker --directory ./templates/docker/
        (uploads template to coderd; triggers Terraform plan validation)
        Produces: "docker" template available in the UI

        ↓

Step 6: coder create <workspace-name> --template docker
        (coderd calls Terraform provisioner → Docker socket → workspace container)
        Produces: Running workspace with code-server + JetBrains Gateway
```

**Key dependency chain:**
- DB must be healthy before coder starts (enforced by `depends_on` + healthcheck)
- Coder API must be up before `coder login` can succeed
- Admin user must exist before `coder login` (with credentials)
- `coder login` session must be active before `coder templates push`
- Template must exist before a workspace using it can be created

---

## MCP Integration Points

### Coder's Own MCP Server (inbound: external agents → Coder)

Coderd exposes an HTTP MCP endpoint at `https://coder.example.com/api/experimental/mcp/http`. This requires enabling experiments on the server:

```
CODER_EXPERIMENTS=oauth2,mcp-server-http
```

External agents (Claude Desktop, Cursor, custom agents) connect to this endpoint and can list workspaces, start/stop workspaces, run commands, and monitor agent activity. Authentication uses OAuth2 for remote clients or the Coder CLI token for local clients (`coder exp mcp configure claude-desktop`).

### In-Workspace MCP (outbound: agent in workspace → external MCP servers)

The Claude Code module installs the Claude Code CLI inside the workspace and can pre-configure MCP servers for the in-workspace agent. MCP server configuration is placed in the workspace via the startup script (typically written to `~/.config/claude/claude_desktop_config.json` or equivalent). The `ANTHROPIC_API_KEY` is passed from `.env` → compose env → `coder_agent` env block → workspace container environment → Claude Code CLI.

---

## Integration Points Summary

| Boundary | Direction | Protocol | Notes |
|----------|-----------|----------|-------|
| External proxy → coderd | Inbound | HTTP/1.1 + WS | Must preserve `Host` header for wildcard routing |
| coderd → Postgres | Outbound | TCP/5432 (DSN) | On internal Docker network; never published externally |
| coderd → Docker socket | Outbound | Unix socket IPC | `/var/run/docker.sock`; requires docker group membership |
| coder-agent → coderd | Outbound from workspace | WireGuard (UDP) + HTTPS relay | Agent dials coderd using `CODER_AGENT_TOKEN` |
| Developer CLI → coderd | Outbound from developer machine | HTTPS | `coder login`, `coder ssh`, `coder templates push` |
| External agent → Coder MCP | Inbound | HTTPS (HTTP MCP endpoint) | Requires `oauth2,mcp-server-http` experiments enabled |
| In-workspace agent → MCP servers | Outbound from workspace | stdio or HTTP | Configured per template; `ANTHROPIC_API_KEY` in env |
| backup.sh → Postgres | Local | `docker exec` | Runs on host; accesses container via Docker |

---

## Anti-Patterns

### Anti-Pattern 1: Named Volume for Postgres Data

**What people do:** Keep the upstream `coder_data` named volume for Postgres.

**Why it's wrong:** Named volume data lives in `/var/lib/docker/volumes/`, invisible on host filesystem. Backup scripts require `docker cp` or running `pg_dump` inside the container and piping out, making cron-friendly non-interactive scripts significantly harder. If the Docker daemon is reinstalled, named volumes may be lost.

**Do this instead:** Bind mount `./data/postgres` to `/var/lib/postgresql/data`. The directory is on host disk, backup scripts can `docker exec pg_dump` and redirect output directly to `./backups/`.

### Anti-Pattern 2: CODER_ACCESS_URL set to localhost or 127.0.0.1

**What people do:** Leave upstream default `CODER_ACCESS_URL: "127.0.0.1"` in compose.yaml.

**Why it's wrong:** Workspace containers resolve `CODER_ACCESS_URL` to dial back to coderd. `127.0.0.1` inside a workspace container points to the container itself, not the host. The coder-agent cannot connect; workspace is permanently "Connecting...".

**Do this instead:** Set `CODER_ACCESS_URL` to the externally reachable URL (`https://coder.example.com`). This also disables the `*.try.coder.app` convenience tunnel (desired for production).

### Anti-Pattern 3: Missing CODER_WILDCARD_ACCESS_URL

**What people do:** Set only `CODER_ACCESS_URL`, omit `CODER_WILDCARD_ACCESS_URL`.

**Why it's wrong:** Without the wildcard, workspace apps (code-server, port-forwarded services) cannot be served via subdomain routing. Users can still SSH and use the terminal, but app buttons in the dashboard either fail or fall back to path-based routing that the reverse proxy may not support.

**Do this instead:** Always configure `CODER_WILDCARD_ACCESS_URL=*.apps.example.com` and ensure the external proxy has a wildcard cert and routes `*.apps.example.com` to `:7080`.

### Anti-Pattern 4: Pushing Templates Before Server is Ready

**What people do:** Run `coder templates push` in an init script immediately after `docker compose up`.

**Why it's wrong:** The coderd API may not be ready even after the container starts. `coder login` will fail; `coder templates push` will fail with connection errors.

**Do this instead:** Gate bootstrap steps on the coderd healthcheck (`curl -sf http://localhost:7080/healthz`). Use a retry loop or a one-shot bootstrap container with `depends_on: coder: condition: service_healthy`.

### Anti-Pattern 5: Secrets in compose.yaml

**What people do:** Hardcode `POSTGRES_PASSWORD`, `ANTHROPIC_API_KEY` directly in `compose.yaml` or commit `.env`.

**Why it's wrong:** Secrets end up in git history.

**Do this instead:** All secrets in gitignored `.env`. `.env.example` with placeholders is the only committed file. `compose.yaml` references variables via `${VAR}` syntax.

---

## Scaling Considerations

This scaffold targets a single Docker host. Scaling concerns are provided for context, not current scope.

| Scale | Architecture Adjustment |
|-------|------------------------|
| 1-20 developers | Current architecture (single host, single coderd, Postgres on same host) — no changes needed |
| 20-100 developers | Move Postgres to a dedicated host or managed DB; separate backup host; consider pinning workspace containers to specific resources |
| 100+ developers | Multi-host Coder deployment with workspace proxies; Kubernetes-based templates; HA Postgres; out of scope for this project |

**First bottleneck on a single host:** Docker daemon concurrency — many simultaneous workspace starts will queue on the single Docker socket. Mitigate by staggering workspace start times.

**Second bottleneck:** Postgres I/O — all Coder state (workspace status polling, audit log, template versions) goes through one Postgres instance. Moving to a dedicated Postgres host on a fast disk addresses this.

---

## Sources

- [Coder Docker Install](https://coder.com/docs/install/docker) — official compose baseline, env vars, socket setup
- [Coder Reverse Proxy (Caddy)](https://coder.com/docs/tutorials/reverse-proxy-caddy) — proxy config, wildcard subdomain routing, port 7080
- [Coder Template from Scratch](https://coder.com/docs/tutorials/template-from-scratch) — coder_agent, docker_container, coder_app wiring
- [coder server create-admin-user CLI reference](https://coder.com/docs/reference/cli/server_create-admin-user) — headless first-user creation
- [Coder Tasks docs](https://coder.com/docs/ai-coder/tasks) — coder_ai_task resource, Claude Code module, ANTHROPIC_API_KEY flow
- [Coder MCP Server docs](https://coder.com/docs/ai-coder/mcp-server) — `coder exp mcp server`, HTTP MCP endpoint, experiments flag
- [coder/modules GitHub — claude-code module](https://github.com/coder/modules/tree/main/claude-code) — module inputs, CODER_MCP_CLAUDE_API_KEY env, MCP config
- [Coder Workspace Proxies](https://coder.com/docs/admin/networking/workspace-proxies) — wildcard subdomain architecture
- Upstream `compose.yaml` in this repository — baseline for refinement

---
*Architecture research for: Self-hosted Coder production scaffold (Docker Compose)*
*Researched: 2026-06-16*
