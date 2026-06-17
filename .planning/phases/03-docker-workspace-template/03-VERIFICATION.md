---
phase: 03-docker-workspace-template
verified: 2026-06-17T15:00:00Z
status: human_needed
score: 5/9 must-haves verified (4 require live UAT — classified as human_needed per scope_note)
overrides_applied: 0
re_verification: null
gaps: []
human_verification:
  - test: "Create a workspace from templates/docker/ and confirm agent shows Connected"
    expected: "Workspace provisions a Docker container on the host; the Coder dashboard shows the agent status as Connected; wildcard-subdomain app URLs render the VS Code and IntelliJ IDEA app buttons"
    why_human: "Requires a live Coder server with the template pushed, a provisioner running, and Docker socket access — cannot be confirmed by grep or static analysis"
  - test: "Click the VS Code app button and confirm a functional browser VSCode session opens"
    expected: "code-server loads in the browser, an editor pane appears, a terminal can be opened, and the working directory is /home/coder"
    why_human: "Runtime browser behavior; requires a running workspace container with code-server installed via the module"
  - test: "Use JetBrains Gateway to connect to the workspace via the IntelliJ IDEA button"
    expected: "Gateway client launches on the developer machine, connects to the workspace container, and an IntelliJ IDEA remote session opens"
    why_human: "Requires JetBrains Gateway client installed locally plus a running workspace; cannot be verified programmatically"
  - test: "Stop the workspace, start it again, and confirm files written to /home/coder before the stop are present after the start"
    expected: "A file created under /home/coder before workspace stop is readable after workspace start — the docker_volume persisted across the stop/start lifecycle"
    why_human: "Requires an actual Docker volume stop/start lifecycle against a running Coder server"
  - test: "On a host where the Docker socket GID differs from the default (e.g., not 998), confirm workspace provisioning succeeds after following the README Docker Socket Permissions instructions"
    expected: "After running stat -c '%g' /var/run/docker.sock, uncommenting group_add in compose.yaml with the discovered GID, and restarting the Coder server, workspace provisioning completes without Docker socket permission errors"
    why_human: "Requires a host with a non-default Docker group GID and an actual provisioning attempt to confirm the documented procedure resolves the failure"
---

# Phase 3: Docker Workspace Template Verification Report

**Phase Goal:** A developer can create a Coder workspace from the Docker template and get a working VSCode (code-server) session and JetBrains Gateway connection, with their home directory persisting across stop/start cycles
**Verified:** 2026-06-17T15:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Scope Note

This is an infrastructure phase (Terraform HCL template + operator README docs). Per 03-VALIDATION.md, there is no applicable unit-test framework for HCL templates. Verification is: (a) structural grep gates on `templates/docker/main.tf` and `README.md`, and (b) identification of runtime success criteria that require live UAT. All five ROADMAP success criteria (SC-1..SC-5) have runtime components that cannot be confirmed without provisioning a workspace against a live Coder server.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `templates/docker/main.tf` exists, is ≥ 90 lines, and contains a complete provider/agent/volume/image/container skeleton (TPL-01, TPL-06) | VERIFIED | File is 264 lines; `resource "docker_container" "workspace"` present at line 188; all required blocks confirmed |
| 2 | The workspace container mounts `docker_volume.home_volume` at `/home/coder`, and the volume uses `lifecycle { ignore_changes = all }` with workspace-ID-keyed name (TPL-04) | VERIFIED | Lines 211-214: `container_path = "/home/coder"`, `volume_name = docker_volume.home_volume.name`; line 124-126: `lifecycle { ignore_changes = all }`; line 120: `"coder-${data.coder_workspace.me.id}-home"` — UUID-keyed |
| 3 | The workspace container entrypoint uses `replace()` + `host-gateway` host entry so the agent reaches the Coder server in both local and production deployments (TPL-06) | VERIFIED | Line 197: `replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")`; lines 204-207: `host { host = "host.docker.internal"; ip = "host-gateway" }` |
| 4 | A commented, non-hardcoded Docker-socket-GID `group_add` block with the `stat -c '%g' /var/run/docker.sock` discovery command is present in `main.tf` (TPL-05) | VERIFIED | Lines 173-186: commented block with `stat -c '%g' /var/run/docker.sock` discovery command and commented `group_add = ["998"]` example; no socket mount in active container code |
| 5 | `module "code-server"` and `module "jetbrains-gateway"` are present with exact version pins, correct `agent_id`, and `count = start_count` (TPL-02, TPL-03) | VERIFIED | Lines 240-249: code-server module version `1.5.0`, `display_name = "VS Code"`, `order = 1`, `folder = "/home/coder"`, `count = start_count`; lines 254-264: jetbrains-gateway version `1.2.6`, `jetbrains_ides = ["IU"]`, `default = "IU"`, `order = 2`, `count = start_count`; both wired to `coder_agent.main.id` |
| 6 | `README.md` contains a `## Workspace Template` section with push/metadata workflow, create-a-workspace path, socket-GID resolution, and connectivity docs (TPL-01, TPL-05, TPL-06, TPL-04 operator note) | VERIFIED | Lines 294-392 of README.md; all 7 structural gate checks pass: heading, push command, edit command, `stat -c '%g'` command, `host.docker.internal`, create path, `/home/coder` |
| 7 | A workspace created from templates/docker/ starts, the agent shows Connected, and wildcard app URLs resolve (SC-1) | HUMAN NEEDED | Requires live Coder server + workspace provisioning |
| 8 | code-server opens a functional browser VSCode session (SC-2) | HUMAN NEEDED | Requires running workspace container + browser session |
| 9 | JetBrains Gateway connects to the workspace (SC-3) | HUMAN NEEDED | Requires Gateway client + running workspace |
| 10 | Stopping and starting a workspace preserves /home/coder contents (SC-4) | HUMAN NEEDED | Requires real stop/start lifecycle |
| 11 | Workspace provisioning succeeds on a host with a non-default Docker socket GID (SC-5) | HUMAN NEEDED | Requires a host with differing GID + actual provisioning |

**Score:** 6/11 truths verified structurally; 5 require human/live verification (this is expected for an infrastructure phase per 03-VALIDATION.md)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `templates/docker/main.tf` | Complete Coder Docker workspace template (≥90 lines, providers, agent, volume, image, container, code-server + jetbrains-gateway modules) | VERIFIED | 264 lines; all required resources and modules present |
| `README.md` | `## Workspace Template` section with push/edit, create, socket-GID, connectivity, persistence | VERIFIED | Section at lines 294-392 (98 lines); all structural gate checks pass |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `docker_container.workspace` | `docker_volume.home_volume` | `volumes { container_path = "/home/coder" }` | WIRED | Lines 210-214: `container_path = "/home/coder"`, `volume_name = docker_volume.home_volume.name` |
| `docker_container.workspace` | Coder server (host) | `host.docker.internal` + `host-gateway` + `replace()` entrypoint | WIRED | Line 197 (replace entrypoint), lines 204-207 (host block with `ip = "host-gateway"`) |
| `module "code-server"` | `coder_agent.main` | `agent_id = coder_agent.main.id` | WIRED | Line 244: `agent_id = coder_agent.main.id` |
| `module "jetbrains-gateway"` | `coder_agent.main` | `agent_id = coder_agent.main.id` | WIRED | Line 258: `agent_id = coder_agent.main.id` |
| `README.md ## Workspace Template` | `templates/docker/main.tf` | `coder templates push docker --directory templates/docker/` | WIRED | Line 306 of README.md |
| `README.md Docker Socket Permissions` | `compose.yaml #group_add block` | `stat -c '%g' /var/run/docker.sock` + uncomment `group_add` | WIRED | Lines 342-359 of README.md |

---

### Data-Flow Trace (Level 4)

Not applicable. This phase produces a Terraform HCL template and operator documentation, not application code with state/props rendering dynamic data. No React/Vue/Svelte components involved.

---

### Behavioral Spot-Checks (Step 7b)

No runnable entry points in this phase (Terraform template requires `terraform init` + a live provisioner). Structural gate commands documented in PLAN frontmatter are the applicable check.

**Task 1 Gate (structural grep):** All 7 assertions pass — `kreuzwerker/docker`, `~> 2.18`, `host-gateway`, `ignore_changes = all`, `coder_workspace.me.id` in volume name, no `hashicorp/docker`, no `coder_parameter`.

**Task 2 Gate (structural grep):** All 6 assertions pass — code-server source, version `1.5.0`, jetbrains-gateway source, version `1.2.6`, `jetbrains_ides = ["IU"]`, start_count count = 3 (docker_container + both modules).

**Plan 02 Gate (structural grep):** All 7 assertions pass — `## Workspace Template`, push command, edit command, `stat -c '%g'` command, `host.docker.internal`, create workspace path, `/home/coder`.

---

### Probe Execution

No probes declared or applicable (no `scripts/*/tests/probe-*.sh` for this infrastructure phase).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TPL-01 | 03-01, 03-02 | Docker-based Terraform template provisions workspaces as containers on the host via the Docker socket | SATISFIED | `resource "docker_container" "workspace"` in main.tf; push workflow in README |
| TPL-02 | 03-01 | Template exposes code-server (browser VSCode) as a workspace app via `coder/code-server` module | SATISFIED (structure) | `module "code-server"` version `1.5.0` present and wired to agent; runtime behavior needs UAT |
| TPL-03 | 03-01 | Template supports JetBrains Gateway (IntelliJ) connectivity via `coder/jetbrains-gateway` module | SATISFIED (structure) | `module "jetbrains-gateway"` version `1.2.6` present, `jetbrains_ides = ["IU"]`; runtime behavior needs UAT |
| TPL-04 | 03-01, 03-02 | Workspace /home is a persistent volume that survives stop/start | SATISFIED (structure) | `docker_volume.home_volume` with `lifecycle { ignore_changes = all }`, UUID-keyed name, mounted at `/home/coder`; stop/start behavior needs UAT |
| TPL-05 | 03-01, 03-02 | Template handles Docker socket access (documented `group_add` / GID) so workspace provisioning works | SATISFIED | Commented `group_add` block + `stat -c '%g'` in main.tf (lines 173-186); full operator procedure in README (lines 335-363) |
| TPL-06 | 03-01, 03-02 | Workspace agent reaches the Coder server access URL reliably | SATISFIED (structure) | `replace()` entrypoint + `host-gateway` host block in main.tf; local vs production connectivity docs in README; agent connectivity needs UAT |

**Orphaned requirements (mapped to Phase 3 in REQUIREMENTS.md but missing from any plan):** None. All 6 requirement IDs (TPL-01..06) are covered by 03-01-PLAN.md (TPL-01..06) and 03-02-PLAN.md (TPL-01, TPL-05, TPL-06).

**Note on REQUIREMENTS.md traceability table:** TPL-02, TPL-03, TPL-04 are marked "Pending" in the traceability table at the bottom of REQUIREMENTS.md. This is a staleness issue in the requirements file — the implementations exist in the committed code (03-01 commit `f5cc44b`). The table entries at the top of the file correctly show `[x]` for all six TPL requirements.

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None found | — | — | — |

No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, or `PLACEHOLDER` markers found in `templates/docker/main.tf` or the `## Workspace Template` section of `README.md`. No empty return stubs, no hardcoded empty data structures. No banned providers (`hashicorp/docker` absent). No `coder_parameter` blocks. No `/var/run/docker.sock` volume mount inside `docker_container.workspace` — only benign references in the variable description and provider host setting, and one commented reference in the GID block.

---

### Human Verification Required

All five items below correspond directly to ROADMAP.md success criteria SC-1..SC-5 and are classified as manual-only in 03-VALIDATION.md. The `<human-check>` from 03-02-PLAN.md Task 1 is merged here (single sink per workflow).

#### 1. Agent Connected and app URLs resolve (SC-1)

**Test:** Push `templates/docker/` via `coder templates push docker --directory templates/docker/ -y` and the `coder templates edit` metadata command from the README. Create a workspace from the Coder dashboard (Templates → Docker Workspace → Create Workspace → Create).
**Expected:** The workspace provisions a Docker container on the host. The Coder dashboard shows the workspace agent status as "Connected". The VS Code and IntelliJ IDEA app buttons appear and their URLs resolve under the wildcard subdomain.
**Why human:** Requires a live Coder server with provisioner running and Docker socket access. Cannot be confirmed by grep or static analysis.

#### 2. Functional browser VSCode session (SC-2)

**Test:** With a running workspace, click the "VS Code" app button.
**Expected:** code-server loads in the browser showing an editor interface. A terminal can be opened. The working directory is `/home/coder`. Normal editing operations work.
**Why human:** Requires a running workspace container with code-server installed by the module, and a browser session.

#### 3. JetBrains Gateway connection (SC-3)

**Test:** With a running workspace, click the "IntelliJ IDEA" app button and follow the Gateway connection flow.
**Expected:** JetBrains Gateway client on the developer's local machine receives the connection URL, establishes an SSH connection to the workspace container, and an IntelliJ IDEA remote IDE session opens.
**Why human:** Requires JetBrains Gateway client installed locally and a running workspace container.

#### 4. Home directory persists across stop/start (SC-4)

**Test:** In a running workspace, create a file under `/home/coder` (e.g., `touch /home/coder/verify-persist.txt`). Stop the workspace. Start the workspace again.
**Expected:** After the workspace starts again, `verify-persist.txt` is present under `/home/coder`. The file was stored in the `docker_volume.home_volume` Docker volume and survived the container lifecycle.
**Why human:** Requires a real stop/start lifecycle against a running Coder server and a real Docker volume.

#### 5. Socket GID resolution works (SC-5)

**Test:** On a host where `stat -c '%g' /var/run/docker.sock` returns a value other than the container default, follow the README's "Docker Socket Permissions" section: discover the GID, uncomment `group_add` in `compose.yaml` with the discovered value, restart the Coder server.
**Expected:** Workspace provisioning completes without Docker socket permission errors. `docker compose logs coder` shows no `permission denied` on socket operations.
**Why human:** Requires a host with a non-default Docker group GID and an actual provisioning attempt.

---

### Gaps Summary

No structural gaps found. All artifacts exist, are substantive (not stubs), and all key links are correctly wired. The five human verification items are runtime success criteria inherent to an infrastructure phase — they are not gaps in the implementation, but rather behaviors that require a live environment to confirm. This is the expected verification state for a Terraform template phase, as documented in 03-VALIDATION.md.

---

_Verified: 2026-06-17T15:00:00Z_
_Verifier: Claude (gsd-verifier)_
