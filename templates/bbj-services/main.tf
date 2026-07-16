# templates/bbj-services/main.tf
# BBjServices workspace template — a daily-driver for BBj developers that
# combines a full dev environment (code-server + JetBrains Gateway + Claude Code)
# with a live BBjServices instance running on port 8888.
#
# Forked from templates/java-fullstack/main.tf. BBj-specific changes:
#   - build context is the operator-supplied host asset folder (var.bbj_context_path)
#   - LICENSE_SERVER build-arg is injected from var.bbj_license_server
#   - BBj stack (BBj version + JDK) is chosen from an admin-curated combo list
#   - BBjServices is started by its own coder_script.bbjservices resource
#     (foreground exec, :8888 port guard) instead of a startup_script background job
#   - coder_app "bbjservices" exposes localhost:8888 via subdomain routing
#
# Workspace parameters (prompted in the Coder UI at create time):
#   git_repo  — optional Git URL to clone into the workspace; editors open it
#   bbj_stack — which curated (BBj version + JDK) combo to build; JDK is derived from it
#
# Requires:
#   - Coder server running (compose.yaml) with BBJ_ASSETS_PATH bind-mounted at /mnt/bbj-assets
#   - CODER_ACCESS_URL set to a reachable address
#   - CODER_WILDCARD_ACCESS_URL set for subdomain app routing (see FLAG-01 in README)
#   - Operator must copy this Dockerfile + playback.properties into BBJ_ASSETS_PATH
#     alongside BBj*.jar and certificate.bls before running coder templates push
#
# Resources:
#   coder_agent      — workspace agent (always present; no count)
#   coder_script     — BBjServices launch (foreground exec, dedicated dashboard log)
#   docker_volume    — persistent /home/coder (survives stop/start)
#   docker_image     — workspace image (built from operator host context)
#   docker_container — ephemeral workspace container (count = start_count)
#   module code-server        — browser VS Code
#   module jetbrains-gateway  — IntelliJ IDEA (Gateway)
#   module claude-code        — Claude Code CLI + auth wiring
#   coder_app bbjservices     — BBjServices HTTP interface on port 8888

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

# Workspace BASE image — pinned default, overridable. Passed as the BASE_IMAGE
# build arg to the Dockerfile, which layers the JDK, Maven and Node.js on top.
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Base image for the workspace (FROM in the Dockerfile). JDK + Maven + Node.js are layered on top."
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

# BBj build context — the host folder bind-mounted into the coder service at
# /mnt/bbj-assets. The operator must place BBj*.jar + certificate.bls +
# the template's Dockerfile + playback.properties in this folder before pushing.
variable "bbj_context_path" {
  description = "Docker build context for the BBjServices image: the host folder (bind-mounted at /mnt/bbj-assets) holding BBj*.jar, certificate.bls, this Dockerfile, and playback.properties."
  type        = string
  default     = "/mnt/bbj-assets"
}

# BLS license server host:port — passed as the LICENSE_SERVER Docker build-arg
# and sed'd into playback.properties at image build time, replacing
# LICENSE_SERVER_PLACEHOLDER. Example: bls.example.com:2002
variable "bbj_license_server" {
  description = "BLS license server host:port (e.g. bls.example.com:2002). Passed as the LICENSE_SERVER Docker build-arg; must be reachable from the Docker host at image build time."
  type        = string
  default     = ""
}

# BBj ships only x86-64 Linux native libraries (libNativeUtil / libUser, and an
# x86-64 ELF loader). On arm64 hosts (Apple Silicon) an arm64 image fails at
# runtime with UnsatisfiedLinkError and "failed to open /lib64/ld-linux-x86-64.so.2".
# Pin the image to linux/amd64 so it is native on x86-64 servers and Rosetta/qemu-
# emulated on Apple Silicon. Override only if BASIS ships arm64 Linux natives.
variable "bbj_platform" {
  description = "Docker platform for the BBjServices image. BBj has no arm64 Linux build, so this must be linux/amd64 (emulated on Apple Silicon)."
  type        = string
  default     = "linux/amd64"
}

# coder_app routing mode for BBjServices. The Coder app tunnels through the agent
# (NO host port), so it is per-workspace and never conflicts — the right way to
# reach 8888 when several workspaces share a Docker host.
#   true (default)  → wildcard SUBDOMAIN routing — the deployment standard: BBj's
#                     Jetty redirects with absolute paths (e.g. / → /index.html),
#                     which escape a path prefix and 404 on the Coder dashboard.
#                     REQUIRES CODER_WILDCARD_ACCESS_URL on the server (see
#                     FLAG-01 / the nip.io tip in the README).
#   false           → PATH-based routing (…/@user/workspace/apps/bbjservices/).
#                     No wildcard URL needed, but only suitable for path-friendly
#                     apps — NOT the BBjServices web UI (absolute redirects).
variable "bbj_app_subdomain" {
  description = "coder_app routing: true = wildcard subdomain (deployment standard; requires CODER_WILDCARD_ACCESS_URL); false = path-based (breaks on BBj's absolute-path redirects)."
  type        = bool
  default     = true
}

# OPTIONAL direct host publish of container 8888 → http://<docker-host>:<port>.
# Default 0 (OFF): the coder_app above is the primary, conflict-free route. Enable
# this only for direct http://localhost:<port> access, and only when you can accept
# the caveat below.
#
# CAVEAT: a host port can be bound by only ONE container, so a fixed value collides
# when multiple BBj workspaces share a host. If you enable it, give each concurrent
# workspace a DISTINCT port (set per template version / via --variable), or leave it
# 0 and use the per-workspace coder_app route instead.
variable "bbj_host_port" {
  description = "Optional host port to publish BBjServices (container 8888) on. 0 = disabled (default; use the coder_app route). A fixed value collides across concurrent workspaces on the same host."
  type        = number
  default     = 0
}

# Bind address for the published host port. 127.0.0.1 = reachable only from the
# Docker host itself (safe default for local dev); 0.0.0.0 = reachable from other
# machines that can reach the host (use deliberately).
variable "bbj_host_port_bind" {
  description = "IP to bind the published BBjServices host port to. 127.0.0.1 (local only) or 0.0.0.0 (all interfaces)."
  type        = string
  default     = "127.0.0.1"
}

# ── Workspace parameters (prompted at create time) ────────────────────────────

# Optional Git repository to clone on first start. Empty = start with an empty
# home. mutable = false: this is a create-time decision (clone-once).
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

# BBj stack selection — build-time, mutable = false (a different combo is a new
# workspace). The selected combo derives the JDK and the BBj installer jar, so
# an unsupported BBj×JDK pairing cannot be selected. The admin curates the list
# in combinations.json (bundled with the template — edit it and re-push).
data "coder_parameter" "bbj_stack" {
  name         = "bbj_stack"
  display_name = "BBj stack"
  description  = "Which curated (BBj version + JDK) combo to build. The JDK is derived from the combo — there is no separate JDK picker, so unsupported BBj×JDK pairings cannot be selected. A different stack requires a new workspace."
  type         = "string"
  default      = local.bbj_combinations[0].id
  mutable      = false
  icon         = "/icon/java.svg"
  order        = 2

  dynamic "option" {
    for_each = local.bbj_combinations
    content {
      name  = option.value.display
      value = option.value.id
    }
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
  # auto-removes it, so it survives workspace deletion.
  claude_volume_name = "coder-${data.coder_workspace_owner.me.id}-claude"

  # Project folder derivation from the optional git_repo parameter.
  repo_url       = data.coder_parameter.git_repo.value
  repo_name      = local.repo_url != "" ? replace(basename(local.repo_url), ".git", "") : ""
  project_folder = local.repo_name != "" ? "/home/coder/${local.repo_name}" : "/home/coder"

  # ── BBj stack combinations ────────────────────────────────────────────────
  # The curated list is read from combinations.json BUNDLED WITH THE TEMPLATE
  # (path.module), NOT from the runtime asset bind mount. This is deliberate:
  # coder_parameter options are the immutable contract of a template VERSION, so
  # they must be deterministic and always visible to the provisioner. Sourcing
  # them from the bind-mounted asset folder made the options flip to the fallback
  # whenever the provisioner couldn't see /mnt/bbj-assets, which orphaned stored
  # parameter values ("value must be one of options" on rebuild). Reading from
  # path.module ships the manifest inside every pushed template version — edit
  # combinations.json and re-push to change the offered combos.
  #
  # The jars/certificate stay in the asset folder (the docker build context); only
  # this small manifest lives with the template. try() keeps terraform validate
  # working even if the file is somehow absent, falling back to default_combinations.
  default_combinations = [
    { id = "bbj-25.12-jdk21", display = "BBj 25.12 · JDK 21 (Adoptium)", jar = "BBj.jar", jdk = "adoptium-21" },
  ]
  bbj_combinations = try(
    jsondecode(file("${path.module}/combinations.json")),
    local.default_combinations,
  )
  combos_by_id = { for c in local.bbj_combinations : c.id => c }
  selected     = local.combos_by_id[data.coder_parameter.bbj_stack.value]
}

# ── Workspace agent ───────────────────────────────────────────────────────────
#
# coder_agent has NO count — it must always exist so the token and init_script
# are generated even when the workspace is stopped.

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
    # top-level "mcpServers" key of the shared ~/.claude.json. Idempotent and
    # non-fatal under set -e (WR-03 warn-and-continue).
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
    # Registers MemPalace's stdio MCP server under "mcpServers". Idempotent and
    # non-fatal under set -e (WR-03 warn-and-continue).
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
    # Idempotent (skip if already installed) and non-fatal (WR-03).
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
    # Idempotent: skip if the checkout already exists. Non-fatal (WR-03).
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
    # Bootstraps ~/.mempalace once, scoped to the project folder. Idempotent and
    # non-fatal (WR-03).
    if command -v mempalace >/dev/null 2>&1 && [ ! -e "$HOME/.mempalace" ]; then
      mempalace init "$PROJECT_DIR" \
        || echo "WARN: mempalace init failed; continuing" >&2
    fi

    # NOTE: the BBjServices launch deliberately does NOT run here — a process
    # backgrounded from startup_script inherits the script's output pipes
    # (Coder warns "output pipes were not closed after 10s" and may terminate
    # the child). It runs as its own coder_script resource below, in
    # parallel, non-blocking, with a per-script log in the dashboard.
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"

    # Real (symlink-free) Claude config dir — see the CLAUDE_CONFIG_DIR block
    # in startup_script. Makes GSD updates work and is honored by Claude Code.
    CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"

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

# ── BBjServices — dedicated script (WR-03 non-fatal) ─────────────────────────
# Foreground under this script (exec): the script shows as running while
# BBjServices is up and its output is the script's dashboard log. No pidfile —
# the port guard is the only idempotency check (nothing else consumed the
# pidfile; bbj-restart manages its own detached relaunch independently).

resource "coder_script" "bbjservices" {
  agent_id           = coder_agent.main.id
  display_name       = "BBjServices"
  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/sh
    if [ ! -x /opt/bbx/bin/bbjservices ]; then
      echo "WARN: /opt/bbx/bin/bbjservices not found; BBjServices will not be available on port 8888" >&2
      exit 0
    fi

    if ss -tlnp 2>/dev/null | grep -q ':8888'; then
      echo "BBjServices already running (port 8888 active); nothing to do."
      exit 0
    fi

    echo "Starting BBjServices (foreground, as root via sudo) — this script stays running while BBjServices is up."
    exec sudo /opt/bbx/bin/bbjservices --launchd
  EOT
}

# ── Persistent home volume ────────────────────────────────────────────────────
#
# docker_volume has NO count — the volume must survive workspace stop/start.
# Name uses the workspace ID (UUID, immutable) — NOT the name, which can change
# and would orphan the volume.

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
# would be destroyed on `coder delete`; an unmanaged, named Docker volume is the
# correct model — Docker creates it on demand and never auto-removes it.

# ── Workspace image (built from operator host context) ────────────────────────
#
# The build context is the operator-supplied host asset folder (var.bbj_context_path,
# default /mnt/bbj-assets), which is bind-mounted into the coder service via compose.yaml.
# The operator must copy this Dockerfile + playback.properties into that folder
# alongside the version jars (e.g. BBj-25.12.jar) and certificate.bls before running
# coder templates push.
#
# Triggers include the selected BBj stack (BBj version + JDK), license server, and JAR
# checksum so any change to those values forces a full image rebuild (and re-runs the
# BBj install).

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}-bbj-${data.coder_parameter.bbj_stack.value}"

  build {
    context    = var.bbj_context_path
    dockerfile = "Dockerfile"
    platform   = var.bbj_platform
    build_args = {
      BASE_IMAGE     = var.workspace_image
      JDK            = local.selected.jdk
      BBJ_JAR_NAME   = local.selected.jar
      MAVEN_VERSION  = var.maven_version
      LICENSE_SERVER = var.bbj_license_server
    }
  }

  triggers = {
    # Use try() so terraform validate succeeds when the asset folder is absent;
    # a real JAR or Dockerfile change in the context folder forces a rebuild.
    dockerfile_sha1 = try(filesha1("${var.bbj_context_path}/Dockerfile"), filesha1("${path.module}/Dockerfile"))
    stack           = data.coder_parameter.bbj_stack.value
    jdk             = local.selected.jdk
    maven_version   = var.maven_version
    license_server  = var.bbj_license_server
    platform        = var.bbj_platform
    bbj_jar_sha1    = try(filesha1("${var.bbj_context_path}/${local.selected.jar}"), "no-jar")
  }

  keep_locally = true
}

# ── Workspace container ───────────────────────────────────────────────────────
#
# count = start_count — container only exists when the workspace is running.
#
# AGENT CONNECTIVITY: when CODER_ACCESS_URL=http://127.0.0.1:7080 (local
# quickstart), the init_script contains 127.0.0.1, which inside the container is
# the container loopback. The entrypoint rewrites it to host.docker.internal.

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

  # Publish BBjServices (container 8888) to a host port so it is reachable at
  # http://<docker-host>:<bbj_host_port> directly (e.g. http://localhost:8888),
  # alongside the coder_app route. Disabled when bbj_host_port = 0.
  dynamic "ports" {
    for_each = var.bbj_host_port > 0 ? [1] : []
    content {
      internal = 8888
      external = var.bbj_host_port
      ip       = var.bbj_host_port_bind
      protocol = "tcp"
    }
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

# Claude Code CLI — installs latest CLI and wires ANTHROPIC_API_KEY.
module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  anthropic_api_key   = var.anthropic_api_key
  install_claude_code = true
}

# ── BBjServices app ──────────────────────────────────────────────────────────
#
# Exposes the BBjServices HTTP interface (port 8888) as a Coder app. Tunnels
# through the agent — no host port, so it is per-workspace and conflict-free.
# Routing mode is var.bbj_app_subdomain (default false = path-based, which needs no
# wildcard URL; true = subdomain, which requires CODER_WILDCARD_ACCESS_URL — see
# FLAG-01). share="owner" restricts access to the workspace owner (T-m12-02).
# The healthcheck polls the server root; interval=10s, threshold=6 (60s grace).

resource "coder_app" "bbjservices" {
  agent_id     = coder_agent.main.id
  slug         = "bbjservices"
  display_name = "BBjServices"
  url          = "http://localhost:8888"
  icon         = "/icon/java.svg"
  subdomain    = var.bbj_app_subdomain
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8888/"
    interval  = 10
    threshold = 6
  }
}
