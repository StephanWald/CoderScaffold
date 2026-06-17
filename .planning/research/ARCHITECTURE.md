# Architecture Research

**Domain:** Portable Claude Code config across Coder Docker workspaces (v1.1 milestone)
**Researched:** 2026-06-17
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Coder Server (compose.yaml)                                                │
│  Templates provision workspaces via Docker socket                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Terraform Template (templates/docker/main.tf)                              │
│                                                                             │
│  ┌──────────────────┐  ┌────────────────────┐  ┌────────────────────────┐  │
│  │  coder_agent     │  │  docker_volume     │  │  docker_volume         │  │
│  │  "main"          │  │  home_volume       │  │  claude_config_volume  │  │
│  │  (no count)      │  │  (no count)        │  │  (no count)            │  │
│  │                  │  │  per-workspace     │  │  per-OWNER             │  │
│  │  startup_script  │  │  UUID key          │  │  owner.id key          │  │
│  │  runs ONCE       │  │                    │  │  prevent_destroy=true  │  │
│  └────────┬─────────┘  └────────┬───────────┘  └───────────┬────────────┘  │
│           │                     │                           │               │
│  ┌────────▼────────────────────────────────────────────────▼────────────┐  │
│  │  docker_container "workspace"  (count = start_count)                 │  │
│  │                                                                      │  │
│  │  volumes { /home/coder        ← home_volume (per-workspace)    }    │  │
│  │  volumes { /home/coder/.claude-shared ← claude_config_volume   }    │  │
│  │                                                                      │  │
│  │  startup_script (via coder_agent):                                   │  │
│  │    1. seed home from /etc/skel (existing, idempotent)                │  │
│  │    2. chown /home/coder/.claude-shared → coder:coder                 │  │
│  │    3. mkdir -p inside .claude-shared                                 │  │
│  │    4. symlink ~/.claude → .claude-shared/dot-claude                  │  │
│  │    5. symlink ~/.claude.json → .claude-shared/dot-claude.json        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────┐  ┌────────────────────┐  ┌────────────────────────┐  │
│  │  module          │  │  module            │  │  module                │  │
│  │  code-server     │  │  jetbrains-gateway │  │  claude-code           │  │
│  │  count=start     │  │  count=start       │  │  count=start           │  │
│  │  agent_id=main   │  │  agent_id=main     │  │  agent_id=main         │  │
│  └──────────────────┘  └────────────────────┘  └────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Key Attribute |
|-----------|----------------|---------------|
| `docker_volume.home_volume` | Per-workspace persistent `/home/coder`. Survives stop/start; deleted on workspace delete. | Keyed on `coder_workspace.me.id` (immutable UUID) |
| `docker_volume.claude_config_volume` | Per-owner shared Claude config. Carries `~/.claude/` and `~/.claude.json` across ALL of this owner's workspaces. | Keyed on `coder_workspace_owner.me.id` (immutable UUID). `prevent_destroy = true` — survives workspace delete. |
| `coder_agent.main` | Always-present. Generates token + init_script. Runs `startup_script` on workspace start. | No `count` — exists in stopped state too. |
| `docker_container.workspace` | Ephemeral workspace container. Mounts both volumes. Runs entrypoint from `init_script`. | `count = start_count` — destroyed on stop. |
| `module.claude-code` | Installs Claude Code CLI, wires `ANTHROPIC_API_KEY` env var, handles workdir trust prompt. | `count = start_count`, `agent_id = coder_agent.main.id` |
| `module.code-server` | Browser VS Code (unchanged from v1.0). | `count = start_count`, `order = 1` |
| `module.jetbrains-gateway` | JetBrains Gateway (unchanged from v1.0). | `count = start_count`, `order = 2` |

## The Core Problem: File vs. Directory Mount

Docker named volumes always mount as **directories**. There is no mechanism to mount a named volume at a file path. Claude Code has two config locations:

- `~/.claude/` — a **directory** (settings, commands, agents, skills, CLAUDE.md, session history)
- `~/.claude.json` — a **file** at `$HOME` root (OAuth session, MCP servers, per-project state, feature flag caches, auth credentials)

Mounting a named volume at `~/.claude.json` would silently turn it into a directory, which Claude Code cannot read as its JSON config file. `~/.claude.json` must be a regular file.

### Why CLAUDE_CONFIG_DIR Does Not Solve This

`CLAUDE_CONFIG_DIR` was proposed as a feature to relocate all Claude config under a custom directory (GitHub issue #25762, opened Feb 2026, still open, no implementation). A related bug report (issue #3833, closed "not planned") showed that even a partially-working `CLAUDE_CONFIG_DIR` still creates local `.claude/` directories in workspaces. The Claude Code docs do not document this variable as supported. **Do not rely on it.**

### Recommended Solution: Neutral Mount Point + Symlinks

Mount the shared volume at a **neutral subdirectory** (`/home/coder/.claude-shared`), then use the `startup_script` to create symlinks that point the canonical locations into it.

```
/home/coder/
  .claude-shared/          ← named volume (per-owner, shared)
    dot-claude/            ← actual directory content for ~/.claude
    dot-claude.json        ← actual file content for ~/.claude.json
  .claude -> .claude-shared/dot-claude       ← symlink (startup_script)
  .claude.json -> .claude-shared/dot-claude.json  ← symlink (startup_script)
```

Claude Code follows symlinks normally. Both locations resolve into the shared volume. One volume carries the complete Claude config surface. The symlinks are recreated idempotently on every workspace start by the `startup_script`.

### Why Not Alternative (a): CLAUDE_CONFIG_DIR

Unimplemented, undocumented, closed as "not planned." Unreliable.

### Why Not Alternative (c): Two Separate Volumes

Mounting one named volume at `/home/coder/.claude` and a second named volume at `/home/coder/.claude.json` would make `.claude.json` a directory, breaking Claude Code's JSON parsing. Even if the mount order were reversed, Docker cannot mount a named volume at a file path.

## Nested Mount Layering Confirmation

Mounting volume A at `/home/coder` and volume B at `/home/coder/.claude-shared` **works correctly** via Linux kernel mount namespaces. Docker applies mounts in declaration order; the child mount (`.claude-shared`) shadows that subdirectory of the parent mount (`/home/coder`) using the standard Linux mount namespace semantics. This is confirmed behavior — the kernel treats each mount point independently, and the child path takes precedence within its subtree.

Key detail: the `volumes{}` blocks in `docker_container` must declare the parent path first, then the child. The kreuzwerker Docker Terraform provider serializes the `volumes{}` blocks in order, which aligns with correct mount ordering.

## Recommended Project Structure (template changes)

```
templates/docker/
└── main.tf              # MODIFIED — add claude_config_volume, second volumes{} block,
                         #   extended startup_script, claude-code module, ANTHROPIC_API_KEY variable
```

No new files. No changes to compose.yaml. The modification is entirely within `templates/docker/main.tf`.

## Architectural Patterns

### Pattern 1: Per-Owner Immutable-Keyed Volume with prevent_destroy

**What:** Name the Claude config volume using the owner's immutable UUID. Apply `prevent_destroy = true` so workspace deletion does not destroy the auth/config that all workspaces share.

**When to use:** Any resource that must outlive individual workspace lifecycles and is scoped to a user (not a workspace).

**Trade-offs:** The volume is never auto-cleaned by Terraform. Operators must manually remove orphaned volumes if a user is deleted. This is acceptable for auth/config data — losing it is worse than leaving it.

```hcl
resource "docker_volume" "claude_config_volume" {
  name = "coder-${data.coder_workspace_owner.me.id}-claude"

  lifecycle {
    ignore_changes  = [name]
    prevent_destroy = true
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.purpose"
    value = "claude-config"
  }
}
```

**Why `data.coder_workspace_owner.me.id` not `.name`:** The owner `id` is a stable UUID assigned at user creation. The owner `name` (username) can change. A username change would produce a new volume name, orphaning the old one. Always key on immutable IDs.

### Pattern 2: Neutral Mount Point + Startup-Script Symlinks

**What:** Mount the shared volume at a neutral path (not the canonical path Claude Code expects). Create symlinks from the canonical paths into the neutral mount point using the `startup_script`.

**When to use:** When the target tool expects a mix of file and directory paths that a single Docker volume mount cannot satisfy simultaneously.

**Trade-offs:** Symlinks add one level of indirection. The `startup_script` must run before Claude Code starts (it does — the agent script runs before any module). The symlinks must be idempotent (`-f` flag or `[ -L ]` guard). If Claude Code ever dereferences symlinks unexpectedly, behavior may differ — but Claude Code follows symlinks normally per standard POSIX behavior.

```hcl
resource "coder_agent" "main" {
  # ...existing fields...

  startup_script = <<-EOT
    set -e

    # Seed home from /etc/skel on the very first workspace start (idempotent).
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # ── Claude Code config (per-owner shared volume) ─────────────────────────
    # The shared volume is mounted at ~/.claude-shared (a neutral path).
    # We create the internal structure and symlink ~/.claude + ~/.claude.json
    # into it. Symlinks are idempotent — recreated on every start.

    CLAUDE_SHARED="$HOME/.claude-shared"

    # Fix ownership on first use (volume starts root-owned when empty).
    if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
      sudo chown -R coder:coder "$CLAUDE_SHARED"
    fi

    # Create internal structure.
    mkdir -p "$CLAUDE_SHARED/dot-claude"

    # Symlink ~/.claude → shared directory.
    ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"

    # Symlink ~/.claude.json → shared file (create if missing).
    if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
      echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
    fi
    ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
  EOT
}
```

**Note on `sudo`:** The `codercom/enterprise-base:ubuntu` image grants the `coder` user passwordless sudo. The `chown` is only needed on first use (when the volume is freshly created and root-owned). The `stat` guard prevents repeated sudo invocations.

### Pattern 3: claude-code Module Placement (count = start_count)

**What:** Place the `claude-code` module alongside the other editor modules (`code-server`, `jetbrains-gateway`), all gated on `count = start_count`. Pass `agent_id` from the always-present `coder_agent.main`.

**When to use:** All workspace-app modules in this template follow this pattern. It ensures `coder_app` resources are only registered when the workspace is running.

**Trade-offs:** The module installs Claude Code CLI on every workspace start if not already present (the module's install script is idempotent). With `install_claude_code = true` and no version pin, it fetches the latest release each start. Pin `claude_code_version` to avoid churn.

```hcl
variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code. Required for AI features."
  type        = string
  sensitive   = true
  default     = ""
}

module "claude-code" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/coder/claude-code/coder"
  version          = "5.2.0"
  agent_id         = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
  install_claude_code = true
  order            = 3
}
```

**`order = 3`** places Claude Code after VS Code (`order = 1`) and JetBrains (`order = 2`) in the workspace UI app list.

## Data Flow

### First Workspace Start (Empty Volume)

```
Terraform apply
  → docker_volume.claude_config_volume created (root-owned, empty)
  → docker_volume.home_volume created (or reused)
  → docker_container.workspace started
      volumes[0]: home_volume → /home/coder
      volumes[1]: claude_config_volume → /home/coder/.claude-shared
  → coder_agent startup_script runs:
      1. /etc/skel seeded → ~/.init_done created
      2. chown /home/coder/.claude-shared → coder:coder
      3. mkdir -p ~/.claude-shared/dot-claude
      4. echo '{}' > ~/.claude-shared/dot-claude.json
      5. ln -sfn ~/.claude-shared/dot-claude ~/.claude
      6. ln -sf ~/.claude-shared/dot-claude.json ~/.claude.json
  → module.claude-code startup script runs:
      - installs claude CLI to ~/.local/bin/claude
      - sets ANTHROPIC_API_KEY env via coder_env resource
  → user runs `claude` → first-run auth → writes to ~/.claude.json (symlink) → persists in shared volume
```

### Subsequent Workspace Start (Existing Volume, Same Owner)

```
Terraform apply (workspace 2 or restart)
  → docker_volume.claude_config_volume: name already matches → no change
  → docker_container.workspace started, same two volume mounts
  → startup_script runs:
      - ~/.init_done exists → skel seeded skipped
      - chown guard: already coder-owned → skipped
      - mkdir -p: idempotent
      - ln -sfn: overwrites symlinks (idempotent with -f)
      - dot-claude.json already exists → not overwritten
  → ANTHROPIC_API_KEY already in env → Claude Code ready immediately
  → user's auth, settings, skills from previous workspace are available
```

### Workspace Delete + New Workspace (Same Owner)

```
Terraform destroy (workspace 1 deleted)
  → docker_container destroyed
  → docker_volume.home_volume destroyed (per-workspace, no prevent_destroy)
  → docker_volume.claude_config_volume: prevent_destroy = true → RETAINED

New workspace created (workspace 2)
  → docker_volume.claude_config_volume: same name (same owner id) → reused
  → auth, settings, history preserved across the new workspace
```

## Integration Points

### What Changes in templates/docker/main.tf

| Location | Change Type | What |
|----------|-------------|------|
| `variable` block (new) | ADD | `variable "anthropic_api_key"` — sensitive string, default `""` |
| After `docker_volume.home_volume` | ADD | `resource "docker_volume" "claude_config_volume"` with per-owner name, `prevent_destroy = true`, `ignore_changes = [name]` |
| `docker_container.workspace` | MODIFY | Add second `volumes {}` block: `container_path = "/home/coder/.claude-shared"`, `volume_name = docker_volume.claude_config_volume.name` |
| `coder_agent.main startup_script` | MODIFY | Append the Claude config setup block (chown guard, mkdir, symlinks) after the existing `/etc/skel` seed |
| After `module.jetbrains-gateway` | ADD | `module "claude-code"` block with `count = start_count`, `agent_id`, `anthropic_api_key`, `version = "5.2.0"`, `order = 3` |
| File header comment | MODIFY | Add `module claude-code` to the resources list |

### What Does Not Change

- `compose.yaml` — no changes
- `scripts/` — no changes
- `.env.example` — `ANTHROPIC_API_KEY` is passed as a Terraform variable at workspace build time, not as a Coder server env var. No compose-level change needed.

### Build Order and Dependencies

Terraform resolves these automatically via the dependency graph, but the logical order is:

1. `data.coder_workspace_owner.me` — provides `id` for volume name (read-only, no creation)
2. `coder_agent.main` — always created first (no count); provides `id` for modules and `init_script` for container entrypoint
3. `docker_volume.home_volume` — no count; created/reused before container
4. `docker_volume.claude_config_volume` — no count; created/reused before container; `prevent_destroy` means reuse on subsequent applies
5. `docker_image.main` — no count; pulled once
6. `docker_container.workspace` — `count = start_count`; depends on both volumes and agent; mounts both volumes
7. `module.code-server`, `module.jetbrains-gateway`, `module.claude-code` — all `count = start_count`; depend on `coder_agent.main.id`; parallel with each other; independent of container resource

**Critical ordering note:** The `startup_script` in `coder_agent` runs inside the container after the container starts. It runs before any module install scripts because the agent starts up, receives the startup script, and executes it before reporting ready to modules. The chown + symlink block must appear in `coder_agent.startup_script`, NOT in a module's post_install_script, to guarantee it runs before `claude-code` module tries to write `~/.claude.json`.

## Anti-Patterns

### Anti-Pattern 1: Mounting Named Volume at ~/.claude.json

**What people do:** Try to mount `docker_volume.claude_config_volume` with `container_path = "/home/coder/.claude.json"`.

**Why it's wrong:** Docker always creates the mount point as a directory. Claude Code expects a JSON file at `~/.claude.json`. The mount creates a directory instead, Claude Code cannot parse it, and it fails silently or with a cryptic JSON error.

**Do this instead:** Mount at a neutral path and symlink.

### Anti-Pattern 2: Keying the Shared Volume on Owner Name (not ID)

**What people do:** `name = "coder-${data.coder_workspace_owner.me.name}-claude"`.

**Why it's wrong:** Owner usernames can be changed by a Coder admin. On the next workspace start, Terraform sees a name change, destroys the old volume (losing all auth/settings), and creates a new empty one.

**Do this instead:** `name = "coder-${data.coder_workspace_owner.me.id}-claude"` — the UUID never changes.

### Anti-Pattern 3: No prevent_destroy on the Shared Config Volume

**What people do:** Omit `prevent_destroy = true`, relying only on `ignore_changes = [name]`.

**Why it's wrong:** When a workspace is deleted (not stopped), Terraform runs `destroy`. Without `prevent_destroy`, it destroys the shared volume, taking all Claude auth and settings with it. The next workspace for the same owner starts with an empty volume.

**Do this instead:** Set `prevent_destroy = true`. The volume then requires explicit manual deletion if needed (acceptable trade-off for auth data).

### Anti-Pattern 4: Putting Symlink Logic in module.claude-code post_install_script

**What people do:** Pass the chown/symlink block as `post_install_script` to the `claude-code` module.

**Why it's wrong:** The `claude-code` module may write to `~/.claude.json` as part of its workdir trust prompt setup. If symlinks aren't in place before that write, the module writes the real file at `~/.claude.json` on the home volume (not the shared volume). The next workspace loses that state.

**Do this instead:** Put the chown/symlink block in `coder_agent.main.startup_script`, which runs before any module install scripts.

### Anti-Pattern 5: Relying on CLAUDE_CONFIG_DIR

**What people do:** Set `CLAUDE_CONFIG_DIR=/home/coder/.claude-shared` as an environment variable, skip the symlink setup.

**Why it's wrong:** `CLAUDE_CONFIG_DIR` is not documented by Anthropic, was requested as an enhancement (issue #25762, open), and a related bug was closed "not planned". Even in partially-working states it still creates local `.claude/` directories. Unreliable for production use.

**Do this instead:** Symlink approach — it works with the documented, stable config locations.

## Reusable Pattern (Drop-in Snippet)

The following pattern is designed to be copied into any future Coder Docker template. It assumes the template already has `coder_agent.main`, `data.coder_workspace_owner.me`, and `docker_container.workspace` following the v1.0 pattern.

```hcl
# ── [REUSABLE] Per-owner Claude Code config volume ──────────────────────────
#
# WHAT: A Docker named volume keyed on the owner's immutable UUID. Shared
#   across ALL workspaces for this owner. Carries ~/.claude/ (directory)
#   and ~/.claude.json (file) via a neutral mount point + symlinks.
#
# HOW TO USE:
#   1. Add this docker_volume resource (below).
#   2. Add the second volumes{} block to docker_container.workspace.
#   3. Add the "Claude Code config" block to coder_agent.main.startup_script.
#   4. Add the claude-code module (below).
#   5. Add the anthropic_api_key variable.
#
# OPERATOR NOTES:
#   - First run: volume starts empty. `claude auth login` authenticates once;
#     auth persists to the shared volume for all future workspaces.
#   - Concurrent writes: avoid running claude in two workspaces simultaneously
#     for the same owner. ~/.claude.json is not write-safe under concurrent
#     access (no file locking). Sequential use is safe.
#   - Volume cleanup: `prevent_destroy = true` means Terraform never removes
#     this volume. To fully remove it: `docker volume rm <name>` manually.
#   - Volume name: coder-<owner-uuid>-claude. List with:
#       docker volume ls -f label=coder.purpose=claude-config
#
# MOUNT LAYOUT INSIDE CONTAINER:
#   /home/coder/.claude-shared/       ← named volume
#   /home/coder/.claude-shared/dot-claude/     (actual ~/.claude contents)
#   /home/coder/.claude-shared/dot-claude.json (actual ~/.claude.json contents)
#   /home/coder/.claude  →  .claude-shared/dot-claude      (symlink)
#   /home/coder/.claude.json  →  .claude-shared/dot-claude.json  (symlink)

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (from console.anthropic.com)."
  type        = string
  sensitive   = true
  default     = ""
}

resource "docker_volume" "claude_config_volume" {
  name = "coder-${data.coder_workspace_owner.me.id}-claude"

  lifecycle {
    ignore_changes  = [name]
    prevent_destroy = true
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.purpose"
    value = "claude-config"
  }
}

# In docker_container.workspace, add alongside the home volume:
#
#   volumes {
#     container_path = "/home/coder/.claude-shared"
#     volume_name    = docker_volume.claude_config_volume.name
#     read_only      = false
#   }
#
# Declare AFTER the home volume volumes{} block (parent mount before child mount).

# In coder_agent.main.startup_script, append AFTER the /etc/skel block:
#
#   # ── Claude Code config (per-owner shared volume) ─────────────────────
#   CLAUDE_SHARED="$HOME/.claude-shared"
#   if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
#     sudo chown -R coder:coder "$CLAUDE_SHARED"
#   fi
#   mkdir -p "$CLAUDE_SHARED/dot-claude"
#   if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
#     echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
#   fi
#   ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"
#   ln -sf  "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"

module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  anthropic_api_key   = var.anthropic_api_key
  install_claude_code = true
  order               = 3
}

# ── [END REUSABLE] ───────────────────────────────────────────────────────────
```

## Scaling Considerations

| Concern | At 1 owner | At 10 owners | At 100 owners |
|---------|------------|--------------|---------------|
| Volume count | 1 claude volume + N home volumes | 10 claude + N homes | 100 claude + N homes — manageable; volumes are cheap |
| Concurrent write risk | Low (1 person, 2+ workspaces rarely active together) | Moderate (same owner pattern) | Same — per-owner, not global; doesn't scale with user count |
| Volume cleanup on user delete | Manual `docker volume rm` | Same | Automate with a cleanup script if needed |
| First-auth UX | Once per owner ever | Same | Same |

## Sources

- GitHub issue #25762 (anthropics/claude-code): `CLAUDE_CONFIG_DIR` enhancement request — open, unimplemented, Feb 2026. **HIGH confidence** (direct GitHub source).
- GitHub issue #3833 (anthropics/claude-code): `CLAUDE_CONFIG_DIR` bug — closed "not planned". Confirms env var is undocumented and unreliable. **HIGH confidence**.
- GitHub issue #24479 (anthropics/claude-code): `~/.claude.json` move to inside `~/.claude/` — open enhancement, no implementation. Confirms `~/.claude.json` is at home root as of current releases. **HIGH confidence**.
- code.claude.com/docs/en/env-vars: Official Claude Code env var docs — no `CLAUDE_CONFIG_DIR` listed. **HIGH confidence**.
- code.claude.com/docs/en/claude-directory: `~/.claude/` directory structure and `~/.claude.json` purpose. **HIGH confidence**.
- Docker Forums (overlapping volume mounts): Confirms child mount shadows parent at Linux kernel mount namespace level. **MEDIUM confidence** (community, confirmed by Linux mount semantics).
- Taesun Lee (Medium): Practical test confirming nested Docker volume mounts at dependent paths work. **MEDIUM confidence** (community test).
- github.com/coder/coder discussions #7610: Per-user shared volume pattern using `owner_id`. Confirms `prevent_destroy` approach. **HIGH confidence** (official Coder community).
- coder.com/docs/admin/templates/extending-templates/resource-persistence: Volume persistence lifecycle documentation. **HIGH confidence**.
- github.com/coder/registry blob main/registry/coder/modules/claude-code/main.tf: Module variable list, `anthropic_api_key` wiring via `coder_env`. **HIGH confidence**.
- `.devcontainer/devcontainer.json` (this repo): Confirms `claude-code-config` named volume mounted at `/home/node/.claude` (directory) works. Does not handle `~/.claude.json`. **HIGH confidence** (direct source read).

---
*Architecture research for: Portable Claude Code config across Coder Docker workspaces*
*Researched: 2026-06-17*
