---
phase: quick-260821-ihu
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/bbj-services/Dockerfile
  - templates/bbj-services/main.tf
  - templates/bbj-services/README.md
autonomous: true
requirements:
  - QUICK-260821-ihu
user_setup: []

estimate:
  tokens: 55000
  raw_tokens: 32000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "A workspace created WITHOUT case_insensitive_project=true behaves byte-for-byte identically to today (no capabilities block, no casefold block runs)."
    - "When case_insensitive_project=true, the workspace mounts an ext4 casefold loopback image at the project folder before the git clone, so a repo cloned into it resolves myfile.txt and MYFILE.TXT to the same file."
    - "The casefold image lives at $HOME/.casefold/project.img on the persistent home volume and survives stop/start without data loss or double-mount."
    - "e2fsprogs + util-linux (mkfs.ext4 -O casefold, chattr +F, losetup, mount) are present in the image."
  artifacts:
    - "templates/bbj-services/main.tf — case_insensitive_project + case_insensitive_size_gb coder_parameters, dynamic capabilities block, casefold startup_script block before the clone"
    - "templates/bbj-services/Dockerfile — apt block installing e2fsprogs + util-linux system-wide"
    - "templates/bbj-services/README.md — new section documenting the parameters, rationale, SYS_ADMIN note, persistence, and the live-deploy caveat"
  key_links:
    - "coder_parameter.case_insensitive_project.value → shell `if` guard in startup_script AND dynamic capabilities for_each in docker_container"
    - "casefold block ordering: MUST run before the `Optional project repo clone` block so the clone populates the mount"
    - "image path under /home/coder (persistent, NOT volume-shadowed) → mountpoint guard for idempotent re-mount"
---

<objective>
Add an OPT-IN, per-workspace case-insensitive project filesystem to the bbj-services Coder template. Mechanism (LOCKED): an ext4 `casefold` loopback image file on the persistent home volume, loop-mounted at the project folder before the git clone. Purpose: let developers work on the CarIT project (written for case-insensitive Windows) on Linux without case-collision breakage.

Purpose: CarIT and similar Windows-origin codebases assume case-insensitive path resolution; on a normal Linux ext4 mount `Foo.bbj` and `foo.bbj` are distinct files, which breaks such projects. ext4 casefold (kernel-native, CONFIG_UNICODE, as used by Android/Proton) gives case-insensitive lookup without ciopfs/FUSE or a host bind-mount.

Output: three edited files (Dockerfile, main.tf, README.md). Workspaces that do not opt in are unchanged.

SCOPE GUARD: static edits ONLY. This environment cannot run terraform or docker and cannot build/start a workspace. Per project memory (infra-needs-live-deploy-gate), a casefold loop mount inside a container CANNOT be proven by static review — runtime verification (build image, start workspace with the parameter on, confirm `myfile.txt` == `MYFILE.TXT`) is a REQUIRED manual step documented for the operator.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@templates/bbj-services/main.tf
@templates/bbj-services/Dockerfile
@templates/bbj-services/README.md

Key patterns to MIRROR (do not invent new styles):
- Dockerfile apt blocks: box-drawing header comment + prose rationale, chained `apt-get update && apt-get install -y --no-install-recommends ... && apt-get clean && rm -rf /var/lib/apt/lists/*`, all as `USER root` (root is already set at line ~50; final `USER coder` at line ~271). Install to /opt or /usr (SYSTEM-WIDE) — /home/coder is a volume-shadowed mount. See MemPalace block (main Dockerfile ~135) and GitHub CLI block (~205) for the exact idiom.
- main.tf coder_parameter: see git_repo (~169) and bbj_stack (~184) — name/display_name/description/type/default/mutable/icon/order.
- main.tf dynamic block gated on a value: see `dynamic "ports"` (~635) — `for_each = <cond> ? [1] : []`.
- startup_script WR-03 warn-and-continue idiom: every step `... || echo "WARN: ...; continuing" >&2` under `set -e`. See the Claude config / MCP registration blocks.
- Terraform interpolation of parameter values into the heredoc: `${local.project_folder}`, `${local.repo_url}` (startup_script ~428-429).
</context>

<tasks>

<task type="tracer">
  <name>Task 1: End-to-end casefold parameter → guarded startup_script mount → capability — one path wired</name>
  <files>templates/bbj-services/main.tf</files>
  <action>Wire the ONE opt-in path through every Terraform layer this feature touches, end-to-end.

(a) PARAMETERS — add two `data "coder_parameter"` blocks after the existing `bbj_stack` param (~line 201), mirroring its shape:
  - `case_insensitive_project`: type = "bool", default = false, mutable = false, order = 3, an icon (e.g. "/icon/folder.svg"), display_name/description explaining the CarIT/Windows case-insensitivity purpose and that it is create-time only.
  - `case_insensitive_size_gb`: type = "number", default = 20, mutable = false, order = 4, description noting it is the loopback image size and only used when the bool is enabled.

(b) STARTUP_SCRIPT BLOCK — insert an idempotent WR-03 (warn-and-continue, non-fatal under set -e) block INTO coder_agent.main.startup_script, positioned STRICTLY BEFORE the existing `── Optional project repo clone (git_repo parameter) ──` block (~line 425) so the clone lands inside the mount. Gate the ENTIRE block behind a shell `if [ "${data.coder_parameter.case_insensitive_project.value}" = "true" ]; then ... fi` (interpolate the parameter value the same way `${local.project_folder}` is interpolated). Inside the guard, interpolate `${data.coder_parameter.case_insensitive_size_gb.value}` for the size and `${local.project_folder}` for the mountpoint. The block must:
  - Set IMG="$HOME/.casefold/project.img" and MP="${local.project_folder}"; `mkdir -p "$HOME/.casefold" "$MP"`.
  - If IMG does not exist: `truncate -s <size>G "$IMG"` then `mkfs.ext4 -O casefold -E encoding=utf8 -F "$IMG"`, each with `|| echo "WARN: ...; continuing" >&2`.
  - Guard the mount with `mountpoint -q "$MP"` — only `sudo mount -o loop "$IMG" "$MP"` when NOT already a mountpoint (idempotent across restarts; re-mounts on every start, never double-mounts).
  - After a successful mount: `sudo chown coder:coder "$MP"` and set the casefold flag on the mounted root dir with `chattr +F "$MP"` (chattr ships in e2fsprogs). Add an inline comment noting the flag is set on the freshly-mkfs'd EMPTY root inode (casefold requires an empty dir); if `chattr +F` on the mount root proves unsupported at runtime, the fallback is to create+chattr a subdir — call this out in the comment as the documented fallback.
  - Every mount/chown/chattr step is `|| echo "WARN: ...; continuing" >&2`.
  Add a box-drawing header comment matching the surrounding blocks explaining the mechanism and the SYS_ADMIN dependency.

(c) CAPABILITY — add a `dynamic "capabilities"` block to `docker_container.workspace` (~line 614), mirroring the `dynamic "ports"` pattern: `for_each = data.coder_parameter.case_insensitive_project.value ? [1] : []`, content `{ add = ["SYS_ADMIN"] }`. Add a comment stating this grants ONLY loop-mount capability, is present ONLY when the parameter is true, and is NOT a new privilege escalation because /var/run/docker.sock (already mounted ~line 665) is already host-root-equivalent. Note in the comment that if loop devices are not available to SYS_ADMIN alone in this provider/kernel, the documented fallback is `privileged = true` (do NOT default to privileged).

Do NOT place fenced code blocks in this action's rendered output; the heredoc content lives inside the terraform string as prose+shell.</action>
  <verify>
    <automated>cd /workspaces/coder/templates/bbj-services && grep -q 'case_insensitive_project' main.tf && grep -q 'case_insensitive_size_gb' main.tf && grep -q 'mkfs.ext4 -O casefold' main.tf && grep -q 'mountpoint -q' main.tf && grep -q 'chattr +F' main.tf && grep -Eq 'add *= *\["SYS_ADMIN"\]' main.tf && grep -q 'dynamic "capabilities"' main.tf && echo GREP_PASS</automated>
  </verify>
  <done>Both parameters exist; the casefold startup_script block appears BEFORE the "Optional project repo clone" block and is wrapped in an `if [ ... = "true" ]` shell guard; the dynamic capabilities block adds SYS_ADMIN only when the parameter is true. grep gate prints GREP_PASS.</done>
</task>

<task type="auto">
  <name>Task 2: Bake casefold tooling (e2fsprogs + util-linux) into the image</name>
  <files>templates/bbj-services/Dockerfile</files>
  <action>Add a dedicated `USER root` apt block to the `base` stage (root is already set ~line 50; place it after the MemPalace CLI block ~147, before the stage boundary), matching the file's one-purpose-per-block convention (box-drawing header + prose rationale + the chained apt idiom). Install `e2fsprogs` (provides mkfs.ext4 with casefold support and chattr) and `util-linux` (provides mount/losetup) with `apt-get update && apt-get install -y --no-install-recommends e2fsprogs util-linux && apt-get clean && rm -rf /var/lib/apt/lists/*`. The prose comment must state: these tools are only exercised when a workspace opts into the case-insensitive project parameter (main.tf); the codercom/enterprise-base:ubuntu base likely already carries a recent e2fsprogs (mkfs.ext4 casefold needs e2fsprogs >= 1.43), so this block guarantees presence and a modern enough version; installed SYSTEM-WIDE (apt → /usr, outside the volume-shadowed /home/coder). Do NOT inline fenced code blocks in this action.</action>
  <verify>
    <automated>cd /workspaces/coder/templates/bbj-services && grep -v '^#' Dockerfile | grep -q 'e2fsprogs' && grep -v '^#' Dockerfile | grep -q 'util-linux' && echo DOCKERFILE_PASS</automated>
  </verify>
  <done>A single apt block installs e2fsprogs + util-linux as root in the base stage, following the existing chained apt-get idiom (clean + rm lists). grep gate prints DOCKERFILE_PASS.</done>
</task>

<task type="auto">
  <name>Task 3: Document the case-insensitive project feature in the README</name>
  <files>templates/bbj-services/README.md</files>
  <action>Add a new section (e.g. a `### FLAG-04: Optional case-insensitive project filesystem` entry under the existing Flags section, or a standalone "## Case-insensitive project filesystem" section — match the file's heading style). Document: (1) the two parameters (`case_insensitive_project` bool default off, `case_insensitive_size_gb` number default 20) and that they are create-time / mutable=false; (2) the CarIT/Windows rationale — the project assumes case-insensitive path resolution, and normal Linux ext4 treats Foo.bbj/foo.bbj as distinct; (3) the mechanism — an ext4 casefold loopback image at `$HOME/.casefold/project.img` on the persistent home volume, loop-mounted at the project folder before the git clone; (4) the SYS_ADMIN note — enabling adds the SYS_ADMIN capability to the container (only when enabled) for the loop mount, and that this is not a new escalation because the Docker socket is already mounted, with the `privileged = true` fallback noted if loop devices need it; (5) persistence/restart behavior — the .img persists on the home volume, the mount is re-established idempotently on every start via a mountpoint guard, stop/start loses no data; (6) the LIVE-DEPLOY CAVEAT prominently — per project memory, static Terraform/Docker review does NOT prove this works; the operator MUST verify at runtime by building the image, starting a workspace with `case_insensitive_project=true`, and confirming case-insensitivity (e.g. `touch MYFILE.TXT && cat myfile.txt` resolves to the same file inside the project folder). State it cannot be validated statically in this repo.</action>
  <verify>
    <automated>cd /workspaces/coder/templates/bbj-services && grep -qi 'case_insensitive_project' README.md && grep -qi 'casefold' README.md && grep -qi 'SYS_ADMIN' README.md && grep -qiE 'CarIT|case-insensit' README.md && echo README_PASS</automated>
  </verify>
  <done>README documents both parameters, the CarIT rationale, the casefold mechanism + image path, the SYS_ADMIN note with privileged fallback, persistence behavior, and the runtime-verification caveat. grep gate prints README_PASS.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| workspace container → host kernel | Loop mount + SYS_ADMIN capability operate against the host kernel's loop/mount subsystem |
| operator-selected parameter → container capabilities | The case_insensitive_project bool controls whether SYS_ADMIN is granted |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-ihu-01 | Elevation of Privilege | docker_container capabilities `add = ["SYS_ADMIN"]` | medium | accept | SYS_ADMIN is granted ONLY when the owner explicitly opts in (dynamic block, default false). It is not a new escalation: /var/run/docker.sock is already mounted (main.tf ~665) and is host-root-equivalent for this single-operator self-hosted deployment. Documented in main.tf comment + README. Full `privileged=true` is deliberately AVOIDED as the default; noted only as a runtime fallback. |
| T-ihu-02 | Denial of Service | loopback image size (case_insensitive_size_gb, sparse truncate) | low | accept | Image is sparse (`truncate -s`), so it consumes real space only as written, capped by the home volume. Default 20 GB is a size ceiling, not an upfront allocation. Owner-selected at create time. |
| T-ihu-03 | Tampering | none — no npm/pip/cargo installs added | low | accept | Only apt packages from the base image's configured repos (e2fsprogs, util-linux); no new package-manager registry install. No package-legitimacy checkpoint required. |
</threat_model>

<verification>
Static gates (all runnable in this repo):
- Task 1: `grep` gate GREP_PASS on main.tf (both params, casefold mkfs, mountpoint guard, chattr, dynamic capabilities + SYS_ADMIN).
- Task 2: `grep` gate DOCKERFILE_PASS (e2fsprogs + util-linux, comment-filtered).
- Task 3: `grep` gate README_PASS.
- Ordering assertion (manual read): the casefold block precedes the "Optional project repo clone" block in main.tf.
- If a dockerized terraform is available to the executor: `terraform fmt -check` and `terraform validate` on templates/bbj-services/ SHOULD pass — but terraform is NOT guaranteed in this environment; grep gates are the authoritative in-repo validation (precedent: STATE.md Phase 04-01 "terraform/tofu not in env — grep assertions served as authoritative validation gate").

RUNTIME verification (operator step, CANNOT run here — documented in README):
- Build the image, create a workspace with case_insensitive_project=true.
- Confirm the mount exists: `mountpoint -q <project_folder>` succeeds; `lsattr -d <project_folder>` shows the casefold (F) flag.
- Confirm case-insensitivity: inside the project folder, `touch MYFILE.TXT && cat myfile.txt` resolves to the same file.
- Confirm a workspace WITHOUT the parameter has no capabilities block and no casefold block runs (unchanged behavior).
- Confirm persistence: stop/start the workspace; data in the mount survives and is not double-mounted.
</verification>

<success_criteria>
- Two coder_parameters (bool + number) added, mutable=false, defaulting to OFF/20.
- Casefold startup_script block is idempotent, WR-03 non-fatal, shell-guarded on the parameter, and ordered BEFORE the git clone.
- SYS_ADMIN granted via a dynamic block ONLY when enabled (mirrors dynamic "ports").
- e2fsprogs + util-linux baked into the image (system-wide, base stage).
- README documents parameters, rationale, SYS_ADMIN/privileged fallback, persistence, and the mandatory runtime-verification caveat.
- Non-opt-in workspaces are byte-for-byte unchanged.
- All three grep gates pass.
</success_criteria>

<output>
Create `.planning/quick/260821-ihu-add-optional-case-insensitive-project-fi/260821-ihu-SUMMARY.md` when done.
</output>
