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
#   docker_volume claude_config_volume — per-owner Claude config (survives workspace delete)
#   module claude-code                 — Claude Code CLI + auth wiring (CLAUDE-01)

terraform {
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
  required_version = ">= 1.9"
}

# ── Variables ─────────────────────────────────────────────────────────────────

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

# ── [REUSABLE] Per-owner Claude Code config volume ──────────────────────────
#
# WHAT: A Docker named volume keyed on the owner's immutable UUID. Shared
#   across ALL workspaces for this owner. Carries ~/.claude/ (directory)
#   and ~/.claude.json (file) via a neutral mount point + symlinks.
#
# HOW TO USE:
#   1. Add this anthropic_api_key variable (below).
#   2. Add the docker_volume.claude_config_volume resource (below).
#   3. Add the second volumes{} block to docker_container.workspace (see
#      the comment inside the container resource block below).
#   4. Add the "Claude Code config" block to coder_agent.main.startup_script
#      (see the comment inside the agent resource block below).
#   5. Add the claude-code module (below).
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
#   /home/coder/.claude-shared/            ← named volume mount point
#   /home/coder/.claude-shared/dot-claude/      (actual ~/.claude contents)
#   /home/coder/.claude-shared/dot-claude.json  (actual ~/.claude.json contents)
#   /home/coder/.claude      →  .claude-shared/dot-claude       (symlink)
#   /home/coder/.claude.json →  .claude-shared/dot-claude.json  (symlink)

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (from console.anthropic.com). Leave empty to use interactive OAuth/subscription login."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
}

# ── Workspace agent ───────────────────────────────────────────────────────────
#
# coder_agent has NO count — it must always exist so the token and init_script
# are generated even when the workspace is stopped. (Pitfall 1)

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    # Seed home from /etc/skel on the very first workspace start (idempotent).
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # ── Claude Code config (per-owner shared volume) ──────────────────────────
    # The shared volume mounts at ~/.claude-shared (neutral path).
    # Symlinks point ~/.claude and ~/.claude.json into it.
    # All steps are idempotent — safe to re-run on every workspace start.
    CLAUDE_SHARED="$HOME/.claude-shared"

    # Fix ownership on first use (volume starts root-owned when empty).
    # chown is scoped narrowly to $CLAUDE_SHARED only (T-04-02).
    # WR-03: make the chown non-fatal under set -e — a missing passwordless sudo
    # in a custom workspace_image (or a locked file) must not abort the whole
    # startup_script before the symlinks are created. Log and continue instead.
    if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
      sudo chown -R coder:coder "$CLAUDE_SHARED" \
        || echo "WARN: could not chown $CLAUDE_SHARED; continuing" >&2
    fi

    # Create internal directory structure.
    mkdir -p "$CLAUDE_SHARED/dot-claude"

    # CR-01 upgrade-path fix: if ~/.claude is a real dir (pre-template workspace),
    # migrate contents into the shared volume before replacing with a symlink.
    # WR-01: only remove the original if the copy actually succeeded, OR the
    # source dir is empty (an empty source is a legitimate no-op). A masked copy
    # failure on a non-empty dir must NOT be followed by rm -rf, or real config
    # is destroyed while nothing was preserved.
    if [ ! -L "$HOME/.claude" ] && [ -e "$HOME/.claude" ]; then
      if cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null \
         || [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
        rm -rf "$HOME/.claude"
      fi
      # else: copy failed on a non-empty dir — leave original in place.
    fi

    # Symlink ~/.claude → shared directory (-sfn: -n treats target as file if symlink).
    ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"

    # CR-01 content-preservation fix: migrate a pre-existing real ~/.claude.json
    # into the shared volume FIRST, before the placeholder can shadow it. The
    # [ ! -L ] && [ -f ] test proves the source is the developer's real file, so
    # force-overwrite the (possibly-placeholder) shared file with the real content.
    # (A no-clobber cp -n here would silently skip once a placeholder exists and
    # then rm the real file — the data-loss bug this ordering prevents.)
    if [ ! -L "$HOME/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then
      cp -f "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"
      rm -f "$HOME/.claude.json"
    fi

    # Initialize ~/.claude.json placeholder only as a last resort — when no real
    # file was migrated and no prior shared file exists (prevents claude from
    # writing ~/.claude.json as a file before the symlink is in place).
    if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
      echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
    fi

    # Symlink ~/.claude.json → shared file.
    ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# ── Persistent home volume (TPL-04) ──────────────────────────────────────────
#
# docker_volume has NO count — the volume must survive workspace stop/start.
# Name uses workspace ID (UUID, immutable) — NOT workspace name, which can
# change and would orphan the volume. (Pitfall 2)

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

# ── Claude config volume (per-owner, CLAUDE-02) ───────────────────────────────
#
# docker_volume has NO count — the volume must survive workspace stop/start
# AND workspace deletion (prevent_destroy = true).
# Name uses owner UUID (immutable) — NOT owner name, which can change and
# would orphan the volume. (D-03)

resource "docker_volume" "claude_config_volume" {
  name = "coder-${data.coder_workspace_owner.me.id}-claude"

  # The volume name is keyed on the immutable owner UUID, so a username rename
  # never changes it. prevent_destroy ensures workspace deletion does NOT
  # destroy shared auth/config. ignore_changes guards against a future
  # name-format change forcing a destroy/recreate. (D-03)
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

# ── Workspace base image ──────────────────────────────────────────────────────
#
# keep_locally = true — prevents the image from being removed when workspaces
# stop. The image is pulled once and reused across workspace starts.

resource "docker_image" "main" {
  name         = var.workspace_image
  keep_locally = true
}

# ── Workspace container (TPL-01, TPL-06) ─────────────────────────────────────
#
# count = start_count — container only exists when the workspace is running.
# When stopped, start_count = 0 and the container is destroyed; the home
# volume persists.
#
# AGENT CONNECTIVITY (TPL-06 / D-09):
# When CODER_ACCESS_URL=http://127.0.0.1:7080 (local quickstart), the
# init_script contains 127.0.0.1. Inside the container, 127.0.0.1 points to
# the container loopback — the agent would connect to itself. The entrypoint
# replaces it with host.docker.internal, which the host entry below resolves
# to the Docker host IP. (Pitfall 3)
#
# For production deployments with a real CODER_ACCESS_URL (IP or domain
# reachable from workspace containers), host.docker.internal is not used —
# the replace() is a no-op and the host entry is benign. (D-10)
#
# DOCKER SOCKET GID (TPL-05 / D-08):
# If workspace provisioning fails with a Docker socket permission error, the
# Docker socket GID on your host may differ from the default. Discover it with:
#   stat -c '%g' /var/run/docker.sock
#
# Note: This template does NOT mount /var/run/docker.sock into workspace
# containers — only the Coder server container has socket access (T-03-01).
# The group_add below is for the workspace container's supplemental GID
# (needed only if the workspace image runs processes that require Docker group
# membership for other reasons). For the standard case, leave it commented.
#
# Uncomment and set the correct GID if you need Docker group access inside
# the workspace container:
#   group_add = ["998"]  # Replace 998 with output of: stat -c '%g' /var/run/docker.sock

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.image_id
  name     = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Replace localhost/127.0.0.1 with host.docker.internal so the workspace
  # agent can reach the Coder server when CODER_ACCESS_URL=http://127.0.0.1:7080.
  # Both entrypoint AND the host entry below are required together. (Pitfall 3)
  entrypoint = ["sh", "-c", replace(
    coder_agent.main.init_script,
    "/(https?://)(localhost|127\\.0\\.0\\.1)/",
    "$${1}host.docker.internal"
  )]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # Add host.docker.internal → host-gateway so the workspace agent can reach
  # the Docker host (= Coder server) on Linux. On Docker Desktop (Mac/Windows),
  # host.docker.internal is injected automatically; this entry ensures parity
  # on Linux Docker Engine. (D-09)
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Mount the persistent home volume at /home/coder (TPL-04 / D-07).
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Mount the per-owner Claude config volume at a neutral path (CLAUDE-02, D-04).
  # Declared AFTER /home/coder so the parent mount is registered before the
  # child mount — required for correct Linux mount-namespace shadowing (T-04-03).
  volumes {
    container_path = "/home/coder/.claude-shared"
    volume_name    = docker_volume.claude_config_volume.name
    read_only      = false
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
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

# ── Editor modules ────────────────────────────────────────────────────────────
#
# Both modules use count = start_count to mirror docker_container.
# Only register the coder_app when the workspace is actually running. (Pitfall 7)

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
# jetbrains_ides = ["IU"] restricts to IntelliJ IDEA Ultimate; no other IDEs.
# folder must be a full absolute path — relative paths fail module validation. (Pitfall 4)
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

# Claude Code CLI — installs latest CLI and wires ANTHROPIC_API_KEY (CLAUDE-01 / D-05, D-06)
# Note: the CLI version is intentionally unpinned (no version pin argument) — a deliberate
# exception to the repo's pin-everything ethos. The Claude CLI moves fast; latest-on-start
# ensures the current stable release is always used. Revisit if CLI churn causes workspace
# breakage (D-06). The claude-code module (v5.2.0) does not take agent_name, folder,
# or order — passing any of them fails `terraform plan` with "Unsupported argument".
module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  anthropic_api_key   = var.anthropic_api_key
  install_claude_code = true
}

# ── [END REUSABLE] ────────────────────────────────────────────────────────────
