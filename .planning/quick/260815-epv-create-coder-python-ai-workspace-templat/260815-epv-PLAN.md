---
phase: quick-260815-epv
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/python-ai/Dockerfile
  - templates/python-ai/main.tf
  - templates/python-ai/README.md
  - README.md
autonomous: true
requirements: [QUICK-260815-epv]

must_haves:
  truths:
    - "templates/python-ai/ exists with main.tf, Dockerfile, README.md and is auto-discoverable by scripts/push-templates.sh (subdir with a .tf file)"
    - "The template is a structural clone of java-fullstack with the Java toolchain replaced by a Python/AI toolchain (uv-managed CPython, ruff/mypy/pytest/ipython, anthropic + claude-agent-sdk, JupyterLab)"
    - "python_version coder_parameter (3.13/3.12/3.11) replaces the jdk parameter; the selected version is a build arg and is baked as the default python3/python"
    - "All Python toolchain installs land OUTSIDE /home/coder (in /opt, /usr) so the persistent home volume does not shadow them at runtime"
    - "`python -c 'import anthropic, claude_agent_sdk'` succeeds in a fresh login shell (documented, deferred-live)"
    - "IDE buttons: code-server (browser VS Code), VS Code Desktop, JetBrains Gateway (PyCharm Professional / PY), plus a JupyterLab app button"
    - "The entire Claude config / MCP / GSD / MemPalace startup_script block is reused verbatim (Java env removed)"
  artifacts:
    - path: "templates/python-ai/Dockerfile"
      provides: "Python/AI workspace image (uv CPython, dev tools, AI SDKs, JupyterLab, MemPalace, gh, SSH host keys, Node LTS)"
      contains: "PYTHON_VERSION"
    - path: "templates/python-ai/main.tf"
      provides: "Coder template: python_version param, docker image/volume/container, code-server + vscode-desktop + jetbrains-gateway(PY) + claude-code modules, JupyterLab app"
      contains: "python_version"
    - path: "templates/python-ai/README.md"
      provides: "Template docs + push/edit commands + DEFERRED live-verification checklist"
      contains: "DEFERRED"
    - path: "README.md"
      provides: "Root README template list entry for python-ai"
      contains: "python-ai"
  key_links:
    - from: "templates/python-ai/main.tf"
      to: "templates/python-ai/Dockerfile"
      via: "docker_image.main build { context = path.module } with build_args BASE_IMAGE + PYTHON_VERSION"
      pattern: "build_args"
    - from: "templates/python-ai/main.tf"
      to: "data.coder_parameter.python_version"
      via: "PYTHON_VERSION build arg + image name + triggers"
      pattern: "python_version"
---

<objective>
Create `templates/python-ai/` (main.tf, Dockerfile, README.md) as a Python-project Coder
workspace template that is a near-structural clone of `templates/java-fullstack`, with the
Java toolchain (JDK + Maven) swapped for a Python/AI toolchain (uv-managed CPython + dev tools
+ AI SDKs + JupyterLab). Add a root README entry. The template auto-registers via
scripts/push-templates.sh (any templates/* subdir with a .tf file), so push-templates.sh needs
NO change — verified: it discovers templates dynamically and only special-cases `bbj-services`
in its per-template --variable block.

Purpose: give Python developers the same batteries-included, Claude-Code-wired workspace the
Java template gives Java developers, without renegotiating any of the proven Claude/MCP/GSD/
MemPalace/reliability idioms.

Output: templates/python-ai/{Dockerfile,main.tf,README.md} + a root README.md template-list entry.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

# THE reference to mirror — read both fully before writing anything
@templates/java-fullstack/main.tf
@templates/java-fullstack/Dockerfile

# Auto-registration mechanism (confirm no change needed)
@scripts/push-templates.sh

# Root README — has a "## Workspace Template" section enumerating templates (docker,
# java-fullstack); add a python-ai subsection in the same style
@README.md

# Secondary reference for the per-owner Claude config volume comment pattern
@templates/coderscaffold/main.tf
</context>

<constraints_carryover>
VERIFIED FACTS (from reading the reference tree — do NOT re-derive):

- Shared module source strings + versions are confirmed real & resolved in
  `templates/java-fullstack/.terraform/modules/modules.json`:
  - code-server:       registry.coder.com/coder/code-server/coder       @ 1.5.0
  - jetbrains-gateway: registry.coder.com/coder/jetbrains-gateway/coder @ 1.2.6
  - claude-code:       registry.coder.com/coder/claude-code/coder       @ 5.2.0
  Use these EXACT strings/versions — no guessing.

- `vscode-desktop` and any `jupyterlab` registry module are NOT in the resolved module set
  (no network to the registry API from this env). They MUST be planned with a pinned,
  known-good version AND flagged [LIVE-VERIFY] in code comments + the README deferred checklist.
  Pin: registry.coder.com/coder/vscode-desktop/coder @ "1.1.0" (last-known-good; verify latest live).
  For JupyterLab, PREFER the registry module registry.coder.com/coder/jupyterlab/coder @ "1.1.0"
  (verify live); if the executor can confirm it does not exist at push time, FALL BACK to the
  coder_app approach described in Task 2. Plan BOTH; comment the chosen path with [LIVE-VERIFY].

- java-fullstack has a committed `.terraform.lock.hcl` + a full provider mirror under
  `.terraform/providers/` (coder/coder, kreuzwerker/docker, hashicorp/http). These let
  `terraform validate` run OFFLINE by copying the mirror + lock into the new template dir.

- push-templates.sh needs NO edit: it loops `templates/*/`, pushes any dir with a *.tf file,
  and only special-cases `bbj-services` in the --variable case block. python-ai has no
  push-time --variable requirement (anthropic_api_key defaults empty, like java-fullstack).
</constraints_carryover>

<tasks>

<task type="auto">
  <name>Task 1: Create templates/python-ai/Dockerfile (Python/AI toolchain)</name>
  <files>templates/python-ai/Dockerfile</files>
  <action>
Clone templates/java-fullstack/Dockerfile structurally, adapting the header comment for Python.
Keep these blocks VERBATIM (only adapt surrounding comments): the `USER root` switch, the
Node.js LTS via NodeSource block (KEEP — needed for Claude Code CLI, GSD, and the node JSON
merges in startup_script), the SSH host-key seeding block (github/gitlab/bitbucket/azure +
StrictHostKeyChecking accept-new), the GitHub CLI (gh) block, the MemPalace CLI block (python3
venv at /opt/mempalace, symlinked to /usr/local/bin/mempalace), and the final `USER coder`.

REMOVE entirely: the JDK install block, the Apache Maven block, and the
/etc/profile.d/10-java-maven.sh JAVA_HOME/MAVEN_HOME profile script. Change the ARG line from
`ARG JDK=...` / `ARG MAVEN_VERSION=...` to `ARG PYTHON_VERSION=3.13`. Keep
`ARG BASE_IMAGE=codercom/enterprise-base:ubuntu` and `FROM ${BASE_IMAGE}`.

ADD the Python/AI toolchain, everything installed to /opt or /usr (NEVER under /home/coder —
the persistent volume shadows it at runtime), each block idempotent where sensible and using
system-path env so all users get it:

  a) uv (Astral) SYSTEM-WIDE: download the standalone installer with
     `UV_INSTALL_DIR=/usr/local/bin sh` (or `env UV_UNMANAGED_INSTALL=/usr/local/bin`) so `uv`
     and `uvx` land on the system PATH — NOT /root or /home/coder. Verify `uv --version` and
     `command -v uvx`.
  b) Export system-wide env in /etc/profile.d/10-uv.sh: set UV_PYTHON_INSTALL_DIR=/opt/uv-python,
     UV_TOOL_DIR=/opt/uv-tools, UV_TOOL_BIN_DIR=/usr/local/bin, and ensure /usr/local/bin is on
     PATH. chmod 0644. (These same vars are ALSO exported in the coder_agent env in main.tf for
     non-login-shell parity — same rationale as the java template's JAVA_HOME/MAVEN_HOME.)
  c) Install the build-arg CPython system-wide: with UV_PYTHON_INSTALL_DIR=/opt/uv-python run
     `uv python install ${PYTHON_VERSION}`, then make `python3` and `python` resolve to it
     system-wide by symlinking the resolved interpreter (`uv python find ${PYTHON_VERSION}`)
     into /usr/local/bin/python3 and /usr/local/bin/python. Verify `python --version` shows the
     selected major.minor.
  d) Pre-bake dev tooling with `uv tool install` (ruff, mypy, pytest, ipython) — with UV_TOOL_DIR
     =/opt/uv-tools and UV_TOOL_BIN_DIR=/usr/local/bin so shims are on PATH and OUTSIDE
     /home/coder. Verify each is on PATH (`command -v ruff mypy pytest ipython`).
  e) AI SDKs importable from the default `python` out of the box (acceptance:
     `python -c "import anthropic, claude_agent_sdk"` succeeds in a fresh login shell). The
     cleanest robust approach: install anthropic + claude-agent-sdk INTO the same uv-managed
     CPython created in (c), i.e. `uv pip install --python /usr/local/bin/python anthropic
     claude-agent-sdk` (that interpreter is the one python/python3 point to, so the import works
     with no venv activation). Do NOT `--system` into enterprise-base's own python and do NOT
     create a separate venv that python does not see. Verify the import line at build time.
  f) JupyterLab launchable as `jupyter lab`: `uv tool install jupyterlab`
     (UV_TOOL_BIN_DIR=/usr/local/bin). Verify `command -v jupyter`.

Reliability idioms on every new RUN block: apt cleanup (`apt-get clean && rm -rf
/var/lib/apt/lists/*`) where apt is used; `set -eux` for multi-step blocks; system paths only.

DISCIPLINE: do NOT write the literal token `import anthropic` or `import claude_agent_sdk` as
prose that a later negative grep could self-invalidate — the verify step greps the Dockerfile
for `python`, not for import literals, so this is safe, but keep AI-SDK verification as an
executable `python -c "..."` RUN line, not a comment.
  </action>
  <verify>
    <automated>bash -c 'set -e; f=templates/python-ai/Dockerfile; test -f "$f"; grep -q "ARG PYTHON_VERSION" "$f"; grep -q "uv python install" "$f"; grep -qi "jupyterlab" "$f"; grep -q "claude-agent-sdk" "$f"; grep -q "anthropic" "$f"; grep -q "/opt/mempalace" "$f"; grep -q "ssh-keyscan" "$f"; grep -q "USER coder" "$f"; ! grep -qiE "JAVA_HOME|MAVEN_HOME|apache-maven|adoptium" "$f"; ! grep -nE "install|cp |ln -s|venv" "$f" | grep -q "/home/coder"; echo DOCKERFILE_OK'</automated>
  </verify>
  <done>Dockerfile exists, layers uv + build-arg CPython + ruff/mypy/pytest/ipython + anthropic/claude-agent-sdk + jupyterlab on codercom/enterprise-base:ubuntu; keeps Node LTS, MemPalace, gh, SSH host-keys verbatim; drops all Java/Maven; no toolchain path touches /home/coder; ends with USER coder. hadolint/`docker build --check` deferred (see Task 5).</done>
</task>

<task type="auto">
  <name>Task 2: Create templates/python-ai/main.tf (Python param + IDE modules + JupyterLab)</name>
  <files>templates/python-ai/main.tf</files>
  <action>
Clone templates/java-fullstack/main.tf. Adapt the header comment block for Python (list the
Python toolchain, editors, and the JupyterLab app). Keep VERBATIM (same shapes, comments
adapted): the terraform block (coder/coder ~> 2.18, kreuzwerker/docker ~> 4.4, required_version
>= 1.9); variables docker_socket, workspace_image (default codercom/enterprise-base:ubuntu),
anthropic_api_key (sensitive, default ""); the coder_parameter "git_repo" (optional,
mutable=false, order 1, icon /icon/git.svg); the docker provider; data sources
coder_provisioner/coder_workspace/coder_workspace_owner; the locals block (username,
claude_volume_name keyed on owner UUID, repo_url/repo_name/project_folder derivation); the
coder_agent "main" startup_script IN FULL (skel seed, the entire Claude config symlink dance,
CLAUDE_CONFIG_DIR physical-dir migration, bypassPermissions node merge, webforJ MCP
registration, MemPalace MCP registration, GSD install, optional git_repo clone, MemPalace init);
the CPU/RAM/Disk metadata blocks; docker_volume "home_volume" (ID-keyed, ignore_changes name,
labels); the Claude config volume comment block (unmanaged per-owner volume); docker_container
"main" (host.docker.internal init_script rewrite in entrypoint, both /home/coder and
/home/coder/.claude-shared volume mounts declared in that order, labels, CODER_AGENT_TOKEN env);
module "claude-code" @ 5.2.0 (install_claude_code=true, anthropic_api_key=var.anthropic_api_key).

DELETE the `maven_version` variable entirely.

SWAP Java → Python:
  1. Replace coder_parameter "jdk" with coder_parameter "python_version": mutable=true, order 2,
     icon "/icon/python.svg", default "3.13". Options (name / value):
       "Python 3.13" / "3.13", "Python 3.12" / "3.12", "Python 3.11" / "3.11".
     Description: build-time default CPython — changing it rebuilds the workspace image; other
     versions remain available at runtime via `uv python install`.
  2. docker_image "main": name = "coder-${data.coder_workspace.me.id}-workspace-${data.coder_parameter.python_version.value}";
     build_args = { BASE_IMAGE = var.workspace_image, PYTHON_VERSION = data.coder_parameter.python_version.value };
     triggers = { dockerfile_sha1 = filesha1(...Dockerfile), python_version = data.coder_parameter.python_version.value }.
     DROP MAVEN_VERSION from both build_args and triggers.
  3. coder_agent "main" env: keep GIT_AUTHOR_*/GIT_COMMITTER_* and
     CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude". REMOVE JAVA_HOME and MAVEN_HOME.
     ADD, for non-login-shell parity with /etc/profile.d/10-uv.sh:
       UV_PYTHON_INSTALL_DIR = "/opt/uv-python"
       UV_TOOL_DIR           = "/opt/uv-tools"
       UV_TOOL_BIN_DIR       = "/usr/local/bin"

IDE modules (all with count = data.coder_workspace.me.start_count, folder = local.project_folder
where the module takes folder):
  - module "code-server" @ 1.5.0 (registry.coder.com/coder/code-server/coder), display_name
    "VS Code", order 1 — verbatim from java template.
  - module "vscode-desktop": source "registry.coder.com/coder/vscode-desktop/coder",
    version "1.1.0"  # [LIVE-VERIFY] exact latest version + that it takes folder — confirm at
    push time against the registry; pin bumped if newer. agent_id = coder_agent.main.id,
    folder = local.project_folder, order 2. Opens local VS Code Desktop over SSH.
  - module "jetbrains-gateway" @ 1.2.6 (registry.coder.com/coder/jetbrains-gateway/coder):
    agent_id, agent_name = "main", folder = local.project_folder, jetbrains_ides = ["PY"],
    default = "PY", order 3.  (PyCharm Professional instead of IntelliJ IU.)

JupyterLab browser button — plan BOTH paths, comment the primary with [LIVE-VERIFY]:
  PRIMARY (preferred): module "jupyterlab", source
  "registry.coder.com/coder/jupyterlab/coder", version "1.1.0"  # [LIVE-VERIFY] confirm module
  exists + exact version + variables (agent_id, order, subdomain) at push time; agent_id =
  coder_agent.main.id, order 4, count = start_count.
  FALLBACK (only if the module is confirmed nonexistent live): a coder_app "jupyterlab" +
  a startup command that launches `jupyter lab` bound to a local port (e.g. 8888) with
  --ServerApp.base_url set to a coder-friendly path, --no-browser, --ip 127.0.0.1, token/auth
  disabled for the loopback app, backgrounded via nohup so it does NOT block startup_script, and
  guarded WR-03 warn-and-continue + idempotent (skip if already listening). Comment this block
  clearly as the fallback and leave it inert (commented) when the module path is used, OR wire
  the coder_app and drop the module — executor picks ONE at push time and documents the choice.
  Acceptance either way: a JupyterLab app button appears in the workspace.

Reliability idioms preserved: any shell you add to startup_script (the JupyterLab fallback) must
be idempotent + non-fatal (WR-03 warn-and-continue, never abort startup_script).
  </action>
  <verify>
    <automated>bash -c 'set -e; f=templates/python-ai/main.tf; test -f "$f"; grep -q "coder/coder" "$f"; grep -q "~> 2.18" "$f"; grep -q "kreuzwerker/docker" "$f"; grep -q "python_version" "$f"; grep -q "/icon/python.svg" "$f"; grep -q "PYTHON_VERSION" "$f"; grep -q "code-server/coder" "$f"; grep -q "vscode-desktop/coder" "$f"; grep -q "jetbrains-gateway/coder" "$f"; grep -q "\"PY\"" "$f"; grep -qi "jupyter" "$f"; grep -q "claude-code/coder" "$f"; grep -q "UV_PYTHON_INSTALL_DIR" "$f"; grep -q "claude_volume_name" "$f"; grep -q "host.docker.internal" "$f"; ! grep -qE "maven_version|JAVA_HOME|MAVEN_HOME|\"jdk\"|\"IU\"" "$f"; echo MAINTF_OK'</automated>
  </verify>
  <done>main.tf exists; python_version param replaces jdk; image name/build_args/triggers use PYTHON_VERSION (no MAVEN_VERSION); agent env drops JAVA_HOME/MAVEN_HOME and adds UV_* vars; code-server + vscode-desktop + jetbrains-gateway(PY) + jupyterlab(or coder_app) + claude-code modules present; entire Claude/MCP/GSD/MemPalace startup_script reused; no jdk/IU/maven residue. `terraform validate` deferred to Task 5.</done>
</task>

<task type="auto">
  <name>Task 3: Write templates/python-ai/README.md + add root README template entry</name>
  <files>templates/python-ai/README.md, README.md</files>
  <action>
Create templates/python-ai/README.md mirroring the STYLE of the "Java full-stack template"
subsection in the root README (java-fullstack has no standalone README.md — match the root
README's prose + the code-fenced push/edit commands). Cover:
  - What it provides: uv-managed selectable CPython (3.13/3.12/3.11, build-time), ruff/mypy/
    pytest/ipython pre-baked, anthropic + claude-agent-sdk importable from the default python,
    JupyterLab, Node.js LTS, VS Code (browser + Desktop), PyCharm Professional (JetBrains
    Gateway), Claude Code + webforJ/MemPalace MCP + GSD, optional git clone. Note python_version
    is build-time (changing it rebuilds the image) and other versions are runtime-available via
    `uv python install`.
  - Why toolchains live in /opt (the /home/coder volume shadows home at runtime).
  - Push + server-side edit commands (mirror the java block; use `--icon "/icon/python.svg"`,
    a python-ai display name + description). Mention ./scripts/push-templates.sh pushes every
    template automatically.
  - Private-repo SSH clone note (reuse the java template's explanation — host keys pre-seeded,
    register Coder's key at the Git host).
  - A DEFERRED LIVE-VERIFICATION CHECKLIST section (literal heading contains "DEFERRED") that a
    human MUST run on a real Coder host with the coder CLI before trusting the template:
      [ ] `coder templates push python-ai --directory templates/python-ai/ -y` succeeds
      [ ] workspace builds for each python_version (3.13/3.12/3.11)
      [ ] `python --version` matches the selected version; `python -c "import anthropic,
          claude_agent_sdk"` succeeds in a fresh login shell
      [ ] `ruff`, `mypy`, `pytest`, `ipython`, `jupyter`, `uv`, `uvx` all on PATH
      [ ] IDE buttons appear and open: VS Code (browser), VS Code Desktop, PyCharm (Gateway)
      [ ] JupyterLab app button appears and launches JupyterLab
      [ ] confirm the vscode-desktop + jupyterlab module source/version pins ([LIVE-VERIFY]
          in main.tf) resolve; bump pins if the registry has newer
      [ ] Claude Code, webforJ MCP, MemPalace MCP, GSD all present (owner-shared volume)

Then EDIT the root README.md: add a "### Python AI template" subsection immediately AFTER the
existing "### Java full-stack template" subsection (inside "## Workspace Template"), in the same
style, briefly describing the template and giving the push + `coder templates edit python-ai
--icon "/icon/python.svg"` commands. Use Edit (scoped) on README.md — do NOT rewrite the file.
  </action>
  <verify>
    <automated>bash -c 'set -e; test -f templates/python-ai/README.md; grep -qi "DEFERRED" templates/python-ai/README.md; grep -qi "jupyter" templates/python-ai/README.md; grep -q "python -c" templates/python-ai/README.md; grep -q "python-ai" README.md; grep -q "Python AI template" README.md; echo READMES_OK'</automated>
  </verify>
  <done>templates/python-ai/README.md documents the template and includes a DEFERRED live-verification checklist enumerating every deferred live check; root README.md has a "### Python AI template" subsection under "## Workspace Template" with push/edit commands, added via scoped Edit (java-fullstack section intact).</done>
</task>

<task type="auto">
  <name>Task 4: Grep self-audit — no toolchain under /home/coder, no Java residue, push-templates unchanged</name>
  <files>templates/python-ai/Dockerfile, templates/python-ai/main.tf</files>
  <action>
Run a static self-audit (no code changes unless it finds a violation, in which case fix the
offending file then re-run):
  a) Assert NO toolchain install/copy/symlink/venv line in the Dockerfile targets /home/coder:
     grep the Dockerfile for lines containing an install/copy/symlink/venv verb AND `/home/coder`
     — expect ZERO matches. (Volume-shadow rule.)
  b) Assert NO Java/Maven residue in either file: no JAVA_HOME, MAVEN_HOME, apache-maven,
     adoptium, maven_version, `"jdk"`, `"IU"` — expect ZERO matches.
  c) Confirm scripts/push-templates.sh still requires NO change: verify it discovers templates
     dynamically (`for dir in ... templates/*/`) and only special-cases `bbj-services` (grep for
     the case label) — so python-ai is auto-discovered with no --variable needs. Do NOT edit
     push-templates.sh; this is a confirmation only.
  d) `bash -n` any shell fragment is not applicable (no standalone .sh added), but if the
     JupyterLab coder_app fallback path was chosen in Task 2, extract nothing — terraform
     validate in Task 5 covers HCL. Report the audit result.
  </action>
  <verify>
    <automated>bash -c 'set -e; D=templates/python-ai/Dockerfile; M=templates/python-ai/main.tf; ! grep -nE "install|cp |ln -s|venv|--python" "$D" | grep -q "/home/coder"; ! grep -qiE "JAVA_HOME|MAVEN_HOME|apache-maven|adoptium|maven_version" "$D" "$M"; ! grep -qE "\"jdk\"|\"IU\"" "$M"; grep -q "templates/\*/" scripts/push-templates.sh; grep -q "bbj-services)" scripts/push-templates.sh; echo AUDIT_OK'</automated>
  </verify>
  <done>Self-audit passes: no Dockerfile toolchain line targets /home/coder; no Java/Maven residue in either file; push-templates.sh confirmed dynamic + unchanged (still only special-cases bbj-services).</done>
</task>

<task type="auto">
  <name>Task 5: Static Terraform + Dockerfile checks (runnable here); enumerate deferred live checks</name>
  <files>templates/python-ai/main.tf</files>
  <action>
Run every static check that IS runnable in this environment; explicitly SKIP-with-note anything
that needs the coder CLI or a running Coder server (deferred per project memory
"infra-needs-live-deploy-gate").

  1. `terraform fmt` on templates/python-ai/ — apply formatting (this is allowed to modify
     main.tf whitespace) then `terraform fmt -check` to confirm clean.
  2. `terraform validate`: terraform is installed (v1.15.7). To validate OFFLINE (no registry
     network), copy the already-resolved provider mirror + lock from the java template into the
     new dir so init needs no download:
       cp templates/java-fullstack/.terraform.lock.hcl templates/python-ai/.terraform.lock.hcl
       mkdir -p templates/python-ai/.terraform
       cp -a templates/java-fullstack/.terraform/providers templates/python-ai/.terraform/providers
     Then run `terraform -chdir=templates/python-ai init -backend=false -input=false` (module
     download for vscode-desktop/jupyterlab may fail offline — if so, re-run init with
     `-get=false` OR temporarily comment the two [LIVE-VERIFY] modules to validate the rest, then
     restore them; document whichever path was taken). Run `terraform -chdir=templates/python-ai
     validate`. Record PASS/FAIL. If module fetch blocks validate entirely offline, note
     `terraform validate` as PARTIAL/DEFERRED for the two unresolved modules and confirm the rest
     of the HCL validates.
     Clean up: leave the copied .terraform/ + lock in place ONLY if they do not get committed —
     add templates/python-ai/.terraform/ to nothing; instead rm -rf templates/python-ai/.terraform
     and templates/python-ai/.terraform.lock.hcl after validating so no mirror is committed
     (java-fullstack already tracks its own; do not duplicate).
  3. Dockerfile static lint: hadolint is NOT installed and `docker build --check` requires a
     build (network). If `command -v hadolint` is empty and no buildkit, SKIP with an explicit
     note. Do run `bash -n` on any inline heredoc shell is N/A. At minimum confirm the Dockerfile
     parses structurally via the Task 1 grep gate (already green).

  Then RESTATE the DEFERRED live-verification checklist (same items as the README) in the task
  output so the SUMMARY carries it: template push, per-version build, python/import checks, tool
  PATH checks, all four IDE/Jupyter buttons, module pin confirmation, Claude/MCP/GSD/MemPalace.
  The SUMMARY MUST reproduce this deferred checklist.
  </action>
  <verify>
    <automated>bash -c 'set -e; command -v terraform >/dev/null && terraform fmt -check templates/python-ai/ && echo FMT_OK || echo "FMT: run terraform fmt"; test ! -d templates/python-ai/.terraform && echo NO_MIRROR_COMMITTED; echo STATIC_DONE'</automated>
  </verify>
  <done>`terraform fmt -check` passes on templates/python-ai/; `terraform validate` run offline (PASS, or documented PARTIAL for the two [LIVE-VERIFY] modules if offline module fetch blocks them) with no .terraform mirror or lock left committed; hadolint/docker-build-check noted as SKIPPED (unavailable); the DEFERRED live-verification checklist is restated for the SUMMARY.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| build-time downloads → image | uv installer, uv-managed CPython, pip packages, apt repos (NodeSource, gh) pulled over HTTPS at image build |
| workspace container → Coder server | agent token + init_script; host.docker.internal rewrite for local access URL |
| owner-shared Claude volume | per-owner credentials/MCP config reused across workspaces |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-epv-01 | Tampering | uv / CPython / pip installs at build | mitigate | HTTPS sources (Astral installer, PyPI, NodeSource, cli.github.com); pin PYTHON_VERSION as build arg; deferred live build verifies `python -c "import anthropic, claude_agent_sdk"` |
| T-epv-02 | Elevation | toolchain baked into /home/coder | mitigate | Hard rule enforced by Task 4 self-audit: all installs to /opt or /usr, never /home/coder — the persistent volume must not shadow (or let a workspace user shadow) system tooling |
| T-epv-03 | Spoofing | git-over-SSH host verification | mitigate | SSH host-key seeding block carried over verbatim (github/gitlab/bitbucket/azure + accept-new) |
| T-epv-SC | Tampering | vscode-desktop / jupyterlab registry module pins | mitigate | [LIVE-VERIFY] pinned versions flagged in main.tf + README deferred checklist; shared modules (code-server/jetbrains-gateway/claude-code) use versions already resolved in java-fullstack/.terraform |
</threat_model>

<verification>
Static (runnable HERE): Task 1/2/3/4 grep gates; `terraform fmt -check`; offline
`terraform validate`; push-templates.sh unchanged confirmation; /home/coder-shadow self-audit.

DEFERRED live checks (require coder CLI + running Coder server — per project memory
"infra-needs-live-deploy-gate"; SUMMARY MUST restate):
  - `coder templates push python-ai` succeeds; workspace builds per python_version.
  - `python --version` matches selection; `python -c "import anthropic, claude_agent_sdk"` OK.
  - ruff/mypy/pytest/ipython/jupyter/uv/uvx on PATH.
  - IDE buttons open: code-server, VS Code Desktop, PyCharm (Gateway); JupyterLab app launches.
  - vscode-desktop + jupyterlab module source/version pins resolve (bump if newer).
  - Claude Code + webforJ MCP + MemPalace MCP + GSD present on owner-shared volume.
</verification>

<success_criteria>
- templates/python-ai/{Dockerfile,main.tf,README.md} exist and pass all static grep gates.
- python_version param (3.13/3.12/3.11) replaces jdk; PYTHON_VERSION drives image name/build_args/
  triggers; no Java/Maven residue anywhere.
- All Python toolchain installs land in /opt or /usr (self-audit green).
- code-server + vscode-desktop + jetbrains-gateway(PY) + claude-code + JupyterLab wiring present;
  Claude/MCP/GSD/MemPalace startup_script reused verbatim.
- Root README has a "### Python AI template" subsection; java-fullstack section intact.
- `terraform fmt -check` passes; `terraform validate` PASS (or documented PARTIAL for [LIVE-VERIFY]
  modules offline); no .terraform mirror committed.
- SUMMARY restates the DEFERRED live-verification checklist.
</success_criteria>

<output>
Create `.planning/quick/260815-epv-create-coder-python-ai-workspace-templat/260815-epv-SUMMARY.md` when done.
The SUMMARY MUST reproduce the DEFERRED live-verification checklist verbatim so the human knows
exactly what to run on a real Coder host before trusting the template.
</output>
