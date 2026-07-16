# templates/coderscaffold/main.tf
# CoderScaffold maintainer workspace template — provisions a Coder workspace
# pre-loaded with the StephanWald/CoderScaffold repo.
#
# Structurally identical to templates/docker/main.tf (same providers, modules,
# resource shapes, pin-everything ethos). Distinguishing additions:
#   - startup_script: idempotent non-fatal git clone of StephanWald/CoderScaffold
#     into $HOME/CoderScaffold (after the GSD install block).
#   - code-server and jetbrains-gateway folder pointed at /home/coder/CoderScaffold
#     (the cloned repo) rather than /home/coder.
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

# Workspace BASE image — pinned default, overridable (D-02). Passed as the
# BASE_IMAGE build arg to templates/coderscaffold/Dockerfile, which layers Node.js on
# top. Override to build from a different base.
# Pin to a specific digest for production reproducibility:
#   codercom/enterprise-base:ubuntu@sha256:<digest>
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Base image for the workspace (FROM in the in-template Dockerfile). Node.js is layered on top."
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
#   - Volume cleanup: the volume is unmanaged (not a Terraform resource), so it
#     persists across workspace deletion automatically. To fully remove it:
#     `docker volume rm <name>` manually (see README "Manual cleanup").
#   - Volume name: coder-<owner-uuid>-claude. List with:
#       docker volume ls --format '{{.Name}}' | grep -- '-claude$'
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

  # Per-owner Claude config volume name, keyed on the immutable owner UUID (a
  # rename never changes it). This volume is intentionally NOT a Terraform
  # resource — see the docker_container mount below. Docker auto-creates it on
  # first workspace start and never auto-removes it, so it survives workspace
  # deletion (D-03) WITHOUT a managed resource + prevent_destroy (which would
  # otherwise block `coder delete` entirely).
  claude_volume_name = "coder-${data.coder_workspace_owner.me.id}-claude"
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
        cfg.mcpServers.mempalace = { command: "mempalace", args: ["mcp", "serve"] };
        fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");
      ' || echo "WARN: could not register MemPalace MCP server; continuing" >&2
    else
      echo "WARN: node not found; skipping MemPalace MCP registration" >&2
    fi

    # ── GSD (gsd-core) — install-once into the shared per-owner ~/.claude ────────
    # GSD installs under ~/.claude (skills, agents, gsd-core/bin), which is the
    # shared per-owner volume — so a single install persists across every one of
    # this owner's workspaces. Guards:
    #   - idempotency: skip if ~/.claude/gsd-core already exists (no re-install,
    #     no repeated network, safe under D-02). To update, delete that dir and
    #     restart, or run the npx command manually.
    #   - non-fatal: a GSD install failure (or missing npm) must NEVER abort the
    #     startup_script under set -e — log a warning and continue (WR-03 lesson).
    #   - prerequisite: npx needs Node.js/npm. If npm is absent from the image,
    #     skip with a clear warning rather than erroring.
    if [ ! -e "$HOME/.claude/gsd-core" ]; then
      if command -v npm >/dev/null 2>&1; then
        npx -y @opengsd/gsd-core@latest --claude --global \
          || echo "WARN: GSD install failed; continuing without it" >&2
      else
        echo "WARN: npm not found; skipping GSD install (install Node.js in the image to enable)" >&2
      fi
    fi

    # ── CoderScaffold repo — clone once on first start ────────────────────────
    # Idempotent: skip if $HOME/CoderScaffold already exists (safe under D-02).
    # Non-fatal (WR-03 pattern): a missing git binary or a network failure must
    # NEVER abort the startup_script under set -e — log a warning and continue.
    # The editors' folder is pointed at this path; they open it once the agent
    # has run and the clone is present.
    if [ ! -d "$HOME/CoderScaffold" ]; then
      if command -v git >/dev/null 2>&1; then
        git clone https://github.com/StephanWald/CoderScaffold.git "$HOME/CoderScaffold" \
          || echo "WARN: CoderScaffold clone failed; continuing" >&2
      else
        echo "WARN: git not found; skipping CoderScaffold clone" >&2
      fi
    fi

    # ── MemPalace — initialize the palace for the cloned repo ─────────────────
    # Bootstraps ~/.mempalace (local ChromaDB store) once, scoped to the cloned
    # CoderScaffold checkout, so MemPalace recall/capture works from first start.
    # Guarded on the `mempalace` CLI being present AND ~/.mempalace being absent
    # (idempotent: never re-inits an existing palace). Non-fatal (WR-03): a missing
    # binary or an init failure must NEVER abort the startup_script — warn and go on.
    if command -v mempalace >/dev/null 2>&1 && [ ! -e "$HOME/.mempalace" ]; then
      mempalace init "$HOME/CoderScaffold" \
        || echo "WARN: mempalace init failed; continuing" >&2
    fi
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

# ── Claude config volume (per-owner, CLAUDE-02 / D-03) ────────────────────────
#
# The per-owner Claude config volume is INTENTIONALLY NOT declared as a
# docker_volume resource. It is referenced by name only, in the docker_container
# mount below (local.claude_volume_name), and Docker auto-creates it on first
# workspace start.
#
# WHY NOT a managed resource:
#   A docker_volume resource declared in this template lives in EVERY workspace's
#   Terraform state. Deleting a workspace runs `terraform destroy`, which would
#   destroy the volume too — taking the owner's shared auth/config with it. The
#   previous design guarded that with `prevent_destroy = true`, but that made the
#   volume undeletable, so `coder delete <workspace>` failed outright:
#     "Resource ... has lifecycle.prevent_destroy set, but the plan calls for
#      this resource to be destroyed."
#   You cannot have a per-workspace-managed resource that outlives the workspace
#   that manages it. An unmanaged, named Docker volume is the correct model:
#   Docker creates it on demand and never auto-removes it, so it persists across
#   workspace stop/start AND workspace deletion with no lifecycle gymnastics.
#
# Trade-off: the volume carries no Terraform-set labels. Discover the per-owner
# volumes by name pattern instead (see README "Manual cleanup"):
#   docker volume ls --format '{{.Name}}' | grep -- '-claude$'

# ── Workspace image (built in-template) ───────────────────────────────────────
#
# Builds templates/coderscaffold/Dockerfile (base image + Node.js) using the host
# Docker daemon via the provisioner. build.context = path.module — the pushed
# template directory is the provisioner's working dir, so the Dockerfile and
# build context resolve there.
#
# keep_locally = true — prevents the image from being removed when workspaces
# stop. Built once and reused; Docker layer cache makes subsequent builds fast
# even though the tag is keyed per-workspace (the Node layer is identical and
# cached across workspaces).
#
# triggers — force a rebuild when the Dockerfile changes (filesha1), so a base
# bump or Node change is picked up on the next workspace build.

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}-workspace"

  build {
    context    = path.module
    dockerfile = "Dockerfile"
    build_args = {
      BASE_IMAGE = var.workspace_image
    }
  }

  triggers = {
    dockerfile_sha1 = filesha1("${path.module}/Dockerfile")
  }

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
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

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
# Both modules use count = start_count to mirror docker_container.
# Only register the coder_app when the workspace is actually running. (Pitfall 7)
# folder points at the cloned CoderScaffold repo (populated by startup_script).

# Browser VS Code via code-server (TPL-02 / D-05)
module "code-server" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/code-server/coder"
  version      = "1.5.0"
  agent_id     = coder_agent.main.id
  folder       = "/home/coder/CoderScaffold"
  display_name = "VS Code"
  order        = 1
}

# JetBrains Gateway — IntelliJ IDEA only (TPL-03 / D-06)
# jetbrains_ides = ["IU"] restricts to IntelliJ IDEA Ultimate; no other IDEs.
# folder must be a full absolute path — relative paths fail module validation. (Pitfall 4)
# Points at the cloned upstream repo (created by startup_script clone step).
module "jetbrains-gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = "/home/coder/CoderScaffold"
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
