# Phase 4: Portable Claude Config - Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 2 (templates/docker/main.tf modified, README.md modified)
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `templates/docker/main.tf` — `variable "anthropic_api_key"` | config | n/a | `variable "docker_socket"` / `variable "workspace_image"` (lines 32–45) | exact |
| `templates/docker/main.tf` — `docker_volume "claude_config_volume"` | resource | CRUD | `docker_volume "home_volume"` (lines 119–145) | exact |
| `templates/docker/main.tf` — second `volumes {}` on `docker_container.workspace` | resource-block | n/a | existing `volumes {}` block (lines 215–219) | exact |
| `templates/docker/main.tf` — Claude config block in `startup_script` | script | event-driven | existing `/etc/skel` guard in `startup_script` (lines 72–79) | role-match |
| `templates/docker/main.tf` — `module "claude-code"` | module | request-response | `module "code-server"` (lines 245–254) / `module "jetbrains-gateway"` (lines 259–269) | exact |
| `README.md` — operator runbook section | docs | n/a | `## Workspace Template` section (lines 296–398) | role-match |

---

## Pattern Assignments

### 1. `variable "anthropic_api_key"` (new variable)

**Analog:** `variable "docker_socket"` and `variable "workspace_image"` — `templates/docker/main.tf` lines 32–45

**Existing pattern (lines 32–45):**
```hcl
variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI. Defaults to /var/run/docker.sock."
  type        = string
}

# Workspace base image — pinned default, overridable (D-02).
# Pin to a specific digest for production reproducibility:
#   codercom/enterprise-base:ubuntu@sha256:<digest>
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Workspace container image. Override to use a custom image."
  type        = string
}
```

**What to copy:** Follow the block structure exactly: `default`, `description`, `type`. For `anthropic_api_key`, add `sensitive = true` (not present in existing variables — this is the only addition). Place the new variable block immediately after `variable "workspace_image"` (line 45), still within the `# ── Variables ──` section. Use `default = ""` so the empty value leaves OAuth/subscription login as the default auth path (D-07).

**Target form:**
```hcl
variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (from console.anthropic.com). Leave empty to use interactive OAuth/subscription login."
  type        = string
  sensitive   = true
  default     = ""
}
```

---

### 2. `docker_volume "claude_config_volume"` (new resource)

**Analog:** `docker_volume "home_volume"` — `templates/docker/main.tf` lines 113–145

**Existing pattern (lines 119–145):**
```hcl
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  # The volume name is keyed on the immutable workspace ID (UUID), so a rename
  # never changes it. ignore_changes on [name] guards against a future name-format
  # change forcing a destroy/recreate (which would lose all home data). (Pitfall 2)
  lifecycle {
    ignore_changes = [name]
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
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}
```

**What to copy:** Copy this block's structure exactly. Key differences for the Claude volume:
- Name uses `data.coder_workspace_owner.me.id` (owner UUID, not workspace UUID) — `"coder-${data.coder_workspace_owner.me.id}-claude"`
- `lifecycle` gets an additional `prevent_destroy = true` line (absent from home_volume — this is the critical addition)
- Labels: keep `coder.owner` and `coder.owner_id`; drop `coder.workspace_id` and `coder.workspace_name_at_creation` (those are workspace-scoped); add `coder.purpose = "claude-config"`
- Place after `docker_volume.home_volume` block (line 145), under the same section header or a new `# ── Claude config volume ──` sub-header

**Target form:**
```hcl
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
```

---

### 3. Second `volumes {}` block on `docker_container.workspace`

**Analog:** Existing `volumes {}` block — `templates/docker/main.tf` lines 215–219

**Existing pattern (lines 215–219):**
```hcl
  # Mount the persistent home volume at /home/coder (TPL-04 / D-07).
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
```

**What to copy:** Copy the block structure identically. The new block must be declared immediately after the existing `volumes {}` block (parent mount before child mount — Linux mount namespace ordering, D-04). Change only `container_path` and `volume_name`. Place before the `labels {}` blocks (line 221).

**Target form:**
```hcl
  # Mount the per-owner Claude config volume at a neutral path.
  # Declared after /home/coder (parent before child — nested mount ordering).
  volumes {
    container_path = "/home/coder/.claude-shared"
    volume_name    = docker_volume.claude_config_volume.name
    read_only      = false
  }
```

---

### 4. Claude config block appended to `coder_agent.main.startup_script`

**Analog:** Existing `/etc/skel` seed block — `templates/docker/main.tf` lines 72–79

**Existing pattern (lines 72–79):**
```hcl
  startup_script = <<-EOT
    set -e
    # Seed home from /etc/skel on the very first workspace start (idempotent).
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi
  EOT
```

**What to copy:** Match the idempotency discipline exactly — every operation is guarded so it is safe to re-run on every workspace start. The `stat`-based `chown` guard (`if [ "$(stat -c '%U' ...)" != "coder" ]`) mirrors the `if [ ! -f ~/.init_done ]` guard. The `mkdir -p` and `ln -sfn`/`ln -sf` flags are intrinsically idempotent. Append inside the same `<<-EOT ... EOT` heredoc, after the existing block.

**Target form (append after line 78, before `EOT`):**
```sh
    # ── Claude Code config (per-owner shared volume) ─────────────────────────
    # The shared volume mounts at ~/.claude-shared (neutral path).
    # Symlinks point ~/.claude and ~/.claude.json into it.
    # All steps are idempotent — safe to re-run on every workspace start.
    CLAUDE_SHARED="$HOME/.claude-shared"

    # Fix ownership on first use (volume starts root-owned when empty).
    if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
      sudo chown -R coder:coder "$CLAUDE_SHARED"
    fi

    # Create internal directory structure.
    mkdir -p "$CLAUDE_SHARED/dot-claude"

    # Initialize ~/.claude.json placeholder if missing (prevents claude from
    # creating a real file at ~/.claude.json before the symlink is in place).
    if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
      echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
    fi

    # Symlink ~/.claude → shared directory (ln -sfn: -n treats target as file if symlink).
    ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"

    # Symlink ~/.claude.json → shared file.
    ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
```

---

### 5. `module "claude-code"` (new module)

**Analog:** `module "code-server"` (lines 245–254) and `module "jetbrains-gateway"` (lines 259–269)

**Existing pattern (lines 245–254 and 259–269):**
```hcl
# Browser VS Code via code-server (TPL-02 / D-05)
module "code-server" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/code-server/coder"
  version      = "1.5.0"
  agent_id     = coder_agent.main.id
  agent_name   = "main"
  folder       = "/home/coder"
  display_name = "VS Code"
  order        = 1
}

# JetBrains Gateway — IntelliJ IDEA only (TPL-03 / D-06)
module "jetbrains-gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = "/home/coder"
  jetbrains_ides = ["IU"]
  default        = "IU"
  order          = 2
}
```

**What to copy:** Copy the `count`, `source`, `version`, `agent_id`, `order` pattern exactly. The `claude-code` module does not take `agent_name` or `folder` inputs — omit those. Add `anthropic_api_key` and `install_claude_code`. Place immediately after `module "jetbrains-gateway"` (line 269).

**Target form:**
```hcl
# Claude Code CLI — installs latest CLI and wires ANTHROPIC_API_KEY (CLAUDE-01 / D-05, D-06)
module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  anthropic_api_key   = var.anthropic_api_key
  install_claude_code = true
  order               = 3
}
```

---

### 6. README.md operator runbook section (new section)

**Analog:** `## Workspace Template` section — `README.md` lines 296–398

**Existing pattern to mirror:**

The existing `## Workspace Template` section (lines 296–398) uses this structure:
- H2 heading for the feature area
- One-sentence intro paragraph
- Named H3 subsections for distinct operator topics
- Fenced bash code blocks for commands
- Inline callout blockquotes (`> **Note:**`) for warnings
- Paragraph prose for failure symptoms and caveats

Key style signals (lines 296–335):
```markdown
## Workspace Template

The `templates/docker/` directory contains a Terraform template that provisions Coder workspaces
as Docker containers on the host machine, with browser VS Code (via code-server), JetBrains
Gateway (IntelliJ IDEA), and a persistent home directory.

### Push the template

Run the following from the repo root (requires the `coder` CLI logged in to your Coder server):
...

> **Note:** If you push a template update later, re-run `coder templates edit` to keep the
> display name, description, and icon — they are not preserved automatically on re-push.
```

**What to copy:** Add a new H3 subsection (`### Claude Code`) nested inside `## Workspace Template`, appended after the existing `### Home directory persistence` subsection (line 395–398). Match the same heading style, prose density, blockquote callout format, and fenced code blocks. Cover exactly the four topics from D-09: (1) first-run login walkthrough, (2) what carries across workspaces, (3) empty-volume seeding behavior, (4) concurrent-write caveat. Add the volume-cleanup note from D-10.

**Placement:** After line 398 (end of `### Home directory persistence`), still inside the `## Workspace Template` section.

**Style reference excerpt (lines 393–398):**
```markdown
### Home directory persistence

Workspace home directories (`/home/coder`) are stored in per-workspace Docker volumes and
survive workspace stop/start cycles. Deleting a workspace deletes its home volume — all files
under `/home/coder` are permanently removed when the workspace is deleted.
```

---

## Shared Patterns

### File header comment update

**Source:** `templates/docker/main.tf` lines 1–15 (resources list comment)

**Apply to:** The file header comment block at the top of `main.tf`. Add `module claude-code` and `docker_volume claude_config_volume` to the resources list.

**Existing block (lines 1–15):**
```hcl
# templates/docker/main.tf
# Docker workspace template — provisions Coder workspaces as Docker containers on the host.
#
# Requires:
#   - Coder server running (compose.yaml) with /var/run/docker.sock mounted
#   - CODER_ACCESS_URL set to a reachable address (see README ## Workspace Template)
#
# Resources:
#   coder_agent      — workspace agent (always present; no count)
#   docker_volume    — persistent /home/coder (survives stop/start)
#   docker_image     — workspace base image (cached locally)
#   docker_container — ephemeral workspace container (count = start_count)
#   module code-server        — browser VS Code (TPL-02)
#   module jetbrains-gateway  — IntelliJ Gateway (TPL-03)
```

**Pattern:** Add new entries after line 14:
```
#   docker_volume claude_config_volume — per-owner Claude config (survives workspace delete)
#   module claude-code                 — Claude Code CLI + auth wiring (CLAUDE-01)
```

### No-count rule for volumes

**Source:** Comment at `templates/docker/main.tf` lines 113–117

**Apply to:** `docker_volume "claude_config_volume"` — must have NO `count` argument, matching `docker_volume "home_volume"`. Volumes must survive workspace stop (when `start_count = 0`).

**Existing comment (lines 113–117):**
```hcl
# ── Persistent home volume (TPL-04) ──────────────────────────────────────────
#
# docker_volume has NO count — the volume must survive workspace stop/start.
# Name uses workspace ID (UUID, immutable) — NOT workspace name, which can
# change and would orphan the volume. (Pitfall 2)
```

### Idempotency discipline in startup_script

**Source:** `templates/docker/main.tf` lines 74–79

**Apply to:** All shell operations in the Claude config startup_script block. Every command must be safe to re-run on every workspace start (guards like `if [ ! -f ... ]`, `stat`-based ownership check, `-p` flag on `mkdir`, `-sf`/`-sfn` flags on `ln`).

### Inline [REUSABLE] comment block (D-08)

**Source:** `ARCHITECTURE.md` lines 362–456 (the full `[REUSABLE]` snippet)

**Apply to:** Place the full `# ── [REUSABLE] Per-owner Claude Code config volume ──` comment block in `main.tf` wrapping the new variable, volume resource, and module — making the snippet self-contained and copy-pasteable per D-08. The comment block text is authoritative in `ARCHITECTURE.md` lines 362–456.

---

## No Analog Found

All 6 changes have close analogs in the existing codebase. No files lack a match.

| File | Role | Data Flow | Note |
|------|------|-----------|------|
| — | — | — | All analogs found |

---

## Metadata

**Analog search scope:** `templates/docker/main.tf` (full file, 270 lines), `README.md` (full file, 398 lines)
**Files scanned:** 2 (plus CONTEXT.md and ARCHITECTURE.md for blueprint)
**Pattern extraction date:** 2026-06-17
