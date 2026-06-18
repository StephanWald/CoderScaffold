# Feature Research

**Domain:** Self-hosted Coder production scaffold (Docker Compose)
**Researched:** 2026-06-16
**Confidence:** HIGH — Coder's own docs, module registry, and upstream compose.yaml examined directly.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that make a self-hosted Coder instance production-usable. Missing any of these means the deployment is fragile, data is at risk, or developers can't reach their workspaces.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Postgres data on host bind mount** | Named Docker volumes disappear on `docker volume prune` or host migration; operators expect DB to live at a known path on disk | LOW | Change `coder_data:` named volume to a bind mount `./data/postgres:/var/lib/postgresql/data`. The `postgres:17` image already in compose just needs the mount path changed. |
| **Version-pinned Coder image** | `:latest` means an uncontrolled `docker compose pull` can break a running instance; production requires reproducibility | LOW | Replace `${CODER_VERSION:-latest}` default with a specific semver tag. Keep env-var override so ops can control upgrades deliberately. |
| **`restart: unless-stopped` on both services** | Both `coder` and `database` containers need to survive host reboots and crash-loop recovery without operator intervention | LOW | One line per service in compose.yaml. The upstream baseline omits this. |
| **Healthcheck on Postgres (already present); add one on Coder** | Coder already `depends_on: database: condition: service_healthy`. Adding a Coder-side healthcheck lets Docker detect a hung process | MEDIUM | Coder's HTTP server can be probed: `curl -f http://localhost:7080/healthz`. The `/healthz` endpoint is documented. |
| **`.env.example` + gitignored `.env`** | All secrets (DB password, API key) must not be committed; operators need a template showing required vars | LOW | `.env.example` with placeholder values committed; `.env` in `.gitignore`. The compose already uses `${VAR:-default}` interpolation. |
| **`CODER_ACCESS_URL` from `.env`** | Without a real URL Coder starts its `*.try.coder.app` convenience tunnel, which is unsuitable for production and breaks non-Docker workspace templates (cannot be localhost) | LOW | Set `CODER_ACCESS_URL` in `.env`; remove the hardcoded `127.0.0.1` in compose.yaml. |
| **`CODER_WILDCARD_ACCESS_URL` from `.env`** | Workspace apps (code-server, port-forwards) are served under a wildcard subdomain. Without this, workspace apps are unreachable | LOW | Must match the pattern `*.apps.example.com` or similar. Needs to align with the external proxy's wildcard routing. |
| **Document the external-proxy contract** | Scaffold serves plain HTTP on 7080; TLS is terminated externally. Operators need to know: (1) bind port, (2) wildcard subdomain routing requirement, (3) pass `Host` header through | LOW | A comment block in compose.yaml or a `PROXY.md` section. Not a code feature but a hard operational requirement. |
| **First admin user bootstrap** | On a fresh install, someone must create the owner account before anyone can log in. `coder server create-admin-user` seeds this directly in the DB without the UI being up | LOW | Document the one-time `docker compose exec coder coder server create-admin-user` invocation in the README. |
| **`pg_dump` backup script** | Postgres data loss is unrecoverable without backups. Operators expect runnable backup tooling at the scaffold level | MEDIUM | Shell script: `docker exec` → `pg_dump -Fc` → timestamped file on host. Reads config from `.env`. Non-interactive, clean exit codes for cron compatibility. |
| **`pg_restore` restore script** | Backups are useless without a tested restore path | MEDIUM | Shell script: accepts dump path as argument, prompts (or flag) for confirmation before overwriting live DB, then `pg_restore` into the container. |

---

### Differentiators (This Scaffold vs. Bare Upstream)

Features beyond the minimal viable install that make the scaffold meaningfully better for production and AI-enabled use.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Docker workspace template (Terraform)** | The upstream compose has no template; a real template is needed before any workspace can be created | HIGH | Uses `kreuzwerker/docker` Terraform provider + Coder's Terraform provider. Creates a `docker_container` from a configurable image with a `coder_agent` inside. |
| **code-server (VSCode in browser) workspace app** | Browser-based VSCode is the default IDE experience most developers expect from a cloud dev environment | MEDIUM | Via `coder_app` resource in the Terraform template. Startup script installs `code-server` via the official installer. Served as a workspace app under the wildcard apps URL. |
| **JetBrains Gateway (IntelliJ) workspace app** | JetBrains users expect native IDE performance via Gateway, not a browser app | MEDIUM | Via the `registry.coder.com/modules/coder/jetbrains-gateway` module. The module creates a `coder_app` with a `jetbrains-gateway://` URL scheme that the local Gateway client picks up. Module accepts `jetbrains_ides`, `folder`, `agent_id`, `arch`. |
| **JetBrains IDE backend pre-installation** | First connection is slow (Gateway downloads the IDE backend). Pre-installing in the workspace image eliminates this delay | MEDIUM | Optional: use the Coder `jetbrains-preinstall` pattern in the Docker image or startup script. Useful for teams using IntelliJ daily. |
| **Persistent home directory (Docker volume)** | Code, config, shell history, and tool installations survive workspace stop/start cycles; without this every workspace restart is destructive | LOW | `docker_volume` resource in Terraform template, named with `coder_workspace.me.id` (immutable), with `lifecycle { ignore_changes = all }` to prevent accidental deletion on workspace name change. |
| **Dotfiles support** | Developers expect their shell config, aliases, and tool preferences to be applied automatically in new workspaces | LOW | Via `registry.coder.com/modules/coder/dotfiles` module in the template. User sets their dotfiles repo URL in Coder preferences; module clones and applies on startup. |
| **Coder Tasks support (`coder_ai_task`)** | Enables the Coder Tasks UI — run and monitor AI coding agents (Claude Code, Aider, Goose) as isolated workspaces from a dedicated dashboard | HIGH | Requires: (1) `coder_ai_task` Terraform resource in the template; (2) `coder_parameter` named "AI Prompt"; (3) an agent module (e.g. `registry.coder.com/modules/coder/claude-code`); (4) `ANTHROPIC_API_KEY` wired into the workspace environment. |
| **`ANTHROPIC_API_KEY` passed into workspace agent** | Claude Code (and automatic task naming) requires the API key in the workspace environment | LOW | Key sourced from `.env` → Coder server environment → Terraform template variable → `coder_agent { env { ANTHROPIC_API_KEY = ... } }`. Mark variable `sensitive = true`. |
| **Coder MCP server exposed (`coder exp mcp server`)** | Enables external AI agents (Claude Desktop, Cursor, custom agents) to drive the Coder instance: list/create/start/stop workspaces, run commands, check agent activity | LOW | The MCP server uses **stdio** transport and is launched on the operator/developer's local machine via `coder exp mcp server` after `coder login`. Scaffold should document the setup flow and `coder exp mcp configure claude-desktop` shortcut. Remote HTTP MCP endpoint is also available at `/api/experimental/mcp/http` when enabled via experiments flag. |
| **In-workspace MCP servers for the AI agent** | Equips the AI agent running inside a workspace with filesystem, git, and fetch tools so it can act autonomously on the codebase | MEDIUM | Configure `~/.config/claude/claude_desktop_config.json` (or equivalent) in the workspace startup script. Standard servers: `@modelcontextprotocol/server-filesystem`, `@modelcontextprotocol/server-git`, `@modelcontextprotocol/server-fetch`. Config written by startup script or baked into the Docker image. |
| **Backup retention (keep last N dumps)** | Naive backup scripts fill disk; production setups prune old dumps automatically | LOW | Add a `find ./data/backups -name "*.dump" -mtime +7 -delete` call at the end of the backup script. Keep it simple — no separate cron container. |
| **Coder agent startup script with git-clone** | Provides a consistent initial state (repo cloned, tools installed) when a workspace is first created, beyond just code-server | MEDIUM | Use `registry.coder.com/modules/coder/git-clone` module or a custom startup script block in the Terraform `coder_agent`. |
| **Resource limits on workspace containers** | Prevent one workspace from starving the host | MEDIUM | Docker `cpu_shares` and `memory` limits on the `docker_container` resource. Note: Docker-based limits are soft for CPU (shares, not hard cap) but hard for memory. Full hard CPU limits require Kubernetes. |

---

### Anti-Features (Explicitly Excluded from v1)

Features that are frequently requested, seem reasonable, but are deliberately not in scope. Reasons are load-bearing; do not re-add without revisiting the rationale.

| Feature | Why Requested | Why Excluded from v1 | What to Do Instead |
|---------|---------------|----------------------|-------------------|
| **Bundled TLS / reverse proxy (Caddy, Traefik, nginx)** | HTTPS is required for production; convenient to bundle | Operators already run a TLS proxy upstream (per PROJECT.md). Bundling adds operational surface, port conflicts, cert management, and ambiguity about who owns TLS. | Document the proxy contract: forward to `127.0.0.1:7080`, pass `Host`, route wildcard subdomain. Operators plug in their existing proxy. |
| **Scheduled backup container (cron sidecar)** | Automated backups are table stakes for production | Scheduling is an operational concern. A cron sidecar adds service complexity, restart ordering, log aggregation needs, and a second container to monitor. | Scripts are written cron-friendly (clean exit codes, no prompts). Operator adds an OS-level cron entry or systemd timer calling the script. This is deferred, not abandoned. |
| **Multi-host / Kubernetes deployment** | Scale-out for larger teams | The entire design (Docker socket mount, bind-mount Postgres, single-host scripts) assumes one Docker host. K8s is an architectural change, not an extension. | When the time comes, use Coder's official Kubernetes Helm chart and external managed Postgres. |
| **Managed / external Postgres (RDS, Cloud SQL)** | Reduce operational burden of DB | Adds a required external dependency, complicates the local dev story, and is orthogonal to the scaffold goal. The self-hosted Postgres container with bind mount is the target. | Switchable later: `CODER_PG_CONNECTION_URL` in `.env` already accepts any DSN. |
| **OIDC / SSO integration** | Production deployments often require SSO (Okta, Azure AD, GitHub) | Requires an external OIDC provider, significantly expands setup surface, and is not needed to validate the scaffold's core value. Password auth is sufficient for v1. | Coder supports OIDC via `CODER_OIDC_*` env vars; add as a v1.x documented extension after core is working. |
| **Monitoring / observability stack (Prometheus, Grafana, Loki)** | Production systems need metrics and logs | Adds substantial infrastructure (3+ additional containers) unrelated to the scaffold's core value. | Coder exposes `/metrics` (Prometheus format). Operators can scrape it with their existing stack. |
| **Automated image builds for workspace containers** | Custom workspace images need a CI pipeline to build and push | Out of scope for the scaffold. The Docker template should use a configurable `image` variable pointing to any registry. | Document the pattern; operator maintains their own image build pipeline. |

---

## Feature Dependencies

```
[Host-disk Postgres bind mount]
    └──required by──> [pg_dump backup script]
                          └──required by──> [pg_restore restore script]
                          └──enables──> [Backup retention / pruning]

[.env file with CODER_ACCESS_URL + CODER_WILDCARD_ACCESS_URL]
    └──required by──> [Workspace apps accessible (code-server, JetBrains)]
    └──required by──> [Coder Tasks (agent needs reachable Coder URL)]

[Docker workspace template (Terraform)]
    └──required by──> [code-server workspace app]
    └──required by──> [JetBrains Gateway workspace app]
    └──required by──> [Persistent home directory]
    └──required by──> [Dotfiles support]
    └──required by──> [Coder Tasks (coder_ai_task resource)]
    └──required by──> [In-workspace MCP servers]
    └──required by──> [Resource limits on containers]

[ANTHROPIC_API_KEY in .env]
    └──required by──> [Coder Tasks (automatic task naming + Claude module)]
    └──required by──> [Claude Code in-workspace agent]

[Coder Tasks (coder_ai_task)]
    └──requires──> [Docker workspace template]
    └──requires──> [ANTHROPIC_API_KEY wiring]
    └──requires──> [Persistent home directory] (AgentAPI state file lost without it)

[Coder MCP server (coder exp mcp server)]
    └──requires──> [CODER_ACCESS_URL configured] (MCP server connects to Coder API)
    └──independent of──> [workspace template] (operates at server level, not workspace level)

[In-workspace MCP servers]
    └──requires──> [Docker workspace template] (config lives in container startup)
    └──enhances──> [Coder Tasks] (gives the agent tools to act on the codebase)
    └──enhances──> [code-server] (agent tools available in the browser IDE environment)

[JetBrains pre-install]
    └──requires──> [JetBrains Gateway workspace app] (only meaningful if Gateway module is present)
    └──optional enhancement of──> [JetBrains Gateway workspace app]
```

### Dependency Notes

- **Persistent home required for Tasks:** Coder's AgentAPI writes a state file into the workspace home. If the home volume is ephemeral, the agent loses its session on workspace stop. Tasks without a persistent home are technically possible but operationally broken.
- **Wildcard URL gates workspace apps:** code-server and JetBrains Gateway are exposed as `coder_app` resources. These are served under the wildcard apps subdomain. If `CODER_WILDCARD_ACCESS_URL` is wrong or missing, both IDEs fail to load, making the template functionally useless even if it provisions correctly.
- **External proxy contract must be documented before template:** Template authors and operators need to know the wildcard routing requirement before they can validate that workspace apps work. This is not a code dependency but a knowledge dependency.
- **Coder Tasks require coder ≥ 2.13:** The `coder_ai_task` Terraform resource was introduced in provider version 2.13. The Terraform template must pin `required_providers { coder = { version = ">= 2.13" } }`.

---

## MVP Definition

### Launch With (v1)

The minimum set that makes this a "production-ready scaffold" rather than the upstream baseline.

- [ ] **Postgres bind mount** — data durability is the core value proposition
- [ ] **Version-pinned Coder image + restart policies** — production reproducibility and crash recovery
- [ ] **`.env.example` + secrets pattern** — security baseline; no secrets in git
- [ ] **`CODER_ACCESS_URL` + `CODER_WILDCARD_ACCESS_URL` from `.env`** — without these, workspace apps are unreachable
- [ ] **Proxy contract documented** — operators need this to configure their TLS terminator
- [ ] **Coder healthcheck on Coder container** — Docker can detect a hung server
- [ ] **`pg_dump` backup script** — production is defined by having a backup path
- [ ] **`pg_restore` restore script** — backups have no value without a tested restore
- [ ] **First admin user bootstrap documentation** — operators need to know how to seed the first account
- [ ] **Docker workspace Terraform template with code-server** — Coder is useless without at least one template
- [ ] **Persistent home directory** — workspace data must survive stop/start
- [ ] **JetBrains Gateway module in template** — stated requirement in PROJECT.md
- [ ] **`ANTHROPIC_API_KEY` wired into workspace agent** — enables Claude Code and automatic Coder Tasks naming
- [ ] **Coder Tasks (`coder_ai_task`) in template** — stated requirement in PROJECT.md
- [ ] **`coder exp mcp server` documented** — external agent integration; stated requirement
- [ ] **In-workspace MCP servers configured** — equips the AI agent with tools; stated requirement

### Add After Validation (v1.x)

- [ ] **Dotfiles module in template** — quality-of-life; add once core template is validated working
- [ ] **JetBrains IDE backend pre-installation** — improves DX but adds image build complexity; defer until JetBrains usage is confirmed
- [ ] **Backup retention / pruning in script** — add once backup script is in use and disk pressure is observed
- [ ] **Resource limits on workspace containers** — Docker CPU shares are soft limits; tune after baseline usage is known
- [ ] **OIDC / SSO configuration** — document as extension; implement when team outgrows password auth
- [ ] **`git-clone` module in template** — convenient but not required for initial template validation

### Future Consideration (v2+)

- [ ] **Multi-host / Kubernetes** — architectural change; different project
- [ ] **Managed external Postgres** — simple env-var change but out of v1 scope
- [ ] **Monitoring/observability stack** — add when operating at scale
- [ ] **Automated workspace image CI pipeline** — only needed when custom images are maintained

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Postgres bind mount | HIGH | LOW | P1 |
| Version pin + restart policy | HIGH | LOW | P1 |
| `.env` secrets pattern | HIGH | LOW | P1 |
| `CODER_ACCESS_URL` / `CODER_WILDCARD_ACCESS_URL` | HIGH | LOW | P1 |
| Proxy contract documentation | HIGH | LOW | P1 |
| `pg_dump` backup script | HIGH | MEDIUM | P1 |
| `pg_restore` restore script | HIGH | MEDIUM | P1 |
| Docker workspace template | HIGH | HIGH | P1 |
| code-server workspace app | HIGH | MEDIUM | P1 |
| Persistent home directory | HIGH | LOW | P1 |
| JetBrains Gateway module | HIGH | MEDIUM | P1 |
| `ANTHROPIC_API_KEY` wiring | HIGH | LOW | P1 |
| Coder Tasks (`coder_ai_task`) | HIGH | HIGH | P1 |
| Coder MCP server documentation | MEDIUM | LOW | P1 |
| In-workspace MCP servers | MEDIUM | MEDIUM | P1 |
| First admin bootstrap documentation | HIGH | LOW | P1 |
| Coder healthcheck | MEDIUM | LOW | P1 |
| Dotfiles module | MEDIUM | LOW | P2 |
| Backup retention / pruning | MEDIUM | LOW | P2 |
| JetBrains pre-install | MEDIUM | MEDIUM | P2 |
| Resource limits | MEDIUM | MEDIUM | P2 |
| OIDC / SSO | LOW (v1) | HIGH | P3 |
| Monitoring stack | LOW (v1) | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1 scope)
- P2: Should have, add when P1 is stable
- P3: Nice to have, future consideration

---

## Sources

- [Coder Docker Install docs](https://coder.com/docs/install/docker) — upstream compose baseline, production vs PoC distinction
- [Coder Admin Setup](https://coder.com/docs/admin/setup) — `CODER_ACCESS_URL`, `CODER_WILDCARD_ACCESS_URL`, first-boot configuration
- [Coder MCP Server docs](https://coder.com/docs/ai-coder/mcp-server) — `coder exp mcp server`, stdio transport, tools exposed, authentication model
- [Coder Tasks docs](https://coder.com/docs/ai-coder/tasks) — `coder_ai_task` resource, agent modules, API key requirements
- [Coder Tasks Core Principles](https://coder.com/docs/ai-coder/tasks-core-principles) — template requirements, AgentAPI, persistent storage requirement
- [Coder Template from Scratch](https://coder.com/docs/tutorials/template-from-scratch) — `coder_agent`, `coder_app`, startup scripts, persistent Docker volumes
- [Coder Resource Persistence](https://coder.com/docs/admin/templates/extending-templates/resource-persistence) — `ignore_changes = all`, immutable IDs, ephemeral vs persistent resources
- [Coder Terraform Variables](https://coder.com/docs/admin/templates/extending-templates/variables) — sensitive variables, CLI/UI/file input methods
- [Coder Terraform Modules](https://coder.com/docs/admin/templates/extending-templates/modules) — available module list (code-server, dotfiles, git-clone, jetbrains, vscode-web)
- [JetBrains Gateway module source](https://github.com/coder/modules/blob/main/jetbrains-gateway/main.tf) — parameters, `coder_app` with gateway:// URL, IDE product codes
- [JetBrains pre-install docs](https://coder.com/docs/admin/templates/extending-templates/jetbrains-preinstall) — backend pre-install pattern, Client Downloader
- [Coder server CLI](https://coder.com/docs/reference/cli/server) — `create-admin-user` for first admin bootstrap
- [Coder Secrets docs](https://coder.com/docs/admin/security/secrets) — dynamic secrets, sensitive variable handling
- [Docker Postgres backup patterns](https://simplebackups.com/blog/docker-postgres-backup-restore-guide-with-examples) — `pg_dump -Fc`, `pg_restore`, compressed formats, Docker exec pattern
- [MCP reference servers](https://github.com/modelcontextprotocol/servers) — filesystem, git, fetch servers for in-workspace MCP configuration
- [Coder homelab blog](https://coder.com/blog/run-coder-in-a-self-hosted-homelab) — self-hosted operational context

---

*Feature research for: self-hosted Coder production scaffold (Docker Compose)*
*Researched: 2026-06-16*
