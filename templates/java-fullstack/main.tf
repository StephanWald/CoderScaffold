# templates/java-fullstack/main.tf
# Universal Java + JS/TS workspace template — a daily-driver for a stack of
# Java/Spring Boot backends and JavaScript/TypeScript (e.g. webforJ) UIs.
#
# Provisions Coder workspaces as Docker containers on the host, pre-loaded with:
#   - a build-time-selected JDK (Adoptium 21/25 or Oracle 21/25)
#   - Apache Maven (pinned 3.9.x)
#   - Node.js LTS (npm/npx) for JS/TS development
#   - VS Code (code-server) + JetBrains Gateway (IntelliJ IDEA) editors
#   - Claude Code CLI + the webforJ MCP server, per-owner shared config
#   - GSD (gsd-core)
#   - an OPTIONAL git repo cloned on first start (prompted at creation)
#
# Workspace parameters (prompted in the Coder UI at create time):
#   git_repo — optional Git URL to clone into the workspace; editors open it
#   jdk      — which JDK to install (build-time; changing it rebuilds the image)
#
# Requires:
#   - Coder server running (compose.yaml) with /var/run/docker.sock mounted
#   - CODER_ACCESS_URL set to a reachable address (see README ## Workspace Template)
#
# Resources:
#   coder_agent      — workspace agent (always present; no count)
#   docker_volume    — persistent /home/coder (survives stop/start)
#   docker_image     — workspace image (JDK/Maven/Node; cached per JDK selection)
#   docker_container — ephemeral workspace container (count = start_count)
#   module code-server        — browser VS Code
#   module jetbrains-gateway  — IntelliJ IDEA (Gateway)
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

# Workspace BASE image — pinned default, overridable (D-02). Passed as the
# BASE_IMAGE build arg to the in-template Dockerfile, which layers the JDK, Maven
# and Node.js on top. Pin to a digest for production reproducibility:
#   codercom/enterprise-base:ubuntu@sha256:<digest>
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Base image for the workspace (FROM in the in-template Dockerfile). JDK + Maven + Node.js are layered on top."
  type        = string
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (from console.anthropic.com). Leave empty to use interactive OAuth/subscription login."
  type        = string
  sensitive   = true
  default     = ""
}

# Pinned Apache Maven version. archive.apache.org retains all releases, so the
# pin is always resolvable (unlike the dlcdn mirror, which keeps only current).
variable "maven_version" {
  description = "Apache Maven version to install (3.9.x stable line)."
  type        = string
  default     = "3.9.16"
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

# JDK selection — build-time. The value is passed as the JDK build arg and is
# part of the image name + triggers, so changing it rebuilds the workspace image
# (mutable = true: editable on a workspace update, which triggers that rebuild).
data "coder_parameter" "jdk" {
  name         = "jdk"
  display_name = "JDK"
  description  = "Java Development Kit to install. Build-time selection — changing it rebuilds the workspace image."
  type         = "string"
  default      = "adoptium-21"
  mutable      = true
  icon         = "/icon/java.svg"
  order        = 2

  option {
    name  = "Adoptium (Temurin) 21 — LTS"
    value = "adoptium-21"
  }
  option {
    name  = "Adoptium (Temurin) 25 — LTS"
    value = "adoptium-25"
  }
  option {
    name  = "Oracle JDK 21 — LTS"
    value = "oracle-21"
  }
  option {
    name  = "Oracle JDK 25 — LTS"
    value = "oracle-25"
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
        cfg.mcpServers.mempalace = { command: "mempalace", args: ["mcp", "serve"] };
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

    # JDK/Maven are installed system-wide in the image at fixed paths regardless
    # of which JDK was selected. Export the homes here for parity in non-login
    # shells (login shells also get them from /etc/profile.d/10-java-maven.sh).
    JAVA_HOME  = "/opt/java/default"
    MAVEN_HOME = "/opt/maven"
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
# Builds the in-template Dockerfile (base image + selected JDK + Maven + Node).
# The image name and triggers both include the JDK selection, so choosing a
# different JDK produces a distinct, separately-cached image and forces a
# rebuild. keep_locally = true keeps built images across workspace stops.

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}-workspace-${data.coder_parameter.jdk.value}"

  build {
    context    = path.module
    dockerfile = "Dockerfile"
    build_args = {
      BASE_IMAGE    = var.workspace_image
      JDK           = data.coder_parameter.jdk.value
      MAVEN_VERSION = var.maven_version
    }
  }

  triggers = {
    dockerfile_sha1 = filesha1("${path.module}/Dockerfile")
    jdk             = data.coder_parameter.jdk.value
    maven_version   = var.maven_version
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

# Browser VS Code via code-server
module "code-server" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/code-server/coder"
  version      = "1.5.0"
  agent_id     = coder_agent.main.id
  folder       = local.project_folder
  display_name = "VS Code"
  order        = 1
}

# JetBrains Gateway — IntelliJ IDEA only (the natural Java IDE).
# folder must be an absolute path — relative paths fail module validation.
module "jetbrains-gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = local.project_folder
  jetbrains_ides = ["IU"]
  default        = "IU"
  order          = 2
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
