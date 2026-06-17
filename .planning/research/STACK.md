# Technology Stack — v1.1 Additions

**Project:** Coder Production Scaffold — v1.1 Portable Claude Code Setup
**Researched:** 2026-06-17
**Scope:** NEW additions only. v1.0 stack (Coder v2.33.8, postgres:17, kreuzwerker/docker ~> 4.4, coder/coder ~> 2.18, code-server 1.5.0, jetbrains-gateway 1.2.6) is validated and unchanged.

---

## New Stack Components for v1.1

### coder/claude-code Registry Module

| Attribute | Value |
|-----------|-------|
| Source | `registry.coder.com/coder/claude-code/coder` |
| Version to pin | **`5.2.0`** |
| Purpose | Install Claude Code CLI in workspace + configure auth env vars |
| Provider constraint | `coder/coder >= 2.12` |
| Terraform constraint | `>= 1.9` (matches existing `required_version`) |
| v4 vs v5 | Use **v5.x** for a non-Tasks install. v5 dropped the `coder_ai_task` wiring that was built into the module — that is irrelevant for this milestone. v5 is the maintained release. v4 is only needed if you want the module itself to wire `coder_ai_task`; since Tasks are deferred to a later milestone, v5 is correct. |
| Downloads | 920,458 (registry signal, as of research date) |

**Why 5.2.0 and not latest:** Pin the exact version for reproducibility. 5.2.0 is the current published release confirmed in the GitHub registry repo (`registry/coder/modules/claude-code/`). The version constraint `"5.2.0"` prevents silent drift.

### No new providers needed

The existing `coder/coder ~> 2.18` and `kreuzwerker/docker ~> 4.4` providers satisfy all v1.1 requirements. No version bumps required.

---

## coder/claude-code Module: Variable Reference

Full variable inventory for `5.2.0`, extracted from `main.tf` in the registry:

| Variable | Type | Default | Notes for v1.1 |
|----------|------|---------|----------------|
| `agent_id` | string | **required** | Wire to `coder_agent.main.id` |
| `install_claude_code` | bool | `true` | Keep default; installs the CLI |
| `claude_code_version` | string | `"latest"` | Acceptable default; pin a semver if reproducibility matters |
| `disable_autoupdater` | bool | `false` | Set `true` in production to prevent silent updates |
| `anthropic_api_key` | string | `""` | Leave empty for subscription/OAuth login (our target). Set only if using API key auth |
| `claude_code_oauth_token` | string | `""` | Sensitive. Leave empty for interactive first-run login; set via `CLAUDE_CODE_OAUTH_TOKEN` env if automating |
| `model` | string | `""` | Optional; defaults to Sonnet when empty |
| `workdir` | string | `null` | When set, pre-creates the directory and pre-accepts the Claude trust prompt in `~/.claude.json`. Set to `/home/coder` to accept the home dir |
| `pre_install_script` | string | `null` | Hook for pre-install steps |
| `post_install_script` | string | `null` | Hook: use this to set `CLAUDE_CONFIG_DIR` if needed (see below) |
| `mcp` | string | `""` | JSON-encoded MCP server config. Leave empty for v1.1 |
| `mcp_config_remote_path` | list(string) | `[]` | Remote MCP configs. Leave empty for v1.1 |
| `managed_settings` | any | `null` | Writes to `/etc/claude-code/managed-settings.d/`. Leave null for v1.1 |
| `enable_ai_gateway` | bool | `false` | Leave false; AI Gateway is out of scope |
| `telemetry` | object | `{}` | OTEL config. Leave empty for v1.1 |
| `icon` | string | `"/icon/claude.svg"` | Keep default |
| `claude_binary_path` | string | `"$HOME/.local/bin"` | Keep default |

**Variables to set for v1.1:**
```hcl
module "claude-code" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "5.2.0"

  agent_id             = coder_agent.main.id
  install_claude_code  = true
  disable_autoupdater  = true          # production stability
  workdir              = "/home/coder" # pre-accepts trust prompt
  # anthropic_api_key and claude_code_oauth_token both left empty
  # → first-run interactive OAuth login flow
}
```

**What the module actually installs/configures:**
- Runs an install script that places the Claude Code CLI binary at `$HOME/.local/bin/claude`
- Creates `coder_env` resources that inject environment variables into the agent: `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `DISABLE_AUTOUPDATER`, and others
- Does NOT create a `coder_app` resource — there is no browser button; Claude Code is a terminal CLI only
- When `workdir` is set: pre-creates the directory and writes a trust entry to `~/.claude.json`

---

## Per-Owner Shared Volume: Identifier Choice

### coder_workspace_owner attributes (coder/coder provider 2.18)

| Attribute | Type | Stable? | Use for volume naming? |
|-----------|------|---------|----------------------|
| `id` | String (UUID) | **Yes — immutable** | **YES** — key the volume on this |
| `name` | String (username) | No — can change | No — changing the username would orphan the volume |
| `full_name` | String | No | No |
| `email` | String | No | No |

**Decision: use `data.coder_workspace_owner.me.id` for the volume name.** This is the UUID of the Coder user account, immutable across username renames. The existing home volume already follows this pattern for workspace ID (`data.coder_workspace.me.id`). Apply the same principle to owner ID.

**Volume name format:**
```hcl
resource "docker_volume" "claude_config_volume" {
  name = "coder-user-${data.coder_workspace_owner.me.id}-claude"

  lifecycle {
    ignore_changes = [name]
  }
}
```

The `ignore_changes = [name]` lifecycle guard (already established in the home volume pattern) prevents a name-format change from triggering destroy/recreate.

---

## Critical Constraint: Docker Named Volume Mounts as a Directory

**This is the single most important technical constraint for v1.1.**

A Docker named volume, when mounted into a container, always mounts as a **directory**. It is impossible to mount a named volume at a single file path. If you specify a file path as `container_path`, Docker creates a directory at that path instead — corrupting the expected file.

Concretely:
- `container_path = "/home/coder/.claude"` — **valid**: mounts the volume as the `~/.claude/` directory. This is correct.
- `container_path = "/home/coder/.claude.json"` — **INVALID**: Docker creates a directory named `.claude.json` at that path. Claude Code then fails to read `~/.claude.json` as a file.

This means you **cannot share `~/.claude.json` via a named volume directly.** The workaround is `CLAUDE_CONFIG_DIR`.

### CLAUDE_CONFIG_DIR: The Solution

`CLAUDE_CONFIG_DIR` is an environment variable supported by Claude Code (documented in the official authentication docs). When set on Linux:

- The `.credentials.json` file (OAuth/subscription credentials) lives at `$CLAUDE_CONFIG_DIR/.credentials.json` instead of `~/.claude/.credentials.json`
- The `~/.claude/` directory contents (settings.json, agents/, skills/, CLAUDE.md, etc.) are read from `$CLAUDE_CONFIG_DIR/` instead of `~/.claude/`
- The `~/.claude.json` file behavior: when `CLAUDE_CONFIG_DIR` is set (e.g. to `~/.claude`), Claude Code writes `claude.json` inside that directory rather than as a separate `~/.claude.json` at the home root. This is confirmed by issue #14313 (the canonical bug/workaround report): `export CLAUDE_CONFIG_DIR=~/.claude` → Claude Code writes its JSON config inside the directory. Without `CLAUDE_CONFIG_DIR`, it writes to `~/. claude.json` (home root).

**CLAUDE_CONFIG_DIR status:** Partially documented. The authentication page explicitly documents it for credentials. The `~/.claude.json` relocation behavior is confirmed by community reports and the Anthropic issue tracker (issue #3833). It is not XDG-standard and not guaranteed to handle every edge case (IDE integration has known bugs with it, per issue #4739). For the Coder workspace use case (terminal CLI only, no IDE extension integration), these limitations do not apply.

### The Implementation Pattern

Set `CLAUDE_CONFIG_DIR=/home/coder/.claude` in the workspace container, and mount the per-owner volume at `/home/coder/.claude`. This:

1. Mounts the named volume as a directory (valid Docker operation)
2. Causes Claude Code to read AND write all its config — credentials, settings, user-scope MCP servers, claude.json — inside `/home/coder/.claude/`
3. Since the volume is shared across all of an owner's workspaces (keyed on `owner.id`), auth and settings persist across workspace starts and are shared between workspaces

**How to set it:**

Option A — via `coder_agent.env`:
```hcl
resource "coder_agent" "main" {
  env = {
    CLAUDE_CONFIG_DIR = "/home/coder/.claude"
    # ... existing env vars
  }
}
```

Option B — via the module's `post_install_script` (if ordering matters relative to install).

Option A is cleaner and consistent with the existing `GIT_AUTHOR_NAME` etc. pattern in the template.

---

## Volume Mount Layering: Named Volumes in kreuzwerker/docker

The `kreuzwerker/docker` provider's `docker_container` resource supports multiple `volumes {}` blocks. You can mount the per-workspace home volume and the per-owner Claude config volume simultaneously:

```hcl
resource "docker_container" "workspace" {
  # ...
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/home/coder/.claude"
    volume_name    = docker_volume.claude_config_volume.name
    read_only      = false
  }
}
```

Docker resolves these correctly: the home volume mounts first at `/home/coder`, then the Claude config volume overlays at `/home/coder/.claude`. The overlay is standard Docker behavior and does not require any special provider support.

**Constraint on `docker_volume` count:** Like `docker_container`, the `docker_volume` resource for the Claude config volume must have NO `count` — the volume must exist even when the workspace is stopped, so the data persists. The container mounts it conditionally via `count = start_count`, but the volume itself is always present.

---

## devcontainer Precedent (Existing Pattern in This Repo)

The `.devcontainer/devcontainer.json` in this repository already demonstrates the exact pattern v1.1 follows:

```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  },
  "mounts": [
    "source=claude-code-config,target=/home/node/.claude,type=volume"
  ]
}
```

It mounts a named Docker volume at `~/.claude` (directory, not file). The v1.1 Coder workspace template applies this same approach, extended with:
- The volume is keyed per-owner (not shared across all users)
- `CLAUDE_CONFIG_DIR` is set to ensure `claude.json` lands inside the mounted directory

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Module version | `coder/claude-code 5.2.0` | `4.x` | v4 is only needed for `coder_ai_task` module integration, which is deferred. v5 is the current maintained release |
| Auth method | Interactive OAuth login (empty `anthropic_api_key`) | `anthropic_api_key` via env | Subscription login requires no operator secret management; API key requires `.env` variable and billing via Console |
| Config sharing method | Named Docker volume at `~/.claude` + `CLAUDE_CONFIG_DIR` | Bind mount of host `~/.claude` | Bind mount exposes host filesystem to workspace containers; named volume is isolated and portable |
| Volume naming key | `coder_workspace_owner.me.id` (UUID) | `coder_workspace_owner.me.name` (username) | Username is mutable; a rename would orphan the volume. UUID is immutable for the lifetime of the Coder user account |
| CLAUDE_CONFIG_DIR value | `/home/coder/.claude` (same as mount point) | A different path | Keeping them identical means "volume mount = config dir" — no path remapping, simpler mental model |
| `~/.claude.json` handling | Relocated into `CLAUDE_CONFIG_DIR` via env var | Separate bind mount for the file | Docker cannot mount a named volume at a single file path; a bind mount of the host file exposes the host |
| Coder Tasks (coder_ai_task) | NOT included in v1.1 | Add now | Tasks are explicitly deferred to a later milestone. Adding them now would require either v4 of the module (for module-bundled Tasks wiring) or manual `coder_ai_task` resource — both out of v1.1 scope |

---

## What NOT to Add in v1.1

| Avoid | Why |
|-------|-----|
| `coder_ai_task` resource | Deferred to a later milestone; requires Coder server >= 2.28 (satisfied) but scope is wrong for v1.1 |
| `coder/claude-code` module `order` variable | Not a variable this module exposes (code-server and jetbrains-gateway expose `order`; claude-code does not create a `coder_app`) |
| `managed_settings` variable | Enterprise policy feature; irrelevant for single-operator scaffold |
| `enable_ai_gateway` variable | AI Gateway / proxy routing is out of scope for this milestone |
| `mcp` / `mcp_config_remote_path` variables | MCP server provisioning via module is out of scope; user adds their own via `claude mcp add --scope user` after auth |
| `ANTHROPIC_API_KEY` in `.env` | Not required for subscription/OAuth login; adding it now pre-empts the interactive login flow (API key takes precedence over subscription credentials in the auth precedence order) |

---

## Version Compatibility Matrix (v1.1 additions)

| Component | Constraint | Satisfied by |
|-----------|------------|-------------|
| `coder/claude-code` module `5.2.0` | `coder/coder >= 2.12`, Terraform `>= 1.9` | `coder/coder ~> 2.18` and `required_version = ">= 1.9"` already in template |
| `coder_workspace_owner.me.id` attribute | Available in `coder/coder >= 2.x` | `~> 2.18` satisfies |
| `CLAUDE_CONFIG_DIR` env var effect on credentials | Claude Code CLI (any current version) | Installed by the module; no version pin on the CLI binary needed for this behavior |
| Docker multi-volume mount layering | `kreuzwerker/docker ~> 4.4` | Already in template |

---

## Sources

- **GitHub `coder/registry` — `registry/coder/modules/claude-code/main.tf` and `README.md`** — module variables, provider constraints, install behavior, v5 Tasks migration note — HIGH confidence (direct source)
- **`coder/terraform-provider-coder` docs — `workspace_owner` data source** — `id` is UUID (immutable), `name` is username (mutable) — HIGH confidence (provider docs)
- **Claude Code official authentication docs (`code.claude.com/docs/en/authentication`)** — `CLAUDE_CONFIG_DIR` relocates `.credentials.json`; credentials stored at `~/.claude/.credentials.json` on Linux — HIGH confidence (official docs)
- **Claude Code official CLI reference (`code.claude.com/docs/en/cli-reference`)** — `claude project purge` references `~/.claude.json` as separate from `~/.claude/` — HIGH confidence (official docs)
- **Claude Code official directory docs (`code.claude.com/docs/en/claude-directory`)** — `~/.claude.json` holds user-scope MCP servers; `~/.claude/` holds settings, agents, skills — HIGH confidence (official docs)
- **GitHub `anthropics/claude-code` issue #3833** — `CLAUDE_CONFIG_DIR` workaround: setting to `~/.claude` causes `claude.json` to live inside the directory; closed without full resolution; partial implementation confirmed — MEDIUM confidence (community-confirmed behavior, not officially documented scope)
- **GitHub `anthropics/claude-code` issue #14313** — Bug: `CLAUDE_CONFIG_DIR` not set → `.claude.json` written to wrong location; workaround `export CLAUDE_CONFIG_DIR=~/.claude` confirmed working — MEDIUM confidence (bug report with confirmed workaround)
- **`.devcontainer/devcontainer.json` in this repo** — established pattern: named volume mounted at `~/.claude` (directory); `ghcr.io/anthropics/devcontainer-features/claude-code:1.0` installs the CLI — HIGH confidence (working in production in this repo)
- **Medium: "Using Claude Code Safely with Dev Containers"** — `CLAUDE_CONFIG_DIR=/home/vscode/.claude` + volume at `~/.claude` as the canonical dev container pattern — MEDIUM confidence (community article, confirmed pattern)
