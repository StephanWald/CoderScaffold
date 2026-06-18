# Stack Research

**Domain:** Self-hosted Coder on Docker Compose (single-host, production-ready)
**Researched:** 2026-06-16
**Confidence:** HIGH (verified against GitHub releases API, Coder registry API, and official docs)

---

## Recommended Stack

### Core Technologies

| Technology | Version / Tag | Purpose | Why Recommended |
|------------|---------------|---------|-----------------|
| `ghcr.io/coder/coder` | `v2.33.8` (stable) | Coder server | `v2.33.x` is the current "stable" track; enterprise-grade. `v2.34.x` is mainline (Coder explicitly warns enterprise customers without staging to prefer stable). Never use `:latest` in production — it prevents rollback and breaks reproducibility. |
| `postgres` | `17` | Workspace metadata store | Coder minimum is Postgres 13; 17 is the current official Coder Docker Compose default and the latest major stable release. Pin the major (`postgres:17`) to get patch updates but not silent major upgrades. |
| `kreuzwerker/docker` TF provider | `~> 4.4` | Provisions workspace containers | The canonical community-maintained Docker provider (HashiCorp transferred ownership). `4.4.0` released 2026-05-15. |
| `coder/coder` TF provider | `~> 2.18` | Coder workspace resources | `2.18.0` is the latest release (2026-05-21). Provides `coder_agent`, `coder_app`, `coder_ai_task`, `coder_task` data source. Provider 2.x requires Coder server >= 2.18.0. |
| Terraform / OpenTofu | `>= 1.9` | Template execution engine | Coder's built-in provisioner daemon bundles a supported Terraform version. Templates using `coder/code-server` and `coder/claude-code` modules require `>= 1.9`. OpenTofu 1.x satisfies the same constraint; Coder server accepts both. |

### Coder Registry Modules

These are Terraform modules sourced from `registry.coder.com`. Pin to explicit versions.

| Module | Pinned Version | Purpose | Downloads (signal) |
|--------|---------------|---------|-------------------|
| `registry.coder.com/coder/code-server/coder` | `1.5.0` | VS Code (code-server) in browser | 3,085,088 — most-used editor module |
| `registry.coder.com/coder/jetbrains-gateway/coder` | `1.2.6` | JetBrains Gateway + IntelliJ button | 3,490,057 — most-used IDE module |
| `registry.coder.com/coder/claude-code/coder` | `5.2.0` | Claude Code CLI install + auth | 920,458 — primary AI agent module |

> **Warning on claude-code v5 vs v4:** v5 is a major refactor that dropped built-in Coder Tasks support. If you need `coder_ai_task` wired through the module, use `4.x` until v5 restores it. For this project (Tasks optional/additive), v5 is appropriate for standalone Claude installs; wire `coder_ai_task` separately in the template.

### Supporting Libraries / Tools

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| `pg_dump` / `pg_restore` | bundled with `postgres:17` image | Database backup/restore | Run via `docker compose exec -T database`. Use custom format (`-Fc`). |
| `.pgpass` or `PGPASSWORD` env var | n/a | Non-interactive auth for backup scripts | `PGPASSWORD` is simplest for scripted `docker compose exec`; `.pgpass` is preferred for on-host `psql` sessions. |
| Docker Compose v2 (`docker compose`) | CLI bundled with Docker Desktop / Docker Engine 20.10+ | Orchestration | Use `docker compose` (plugin), not `docker-compose` (v1 Python tool, deprecated). |

---

## Key Environment Variables

### Coder Server (`CODER_*`)

| Variable | Example / Default | Production Behavior |
|----------|-------------------|---------------------|
| `CODER_ACCESS_URL` | `https://coder.example.com` | **Required for production.** Setting any reachable URL disables the automatic `*.try.coder.app` dev tunnel. Must be reachable by workspaces — `127.0.0.1` only works for Docker-local templates. |
| `CODER_WILDCARD_ACCESS_URL` | `*.coder.example.com` | Enables workspace app subdomain routing. External proxy must route `*.<apps-domain>` to the Coder server. Do not use a top-level domain (cookie scope issues). |
| `CODER_PG_CONNECTION_URL` | `postgresql://user:pass@database/coder?sslmode=disable` | DSN for the Postgres container on the Docker Compose network. `sslmode=disable` is correct for intra-container traffic. |
| `CODER_HTTP_ADDRESS` | `0.0.0.0:7080` | Bind address. Default in the CLI is `127.0.0.1:3000`; the upstream compose file overrides to `0.0.0.0:7080` to expose on the Docker network and host port. Keep `7080` for the HTTP-only/proxy pattern. |
| `CODER_TELEMETRY_ENABLE` | `false` | Coder collects anonymized usage by default (`true`). Set `false` for airgapped or privacy-controlled deployments. |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | Not a Coder server variable. Pass to workspace containers via `coder_agent.env` or the `claude-code` module's `anthropic_api_key` variable. Source from `.env`, gitignored. |

### Postgres Container

| Variable | Default in compose | Notes |
|----------|--------------------|-------|
| `POSTGRES_USER` | `username` | Override via `.env` |
| `POSTGRES_PASSWORD` | `password` | Override via `.env`; used in `CODER_PG_CONNECTION_URL` |
| `POSTGRES_DB` | `coder` | Database name Coder connects to |

---

## Data Persistence: Host Bind Mount vs Named Volume

**Decision: Use a host bind mount (`./data/postgres`).**

Rationale from PROJECT.md: data must survive container recreation AND be visible on the host for backup scripts to access.

### Bind Mount Configuration

```yaml
database:
  image: "postgres:17"
  volumes:
    - ./data/postgres:/var/lib/postgresql/data
```

### Permissions Gotcha (CRITICAL)

The official `postgres` image runs as UID/GID `999` (the `postgres` user inside the container). If the host directory is owned by a different UID (e.g., `1000`), Postgres startup will fail with "Permission denied" or "could not change directory to '/var/lib/postgresql/data'".

**Fix before first `docker compose up`:**

```bash
mkdir -p ./data/postgres
sudo chown -R 999:999 ./data/postgres
```

Alternatively, let Docker create the directory on first run — but only if the parent directory is writable and you pre-chown it. Do not mount the directory itself as a Docker volume first and then switch to bind mount; the ownership will be set by the named volume driver (root), not the postgres user.

**Named volume alternative:** Named volumes handle ownership automatically (Docker sets the initial ownership to match the container user). They are simpler but opaque on the host — you cannot directly rsync or inspect the data files without `docker volume inspect` or running a helper container. For this project's backup-script requirement, bind mount is the correct choice.

---

## pg_dump / pg_restore Conventions

### Backup (custom format — recommended)

```bash
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
  pg_dump \
    --username "${POSTGRES_USER}" \
    --format=custom \
    --no-owner \
    --no-acl \
    "${POSTGRES_DB}" \
  > "./backups/coder-$(date +%Y%m%dT%H%M%S).dump"
```

Key flags:
- `-Fc` / `--format=custom`: Compressed, supports selective restore, required by `pg_restore`. Prefer over plain SQL for production.
- `--no-owner`: Makes dump portable across different DB users.
- `--no-acl`: Omits GRANT/REVOKE statements that are environment-specific.
- `-T` on `exec`: Disables TTY allocation — required when piping stdout to a file. Without `-T`, Docker allocates a pseudo-TTY and corrupts binary dump files.
- `PGPASSWORD` env var: Non-interactive auth. The variable is passed to the `docker compose exec` process environment, not the container's environment, so prefix it inline or export it in the script scope.

### Restore

```bash
PGPASSWORD="${POSTGRES_PASSWORD}" \
  docker compose exec -T database \
  pg_restore \
    --username "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --no-owner \
    --no-acl \
    --clean \
    --if-exists \
  < "./backups/coder-20260615T120000.dump"
```

Key flags:
- `--clean --if-exists`: Drops existing objects before recreating. Required for a full restore over a live database.
- Pipe via stdin (`<`) rather than passing the filename as an argument — this works identically with `docker compose exec -T` when the dump is on the host.

### .pgpass for on-host psql (optional)

If you run `psql` directly on the host (not via `docker compose exec`), create `~/.pgpass`:

```
localhost:5432:coder:username:password
```

Chmod to `0600` — Postgres refuses the file if world-readable.

---

## Terraform Workspace Template Structure

### Required Providers Block

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.18"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.4"
    }
  }
}
```

### Core Resources

```hcl
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_task" "me" {}  # for Coder Tasks support

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"

  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key  # sourced from template parameter
  }

  startup_script_behavior = "blocking"
  startup_script = <<-EOT
    # agent setup
  EOT
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.name
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  ]

  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Workspace home persistence
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }
}
```

> **`host.docker.internal` pattern:** Required because the Coder server runs in Docker. The agent init script references the Coder access URL; if `CODER_ACCESS_URL` is `127.0.0.1`, the workspace container cannot reach it. The `replace()` call rewrites localhost refs to `host.docker.internal`. In production (where `CODER_ACCESS_URL` is a real domain), this replacement is a no-op.

### code-server Module

```hcl
module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "1.5.0"

  agent_id = coder_agent.main.id
  folder   = "/home/coder"
}
```

Module provider requirements: `coder >= 2.5`, Terraform `>= 1.9`.

### JetBrains Gateway Module

```hcl
module "jetbrains-gateway" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/jetbrains-gateway/coder"
  version = "1.2.6"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"

  # Defaults: IU (IntelliJ IDEA Ultimate), PY, WS, GO, CL, PS, RM, RD, RR
  # Override to limit choices:
  jetbrains_ides = ["IU"]
}
```

Module provider requirements: `coder >= 2.5`, Terraform `>= 1.0`.

### Claude Code Module

```hcl
module "claude-code" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "5.2.0"

  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
  workdir           = "/home/coder"

  # Optional: inject MCP servers into Claude Code's user config
  mcp = jsonencode({
    mcpServers = {
      coder = {
        command = "coder"
        args    = ["exp", "mcp", "server"]
      }
    }
  })
}
```

Module provider requirements: `coder >= 2.12`, Terraform `>= 1.9`.

### Coder Tasks (coder_ai_task)

```hcl
resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  open_in      = "slim-window"
  command      = "claude"
}

resource "coder_ai_task" "task" {
  count  = data.coder_task.me.enabled ? data.coder_workspace.me.start_count : 0
  app_id = coder_app.claude.id
}
```

`coder_ai_task` makes this template selectable in the Coder Tasks UI. The `count` guard ensures the resource only provisions when running in a task context (`data.coder_task.me.enabled = true`).

---

## Coder's MCP Server (`coder exp mcp`)

### What it is

`coder exp mcp server` launches a stdio-transport MCP server using the authenticated Coder CLI session. It exposes workspace management tools (list/create/start/stop workspaces, run commands, check agent activity) to external AI agents.

### Local invocation (for Claude Desktop / external agents)

```bash
coder login https://coder.example.com
coder exp mcp configure claude-desktop   # writes ~/.config/claude/claude_desktop_config.json
coder exp mcp configure cursor           # writes Cursor MCP config
# For any other agent:
coder exp mcp server                     # starts the stdio MCP server
```

The server inherits the CLI's authenticated session (CODER_TOKEN env var or ~/.config/coderv2/session).

### Remote HTTP MCP (experimental)

Enable with server-side experiment flags:

```bash
CODER_EXPERIMENTS=oauth2,mcp-server-http coder server ...
```

This exposes an HTTP MCP endpoint at `https://coder.example.com/api/experimental/mcp/http` with OAuth2 authentication — required for web-based agents (claude.ai, etc.). As of v2.33.x this is experimental and subject to change.

### In-workspace MCP servers

MCP servers running inside workspace containers are configured via the `claude-code` module's `mcp` variable (writes to Claude Code's user-scope config) or via `.vscode/mcp.json` for VS Code-based agents. The `coder exp mcp server` command can also be run inside a workspace container to give the in-workspace agent access to the Coder control plane.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Coder image tag | Pinned version (`v2.33.8`) | `:latest` | `:latest` cannot be rolled back, drifts silently, breaks reproducibility in CI |
| Coder release track | `v2.33.x` (stable) | `v2.34.x` (mainline) | Mainline releases are explicitly flagged by Coder as "not recommended for enterprise customers without a staging environment" |
| Postgres data | Host bind mount `./data/postgres` | Named Docker volume | Named volume is opaque on host; backup scripts need direct file system access or a helper container |
| pg_dump format | Custom (`-Fc`) | Plain SQL (`-Fp`) | Plain SQL cannot be selectively restored, no built-in compression, slower for large DBs |
| Docker provider | `kreuzwerker/docker ~> 4.4` | `hashicorp/docker` | HashiCorp archived their copy and officially transferred to kreuzwerker |
| IDE module | `coder/jetbrains-gateway` | `coder/jetbrains` (Toolbox) | Gateway is the standard SSH-based remote development path; Toolbox module is heavier (manages local installations) |
| Claude module version | `coder/claude-code 5.2.0` | `4.x` | Use 4.x only if you need built-in `coder_ai_task` wiring from the module; 5.x is the current maintained version |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ghcr.io/coder/coder:latest` | Non-reproducible; can't pin or roll back; upstream automation docs warn about this | `ghcr.io/coder/coder:v2.33.8` (or current stable) |
| Named Docker volume for Postgres | Can't directly access data files from host for backup scripts | Bind mount `./data/postgres` with `chown 999:999` |
| `docker-compose` (v1, hyphenated) | Python-based v1 CLI is deprecated since 2023; missing Compose spec features | `docker compose` (v2 plugin) |
| Postgres < 13 | Not supported by Coder | `postgres:17` |
| `hashicorp/docker` Terraform provider | Archived by HashiCorp | `kreuzwerker/docker` |
| `CODER_ACCESS_URL=127.0.0.1` in production | Workspaces in non-Docker templates cannot reach the server | A real IP or domain reachable from workspace containers |
| Postgres exposed on host port in compose | Creates unnecessary attack surface; Coder server reaches it by Docker network name | Remove `ports:` from database service; use `database:5432` DSN |
| `coder/claude-code` v5 for Coder Tasks | v5 dropped `coder_ai_task` integration; currently broken for Tasks use | Use `coder/claude-code 4.x` OR wire `coder_ai_task` directly (module-independent) |

---

## Version Compatibility Matrix

| Component | Constraint | Notes |
|-----------|------------|-------|
| Coder server `v2.33.x` | Terraform provider `coder/coder >= 2.18` requires server `>= 2.18` | v2.33 satisfies this |
| `coder/code-server` module `1.5.0` | `coder/coder >= 2.5`, Terraform `>= 1.9` | |
| `coder/jetbrains-gateway` module `1.2.6` | `coder/coder >= 2.5`, Terraform `>= 1.0` | Broader Terraform constraint |
| `coder/claude-code` module `5.2.0` | `coder/coder >= 2.12`, Terraform `>= 1.9` | |
| `coder_ai_task` resource | Coder server `>= 2.28` for `enabled`/`prompt` fields | v2.33 satisfies this |
| Postgres bind mount | UID 999 ownership on host path | Pre-create directory with `sudo chown -R 999:999` |
| `kreuzwerker/docker` `4.4.0` | Terraform `>= 1.0` | |

---

## Sources

- **GitHub Releases API** — `github.com/coder/coder` releases, `github.com/coder/terraform-provider-coder` releases, `github.com/kreuzwerker/terraform-provider-docker` releases — HIGH confidence (direct API, confirmed 2026-06-16)
- **Coder Registry API** — `registry.coder.com/api/modules` — module versions, variables, and source for `coder/claude-code 5.2.0`, `coder/code-server 1.5.0`, `coder/jetbrains-gateway 1.2.6`, `coder/mux 1.4.3` — HIGH confidence
- **Context7 / `coder/terraform-provider-coder`** — `coder_agent`, `coder_app`, `coder_ai_task`, `coder_task` data source schema — HIGH confidence
- **coder.com/docs/install/docker** — Baseline compose file, environment variable documentation — HIGH confidence
- **coder.com/docs/ai-coder/mcp-server** — `coder exp mcp server` behavior, remote HTTP experiment flags — MEDIUM confidence (experimental feature, subject to change)
- **coder.com/docs/ai-coder/tasks** — Coder Tasks architecture, `coder_ai_task` requirement — HIGH confidence
- **docker-library/postgres GitHub issues #1010, #26** — UID 999 bind mount permissions pattern — HIGH confidence (well-established Docker community knowledge)
- **Coder release notes** — Stable (`v2.33.x`) vs mainline (`v2.34.x`) track distinction — HIGH confidence

---

*Stack research for: Coder self-hosted Docker Compose production scaffold*
*Researched: 2026-06-16*
