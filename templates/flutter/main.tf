# templates/flutter/main.tf
# Flutter / Dart workspace template — a daily-driver for Flutter-first projects with
# first-class AI tooling (Claude Code, MemPalace MCP, GSD).
#
# Provisions Coder workspaces as Docker containers on the host, pre-loaded with:
#   - a build-time-selected Flutter SDK channel (stable/beta), which bundles Dart
#   - `flutter` and `dart` on the system PATH from the first login
#   - Node.js LTS (npm/npx) for Claude Code CLI, GSD, and node JSON merges
#   - VS Code (code-server browser, with Dart + Flutter extensions) + VS Code Desktop
#     + IntelliJ IDEA Ultimate (JetBrains Gateway)
#   - Claude Code CLI + webforJ MCP + MemPalace MCP, per-owner shared config
#   - GSD (gsd-core)
#   - an OPTIONAL git repo cloned on first start (prompted at creation)
#
# Workspace parameters (prompted in the Coder UI at create time):
#   git_repo        — optional Git URL to clone into the workspace; editors open it
#   flutter_channel — which Flutter channel to install (build-time; changing rebuilds)
#
# Requires:
#   - Coder server running (compose.yaml) with /var/run/docker.sock mounted
#   - CODER_ACCESS_URL set to a reachable address (see README ## Workspace Template)
#   - Host /var/run/docker.sock present and accessible (the Coder server compose
#     already ensures this); GID must match docker_group_id variable (default 999)
#
# Resources:
#   coder_agent         — workspace agent (always present; no count)
#   docker_volume       — persistent /home/coder (survives stop/start)
#   docker_image        — workspace image (Flutter/Dart; cached per flutter_channel)
#   docker_container    — ephemeral workspace container (count = start_count);
#                         mounts host Docker socket for docker-outside-of-docker
#                         (`docker` / `docker compose` available in workspace)
#   module code-server        — browser VS Code (Dart + Flutter + Claude Code extensions)
#   module vscode-desktop     — local VS Code Desktop via SSH  [LIVE-VERIFY]
#   module jetbrains-gateway  — IntelliJ IDEA Ultimate (Gateway)
#   module claude-code        — Claude Code CLI + auth wiring

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

# Host Docker socket GID for docker-outside-of-docker access.
# The coder user (the image's final USER) needs to be in the host docker group
# to read/write the socket mounted at /var/run/docker.sock. Discover the correct
# GID on the host with:
#   stat -c '%g' /var/run/docker.sock
# 999 is the standard GID on Debian/Ubuntu Docker Engine installations.
# Docker Desktop (Mac/Windows) uses a different GID — override this variable
# if socket access inside the workspace returns "permission denied".
variable "docker_group_id" {
  default     = "999"
  description = "GID of the host's docker group (used for /var/run/docker.sock access). Discover with: stat -c '%g' /var/run/docker.sock on the host. Override if your host docker socket GID differs from 999 (the Debian/Ubuntu default)."
  type        = string
}

# Workspace BASE image — pinned default, overridable (D-02). Passed as the
# BASE_IMAGE build arg to the in-template Dockerfile, which layers the Flutter SDK,
# Node.js, and the AI/dev plumbing on top. Pin to a digest for production
# reproducibility:
#   codercom/enterprise-base:ubuntu@sha256:<digest>
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Base image for the workspace (FROM in the in-template Dockerfile). The Flutter SDK toolchain is layered on top."
  type        = string
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (from console.anthropic.com). Leave empty to use interactive OAuth/subscription login."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Workspace parameters (prompted at create time) ────────────────────────────
#
# coder_parameter is a DATA SOURCE — its `.value` is resolved from the user's
# input when the workspace is created/updated.

# Optional Git repository to clone on first start. Empty = start with an empty
# home. mutable = false: this is a create-time decision (clone-once); changing it
# later would not re-clone an existing checkout, so it is not offered as editable.
data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository (optional)"
  description  = "HTTPS or SSH URL of a Git repo to clone into the workspace on first start. Leave blank to start with an empty workspace."
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/git.svg"
  order        = 1
}

# Flutter channel selection — build-time. The value is passed as the FLUTTER_CHANNEL
# build arg and is part of the image name + triggers, so changing it rebuilds the
# workspace image (mutable = true: editable on a workspace update, which triggers
# that rebuild). The Flutter SDK bundles the matching Dart SDK; other channels
# remain available at runtime via `flutter channel <name> && flutter upgrade`.
data "coder_parameter" "flutter_channel" {
  name         = "flutter_channel"
  display_name = "Flutter channel"
  description  = "Flutter release channel to install. Build-time selection — changing it rebuilds the workspace image. The SDK bundles the matching Dart. Switch at runtime with `flutter channel`."
  type         = "string"
  default      = "stable"
  mutable      = true
  icon         = "/icon/flutter.svg"
  order        = 2

  option {
    name  = "Stable"
    value = "stable"
  }
  option {
    name  = "Beta"
    value = "beta"
  }
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

  # Per-owner Claude config volume name, keyed on the immutable owner UUID (a
  # rename never changes it). Intentionally NOT a Terraform resource — see the
  # docker_container mount below. Docker auto-creates it on first start and never
  # auto-removes it, so it survives workspace deletion (D-03).
  claude_volume_name = "coder-${data.coder_workspace_owner.me.id}-claude"

  # Project folder derivation from the optional git_repo parameter.
  # basename() on a Git URL yields "<repo>.git"; strip the suffix for the dir.
  # When no repo is given, editors open the home directory.
  repo_url       = data.coder_parameter.git_repo.value
  repo_name      = local.repo_url != "" ? replace(basename(local.repo_url), ".git", "") : ""
  project_folder = local.repo_name != "" ? "/home/coder/${local.repo_name}" : "/home/coder"
}

# ── Workspace agent ───────────────────────────────────────────────────────────
#
# coder_agent has NO count — it must always exist so the token and init_script
# are generated even when the workspace is stopped. (Pitfall 1)

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # The vscode-desktop registry module below provides the folder-aware VS Code
  # Desktop button; disable the agent's built-in one so it isn't shown twice.
  display_apps {
    vscode = false
  }

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

    # Fix ownership on first use (volume starts root-owned when empty). Non-fatal
    # under set -e (WR-03): a missing passwordless sudo must not abort startup.
    if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
      sudo chown -R coder:coder "$CLAUDE_SHARED" \
        || echo "WARN: could not chown $CLAUDE_SHARED; continuing" >&2
    fi

    # Create internal directory structure.
    mkdir -p "$CLAUDE_SHARED/dot-claude"

    # Migrate a pre-existing real ~/.claude dir into the shared volume before
    # replacing it with a symlink. Only remove the original if the copy succeeded
    # or the source was empty (never rm -rf after a masked copy failure, WR-01).
    if [ ! -L "$HOME/.claude" ] && [ -e "$HOME/.claude" ]; then
      if cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null \
         || [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
        rm -rf "$HOME/.claude"
      fi
    fi

    # Symlink ~/.claude → shared directory.
    ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"

    # Migrate a pre-existing real ~/.claude.json into the shared volume FIRST,
    # before the placeholder can shadow it (CR-01 content preservation).
    if [ ! -L "$HOME/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then
      cp -f "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"
      rm -f "$HOME/.claude.json"
    fi

    # Initialize ~/.claude.json placeholder only as a last resort.
    if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
      echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
    fi

    # Symlink ~/.claude.json → shared file.
    ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"

    # ── CLAUDE_CONFIG_DIR — symlink-free config root for Claude Code AND GSD ──
    # The agent env sets CLAUDE_CONFIG_DIR to the PHYSICAL shared dir (not the
    # ~/.claude symlink). GSD >= 1.7.0 refuses to install/update into a
    # symlinked config root (write-confinement guard); the env var hands it —
    # and Claude Code — the resolved path, so /gsd-update works with no flags.
    # With CLAUDE_CONFIG_DIR set, Claude Code reads $CLAUDE_CONFIG_DIR/.claude.json
    # rather than ~/.claude.json: migrate the legacy shared file once, then keep
    # the old location as a symlink so ~/.claude.json and all prior references
    # stay coherent (writes follow the symlink). Idempotent.
    if [ ! -L "$CLAUDE_SHARED/dot-claude.json" ] && [ -f "$CLAUDE_SHARED/dot-claude.json" ] \
       && [ ! -f "$CLAUDE_SHARED/dot-claude/.claude.json" ]; then
      cp -f "$CLAUDE_SHARED/dot-claude.json" "$CLAUDE_SHARED/dot-claude/.claude.json"
    fi
    if [ ! -f "$CLAUDE_SHARED/dot-claude/.claude.json" ]; then
      echo '{}' > "$CLAUDE_SHARED/dot-claude/.claude.json"
    fi
    ln -sf "dot-claude/.claude.json" "$CLAUDE_SHARED/dot-claude.json"

    # ── Claude permissions — force bypassPermissions in every workspace ───────
    # Merges permissions.defaultMode = "bypassPermissions" into the shared Claude
    # Code settings file so `claude` behaves as if launched with
    # --dangerously-skip-permissions in every workspace of THIS owner. Scope: this
    # writes ONLY to $CLAUDE_SHARED/dot-claude/settings.json — the per-owner Docker
    # volume mounted inside workspace containers — never the operator host. Merged
    # with node (guaranteed present in the image) so all other existing settings.json
    # keys are preserved. Idempotent: re-asserts the key on every start. Non-fatal
    # under set -e (WR-03 warn-and-continue): a missing node or a write failure must
    # NEVER abort the startup_script — log and continue.
    if command -v node >/dev/null 2>&1; then
      CLAUDE_SETTINGS="$CLAUDE_SHARED/dot-claude/settings.json" node -e '
        const fs = require("fs");
        const f = process.env.CLAUDE_SETTINGS;
        let cfg = {};
        try { cfg = JSON.parse(fs.readFileSync(f, "utf8") || "{}") || {}; } catch (e) {}
        cfg.permissions = cfg.permissions || {};
        cfg.permissions.defaultMode = "bypassPermissions";
        fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");
      ' || echo "WARN: could not set Claude bypassPermissions; continuing" >&2
    else
      echo "WARN: node not found; skipping Claude bypassPermissions setup" >&2
    fi

    # ── webforJ MCP server — preconfigure in user-scope Claude config ─────────
    # Registers the hosted webforJ MCP server (https://mcp.webforj.com/) under the
    # top-level "mcpServers" key of the shared ~/.claude.json, so every workspace
    # for this owner has it available out of the box. Merged with node (guaranteed
    # present — Node.js is layered into the workspace image) so existing config and
    # auth are preserved. Idempotent: re-asserts the entry on every start without
    # duplicating. Non-fatal under set -e (WR-03 warn-and-continue): a missing node
    # or a write failure must NEVER abort the startup_script — log and continue.
    if command -v node >/dev/null 2>&1; then
      CLAUDE_JSON="$CLAUDE_SHARED/dot-claude.json" node -e '
        const fs = require("fs");
        const f = process.env.CLAUDE_JSON;
        let cfg = {};
        try { cfg = JSON.parse(fs.readFileSync(f, "utf8") || "{}") || {}; } catch (e) {}
        cfg.mcpServers = cfg.mcpServers || {};
        cfg.mcpServers.webforj = { type: "http", url: "https://mcp.webforj.com/" };
        fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");
      ' || echo "WARN: could not register webforJ MCP server; continuing" >&2
    else
      echo "WARN: node not found; skipping webforJ MCP registration" >&2
    fi

    # ── MemPalace MCP server — preconfigure in user-scope Claude config ────────
    # Registers MemPalace's stdio MCP server (the system-wide `mempalace` CLI baked
    # into the image, run as `mempalace mcp serve`) under the top-level "mcpServers"
    # key of the shared ~/.claude.json, so every workspace for this owner has local
    # memory available out of the box. Merged with node (guaranteed present) so
    # existing config and auth are preserved. Idempotent: re-asserts the entry on
    # every start without duplicating. Non-fatal under set -e (WR-03 warn-and-
    # continue): a missing node or a write failure must NEVER abort the
    # startup_script — log and continue.
    if command -v node >/dev/null 2>&1; then
      CLAUDE_JSON="$CLAUDE_SHARED/dot-claude.json" node -e '
        const fs = require("fs");
        const f = process.env.CLAUDE_JSON;
        let cfg = {};
        try { cfg = JSON.parse(fs.readFileSync(f, "utf8") || "{}") || {}; } catch (e) {}
        cfg.mcpServers = cfg.mcpServers || {};
        cfg.mcpServers.mempalace = { command: "/opt/mempalace/bin/mempalace-mcp", args: [] };
        fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");
      ' || echo "WARN: could not register MemPalace MCP server; continuing" >&2
    else
      echo "WARN: node not found; skipping MemPalace MCP registration" >&2
    fi

    # ── GSD (gsd-core) — install-once into the shared per-owner ~/.claude ────────
    # Idempotent (skip if already installed) and non-fatal (WR-03): a failed or
    # npm-less install must never abort startup.
    if [ ! -e "$HOME/.claude/gsd-core" ]; then
      if command -v npm >/dev/null 2>&1; then
        npx -y @opengsd/gsd-core@latest --claude --global \
          || echo "WARN: GSD install failed; continuing without it" >&2
      else
        echo "WARN: npm not found; skipping GSD install" >&2
      fi
    fi

    # ── Optional project repo clone (git_repo parameter) ──────────────────────
    # Clone the user-supplied repo into the derived project folder on first start.
    # Idempotent: skip if the checkout already exists. Non-fatal (WR-03): a missing
    # git binary or a clone failure must never abort the startup_script.
    PROJECT_DIR="${local.project_folder}"
    GIT_REPO="${local.repo_url}"
    if [ -n "$GIT_REPO" ] && [ ! -e "$PROJECT_DIR/.git" ]; then
      if command -v git >/dev/null 2>&1; then
        git clone "$GIT_REPO" "$PROJECT_DIR" \
          || echo "WARN: git clone of $GIT_REPO failed; continuing" >&2
      else
        echo "WARN: git not found; skipping project clone" >&2
      fi
    fi

    # ── MemPalace — initialize the palace for the project ─────────────────────
    # Bootstraps ~/.mempalace (local ChromaDB store) once, scoped to the project
    # folder, so MemPalace recall/capture works from first start. PROJECT_DIR is
    # the cloned repo path when the optional git_repo parameter was supplied, else
    # $HOME — so init is best-effort whether or not a repo was cloned. Guarded on
    # the `mempalace` CLI being present AND ~/.mempalace being absent (idempotent:
    # never re-inits an existing palace). Non-fatal (WR-03): a missing binary or an
    # init failure must NEVER abort the startup_script — warn and continue.
    if command -v mempalace >/dev/null 2>&1 && [ ! -e "$HOME/.mempalace" ]; then
      mempalace init "$PROJECT_DIR" \
        || echo "WARN: mempalace init failed; continuing" >&2
    fi

  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"

    # Real (symlink-free) Claude config dir — see the CLAUDE_CONFIG_DIR block
    # in startup_script. Makes GSD updates work and is honored by Claude Code.
    CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"

    # Flutter toolchain env. flutter/dart are symlinked into /usr/local/bin (already
    # on PATH) and /etc/profile.d/10-flutter.sh exports these for login shells;
    # mirror them here for non-login-shell parity (agent shell, coder_script, etc.),
    # same rationale as the toolchain homes in the java-fullstack template. PUB_CACHE
    # lives on the persistent home volume so activated dart/flutter packages survive
    # restarts.
    FLUTTER_HOME = "/opt/flutter"
    PUB_CACHE    = "/home/coder/.pub-cache"
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

# ── Persistent home volume ────────────────────────────────────────────────────
#
# docker_volume has NO count — the volume must survive workspace stop/start.
# Name uses the workspace ID (UUID, immutable) — NOT the name, which can change
# and would orphan the volume. (Pitfall 2)

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

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

# ── Claude config volume (per-owner) ──────────────────────────────────────────
#
# Intentionally NOT a docker_volume resource — it is referenced by name only in
# the docker_container mount below (local.claude_volume_name). A managed resource
# would be destroyed on `coder delete`, taking the owner's shared auth with it;
# prevent_destroy would instead make delete fail outright. An unmanaged, named
# Docker volume is the correct model — Docker creates it on demand and never
# auto-removes it. Discover per-owner volumes by name pattern:
#   docker volume ls --format '{{.Name}}' | grep -- '-claude$'

# ── Workspace image (built in-template) ───────────────────────────────────────
#
# Builds the in-template Dockerfile (base image + selected Flutter channel + Node).
# The image name and triggers both include the flutter_channel selection, so
# choosing a different channel produces a distinct, separately-cached image and
# forces a rebuild. keep_locally = true keeps built images across workspace stops.

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}-workspace-${data.coder_parameter.flutter_channel.value}"

  build {
    context    = path.module
    dockerfile = "Dockerfile"
    build_args = {
      BASE_IMAGE      = var.workspace_image
      FLUTTER_CHANNEL = data.coder_parameter.flutter_channel.value
    }
  }

  triggers = {
    dockerfile_sha1 = filesha1("${path.module}/Dockerfile")
    flutter_channel = data.coder_parameter.flutter_channel.value
  }

  keep_locally = true
}

# ── Workspace container ───────────────────────────────────────────────────────
#
# count = start_count — container only exists when the workspace is running.
#
# AGENT CONNECTIVITY (D-09): when CODER_ACCESS_URL=http://127.0.0.1:7080 (local
# quickstart), the init_script contains 127.0.0.1, which inside the container is
# the container loopback. The entrypoint rewrites it to host.docker.internal,
# resolved by the host entry below. For a real CODER_ACCESS_URL the replace() is
# a no-op and the host entry is benign. (Pitfall 3 / D-10)

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.image_id
  name     = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(
    coder_agent.main.init_script,
    "/(https?://)(localhost|127\\.0\\.0\\.1)/",
    "$${1}host.docker.internal"
  )]
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Persistent home volume at /home/coder.
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Per-owner Claude config volume at a neutral path. Declared AFTER /home/coder
  # so the parent mount registers first (Linux mount-namespace shadowing).
  volumes {
    container_path = "/home/coder/.claude-shared"
    volume_name    = local.claude_volume_name
    read_only      = false
  }

  # Host Docker socket — docker-outside-of-docker. The Docker CLI + Compose
  # plugin baked into the image (Dockerfile) drive the HOST daemon via this
  # socket. Compose stacks run as SIBLING containers alongside the workspace.
  # host_path is a HOST filesystem path (/var/run/docker.sock must exist on
  # the host — the Coder server's own compose.yaml already mounts it there).
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = false
  }

  # Join the host docker group so the coder user can access the mounted socket.
  # Discover the correct GID with: stat -c '%g' /var/run/docker.sock on the host.
  # A mismatch between this GID and the host socket's actual GID causes
  # "permission denied" when running docker commands inside the workspace.
  # Override the docker_group_id variable if your host differs from the default.
  group_add = [var.docker_group_id]

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
# count = start_count mirrors docker_container. folder points at the cloned repo
# when git_repo was supplied (local.project_folder), else /home/coder.

# Browser VS Code via code-server. Pre-installs Dart + Flutter + Claude Code extensions from
# Open VSX (the marketplace code-server uses).
# [LIVE-VERIFY] Confirm the Open VSX extension ids resolve at push time:
# "Dart-Code.dart-code", "Dart-Code.flutter", and "Anthropic.claude-code". If any fails
# to install, the module logs a warning and continues — remove the offending id or install
# it manually from the code-server UI.
module "code-server" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/code-server/coder"
  version      = "1.5.0"
  agent_id     = coder_agent.main.id
  folder       = local.project_folder
  display_name = "VS Code"
  extensions   = ["Dart-Code.dart-code", "Dart-Code.flutter", "Anthropic.claude-code"]
  order        = 1
}

# VS Code Desktop — opens the user's locally-installed VS Code over SSH.
# [LIVE-VERIFY] Confirm the module exists at registry.coder.com/coder/vscode-desktop/coder,
# verify the exact latest version (1.1.0 is last-known-good), and confirm the
# `folder` variable is accepted — bump the pin if the registry has a newer version.
module "vscode-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.1.0" # [LIVE-VERIFY] confirm version at push time
  agent_id = coder_agent.main.id
  folder   = local.project_folder
  order    = 2
}

# JetBrains Gateway — IntelliJ IDEA Ultimate (supports the Dart + Flutter plugins;
# install them once from the IDE's plugin marketplace). folder must be an absolute
# path — relative paths fail module validation.
module "jetbrains-gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = local.project_folder
  jetbrains_ides = ["IU"]
  default        = "IU"
  order          = 3
}

# Claude Code CLI — installs latest CLI and wires ANTHROPIC_API_KEY. CLI version
# intentionally unpinned (the Claude CLI moves fast; latest-on-start is wanted).
# The module (v5.2.0) does not take agent_name/folder/order.
module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  anthropic_api_key   = var.anthropic_api_key
  install_claude_code = true
}
