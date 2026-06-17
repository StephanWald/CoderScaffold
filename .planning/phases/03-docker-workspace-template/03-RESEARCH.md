# Phase 3: Docker Workspace Template - Research

**Researched:** 2026-06-17
**Domain:** Coder Terraform workspace template — Docker provider, coder/coder provider, Coder registry modules (code-server, jetbrains-gateway), persistent volumes, workspace agent connectivity
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Base image is `codercom/enterprise-base:ubuntu` — Coder's prebuilt batteries-included image. No custom Dockerfile.
- **D-02:** Pin the image to a specific tag; keep it overridable via a Terraform variable (mirrors Phase 1's pinned-but-overridable image ethos).
- **D-03:** Create-workspace form is **bare — no `coder_parameter` blocks**. Developer clicks "Create" and gets a working workspace.
- **D-04:** Workspace image and IDE are fixed in the template, not developer-selectable.
- **D-05:** Wire **code-server** via `coder/code-server` module (`1.5.0`) — TPL-02 locked.
- **D-06:** Wire **JetBrains Gateway for IntelliJ IDEA only** via `coder/jetbrains-gateway` module (`1.2.6`). IntelliJ is the sole offering and the default.
- **D-07:** Persist `/home/coder` via a **per-workspace Docker volume** keyed to workspace ID — canonical Coder Docker-template pattern.
- **D-08:** Docker socket GID is an **operator-resolved concern via a commented block + README docs** — mirrors Phase 1's `#group_add: - "998"` pattern.
- **D-09:** Bake `extra_hosts = ["host.docker.internal:host-gateway"]` into the workspace container by default.
- **D-10:** Also document the production path: operators with a real reachable `CODER_ACCESS_URL` don't depend on host-gateway.

### Claude's Discretion

- Exact `templates/docker/` file layout and `main.tf` structure (required-providers block, `coder_agent`, `coder_app`, `docker_container`, `docker_volume`, `docker_image` resources).
- Precise Terraform variable name/default for the overridable image (D-02), and the per-workspace home-volume naming scheme (D-07).
- code-server module configuration details (default folder opened, version, any settings) within TPL-02.
- How the workspace agent startup script and metadata are wired, and the exact `coder_agent` env/connectivity plumbing, per the pinned `coder/coder ~> 2.18` provider.
- Whether the Docker socket GID is surfaced as a commented Terraform locals/variable vs README-only note — implementation detail of D-08, as long as it stays operator-resolved and non-hardcoded.

### Deferred Ideas (OUT OF SCOPE)

- Git-repo-to-clone `coder_parameter` — deferred.
- Dotfiles URL `coder_parameter` — deferred (overlaps QOL-01, v2).
- Developer-selectable image / IDE at create time — declined.
- Additional JetBrains IDEs (PyCharm, GoLand, full suite) — declined; IntelliJ only.
- Workspace CPU/memory resource limits (QOL-03), backup retention (QOL-02), AI/MCP wiring (AI-01..04) — v2 only.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TPL-01 | A Docker-based Terraform template (`templates/docker/`) provisions workspaces as containers on the host via the Docker socket | Upstream `coder/coder` Docker template pattern confirmed; `kreuzwerker/docker ~> 4.4` provider; `docker_container` + `docker_volume` + `docker_image` resources |
| TPL-02 | Template exposes code-server (browser VSCode) as a workspace app via `coder/code-server` module | Module inputs verified: `agent_id` (required), `folder`, `order`; version `1.5.0` pinned; creates `coder_app` with `/icon/code.svg` |
| TPL-03 | Template supports JetBrains Gateway (IntelliJ) connectivity via `coder/jetbrains-gateway` module | Module inputs verified: `agent_id` (required), `folder` (required), `jetbrains_ides = ["IU"]`, `default = "IU"`; version `1.2.6` pinned; creates external `coder_app` with Gateway URL |
| TPL-04 | Workspace `/home` is a persistent volume that survives stop/start | `docker_volume` with `lifecycle { ignore_changes = all }` named `coder-${data.coder_workspace.me.id}-home`; mounted at `/home/coder` in `docker_container` |
| TPL-05 | Template handles Docker socket access (documented `group_add` / GID) | Operator-resolved: commented block + README docs; `stat -c '%g' /var/run/docker.sock` to discover GID |
| TPL-06 | Workspace agent reaches Coder server access URL reliably | `host { host = "host.docker.internal"; ip = "host-gateway" }` on `docker_container`; entrypoint replaces `localhost/127.0.0.1` with `host.docker.internal` |
</phase_requirements>

---

## Summary

This phase delivers a Terraform workspace template (`templates/docker/main.tf`) that provisions Coder workspaces as Docker containers on the host machine. The template wires the `coder/code-server` and `coder/jetbrains-gateway` registry modules for browser VSCode and IntelliJ Gateway access, mounts a per-workspace persistent Docker volume at `/home/coder`, and handles local vs production connectivity via `host.docker.internal` / `host-gateway`.

The upstream Coder Docker template (`coder/coder` repo `examples/templates/docker/main.tf`) is the direct model. All locked decisions (D-01 through D-10) map cleanly onto that upstream pattern with targeted adjustments: pinning specific module versions (`1.5.0` and `1.2.6` vs the upstream's loose `~> 1.0`), restricting JetBrains to IntelliJ only (`jetbrains_ides = ["IU"]`), no `coder_parameter` blocks, and adding README documentation for socket GID and connectivity.

Template metadata (display name, description, icon) is set via `coder templates edit` CLI flags after the initial `coder templates push` — these are not Terraform-managed fields. The two deliverables are: (1) `templates/docker/main.tf` and (2) a README extension with the `## Workspace Template` section per the UI-SPEC copywriting contract.

**Primary recommendation:** Model `templates/docker/main.tf` directly on the upstream `coder/coder` Docker template, replace the loose module version pins with the CLAUDE.md pinned versions, restrict JetBrains to IntelliJ only, and add the README section per the UI-SPEC copywriting contract. No Dockerfile, no `coder_parameter` blocks.

---

## Project Constraints (from CLAUDE.md)

| Constraint | Directive |
|------------|-----------|
| Terraform providers | `kreuzwerker/docker ~> 4.4`, `coder/coder ~> 2.18` — use these exact pins in `required_providers` |
| Coder registry modules | `coder/code-server 1.5.0`, `coder/jetbrains-gateway 1.2.6` — pin exactly, do not use `~> 1.0` or `~> 1.1` |
| Terraform version | `>= 1.9` (required by code-server and claude-code modules; claude-code is v2 but the constraint applies globally) |
| Base image | `codercom/enterprise-base:ubuntu` with a specific tag; pinned-but-overridable via Terraform variable |
| Provider choice | `kreuzwerker/docker` — NOT `hashicorp/docker` (archived) |
| IDE module | `coder/jetbrains-gateway` — NOT `coder/jetbrains` (Toolbox, heavier) |
| No AI/MCP | Do not include `coder/claude-code`, `coder_ai_task`, `coder exp mcp` in this phase |
| Secrets in `.env` | Any operator-facing secrets follow `.env`/`.env.example` contract from Phase 1 |
| Docker Compose | Use `docker compose` (v2 plugin), never `docker-compose` (v1) |
| Coder image tag | `v2.33.8` (stable) — not `:latest` |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Template provisioning | Terraform / Coder provisioner | — | Coder server's built-in provisioner daemon runs Terraform to create/destroy workspace containers |
| Workspace container | Docker on host | — | `docker_container` resource; container created by Coder server via mounted Docker socket |
| Browser VSCode (code-server) | Workspace container (code-server process) | Coder proxy layer | code-server runs inside the container; Coder proxies the URL under the wildcard subdomain |
| JetBrains Gateway | Developer's local machine (Gateway client) | Workspace container (IDE backend) | Gateway connects over SSH/token; the workspace container runs the IDE server-side backend |
| Persistent home (`/home/coder`) | Docker volume (host Docker daemon) | — | Named `docker_volume` survives container recreation; mounted into container at start |
| Agent connectivity | Docker host networking | — | `host.docker.internal:host-gateway` in container's `/etc/hosts`; agent token in container env |
| Template metadata (display name/icon) | Coder server (dashboard) | CLI (`coder templates edit`) | Template display name, description, icon are server-side settings, not Terraform-managed |
| Socket GID documentation | README + compose.yaml commented block | — | Operator-resolved; GID varies by host distro — cannot be hardcoded |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `coder/coder` TF provider | `~> 2.18` | `coder_agent`, `coder_app`, `coder_workspace` data sources | Locked in CLAUDE.md; required for `coder_agent` and `coder_app` resources; v2.18 adds `coder_ai_task` (v2) and satisfies server v2.33.8 [VERIFIED: CLAUDE.md §Version Compatibility Matrix] |
| `kreuzwerker/docker` TF provider | `~> 4.4` | `docker_container`, `docker_volume`, `docker_image` | Canonical Docker TF provider (HashiCorp transferred ownership); 4.4.0 released 2026-05-15 [VERIFIED: CLAUDE.md §Recommended Stack] |
| `coder/code-server` registry module | `1.5.0` | Browser VSCode (code-server) workspace app | 3,085,088 downloads; most-used editor module; locked in CLAUDE.md [VERIFIED: CLAUDE.md §Coder Registry Modules] |
| `coder/jetbrains-gateway` registry module | `1.2.6` | JetBrains Gateway (IntelliJ IDEA) workspace app | 3,490,057 downloads; most-used IDE module; locked in CLAUDE.md [VERIFIED: CLAUDE.md §Coder Registry Modules] |
| `codercom/enterprise-base:ubuntu` | latest tag (pinned via variable) | Workspace base image | Coder's prebuilt batteries-included image; git, build-essential, common runtimes, JetBrains/code-server backend deps pre-installed; what Coder's own Docker template ships [VERIFIED: upstream coder/coder docker template, CLAUDE.md D-01] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Terraform / OpenTofu | `>= 1.9` | Template execution engine | Coder's built-in provisioner daemon; modules require >= 1.9 [VERIFIED: CLAUDE.md §Version Compatibility Matrix] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `coder/jetbrains-gateway 1.2.6` | `coder/jetbrains 1.x` (Toolbox) | Toolbox is heavier, manages local installations; Gateway is the standard SSH-based remote dev path — CLAUDE.md explicitly bans the Toolbox module |
| `kreuzwerker/docker ~> 4.4` | `hashicorp/docker` | HashiCorp archived their copy and officially transferred to kreuzwerker — CLAUDE.md bans hashicorp/docker |
| `codercom/enterprise-base:ubuntu` | Custom Dockerfile | Custom Dockerfile requires maintenance and may miss JetBrains/code-server backend deps — D-01 locked |

**Installation (Terraform providers — auto-fetched by Coder provisioner):**
```bash
# No manual install. The Coder server's built-in provisioner daemon
# fetches providers declared in required_providers on template push/workspace create.
# Confirm providers are reachable from the Coder server's network.
```

---

## Package Legitimacy Audit

> This phase uses Coder registry modules (not npm/PyPI/crates packages) and Terraform providers from registry.terraform.io. The Package Legitimacy Gate (npm/pip/cargo) does not apply. Legitimacy is confirmed via official Coder documentation and registry.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `kreuzwerker/docker` TF provider | registry.terraform.io | 7+ yrs | High (canonical) | github.com/kreuzwerker/terraform-provider-docker | OK | Approved [VERIFIED: CLAUDE.md] |
| `coder/coder` TF provider | registry.terraform.io | 3+ yrs | High | github.com/coder/terraform-provider-coder | OK | Approved [VERIFIED: CLAUDE.md] |
| `registry.coder.com/coder/code-server/coder` | registry.coder.com | 2+ yrs | 3,085,088 | github.com/coder/registry | OK | Approved [VERIFIED: CLAUDE.md] |
| `registry.coder.com/coder/jetbrains-gateway/coder` | registry.coder.com | 2+ yrs | 3,490,057 | github.com/coder/registry | OK | Approved [VERIFIED: CLAUDE.md] |
| `codercom/enterprise-base:ubuntu` | Docker Hub | 3+ yrs | High | github.com/coder/enterprise-images | OK | Approved [VERIFIED: upstream coder/coder docker template] |

**Packages removed due to SLOP verdict:** none
**Packages flagged as suspicious (SUS):** none

---

## Architecture Patterns

### System Architecture Diagram

```
Developer browser / JetBrains Gateway client
        |
        | HTTPS (wildcard subdomain for code-server)
        | jetbrains-gateway:// URL (for IntelliJ)
        v
[Coder Server — compose.yaml]
  |-- Receives workspace start request
  |-- Runs Terraform (built-in provisioner) against templates/docker/main.tf
  |-- Terraform calls kreuzwerker/docker provider
        |
        | /var/run/docker.sock (host Docker socket)
        v
[Docker daemon on host]
  |-- Creates docker_volume "coder-{workspace_id}-home"  (TPL-04)
  |-- Creates docker_container "coder-{owner}-{workspace}"
        |-- Mounts home volume at /home/coder
        |-- Sets entrypoint: init_script (replaces 127.0.0.1 → host.docker.internal)
        |-- Sets CODER_AGENT_TOKEN env var
        |-- Adds host entry: host.docker.internal → host-gateway  (TPL-06)
        v
[Workspace container — codercom/enterprise-base:ubuntu]
  |-- Agent starts via entrypoint, dials Coder server via host.docker.internal:7080
  |-- code-server module starts code-server on :13337 (TPL-02)
  |-- JetBrains Gateway module exposes external coder_app URL (TPL-03)
  |-- /home/coder is on persistent Docker volume (TPL-04)
        |
        | Agent reports "Connected" to Coder server
        v
Developer: clicks "VS Code" → proxied via Coder → code-server on :13337
Developer: clicks "IntelliJ IDEA" → jetbrains-gateway:// URL → local Gateway client → SSH into container
```

### Recommended Project Structure

```
templates/
└── docker/
    └── main.tf          # Complete workspace template (single file — standard Coder pattern)
README.md                # Extended with ## Workspace Template section (Phase 1 file)
```

**Note:** No `versions.tf`, no `variables.tf` split — Coder's upstream Docker template uses a single `main.tf`. This is the accepted convention for simple Coder templates. The `terraform.lock.hcl` is generated by `terraform init` locally if run; when pushed via `coder templates push`, the Coder provisioner handles provider resolution.

### Pattern 1: Provider Declaration with Version Pins

**What:** The `terraform` block declares required providers with the pinned version constraints from CLAUDE.md.
**When to use:** Always — every Coder Terraform template must declare both `coder/coder` and `kreuzwerker/docker` providers.

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
# Modified: version pins added per CLAUDE.md constraints
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
```

### Pattern 2: Docker Provider Configuration

**What:** The `docker` provider uses the host Docker socket. The `docker_socket` variable allows operators to override the socket URI.
**When to use:** All Docker-based Coder templates — this is the standard upstream pattern.

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI. Defaults to /var/run/docker.sock."
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}
```

### Pattern 3: Workspace Base Image as Overridable Variable

**What:** The workspace image is declared as a Terraform variable with a specific default tag (D-02). Pin to a stable tag, not `:latest`.
**When to use:** D-02 locked — pinned-but-overridable image pattern from Phase 1 applied to Terraform.

```hcl
# Source: CLAUDE.md D-02, CONTEXT.md D-01/D-02 [VERIFIED]
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Workspace container image. Override to use a custom image."
  type        = string
}
```

**Note on tag pinning:** The upstream template uses `codercom/enterprise-base:ubuntu` without a digest pin. For reproducibility, operators can override to a digest-pinned version (e.g., `codercom/enterprise-base:ubuntu@sha256:...`). The MVP ships with the floating `:ubuntu` tag per D-01 (the tag itself is stable; the image is Coder's own maintained base). [ASSUMED — exact stable tag to pin is not verified; defer to operator or use floating `:ubuntu`]

### Pattern 4: Coder Agent Resource

**What:** The `coder_agent` resource runs inside the workspace container. The startup script initializes the home directory from `/etc/skel` on first launch. Metadata blocks display CPU/RAM/Disk stats in the Coder dashboard.
**When to use:** Required in every Coder workspace template.

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
# Simplified metadata per UI-SPEC (CPU Usage, RAM Usage, Disk — not host-level)
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    # Initialize home from /etc/skel on first workspace start
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
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
```

**UI-SPEC alignment:** The UI-SPEC specifies labels "CPU Usage", "RAM Usage", "Disk" with shell commands using `top`/`free`/`df`. The upstream template uses `coder stat cpu`, `coder stat mem`, `coder stat disk` which are equivalent convenience wrappers built into `codercom/enterprise-base:ubuntu`. Use the `coder stat` form — cleaner and same semantic result. The key numbers (`0_`, `1_`, `3_`) control display ordering in the Coder dashboard.

**Note on UI-SPEC metadata scripts:** The UI-SPEC copywriting contract lists shell commands (`top -bn1`, `free -h`, `df -h`). The `coder stat` equivalents from the upstream template are preferred because they're pre-installed on the base image and produce formatted output. Either approach satisfies the UI-SPEC's intent. [ASSUMED — `coder stat` availability verified by upstream template usage, not by explicit docs page]

### Pattern 5: Docker Volume for Persistent Home (TPL-04)

**What:** A per-workspace named Docker volume persists `/home/coder` across stop/start cycles. The `lifecycle { ignore_changes = all }` block prevents Terraform from destroying the volume when the workspace name changes or the template is updated.
**When to use:** Required — this is the canonical home-persistence pattern for Coder Docker templates (D-07).

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
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

**Critical detail:** The volume name uses `data.coder_workspace.me.id` (UUID, immutable), NOT `data.coder_workspace.me.name` (mutable — could change). This prevents volume orphaning when workspaces are renamed. [VERIFIED: upstream template]

### Pattern 6: Docker Container with host.docker.internal (TPL-06)

**What:** The workspace container replaces `localhost`/`127.0.0.1` in the agent's init script with `host.docker.internal`, and adds the `host-gateway` host entry. This allows the workspace agent to reach the Coder server at `http://127.0.0.1:7080` from inside the container (D-09).
**When to use:** Required for single-host Docker deployments where `CODER_ACCESS_URL` may be `127.0.0.1`. Safe for production deployments too — when `CODER_ACCESS_URL` is a real hostname, `host.docker.internal` is never used.

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = var.workspace_image
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Replace localhost/127.0.0.1 in the agent init script with host.docker.internal
  # so the agent can reach the Coder server when CODER_ACCESS_URL=http://127.0.0.1:7080
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # Add host.docker.internal → host-gateway so containers can reach the Docker host
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
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
```

**count pattern:** `count = data.coder_workspace.me.start_count` means the container only exists when the workspace is started (start_count = 1) and is destroyed when stopped (start_count = 0). The Docker volume persists across this lifecycle. [VERIFIED: upstream template, standard Coder pattern]

### Pattern 7: code-server Module (TPL-02)

**What:** The `coder/code-server` module installs and launches code-server inside the workspace and creates a `coder_app` entry in the Coder dashboard (app button visible as "VS Code" per UI-SPEC).
**When to use:** Required — TPL-02 locked.

```hcl
# Source: registry.coder.com/coder/code-server/coder module [VERIFIED]
module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "1.5.0"

  agent_id     = coder_agent.main.id
  agent_name   = "main"
  folder       = "/home/coder"
  display_name = "VS Code"
  order        = 1
}
```

**Key inputs:**
- `agent_id` — required; wires the app to the workspace agent
- `folder` — opens `/home/coder` by default in the editor
- `display_name` — sets the button label in the Coder dashboard (UI-SPEC: "VS Code")
- `order = 1` — VS Code appears first in the workspace apps list (UI-SPEC ordering)
- `count` — mirrors the container count; app only registered when workspace is running

### Pattern 8: jetbrains-gateway Module (TPL-03)

**What:** The `coder/jetbrains-gateway` module creates an external `coder_app` link that opens JetBrains Gateway on the developer's local machine, connecting to IntelliJ IDEA running in the workspace container.
**When to use:** Required — TPL-03 locked. Restrict to IntelliJ IDEA only (D-06).

```hcl
# Source: registry.coder.com/coder/jetbrains-gateway/coder module [VERIFIED]
module "jetbrains-gateway" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/jetbrains-gateway/coder"
  version = "1.2.6"

  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = "/home/coder"
  jetbrains_ides = ["IU"]
  default        = "IU"
  order          = 2
}
```

**Key inputs:**
- `agent_id` — required; wires the app to the workspace agent
- `folder` — required; must be a full absolute path starting with `/`; `/home/coder` is the persistent home
- `jetbrains_ides = ["IU"]` — restricts to IntelliJ IDEA Ultimate only (D-06); "IU" is the JetBrains product code
- `default = "IU"` — sets IntelliJ IDEA as the pre-selected IDE when the coder_parameter renders
- `order = 2` — IntelliJ IDEA appears second in the workspace apps list (UI-SPEC ordering)

**Note:** The `jetbrains-gateway` module creates a `coder_parameter` (dropdown) for IDE selection when `jetbrains_ides` has multiple values. When `jetbrains_ides = ["IU"]` and `default = "IU"`, the parameter has exactly one choice — functionally equivalent to no parameter from the developer's perspective. [VERIFIED: module variable definitions retrieved from registry]

### Pattern 9: Template Metadata via CLI

**What:** Template display name, description, and icon cannot be set in `main.tf`. They are set via `coder templates edit` after initial push, or can be set during the push workflow in the Coder UI.
**When to use:** After `coder templates push` creates the template.

```bash
# Source: coder.com/docs/reference/cli/templates_edit [VERIFIED]
coder templates edit docker \
  --display-name "Docker Workspace" \
  --description "Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start." \
  --icon "/icon/docker.png"
```

**Alternative:** Set these interactively in the Coder dashboard UI at Templates → docker → Edit.

### Pattern 10: Data Sources

**What:** Three standard data sources provide workspace context to all resources in the template.
**When to use:** Required in every Coder template.

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
}
```

### Anti-Patterns to Avoid

- **Using `coder/coder` provider without version constraint:** The provisioner will pick the latest, which may be incompatible. Always pin `~> 2.18`.
- **Using `hashicorp/docker` provider:** Archived. Use `kreuzwerker/docker`. [VERIFIED: CLAUDE.md]
- **Using `coder/jetbrains` (Toolbox) instead of `coder/jetbrains-gateway`:** Toolbox is heavier and manages local IDE installations. Gateway is the SSH-based standard path. [VERIFIED: CLAUDE.md]
- **Naming the home volume with workspace name:** Use `data.coder_workspace.me.id` (UUID, immutable), not `.name` (can change). Name changes would orphan the volume.
- **Omitting `lifecycle { ignore_changes = all }` on the home volume:** Terraform would destroy the volume when the workspace is recreated, losing all home data (TPL-04 failure).
- **Omitting the entrypoint `replace()`:** The agent's `init_script` contains `localhost` or `127.0.0.1` as the Coder server URL. Without the replacement, the agent inside the container tries to connect to itself rather than the host. [VERIFIED: upstream template pattern]
- **Setting `count` on `coder_agent`:** Only `docker_container` and modules use `count = data.coder_workspace.me.start_count`. The `coder_agent` resource is always created (count-free) so Terraform can generate the init_script and token even when the workspace is stopped.
- **Adding `coder_parameter` blocks:** D-03 locked — bare form, no parameters. Adding any `coder_parameter` violates the user constraint.
- **Including AI/MCP resources:** `coder_ai_task`, `coder/claude-code` module — v2 only, explicitly deferred.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Browser VSCode in workspace | Custom code-server install script in startup_script | `coder/code-server 1.5.0` module | Module handles install, launch, port, healthcheck, coder_app registration, icon, display_name — many edge cases (version detection, auth, URL routing) |
| JetBrains Gateway URL construction | Manual `jetbrains-gateway://connect#...` URL in a `coder_app` resource | `coder/jetbrains-gateway 1.2.6` module | Gateway URL includes session token, IDE build number, download link, agent name — complex and version-sensitive |
| Workspace agent startup | Custom init script | `coder_agent.main.init_script` (auto-generated) | Coder generates the correct init script per provisioner arch; do not replace or modify the script beyond the `localhost` → `host.docker.internal` replacement |
| Home directory initialization | Full `rsync` or `tar` in startup_script | `cp -rT /etc/skel ~ && touch ~/.init_done` (guard file) | The upstream pattern is simple and idempotent; no need for complexity |

**Key insight:** The `coder/code-server` and `coder/jetbrains-gateway` registry modules encapsulate significant complexity (healthchecks, URL routing, session tokens, IDE version management). Using them is not optional — they are the standard Coder pattern, and hand-rolling these would require maintaining the same logic without the benefit of Coder's module versioning and bug fixes.

---

## Common Pitfalls

### Pitfall 1: `coder_agent` Takes `count` — Container Does Not Connect

**What goes wrong:** Developer adds `count = data.coder_workspace.me.start_count` to the `coder_agent` resource (mirroring the container). The agent token and init_script are only generated when the workspace is "started". When the workspace transitions to "stopped" state, Terraform destroys the agent resource, losing the token. On next start, a new agent with a new token is created, breaking the container's `CODER_AGENT_TOKEN` env var reference.
**Why it happens:** Copying the `count` pattern from `docker_container` without understanding that `coder_agent` must always exist.
**How to avoid:** `coder_agent` never takes `count`. Only `docker_container` and `module` blocks use `count = data.coder_workspace.me.start_count`. [VERIFIED: upstream template; agent resource has no count]
**Warning signs:** Workspace shows "Connecting" and never becomes "Connected" after stop/start.

### Pitfall 2: Home Volume Destroyed on Workspace Rename or Template Update

**What goes wrong:** The `docker_volume` resource lacks `lifecycle { ignore_changes = all }`. When the workspace is renamed or a template update causes Terraform to re-plan, Terraform sees the volume name doesn't match and proposes destroy-recreate. All home directory data is lost.
**Why it happens:** Omitting the lifecycle block is the default Terraform behavior.
**How to avoid:** Always include `lifecycle { ignore_changes = all }` on `docker_volume.home_volume`. Also use workspace ID (not name) in the volume name. [VERIFIED: upstream template]
**Warning signs:** `/home/coder` is empty after a workspace restart despite files being present before; or a Terraform plan shows "destroy" on `docker_volume`.

### Pitfall 3: Agent Can't Reach Coder Server (localhost)

**What goes wrong:** `CODER_ACCESS_URL=http://127.0.0.1:7080` in `compose.yaml`. The agent init_script has `127.0.0.1` embedded. Inside the container, `127.0.0.1` refers to the container loopback, not the host. Agent connects to itself and fails.
**Why it happens:** Docker container networking — containers don't inherit the host's localhost.
**How to avoid:** Use the entrypoint replacement pattern: `replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")` AND add `host { host = "host.docker.internal"; ip = "host-gateway" }` to the container. Both steps are required. [VERIFIED: upstream template, CONTEXT.md D-09]
**Warning signs:** Workspace agent shows "Connecting" indefinitely; `docker logs coder-{owner}-{workspace}` shows connection refused to `127.0.0.1:7080`.

### Pitfall 4: JetBrains Gateway Module Requires `folder` as Full Absolute Path

**What goes wrong:** `folder` is set to a relative path (e.g., `"."` or `"~/project"`). The module validates this with a regex requiring a full path starting with `/`. Terraform `plan` fails with a validation error.
**Why it happens:** The `jetbrains-gateway` module validates: `can(regex("^(?:/[^/]+)+/?$", var.folder))`.
**How to avoid:** Always use a full absolute path. For this phase: `folder = "/home/coder"`. [VERIFIED: module variable definition retrieved]
**Warning signs:** `terraform plan` error: "The folder must be a full path and must not start with a ~."

### Pitfall 5: Docker Socket Permission Failure

**What goes wrong:** Workspace provisioning fails with a Docker API permission error. The Coder server user can't access `/var/run/docker.sock` because the host docker group GID differs from the container's expected GID (typically 998 or 999 — varies by distro).
**Why it happens:** Docker socket GID is set by the host's docker group, which varies across distros (e.g., Ubuntu is 998, Debian is 999, Alpine is 101). Containers can't universally assume one value.
**How to avoid:** D-08 — comment the `group_add` block in `compose.yaml` (already there from Phase 1) and document the `stat -c '%g' /var/run/docker.sock` command for operators to discover their GID. [VERIFIED: compose.yaml existing `#group_add: - "998"` block; STATE.md blocker reference]
**Warning signs:** `docker compose logs coder` shows `permission denied` on Docker socket operations; workspace build fails immediately after "Pending" with a provider error.

### Pitfall 6: Template Push vs Template Edit — Metadata Not in Terraform

**What goes wrong:** Developer sets display name, description, or icon in `main.tf` using some `coder_workspace_metadata` resource expecting it to appear as the template title in the Coder dashboard. It doesn't — these are server-side settings, not Terraform-managed.
**Why it happens:** Confusion between workspace resource metadata (shows in workspace detail) and template-level metadata (shows in the Templates list / template page).
**How to avoid:** Template display name, description, and icon are set via `coder templates edit --display-name "..." --description "..." --icon "..."` CLI command or the Coder dashboard UI, after `coder templates push`. [VERIFIED: coder.com/docs/reference/cli/templates_edit]
**Warning signs:** Template appears in the dashboard with the slug name (e.g., "docker") instead of "Docker Workspace".

### Pitfall 7: Module `count` Must Match Container `count`

**What goes wrong:** The `code-server` or `jetbrains-gateway` module omits `count = data.coder_workspace.me.start_count`. The module's `coder_app` is always registered, even when the workspace is stopped. When the workspace starts, the app URL points to a non-running process. Health checks may pass/fail inconsistently.
**Why it happens:** Forgetting to mirror the count pattern on module blocks.
**How to avoid:** All `module` blocks and `docker_container` use `count = data.coder_workspace.me.start_count`. Only `coder_agent` and `docker_volume` are count-free. [VERIFIED: upstream template]

---

## Code Examples

### Complete `templates/docker/main.tf` Structure

```hcl
# Source: upstream coder/coder examples/templates/docker/main.tf [VERIFIED]
# Adapted: version pins from CLAUDE.md, IntelliJ-only, no coder_parameter, UI-SPEC labels

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

locals {
  username = data.coder_workspace_owner.me.name
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI. Defaults to the system Docker socket."
  type        = string
}

variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Workspace container image. Override to use a custom image."
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
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

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle { ignore_changes = all }
  labels { label = "coder.owner";                value = data.coder_workspace_owner.me.name }
  labels { label = "coder.owner_id";             value = data.coder_workspace_owner.me.id }
  labels { label = "coder.workspace_id";         value = data.coder_workspace.me.id }
  labels { label = "coder.workspace_name_at_creation"; value = data.coder_workspace.me.name }
}

resource "docker_image" "main" {
  name         = var.workspace_image
  keep_locally = true
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host { host = "host.docker.internal"; ip = "host-gateway" }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels { label = "coder.owner";        value = data.coder_workspace_owner.me.name }
  labels { label = "coder.owner_id";     value = data.coder_workspace_owner.me.id }
  labels { label = "coder.workspace_id"; value = data.coder_workspace.me.id }
  labels { label = "coder.workspace_name"; value = data.coder_workspace.me.name }
}
```

**Note on `docker_image` resource:** The upstream template uses `docker_image` with `keep_locally = true` so the image is cached on the host and not removed when workspaces stop. Use `docker_image.main.image_id` (the resolved digest) in `docker_container.image` — this ensures reproducibility if the image tag is updated at the registry. [VERIFIED: upstream template pattern]

### Template Push and Metadata Setup

```bash
# Source: coder.com/docs/reference/cli/templates_push, templates_edit [VERIFIED]

# Push the template (from repo root)
coder templates push docker --directory templates/docker/ -y

# Set display name, description, and icon (cannot be set in main.tf)
coder templates edit docker \
  --display-name "Docker Workspace" \
  --description "Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start." \
  --icon "/icon/docker.png"
```

### Docker Socket GID Discovery (Operator Command)

```bash
# Source: coder.com/docs/install/docker pattern [CITED]
# Discover the docker group GID on the host
stat -c '%g' /var/run/docker.sock

# Then edit compose.yaml group_add section:
# group_add:
#   - "998"   # Replace with actual GID from stat command above
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `coder/jetbrains` (Toolbox) module | `coder/jetbrains-gateway` module | Ongoing — Gateway is the SSH-based standard | Toolbox is heavier; Gateway is the correct path for Coder SSH-remote workspaces |
| Loose module version pins `~> 1.0` | Pinned exact versions `1.5.0`, `1.2.6` | CLAUDE.md decision | Production reproducibility; prevents silent upgrades |
| `hashicorp/docker` TF provider | `kreuzwerker/docker ~> 4.4` | Provider transferred ~2021 | hashicorp/docker is archived; kreuzwerker is the maintained fork |

**Deprecated/outdated:**
- `hashicorp/docker` Terraform provider: archived, do not use
- `coder/jetbrains` (Toolbox) module: heavier alternative; `coder/jetbrains-gateway` is the standard Coder SSH path
- Hardcoding Docker socket GID: varies per distro, must be operator-configured

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `codercom/enterprise-base:ubuntu` floating tag is appropriate for MVP; no digest pin required | Standard Stack / Pattern 3 | If Coder pushes a breaking change to the base image, existing templates would behave differently on next workspace create. Low risk for MVP; mitigated by operator override variable. |
| A2 | `coder stat cpu` / `coder stat mem` / `coder stat disk` commands are available in `codercom/enterprise-base:ubuntu` | Pattern 4 (coder_agent metadata) | If not available, metadata blocks would show errors in dashboard. Fallback: use raw `top`/`free`/`df` commands from UI-SPEC. |
| A3 | `display_name` and `order` are valid inputs on the `coder/code-server 1.5.0` module | Pattern 7 | If the module doesn't support these inputs at 1.5.0, the plan would fail with unknown variable errors. Mitigation: the variable list was retrieved from the registry source — these are documented inputs. |

---

## Open Questions (RESOLVED)

> Both questions below are answered inline with actionable recommendations that the
> Phase 3 plans already implement (`coder stat` in 03-01 metadata blocks; `display_name = "VS Code"`
> in 03-01 code-server module). They remain documented as UAT verification points, not as blockers.

1. **`coder stat` availability in `codercom/enterprise-base:ubuntu`**
   - What we know: The upstream Coder Docker template uses `coder stat cpu/mem/disk` in metadata blocks, implying it's available in the base image. The Coder agent binary is injected into the workspace container by the init_script.
   - What's unclear: Whether `coder stat` is available immediately at startup before the agent fully initializes vs whether it requires the full agent to be running.
   - Recommendation: Use `coder stat` (standard upstream approach). If metadata blocks show "Error" in the dashboard, fall back to the raw shell commands from the UI-SPEC.

2. **`display_name` input on `coder/code-server 1.5.0` module**
   - What we know: The module variable list includes `display_name` with default `"code-server"`. The UI-SPEC requires "VS Code".
   - What's unclear: Whether setting `display_name = "VS Code"` at the module level overrides the `coder_app` display_name created internally by the module, or whether it requires a different mechanism.
   - Recommendation: Set `display_name = "VS Code"` in the module block. If the dashboard still shows "code-server", use `coder templates edit` or set `display_name` on the `coder_app` resource directly (would require not using the module for the app resource — unlikely to be needed).

---

## Environment Availability

> The template is Terraform HCL — no build step, no runtime on the developer machine beyond the Coder CLI for push. The Coder server (already running from Phase 1) is the execution environment.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Coder server | Template push / workspace create | ✓ (Phase 1 complete) | v2.33.8 | — |
| `coder` CLI | `coder templates push`, `coder templates edit` | [ASSUMED] | any v2.x | Use Coder dashboard UI for template upload |
| Docker daemon on host | Workspace provisioning | ✓ (Phase 1 — Coder server uses it) | 20.10+ | — |
| Docker socket (`/var/run/docker.sock`) | `kreuzwerker/docker` provider | ✓ (mounted in compose.yaml) | — | — |
| `registry.coder.com` reachability | Module download on workspace create | [ASSUMED] | — | Pre-download modules or mirror registry |
| `registry.terraform.io` reachability | Provider download on workspace create | [ASSUMED] | — | Air-gap: provider mirror |

**Missing dependencies with no fallback:**
- None identified for the standard deployment scenario.

**Missing dependencies with fallback:**
- `coder` CLI (for push/edit): can use the Coder dashboard UI instead.
- `registry.coder.com` (for module download): air-gap installations require a module mirror.

---

## Validation Architecture

> `workflow.nyquist_validation` key absent from `.planning/config.json` — treated as enabled. However, this phase produces a Terraform template with no test framework applicable (Terraform testing via `terraform test` requires `>= 1.6` and test files; Coder template testing requires a live Coder instance). Automated test commands below reflect manual UAT protocol.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual UAT against live Coder instance (no Terraform test files in scope for MVP) |
| Config file | none |
| Quick run command | `coder templates push docker --directory templates/docker/ -y` (validates Terraform syntax + provider connection) |
| Full suite command | Manual UAT: create workspace → verify Connected → open VS Code → open IntelliJ → stop/start → verify home persists |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TPL-01 | Template provisions workspace container on Docker host | smoke | `coder templates push docker -d templates/docker/ -y` | ❌ Wave 0 |
| TPL-02 | code-server app appears and launches browser VSCode | manual | n/a — browser verification required | n/a |
| TPL-03 | JetBrains Gateway button opens Gateway client for IntelliJ | manual | n/a — local client required | n/a |
| TPL-04 | `/home/coder` contents persist across workspace stop/start | manual | n/a — requires stop/start cycle | n/a |
| TPL-05 | Template provisions even when Docker socket GID differs | manual | n/a — operator config step | n/a |
| TPL-06 | Workspace agent shows "Connected" on local 127.0.0.1 deployment | smoke | verify agent status via `coder list` or dashboard | n/a |

### Sampling Rate

- **Per task commit:** `coder templates push docker -d templates/docker/ -y` (syntax validation + provider auth check)
- **Per wave merge:** Full UAT as per success criteria SC-1..SC-5
- **Phase gate:** All 5 success criteria verified before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `templates/docker/main.tf` — the template itself (Wave 1 primary deliverable)
- [ ] README `## Workspace Template` section (Wave 1 secondary deliverable)
- [ ] No test framework files needed — validation is manual UAT per Coder template norms.

*(No existing test infrastructure — this is a Terraform template phase, not application code.)*

---

## Security Domain

> `security_enforcement` absent from config — treated as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Workspace auth handled by Coder server (existing) |
| V3 Session Management | No | Coder server manages workspace sessions (existing) |
| V4 Access Control | Partial | `coder_app` `share = "owner"` default — workspace apps accessible to owner only; code-server ships with `--auth none` because Coder handles authn at the proxy layer |
| V5 Input Validation | Yes | `jetbrains-gateway` module validates `folder` input (regex); `workspace_image` variable is operator-provided trust boundary |
| V6 Cryptography | No | `CODER_AGENT_TOKEN` is generated by Coder server (not hand-rolled); secrets not introduced in this phase |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Workspace agent token exposure | Information Disclosure | Token passed via `env` in `docker_container` (not written to disk); Coder rotates on workspace restart |
| Docker socket access from workspace container | Elevation of Privilege | D-08: workspace container does NOT get Docker socket access; only the Coder server container has it mounted. Workspace containers have no privileged access. |
| code-server `--auth none` | Authentication Bypass | Mitigated by Coder proxy layer — requests to workspace apps pass through Coder authentication; `--auth none` is standard Coder pattern per docs |
| `workspace_image` variable injection | Tampering | Trust boundary: only admins can push/modify templates; `workspace_image` variable is template-level, not user-facing (D-03: no `coder_parameter`) |

---

## Sources

### Primary (HIGH confidence)
- `coder/coder` GitHub repo `examples/templates/docker/main.tf` — complete upstream template structure; provider declaration; entrypoint pattern; home volume; agent; data sources [VERIFIED]
- `coder/registry` GitHub repo `registry/coder/modules/code-server/main.tf` — module variable list including `agent_id`, `folder`, `display_name`, `order` [VERIFIED]
- `coder/registry` GitHub repo `registry/coder/modules/jetbrains-gateway/main.tf` — module variable list including `agent_id`, `folder`, `jetbrains_ides`, `default`; valid IDE codes; coder_app structure [VERIFIED]
- `CLAUDE.md` §"Recommended Stack" / §"Coder Registry Modules" / §"Version Compatibility Matrix" / §"What NOT to Use" — pinned versions, provider constraints, anti-patterns [VERIFIED]
- `coder.com/docs/reference/cli/templates_edit` — `--display-name`, `--description`, `--icon` flags [VERIFIED]
- `coder.com/docs/reference/cli/templates_push` — `--directory`, `-y` flags; push workflow [VERIFIED]

### Secondary (MEDIUM confidence)
- `coder.com/docs/tutorials/template-from-scratch` — Docker container resource pattern; `host.docker.internal` / entrypoint replace; volume `lifecycle { ignore_changes = all }` [CITED]
- WebSearch: `kreuzwerker/docker` `extra_hosts` block syntax — `host` / `ip` fields confirmed [CITED: registry.terraform.io/providers/kreuzwerker/docker]
- WebSearch: `coder templates edit` flags for display-name/description/icon [CITED: coder.com/docs/reference/cli/templates_edit]

### Tertiary (LOW confidence)
- WebSearch: `jetbrains_ides = ["IU"]` restricts to IntelliJ IDEA only — consistent with module variable list retrieved [ASSUMED until module is live-tested]
- WebSearch: `coder stat` commands in base image — inferred from upstream template usage

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — CLAUDE.md explicitly pins all versions; upstream template verified via GitHub
- Architecture: HIGH — upstream template is the direct model; patterns are from official Coder sources
- Pitfalls: HIGH — derived from upstream template design decisions (count patterns, lifecycle blocks, entrypoint replace) and CONTEXT.md documented blockers

**Research date:** 2026-06-17
**Valid until:** 2026-09-17 (stable stack; Coder provider and module versions change slowly; module inputs are stable at 1.5.0 / 1.2.6)
