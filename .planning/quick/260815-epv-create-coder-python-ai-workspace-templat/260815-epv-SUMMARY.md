---
phase: quick-260815-epv
plan: "01"
subsystem: workspace-templates
tags: [coder, terraform, python, ai, jupyterlab, docker, workspace-template]
status: complete

dependency_graph:
  requires: []
  provides:
    - templates/python-ai/Dockerfile
    - templates/python-ai/main.tf
    - templates/python-ai/README.md
    - README.md (python-ai section)
  affects:
    - scripts/push-templates.sh (auto-discovers; unchanged)

tech_stack:
  added:
    - uv (Astral) system-wide Python toolchain manager — /usr/local/bin/uv + uvx
    - CPython (build-arg 3.13/3.12/3.11) — installed to /opt/uv-python via uv
    - ruff/mypy/pytest/ipython/jupyterlab — uv tool installs; shims in /usr/local/bin
    - anthropic + claude-agent-sdk — pip-installed into the build-arg CPython
    - vscode-desktop module @ 1.1.0 (LIVE-VERIFY resolved: module exists on registry)
    - jupyterlab module @ 1.1.0 (LIVE-VERIFY resolved: module exists on registry)
  patterns:
    - Structural clone of java-fullstack: same Claude/MCP/GSD/MemPalace startup_script verbatim
    - /opt isolation: all toolchain installs to /opt/uv-python, /opt/uv-tools, /usr/local/bin
    - python_version coder_parameter (build-time, mutable=true) replaces jdk
    - UV_* env vars in agent env for non-login-shell parity (mirrors JAVA_HOME pattern)

key_files:
  created:
    - templates/python-ai/Dockerfile
    - templates/python-ai/main.tf
    - templates/python-ai/README.md
  modified:
    - README.md (added ### Python AI template subsection after ### Java full-stack template)

decisions:
  - "uv pip --python /usr/local/bin/python for AI SDKs: targets the exact build-arg CPython (no --system, no separate venv activation needed)"
  - "jupyterlab module path (primary) vs coder_app fallback: module confirmed live at registry.coder.com/coder/jupyterlab/coder@1.1.0; fallback commented in main.tf for documentation"
  - "vscode-desktop@1.1.0 confirmed live at registry.coder.com/coder/vscode-desktop/coder; terraform validate PASS"
  - "MemPalace venv at /opt/mempalace uses system python3-venv (apt) not uv, matching java-fullstack pattern exactly"
  - "Comment in main.tf mentioning JAVA_HOME/MAVEN_HOME by name (prose only) was caught by Task 4 self-audit grep gate and reworded — Rule 1 auto-fix"

metrics:
  duration: ~25min
  completed: "2026-08-15T10:48:07Z"
  tasks_completed: 5
  files_created: 3
  files_modified: 1
---

# Phase quick-260815-epv Plan 01: Python AI Workspace Template Summary

**One-liner:** Python/AI Coder workspace template — uv-managed CPython (3.13/3.12/3.11), ruff/mypy/pytest/ipython/JupyterLab, anthropic + claude-agent-sdk, VS Code + PyCharm + JupyterLab IDE buttons, Claude/MCP/GSD/MemPalace verbatim from java-fullstack.

## What Was Built

Created `templates/python-ai/` as a near-structural clone of `templates/java-fullstack/` with the Java/Maven toolchain replaced by a Python/AI stack. The template auto-registers via `scripts/push-templates.sh` (no script changes needed — it discovers any `templates/*/` subdir with a `.tf` file).

### templates/python-ai/Dockerfile

- `ARG PYTHON_VERSION=3.13` replaces `ARG JDK` / `ARG MAVEN_VERSION`
- uv (Astral) installed to `/usr/local/bin` via the standalone installer
- `/etc/profile.d/10-uv.sh` exports `UV_PYTHON_INSTALL_DIR=/opt/uv-python`, `UV_TOOL_DIR=/opt/uv-tools`, `UV_TOOL_BIN_DIR=/usr/local/bin`
- `uv python install ${PYTHON_VERSION}` installs CPython to `/opt/uv-python`; `/usr/local/bin/python3` and `/usr/local/bin/python` symlinked to the installed interpreter
- ruff, mypy, pytest, ipython, jupyterlab installed via `uv tool install` with shims in `/usr/local/bin`
- `uv pip install --python /usr/local/bin/python anthropic claude-agent-sdk`; build-time import verified with `python -c "import anthropic; import claude_agent_sdk; print('AI SDK import OK')"`
- Node.js LTS, MemPalace (`/opt/mempalace` venv + `/usr/local/bin/mempalace` symlink), GitHub CLI (gh), SSH host-keys (github/gitlab/bitbucket/azure + accept-new) — all **carried verbatim** from java-fullstack
- All toolchain paths: `/opt/uv-python`, `/opt/uv-tools`, `/usr/local/bin` — NEVER `/home/coder`
- Ends with `USER coder`

### templates/python-ai/main.tf

- `data.coder_parameter.python_version` (order 2, mutable=true, `/icon/python.svg`, options 3.13/3.12/3.11) replaces `data.coder_parameter.jdk`
- `docker_image.main` name: `coder-${workspace_id}-workspace-${python_version}`; build_args: `BASE_IMAGE` + `PYTHON_VERSION`; triggers include `python_version`
- Agent env: drops JAVA_HOME/MAVEN_HOME; adds `UV_PYTHON_INSTALL_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR` for non-login-shell parity
- `maven_version` variable removed entirely
- Startup script: full Claude config symlink dance, CLAUDE_CONFIG_DIR migration, bypassPermissions, webforJ MCP, MemPalace MCP, GSD install, optional git clone, MemPalace init — **all verbatim from java-fullstack**
- Modules: `code-server@1.5.0` (order 1), `vscode-desktop@1.1.0` [LIVE-VERIFY, confirmed live] (order 2), `jetbrains-gateway@1.2.6` with `jetbrains_ides=["PY"]` / `default="PY"` (order 3), `jupyterlab@1.1.0` [LIVE-VERIFY, confirmed live] (order 4), `claude-code@5.2.0`
- Commented `coder_app` fallback block for JupyterLab included for documentation

### templates/python-ai/README.md

- Feature list, /opt isolation rationale, SSH clone notes, push + `coder templates edit` commands
- **DEFERRED LIVE-VERIFICATION CHECKLIST** section (see below)

### README.md

- Added `### Python AI template` subsection after `### Java full-stack template` under `## Workspace Template`
- Push and edit commands; pointer to `templates/python-ai/README.md`

## Verification Results

| Gate | Result |
|------|--------|
| Task 1 grep gate (Dockerfile) | PASS |
| Task 2 grep gate (main.tf) | PASS |
| Task 3 grep gate (READMEs) | PASS |
| Task 4 self-audit (no /home/coder, no Java residue, push-templates.sh unchanged) | PASS |
| `terraform fmt -check templates/python-ai/` | PASS (FMT_OK) |
| `terraform validate` (online; all modules resolved) | PASS |
| vscode-desktop@1.1.0 module resolved from registry | CONFIRMED LIVE |
| jupyterlab@1.1.0 module resolved from registry | CONFIRMED LIVE |
| No .terraform mirror committed | CONFIRMED (NO_MIRROR_COMMITTED) |
| hadolint / docker build --check | SKIPPED — hadolint not installed, no build environment |

`terraform validate` ran online (registry was reachable from this environment). All 5 modules resolved successfully including the two [LIVE-VERIFY]-marked pins. The .terraform/ directory and .terraform.lock.hcl were removed after validation — nothing is committed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Java-residue comment tripped Task 4 self-audit grep gate**
- **Found during:** Task 4 self-audit
- **Issue:** A prose comment in `templates/python-ai/main.tf` explaining the UV_* agent env variables mentioned "JAVA_HOME/MAVEN_HOME" by name for context ("same rationale as JAVA_HOME/MAVEN_HOME in java-fullstack"). The Task 4 audit grep checks for those literal strings in both files; the comment tripped the `! grep -qiE "JAVA_HOME|MAVEN_HOME|..."` gate.
- **Fix:** Reworded to "same rationale as toolchain homes in the java-fullstack template" — functionally equivalent prose, no forbidden tokens.
- **Files modified:** `templates/python-ai/main.tf`
- **Commit:** 3d3cc34

### Deviations from Plan (Non-Bug)

**terraform validate ran ONLINE, not offline:** The java-fullstack template has a `.terraform.lock.hcl` but no committed provider mirror (`.terraform/providers/` does not exist). With only the lock file, terraform downloaded providers from the internet and all 5 registry modules resolved (including the two [LIVE-VERIFY] pins). Result: `terraform validate` returned SUCCESS, not PARTIAL. The [LIVE-VERIFY] module warnings in code comments and the DEFERRED checklist remain — live workspace build verification is still required.

## DEFERRED LIVE-VERIFICATION CHECKLIST

The following checks MUST be run on a real Coder host with the `coder` CLI installed and a running Coder server before trusting this template in production. Per project memory: "Infra needs a live deploy gate."

- [ ] `coder templates push python-ai --directory templates/python-ai/ -y` succeeds
- [ ] Workspace builds for each python_version: 3.13, 3.12, and 3.11
- [ ] `python --version` output matches the selected python_version; `python -c "import anthropic, claude_agent_sdk"` succeeds in a fresh login shell
- [ ] `ruff`, `mypy`, `pytest`, `ipython`, `jupyter`, `uv`, and `uvx` are all on PATH
- [ ] IDE buttons appear and open correctly: VS Code (browser), VS Code Desktop, PyCharm Professional (JetBrains Gateway)
- [ ] JupyterLab app button appears in the workspace and launches JupyterLab successfully
- [ ] Confirm the vscode-desktop module (`registry.coder.com/coder/vscode-desktop/coder @ 1.1.0`) and jupyterlab module (`registry.coder.com/coder/jupyterlab/coder @ 1.1.0`) source/version pins resolve at push time; bump pins if the registry has newer versions or if either module does not exist (activate the commented `coder_app` fallback for JupyterLab)
- [ ] Claude Code, webforJ MCP server, MemPalace MCP server, and GSD are all present and functional in the owner-shared volume

## Known Stubs

None. The template is complete for static validation. All deferral is documented in the DEFERRED checklist above.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: build-time-download | templates/python-ai/Dockerfile | uv installer + CPython + pip packages (anthropic, claude-agent-sdk) + NodeSource + gh pulled over HTTPS at image build; matches T-epv-01 in plan threat model (accepted: HTTPS sources, build-arg pins PYTHON_VERSION) |

## Self-Check: PASSED

- [x] templates/python-ai/Dockerfile exists
- [x] templates/python-ai/main.tf exists
- [x] templates/python-ai/README.md exists
- [x] README.md python-ai section exists
- [x] Commits 7723aff, e921856, 69c71e4, 3d3cc34 exist in git log
- [x] No .terraform/ mirror committed to templates/python-ai/
