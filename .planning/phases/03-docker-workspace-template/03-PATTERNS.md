# Phase 3: Docker Workspace Template - Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 2 (templates/docker/main.tf, README.md extension)
**Analogs found:** 0 exact / 2 total (no Terraform exists in repo; closest analogs are compose.yaml and backup scripts)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `templates/docker/main.tf` | config (Terraform template) | request-response (workspace lifecycle) | `compose.yaml` | convention-match (both declare infrastructure resources with pinned-but-overridable versions) |
| `README.md` (extension) | docs | n/a | `README.md` (existing sections) | exact (extend same file, same structure) |

---

## Pattern Assignments

### `templates/docker/main.tf` (Terraform workspace template)

**Greenfield file** — no Terraform exists in the repo. Pattern is derived from:
1. The upstream `coder/coder` Docker template (canonical model per RESEARCH.md)
2. `compose.yaml` for project-level conventions (comments, version-pinning style, operator-facing patterns)
3. `scripts/backup.sh` for non-interactive/annotated script conventions

The complete structure is provided in RESEARCH.md §"Code Examples". The sections below highlight the specific patterns to copy from within-repo analogs where applicable.

---

#### Pattern: Pinned-but-overridable image reference

**Analog:** `compose.yaml` lines 5, 42

```yaml
# compose.yaml lines 5 — Coder image: pinned tag, overridable via env vars
image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}

# compose.yaml line 42 — Postgres image: major pinned, not :latest
image: "postgres:17"
```

**Apply as** (Terraform equivalent — D-02):
```hcl
variable "workspace_image" {
  default     = "codercom/enterprise-base:ubuntu"
  description = "Workspace container image. Override to use a custom image."
  type        = string
}

resource "docker_image" "main" {
  name         = var.workspace_image
  keep_locally = true
}
```

The `variable` block with a concrete default mirrors `${VAR:-default}`. `keep_locally = true` ensures the image is not purged when workspaces stop (mirrors the persistent-data intent of the named volume pattern).

---

#### Pattern: Commented operator-resolved block

**Analog:** `compose.yaml` lines 27–28

```yaml
# compose.yaml lines 27–28
#group_add:
#  - "998" # docker group on host
```

**Apply as** (Terraform equivalent — D-08, TPL-05):
```hcl
# templates/docker/main.tf — Docker socket GID (TPL-05 / D-08)
# Uncomment and set the correct GID if workspace provisioning fails with
# a Docker socket permission error. Discover the GID with:
#   stat -c '%g' /var/run/docker.sock
#
# resource "docker_container" "workspace" {
#   ...
#   # group_add = ["998"]  # Replace 998 with the actual docker group GID
# }
```

The comment style — brief explanation of why + operator discovery command — mirrors the Phase 1 compose.yaml pattern.

---

#### Pattern: Comment header and annotation style

**Analog:** `scripts/backup.sh` lines 1–16 (file-level header + inline section banners)

```bash
# scripts/backup.sh lines 1-7
#!/usr/bin/env bash
# scripts/backup.sh — Non-interactive pg_dump -Fc backup to ./backups/
#
# Usage: ./scripts/backup.sh
#
# Reads connection config from .env (...)
# Falls back to compose.yaml defaults (...) if .env is absent.
```

**Apply as** in `main.tf` (HCL comment style):
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

---

#### Pattern: Required providers block with exact pins

**Source:** RESEARCH.md Pattern 1 (derived from upstream coder/coder template + CLAUDE.md)
No in-repo HCL analog exists — this is the complete canonical form.

```hcl
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

---

#### Pattern: Docker provider + optional socket override

**Source:** RESEARCH.md Pattern 2

```hcl
variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI. Defaults to /var/run/docker.sock."
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}
```

---

#### Pattern: Standard data sources

**Source:** RESEARCH.md Pattern 10

```hcl
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
}
```

---

#### Pattern: coder_agent resource (NO count)

**Source:** RESEARCH.md Pattern 4. Critical: `coder_agent` must NOT have `count`.

```hcl
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
```

---

#### Pattern: Persistent home volume (TPL-04)

**Source:** RESEARCH.md Pattern 5. `lifecycle { ignore_changes = all }` and UUID-keyed name are mandatory.

```hcl
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }

  labels { label = "coder.owner";                  value = data.coder_workspace_owner.me.name }
  labels { label = "coder.owner_id";               value = data.coder_workspace_owner.me.id }
  labels { label = "coder.workspace_id";           value = data.coder_workspace.me.id }
  labels { label = "coder.workspace_name_at_creation"; value = data.coder_workspace.me.name }
}
```

---

#### Pattern: docker_container with host.docker.internal (TPL-06)

**Source:** RESEARCH.md Pattern 6. Both the entrypoint replacement AND the host entry are required together.

```hcl
resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels { label = "coder.owner";         value = data.coder_workspace_owner.me.name }
  labels { label = "coder.owner_id";      value = data.coder_workspace_owner.me.id }
  labels { label = "coder.workspace_id";  value = data.coder_workspace.me.id }
  labels { label = "coder.workspace_name"; value = data.coder_workspace.me.name }
}
```

---

#### Pattern: code-server module (TPL-02)

**Source:** RESEARCH.md Pattern 7. `count` must mirror `docker_container`.

```hcl
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
```

---

#### Pattern: jetbrains-gateway module (TPL-03)

**Source:** RESEARCH.md Pattern 8. `folder` must be absolute path. `jetbrains_ides = ["IU"]` restricts to IntelliJ only (D-06).

```hcl
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

---

### `README.md` (docs extension — `## Workspace Template` section)

**Analog:** `README.md` existing sections (lines 1–199+)

**Existing README section pattern** (lines 50–99):
- H2 heading for each major topic
- Prose intro sentence
- Numbered steps for operator actions
- Inline code blocks for commands
- Callout blockquote (`>`) for warnings/caveats
- Failure symptom / diagnostic pattern at section end

**Copy this section structure** for the new `## Workspace Template` section:

```markdown
## Workspace Template

[One-sentence what + where]

### Push the template

```bash
# Push from repo root (requires coder CLI logged in)
coder templates push docker --directory templates/docker/ -y

# Set display name, description, and icon (not Terraform-managed)
coder templates edit docker \
  --display-name "Docker Workspace" \
  --description "Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start." \
  --icon "/icon/docker.png"
```

### Create a workspace

[Dashboard steps + what appears]

### Docker socket permissions (if provisioning fails)

[Mirror the compose.yaml `#group_add` pattern — operator discovery command + edit step]

```bash
stat -c '%g' /var/run/docker.sock
```

> **[callout for GID variation caveat]**

### Connectivity: local vs production

[D-09 / D-10 explanation — when host.docker.internal applies vs real CODER_ACCESS_URL]
```

**Specific patterns to match from README lines 66–99 (Postgres storage section):**
- Failure symptom block: what you see + which log command to run + root cause
- Callout blockquote with `**Linux only.**` → adapt to `**Local deployment note.**`
- Numbered steps for operator actions

---

## Shared Patterns

### Version pinning with overridable default

**Source:** `compose.yaml` lines 5, 42, 47–49
**Apply to:** `templates/docker/main.tf` `variable "workspace_image"` and `variable "docker_socket"`

Pattern: always provide a concrete default (`codercom/enterprise-base:ubuntu`, `""`, `0.0.0.0:7080`). Never use `:latest`. Accompany with a comment explaining when to override.

```yaml
# compose.yaml line 5 — canonical form
image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}
```

```yaml
# compose.yaml line 15
CODER_ACCESS_URL: "${CODER_ACCESS_URL:-http://127.0.0.1:7080}" # CFG-03
```

### Commented-out operator-resolved block

**Source:** `compose.yaml` lines 24–28
**Apply to:** `templates/docker/main.tf` Docker socket GID comment (TPL-05)

```yaml
# compose.yaml lines 24–28
# If the coder user does not have write permissions on
# the docker socket, you can uncomment the following
# lines and set the group ID to one that has write
# permissions on the docker socket.
#group_add:
#  - "998" # docker group on host
```

The pattern: multi-line prose comment explaining the why → commented-out code block → inline note on what value to substitute. Mirror this exactly for the `group_add` equivalent in the Terraform container resource.

### Failure symptom documentation

**Source:** `README.md` lines 90–99
**Apply to:** `README.md` `## Workspace Template` section (Docker socket GID failure, agent connectivity failure)

```markdown
**Failure symptom if you skip the `chown` step:** The `database` service exits immediately. Run
`docker compose logs database` and you will see:

```
chown: changing ownership ...
```
```

Pattern: bold `**Failure symptom ...**` lead → one-sentence description → diagnostic command → what the output looks like.

### Non-interactive exit code convention

**Source:** `scripts/backup.sh` lines 17, 87–91
**Apply to:** README operator commands (must return meaningful exit codes — operator runs `coder templates push` in CI)

```bash
# scripts/backup.sh lines 87-91
if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file is zero bytes: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi
```

`coder templates push ... -y` follows the same convention: exits 0 on success, non-zero on error, `-y` suppresses interactive prompts. Document the `-y` flag explicitly in the README push command.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `templates/docker/main.tf` (HCL structure) | config | request-response | No Terraform exists in this repo. Complete structure derived from upstream `coder/coder` Docker template + RESEARCH.md. Planner should use RESEARCH.md §"Code Examples" as the primary reference for the complete file. |

---

## Count Pattern Rules (critical — no in-repo analog)

These rules have no existing in-repo parallel but are essential to get right:

| Resource | count | Reason |
|----------|-------|--------|
| `coder_agent` | **none** | Must always exist so token + init_script are generated even when workspace is stopped |
| `docker_volume` | **none** | Must always exist to preserve home data across stop/start |
| `docker_image` | **none** | Image resource is lifecycle-independent of workspace state |
| `docker_container` | `data.coder_workspace.me.start_count` | Container only exists when workspace is running |
| `module "code-server"` | `data.coder_workspace.me.start_count` | App only registered when workspace is running |
| `module "jetbrains-gateway"` | `data.coder_workspace.me.start_count` | Same |

---

## Metadata

**Analog search scope:** `/workspaces/coder/` root (compose.yaml, scripts/, README.md)
**Files scanned:** 4 (compose.yaml, scripts/backup.sh, scripts/restore.sh header, README.md)
**No templates/ directory exists** — confirmed greenfield
**Pattern extraction date:** 2026-06-17
