---
phase: quick-260716-cef
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /Users/beff/coder-bbj-private/modules/bbj-base/main.tf
  - /Users/beff/coder-bbj-private/modules/bbj-base/variables.tf
  - /Users/beff/coder-bbj-private/modules/bbj-base/outputs.tf
  - /Users/beff/coder-bbj-private/templates/bbj-dev/main.tf
  - /Users/beff/coder-bbj-private/scripts/push-templates.sh
  - /Users/beff/coder-bbj-private/.gitignore
autonomous: true
requirements: [QUICK-260716-cef]
must_haves:
  truths:
    - "bbj-dev workspaces provision identically after the refactor: same container name, same home/claude/svn volume names, same mount ORDER (home, then .claude-shared, then .subversion)"
    - "The shared house pattern (agent, startup_script, home volume, container, editor modules) lives in ONE reusable module consumed by bbj-dev"
    - "The module inputs support bbj-ls-dev's future migration (differing code-server vs jetbrains folders, extra_env, extra_volumes, extra_startup_script)"
    - "push-templates.sh stages the shared module into every consuming template dir before pushing, and staged copies are gitignored"
    - "The public /Users/beff/coder/templates/bbj-services template is completely untouched"
  artifacts:
    - path: "/Users/beff/coder-bbj-private/modules/bbj-base/main.tf"
      provides: "Shared coder_agent, home volume, workspace container, editor modules, data sources"
      contains: "resource \"coder_agent\" \"main\""
    - path: "/Users/beff/coder-bbj-private/modules/bbj-base/variables.tf"
      provides: "Module inputs (image_id, anthropic_api_key, folders, extra_env/volumes/startup, ports)"
      contains: "variable \"extra_volumes\""
    - path: "/Users/beff/coder-bbj-private/modules/bbj-base/outputs.tf"
      provides: "agent_id output"
      contains: "output \"agent_id\""
    - path: "/Users/beff/coder-bbj-private/templates/bbj-dev/main.tf"
      provides: "Thin consumer of the bbj-base module"
      contains: "source  = \"./modules/bbj-base\""
    - path: "/Users/beff/coder-bbj-private/scripts/push-templates.sh"
      provides: "Module staging before push loop"
      contains: "modules/bbj-base"
    - path: "/Users/beff/coder-bbj-private/.gitignore"
      provides: "Ignore staged module copies"
      contains: "templates/*/modules/"
  key_links:
    - from: "/Users/beff/coder-bbj-private/templates/bbj-dev/main.tf"
      to: "modules/bbj-base"
      via: "module \"base\" call"
      pattern: "source\\s*=\\s*\"\\./modules/bbj-base\""
    - from: "coder_script + coder_app (bbj-dev)"
      to: "module.base.agent_id"
      via: "agent_id wiring"
      pattern: "module\\.base\\.agent_id"
---

<objective>
Extract the common "house pattern" from `/Users/beff/coder-bbj-private/templates/bbj-dev/main.tf` into a reusable Terraform module `modules/bbj-base/`, and refactor bbj-dev into a thin consumer of it. Update the push script to stage the module into each consuming template before pushing.

Purpose: Eliminate duplication between bbj-dev and its siblings (bbj-ls-dev migrates later) so the shared agent/startup/volume/container/editor scaffolding is maintained in one place. Behavior for bbj-dev MUST be byte-for-byte identical at provision time — same names, same mount order — so existing workspaces are not destroyed.

Output: `modules/bbj-base/{main,variables,outputs}.tf`, a rewritten `templates/bbj-dev/main.tf`, an updated `scripts/push-templates.sh`, and a `.gitignore` entry. All edits land in the SEPARATE git repo `/Users/beff/coder-bbj-private`.

CRITICAL SCOPE: Do NOT touch anything under `/Users/beff/coder/templates/`. Do NOT migrate `bbj-ls-dev` or `template-dev`. Only bbj-dev is refactored in this task.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
All edits happen in the private repo. Use `git -C /Users/beff/coder-bbj-private ...` for every commit. Commit message style (from `git log`): lowercase conventional prefixes like `feat:`, `fix:`, `refactor:`, `feat(bbj-dev):`.

Source to extract from — read fully before editing:
@/Users/beff/coder-bbj-private/templates/bbj-dev/main.tf

Future consumer (do NOT edit — its shape dictates required module inputs):
@/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf

<interfaces>
<!-- Facts already confirmed by reading the source. Use directly; no re-exploration needed. -->

Verbatim-movable (NO Terraform interpolation inside): the bbj-dev startup_script
(skel seed → Claude shared-volume config → CLAUDE_CONFIG_DIR migration →
bypassPermissions node merge → webforJ MCP → MemPalace MCP → GSD install → trailing NOTE).
It is pure shell. Preserve the `<<-EOT` heredoc form and all `$VAR`/`$HOME` references as-is.

Escaping to preserve EXACTLY (do not unescape):
  - Disk metadata: `coder stat disk --path $${HOME}`
  - Container entrypoint rewrite: `"$${1}host.docker.internal"` and the regex `"/(https?://)(localhost|127\\.0\\.0\\.1)/"`

Shared house pattern present in BOTH templates (goes into the module):
  - terraform { required_providers { coder ~> 2.18, docker ~> 4.4 } required_version >= 1.9 }
  - data "coder_provisioner"/"coder_workspace"/"coder_workspace_owner" "me"
  - local claude_volume_name = "coder-${data.coder_workspace_owner.me.id}-claude"
  - coder_agent "main" { arch, os=linux, startup_script, env{GIT_* + CLAUDE_CONFIG_DIR}, 3 metadata blocks }
  - docker_volume "home_volume" name="coder-${data.coder_workspace.me.id}-home" (lifecycle ignore_changes=[name], 4 labels)
  - docker_container "workspace" count=start_count, entrypoint rewrite, host-gateway host block,
    volumes home + .claude-shared, 4 labels
  - module code-server(1.5.0), jetbrains-gateway(1.2.6), claude-code(5.2.0), each count=start_count

bbj-dev DELTAS that stay in / are passed by the consumer:
  - env extras: JAVA_HOME, MAVEN_HOME, ANT_HOME, BBJ_HOME, BBJ_SRC_DIR, BBJ_SVN_BRANCH
  - extra volume: /home/coder/.subversion → local.svn_volume_name = "coder-${owner.id}-svn"
  - ports: internal 8888, external var.bbj_host_port (0=disabled), bind var.bbj_host_port_bind
  - folders: code-server AND jetbrains both = local.project_folder (they match for bbj-dev)
  - docker_image "main" (build context/dockerfile/build_args/triggers) — template-specific, STAYS
  - coder_parameter svn_branch + bbj_stack, combinations.json locals — STAY
  - coder_script bbj_checkout, coder_script bbjservices, coder_app bbjservices — STAY

bbj-ls-dev future needs (drive input design, do not implement its migration now):
  - code_server_folder = repos_dir  BUT  jetbrains_folder = "${repos_dir}/bbj-language-server" (they DIFFER)
  → the module MUST expose code-server folder and jetbrains folder as SEPARATE inputs.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create the modules/bbj-base/ shared module</name>
  <files>/Users/beff/coder-bbj-private/modules/bbj-base/variables.tf, /Users/beff/coder-bbj-private/modules/bbj-base/outputs.tf, /Users/beff/coder-bbj-private/modules/bbj-base/main.tf</files>
  <action>
Create `modules/bbj-base/` with three files.

variables.tf — declare inputs:
  - `image_id` (string) — the built workspace image id, wired to docker_container.image.
  - `anthropic_api_key` (string, sensitive, default "") — forwarded to the claude-code module.
  - `code_server_folder` (string) — folder the code-server editor opens.
  - `jetbrains_folder` (string) — folder JetBrains Gateway opens. Kept SEPARATE from code_server_folder because bbj-ls-dev opens different folders in each; bbj-dev passes the same value to both.
  - `extra_env` (map(string), default {}) — merged over the base agent env via merge().
  - `extra_startup_script` (string, default "") — appended to the end of the shared startup_script.
  - `extra_volumes` (list(object({ container_path = string, volume_name = string })), default []) — extra container mounts, rendered by a dynamic block AFTER the static home + .claude-shared mounts so mount-namespace ordering is preserved.
  - `port_internal` (number, default 0) — container port to publish.
  - `port_external` (number, default 0) — host port; when 0, NO port block is emitted (publishing disabled).
  - `port_bind` (string, default "127.0.0.1") — host IP to bind the published port.

outputs.tf — `output "agent_id" { value = coder_agent.main.id }`. No other outputs needed.

main.tf — move the shared house pattern from templates/bbj-dev/main.tf VERBATIM:
  - terraform { required_providers { coder = { source="coder/coder", version="~> 2.18" }, docker = { source="kreuzwerker/docker", version="~> 4.4" } } required_version = ">= 1.9" }. Do NOT add a `provider "docker"` block — provider CONFIG stays in the root template and is inherited.
  - data "coder_provisioner"/"coder_workspace"/"coder_workspace_owner" "me" {}.
  - locals { claude_volume_name = "coder-${data.coder_workspace_owner.me.id}-claude" }. Drop the unused `username` local.
  - coder_agent "main": copy startup_script heredoc EXACTLY as in bbj-dev (lines 198-322), then append the extra_startup_script input at the very end so `${var.extra_startup_script}` renders after the trailing NOTE. env = merge({ GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL (same coalesce/email expressions), CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude" }, var.extra_env). Keep all three metadata blocks verbatim including `--path $${HOME}`.
  - docker_volume "home_volume": name = "coder-${data.coder_workspace.me.id}-home", lifecycle ignore_changes=[name], all 4 labels — verbatim.
  - docker_container "workspace": count = data.coder_workspace.me.start_count; image = var.image_id; name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"; hostname; the entrypoint replace() rewrite verbatim (preserve `$${1}` and the regex escaping); env CODER_AGENT_TOKEN; host block host.docker.internal→host-gateway. Then: dynamic "ports" over `var.port_external > 0 ? [1] : []` with internal=var.port_internal, external=var.port_external, ip=var.port_bind, protocol="tcp". Then STATIC volumes in ORDER: (1) /home/coder → home_volume, (2) /home/coder/.claude-shared → local.claude_volume_name. Then dynamic "volumes" over var.extra_volumes with container_path/volume_name and read_only=false. Then the 4 labels verbatim.
  - module "code-server" (count=start_count, version "1.5.0", agent_id=coder_agent.main.id, folder=var.code_server_folder, display_name "VS Code", order 1).
  - module "jetbrains-gateway" (count=start_count, version "1.2.6", agent_id, agent_name "main", folder=var.jetbrains_folder, jetbrains_ides ["IU"], default "IU", order 2).
  - module "claude-code" (count=start_count, version "5.2.0", agent_id, anthropic_api_key=var.anthropic_api_key, install_claude_code=true).

Do NOT include docker_image, coder_parameter, coder_script, coder_app, or combinations locals — those are bbj-dev-specific and stay in the consumer.

Commit: `git -C /Users/beff/coder-bbj-private add modules/ && git -C /Users/beff/coder-bbj-private commit -m "feat: extract shared bbj-base terraform module"`.
  </action>
  <verify>
    <automated>test -f /Users/beff/coder-bbj-private/modules/bbj-base/main.tf && test -f /Users/beff/coder-bbj-private/modules/bbj-base/variables.tf && test -f /Users/beff/coder-bbj-private/modules/bbj-base/outputs.tf && grep -q 'resource "coder_agent" "main"' /Users/beff/coder-bbj-private/modules/bbj-base/main.tf && grep -q 'dynamic "volumes"' /Users/beff/coder-bbj-private/modules/bbj-base/main.tf && grep -q 'dynamic "ports"' /Users/beff/coder-bbj-private/modules/bbj-base/main.tf && grep -q 'coder-${data.coder_workspace.me.id}-home' /Users/beff/coder-bbj-private/modules/bbj-base/main.tf && grep -q 'variable "extra_volumes"' /Users/beff/coder-bbj-private/modules/bbj-base/variables.tf && grep -q 'output "agent_id"' /Users/beff/coder-bbj-private/modules/bbj-base/outputs.tf && grep -q 'path \$\${HOME}' /Users/beff/coder-bbj-private/modules/bbj-base/main.tf</automated>
  </verify>
  <done>modules/bbj-base/ exists with main/variables/outputs.tf. coder_agent, home volume (name unchanged), workspace container (with dynamic ports + static home/.claude-shared then dynamic extra_volumes, in that order), and the three editor modules are present. agent_id output exists. Escaping ($${HOME}, entrypoint rewrite) preserved. Committed.</done>
</task>

<task type="auto">
  <name>Task 2: Rewrite templates/bbj-dev/main.tf as a thin consumer</name>
  <files>/Users/beff/coder-bbj-private/templates/bbj-dev/main.tf</files>
  <action>
Rewrite templates/bbj-dev/main.tf keeping ONLY the template-specific parts plus a call to the module. Preserve the top header comment block, and update it to mention the split into ./modules/bbj-base.

KEEP verbatim (template-specific):
  - terraform { required_providers coder ~> 2.18 + docker ~> 4.4, required_version >= 1.9 } — root needs it for the docker provider config.
  - All variables: docker_socket, workspace_image, anthropic_api_key, maven_version, ant_version, bbj_context_path, bbj_license_server, bbj_platform, bbj_app_subdomain, bbj_host_port, bbj_host_port_bind.
  - coder_parameter "svn_branch" and "bbj_stack" (with its dynamic option block).
  - provider "docker" { host = ... }.
  - The combinations locals block (default_combinations, bbj_combinations from combinations.json, combos_by_id, selected) PLUS the bbj-dev locals it needs: bbj_src_dir, project_folder, and svn_volume_name = "coder-${data.coder_workspace_owner.me.id}-svn".
  - docker_image "main" — verbatim (build context/dockerfile/build_args/triggers/keep_locally).
  - coder_script "bbj_checkout" and coder_script "bbjservices" — verbatim EXCEPT change `agent_id = coder_agent.main.id` → `agent_id = module.base.agent_id`.
  - coder_app "bbjservices" — verbatim EXCEPT `agent_id = coder_agent.main.id` → `agent_id = module.base.agent_id`.

ADD data sources needed by the consumer for image naming and svn volume: keep `data "coder_workspace" "me" {}` (docker_image.main.name uses data.coder_workspace.me.id) and `data "coder_workspace_owner" "me" {}` (svn_volume_name uses its id). These duplicate the module's internal data sources — that is intentional and cheap (Coder replans per workspace; no shared state).

REMOVE (now provided by the module): coder_agent "main", docker_volume "home_volume", docker_container "workspace", module "code-server", module "jetbrains-gateway", module "claude-code", the claude_volume_name local, and the coder_provisioner data source (only the module needs arch).

ADD the module call:
  module "base" {
    source               = "./modules/bbj-base"
    image_id             = docker_image.main.image_id
    anthropic_api_key    = var.anthropic_api_key
    code_server_folder   = local.project_folder
    jetbrains_folder     = local.project_folder
    extra_env = {
      JAVA_HOME      = "/opt/java/default"
      MAVEN_HOME     = "/opt/maven"
      ANT_HOME       = "/opt/ant"
      BBJ_HOME       = "/opt/bbx"
      BBJ_SRC_DIR    = local.bbj_src_dir
      BBJ_SVN_BRANCH = data.coder_parameter.svn_branch.value
    }
    extra_volumes = [{ container_path = "/home/coder/.subversion", volume_name = local.svn_volume_name }]
    port_internal = 8888
    port_external = var.bbj_host_port
    port_bind     = var.bbj_host_port_bind
  }

Do NOT put `count` on the module call — the container inside the module already gates on start_count via its own data source; a module-level count would double-gate and break.

Confirm container name, home/claude/svn volume names all derive from data sources (unchanged strings) so existing workspaces keep their data.

Commit: `git -C /Users/beff/coder-bbj-private add templates/bbj-dev/main.tf && git -C /Users/beff/coder-bbj-private commit -m "refactor(bbj-dev): consume shared bbj-base module"`.
  </action>
  <verify>
    <automated>cd /Users/beff/coder-bbj-private && grep -q 'source  *= *"\./modules/bbj-base"' templates/bbj-dev/main.tf && grep -q 'module\.base\.agent_id' templates/bbj-dev/main.tf && test $(grep -c 'module\.base\.agent_id' templates/bbj-dev/main.tf) -ge 3 && ! grep -q 'resource "coder_agent" "main"' templates/bbj-dev/main.tf && ! grep -q 'resource "docker_container" "workspace"' templates/bbj-dev/main.tf && ! grep -q 'resource "docker_volume" "home_volume"' templates/bbj-dev/main.tf && grep -q 'resource "docker_image" "main"' templates/bbj-dev/main.tf && grep -q 'coder-${data.coder_workspace_owner.me.id}-svn' templates/bbj-dev/main.tf && grep -q 'port_internal = 8888' templates/bbj-dev/main.tf</automated>
  </verify>
  <done>bbj-dev main.tf is a thin consumer: module "base" call present, coder_script + coder_app wired to module.base.agent_id (>=3 refs), agent/volume/container resources removed, docker_image + params + coder_scripts + coder_app + combinations locals retained, svn volume passed via extra_volumes. Committed.</done>
</task>

<task type="auto">
  <name>Task 3: Module staging in push script + .gitignore, then validate</name>
  <files>/Users/beff/coder-bbj-private/scripts/push-templates.sh, /Users/beff/coder-bbj-private/.gitignore</files>
  <action>
1. push-templates.sh — before the "Discover and push all templates" loop (after asset staging, ~line 90), add a MODULE STAGING step. Under `set -euo pipefail` discipline: for each `templates/*/` dir whose `main.tf` contains the string `./modules/bbj-base`, remove any existing staged copy and copy the repo-root `modules/` dir into it, e.g. `rm -rf "${dir}modules" && cp -R "${PROJECT_ROOT}/modules" "${dir}modules"`. Guard: if the referencing template exists but `${PROJECT_ROOT}/modules` is missing, echo an ERROR to stderr and `exit 1` (meaningful failure code). Echo which templates were staged. Local modules (`source = "./modules/..."`) are resolved from the pushed directory, so the copy must exist before `coder templates push`.

2. .gitignore — append a line `templates/*/modules/` (staged copies are build artifacts, never committed). Keep existing entries.

3. Validate the STAGED bbj-dev (mirror what the push script does):
   - Detect the Terraform CLI: prefer `terraform`, else `tofu`. If NEITHER is on PATH, skip binary validation, do a careful manual HCL review of both files (matched braces, all module inputs supplied, no dangling coder_agent references), and record in the SUMMARY that CLI validation was skipped because no terraform/tofu binary was available.
   - If a binary exists: `rm -rf /Users/beff/coder-bbj-private/templates/bbj-dev/modules && cp -R /Users/beff/coder-bbj-private/modules /Users/beff/coder-bbj-private/templates/bbj-dev/modules`, then in that dir run `<bin> init -backend=false` followed by `<bin> validate`. Registry modules (registry.coder.com) need network during init — if init fails purely due to network/registry download, fall back to `<bin> fmt -check -recursive` (or a fmt of the module + template) and note the network limitation in the SUMMARY. Always clean up the staged copy afterward: `rm -rf /Users/beff/coder-bbj-private/templates/bbj-dev/modules`.

4. Commit: `git -C /Users/beff/coder-bbj-private add scripts/push-templates.sh .gitignore && git -C /Users/beff/coder-bbj-private commit -m "feat: stage bbj-base module into consuming templates on push"`.

Confirm nothing under /Users/beff/coder/templates/ was modified (this task only writes inside /Users/beff/coder-bbj-private).
  </action>
  <verify>
    <automated>cd /Users/beff/coder-bbj-private && grep -q 'modules/bbj-base' scripts/push-templates.sh && grep -q 'cp -R' scripts/push-templates.sh && bash -n scripts/push-templates.sh && grep -q 'templates/\*/modules/' .gitignore && test ! -d templates/bbj-dev/modules && git -C /Users/beff/coder-bbj-private status --porcelain | grep -qv 'coder/templates' </automated>
  </verify>
  <done>push-templates.sh stages repo-root modules/ into any template referencing ./modules/bbj-base before the push loop, with fail-fast on a missing modules dir; .gitignore ignores templates/*/modules/; staged copy cleaned up; validation attempted (terraform/tofu if present, else documented manual review); all committed. bash -n passes.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| operator host → workspace container | Existing boundary, unchanged by this refactor |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-cef-01 | Tampering | Behavior drift during extraction (names/mount order change → destroys existing workspaces) | mitigate | Verify container/volume names derive from data sources (unchanged strings) and static mounts precede dynamic extra_volumes; grep gates in Task 1/2 |
| T-cef-02 | Information Disclosure | anthropic_api_key input | mitigate | Declared `sensitive = true` in the module, forwarded only to the claude-code module (same as source) |
| T-cef-SC | Tampering | New package/module installs | accept | No new npm/pip/cargo packages; registry.coder.com module versions (1.5.0/1.2.6/5.2.0) copied verbatim from the audited source template |
</threat_model>

<verification>
- bbj-dev provision behavior is identical: container name `coder-<owner>-<workspace>`, home volume `coder-<workspace_id>-home`, claude volume `coder-<owner_id>-claude`, svn volume `coder-<owner_id>-svn` all unchanged.
- Volume mount order in the module container: home → .claude-shared → (dynamic) .subversion.
- `git -C /Users/beff/coder-bbj-private log --oneline -3` shows the three atomic commits.
- Nothing under /Users/beff/coder/templates/ changed.
</verification>

<success_criteria>
- modules/bbj-base/ exists and holds the shared house pattern with the full input set (image_id, anthropic_api_key, separate folder inputs, extra_env/volumes/startup, port trio).
- templates/bbj-dev/main.tf is a thin consumer wiring coder_script/coder_app to module.base.agent_id, with docker_image/params/scripts/app retained.
- push-templates.sh stages the module before pushing; .gitignore ignores staged copies.
- Validation performed (CLI or documented manual review); staged copies cleaned up.
- Three atomic commits in the private repo; public template untouched; bbj-ls-dev and template-dev untouched.
</success_criteria>

<output>
Create `.planning/quick/260716-cef-extract-shared-bbj-base-module-from-bbj-/260716-cef-SUMMARY.md` when done.
</output>
