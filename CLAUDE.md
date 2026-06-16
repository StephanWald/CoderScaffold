# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This directory is a **Docker Compose deployment** of [Coder](https://coder.com) (the self-hosted cloud development environment platform). It is not application source — it contains no Go/TypeScript code, no build, no tests. The only artifact is `compose.yaml`, which runs the prebuilt `ghcr.io/coder/coder` image against a PostgreSQL database.

## Commands

```bash
docker compose up -d        # Start Coder + Postgres in the background
docker compose down         # Stop the stack (volumes persist)
docker compose logs -f coder # Tail the Coder server logs
docker compose pull         # Fetch a newer image, then `up -d` to apply
```

Coder serves on **http://localhost:7080** once up.

### Resetting state

State lives entirely in two named Docker volumes — there is no on-disk data to edit:

```bash
docker volume rm coder_coder_data  # Wipe the Postgres database (full reset)
docker volume rm coder_coder_home  # Reset the dev tunnel URL (*.try.coder.app)
```

## Architecture

Two services in `compose.yaml`:

- **`coder`** — the Coder control plane. Mounts the host Docker socket (`/var/run/docker.sock`) so it can provision workspaces as containers on the host. Depends on `database` being healthy before starting.
- **`database`** — PostgreSQL 17 (minimum supported is 13). Coder connects via `CODER_PG_CONNECTION_URL`.

Configuration is driven by environment variables with `${VAR:-default}` fallbacks, so the stack runs with zero setup but every value is overridable from the shell environment or a `.env` file. Key ones:

- `CODER_VERSION` / `CODER_REPO` — pin the image tag/registry. **Keep the image reference stable** — a comment in `compose.yaml` notes it is depended on by Coder's documentation and automations.
- `CODER_ACCESS_URL` — **must** be an IP or domain that provisioned workspaces can reach. It cannot be `localhost`/`127.0.0.1` for non-Docker templates; the committed default of `127.0.0.1` only works for the Docker-based quickstart.
- `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` — database credentials, referenced in both the `database` service and the connection URL.

## Gotchas

- **Docker socket permissions**: if the `coder` user can't write to the host Docker socket, uncomment the `group_add` block in `compose.yaml` and set the GID to the host's `docker` group.
- The `coder_home` volume is a dev-tunnel convenience and is safe to remove in production — Coder recreates what it needs on restart.

<!-- GSD:project-start source:PROJECT.md -->

## Project

**Coder Production Scaffold**

A Docker Compose–based, production-ready scaffold for self-hosting [Coder](https://coder.com) (the self-hosted cloud development environment platform). It refines the upstream Docker install (https://coder.com/docs/install/docker) into a deployable environment with durable Postgres persistence on host disk, database backup/restore tooling, environment-driven configuration, and a starter workspace template that gives developers VSCode (code-server) and IntelliJ (JetBrains Gateway) dev containers with AI agent + MCP integration.

**Core Value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — the Postgres state survives container recreation and can be backed up/restored.

### Constraints

- **Tech stack**: Docker Compose, `postgres` (≥13, upstream uses 17), Coder server image (`ghcr.io/coder/coder`), Terraform for the workspace template.
- **Compatibility**: keep the Coder image reference overridable (`CODER_REPO`/`CODER_VERSION`) — upstream docs/automations depend on a stable reference.
- **Security**: all secrets (DB password, `ANTHROPIC_API_KEY`) live in gitignored `.env`; only `.env.example` with placeholders is committed.
- **Operability**: backup/restore scripts must be non-interactive and return meaningful exit codes so external schedulers/backup tooling can call them.
- **Networking**: server binds `0.0.0.0:7080` (HTTP); TLS and the wildcard apps subdomain are an external-proxy responsibility.

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

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

| Module | Pinned Version | Purpose | Downloads (signal) |
|--------|---------------|---------|-------------------|
| `registry.coder.com/coder/code-server/coder` | `1.5.0` | VS Code (code-server) in browser | 3,085,088 — most-used editor module |
| `registry.coder.com/coder/jetbrains-gateway/coder` | `1.2.6` | JetBrains Gateway + IntelliJ button | 3,490,057 — most-used IDE module |
| `registry.coder.com/coder/claude-code/coder` | `5.2.0` | Claude Code CLI install + auth | 920,458 — primary AI agent module |

### Supporting Libraries / Tools

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| `pg_dump` / `pg_restore` | bundled with `postgres:17` image | Database backup/restore | Run via `docker compose exec -T database`. Use custom format (`-Fc`). |
| `.pgpass` or `PGPASSWORD` env var | n/a | Non-interactive auth for backup scripts | `PGPASSWORD` is simplest for scripted `docker compose exec`; `.pgpass` is preferred for on-host `psql` sessions. |
| Docker Compose v2 (`docker compose`) | CLI bundled with Docker Desktop / Docker Engine 20.10+ | Orchestration | Use `docker compose` (plugin), not `docker-compose` (v1 Python tool, deprecated). |

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

## Data Persistence: Host Bind Mount vs Named Volume

### Bind Mount Configuration

### Permissions Gotcha (CRITICAL)

## pg_dump / pg_restore Conventions

### Backup (custom format — recommended)

- `-Fc` / `--format=custom`: Compressed, supports selective restore, required by `pg_restore`. Prefer over plain SQL for production.
- `--no-owner`: Makes dump portable across different DB users.
- `--no-acl`: Omits GRANT/REVOKE statements that are environment-specific.
- `-T` on `exec`: Disables TTY allocation — required when piping stdout to a file. Without `-T`, Docker allocates a pseudo-TTY and corrupts binary dump files.
- `PGPASSWORD` env var: Non-interactive auth. The variable is passed to the `docker compose exec` process environment, not the container's environment, so prefix it inline or export it in the script scope.

### Restore

- `--clean --if-exists`: Drops existing objects before recreating. Required for a full restore over a live database.
- Pipe via stdin (`<`) rather than passing the filename as an argument — this works identically with `docker compose exec -T` when the dump is on the host.

### .pgpass for on-host psql (optional)

## Terraform Workspace Template Structure

### Required Providers Block

### Core Resources

### code-server Module

### JetBrains Gateway Module

### Claude Code Module

### Coder Tasks (coder_ai_task)

## Coder's MCP Server (`coder exp mcp`)

### What it is

### Local invocation (for Claude Desktop / external agents)

# For any other agent:

### Remote HTTP MCP (experimental)

### In-workspace MCP servers

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

## Sources

- **GitHub Releases API** — `github.com/coder/coder` releases, `github.com/coder/terraform-provider-coder` releases, `github.com/kreuzwerker/terraform-provider-docker` releases — HIGH confidence (direct API, confirmed 2026-06-16)
- **Coder Registry API** — `registry.coder.com/api/modules` — module versions, variables, and source for `coder/claude-code 5.2.0`, `coder/code-server 1.5.0`, `coder/jetbrains-gateway 1.2.6`, `coder/mux 1.4.3` — HIGH confidence
- **Context7 / `coder/terraform-provider-coder`** — `coder_agent`, `coder_app`, `coder_ai_task`, `coder_task` data source schema — HIGH confidence
- **coder.com/docs/install/docker** — Baseline compose file, environment variable documentation — HIGH confidence
- **coder.com/docs/ai-coder/mcp-server** — `coder exp mcp server` behavior, remote HTTP experiment flags — MEDIUM confidence (experimental feature, subject to change)
- **coder.com/docs/ai-coder/tasks** — Coder Tasks architecture, `coder_ai_task` requirement — HIGH confidence
- **docker-library/postgres GitHub issues #1010, #26** — UID 999 bind mount permissions pattern — HIGH confidence (well-established Docker community knowledge)
- **Coder release notes** — Stable (`v2.33.x`) vs mainline (`v2.34.x`) track distinction — HIGH confidence

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
