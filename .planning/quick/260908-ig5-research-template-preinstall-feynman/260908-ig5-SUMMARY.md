---
quick_id: 260908-ig5
slug: research-template-preinstall-feynman
status: complete
date: 2026-09-08
phase: quick-260908-ig5
plan: 01
tasks_completed: 3
tasks_total: 3
commits: 1
plan_head_before: 7f69c0418be6a5454d0947ad6cff9e0aa72d0595
actuals:
  tokens: 11000
  tasks: 3
  commits: 1
---

# Phase quick-260908-ig5 Plan 01: Research Template with Feynman Preinstall Summary

New `templates/research/` workspace template — python-ai copy with Feynman (@companion-ai/feynman) npm -g system-path install layer added, identity comments updated, README rewritten for the research use case.

## What Was Done

### Task 1: Copy python-ai → research; add Feynman npm -g install layer

Copied `templates/python-ai/` to `templates/research/` (cp -a, preserving `.terraform.lock.hcl`). Added a new root-USER RUN layer in the Dockerfile immediately before `USER coder`, positioned after the Node.js LTS layer (setup_lts.x, line 28). The Feynman layer:

- Comment block explains: what Feynman is (open-source AI research agent), why npm -g (system path /usr/lib/node_modules, outside /home/coder volume), why the curl installer is NOT used (targets ~/.local — volume-shadowed), and that Node 24.x from the layer above satisfies >=22.22.0 <26.
- Single RUN with `set -eux`: `npm install -g @companion-ai/feynman` then `feynman --version` (fail-fast if package broken or renamed).
- Does NOT run `feynman setup` or `feynman serve` at build time.

### Task 2: Update main.tf + Dockerfile identity comments

Updated only the header/identity comment blocks — no resource, module, data, variable, local, or startup_script logic changed:

- `templates/python-ai/main.tf` → `templates/research/main.tf`; summary describes the research template; Feynman added as a bullet (`@companion-ai/feynman` + first-run/workbench pattern) in the "pre-loaded with" list.
- `templates/python-ai/Dockerfile` → `templates/research/Dockerfile`; top summary updated to note the Feynman research agent is layered on top.
- `terraform fmt -check main.tf` passes (comment-only edits, no HCL structure changed).

### Task 3: Rewrite README.md

README retitled "Research Workspace Template". Changes from the python-ai README:

- Intro: describes python-ai toolchain + Feynman, aimed at research projects.
- "What it provides" list: all python-ai bullets kept; Feynman bullet added (reads papers, web search, research drafts, experiment planning, citations; npm -g install → system PATH from first login).
- New "Using Feynman" section: `feynman setup` (interactive wizard, persists on home volume, NOT at build time) + `feynman serve` (local workbench server + authenticated localhost URL; `--no-auth` for plain URL; no coder_app button — default port undocumented; access via `coder port-forward <workspace> --tcp <port>:<port>` from local machine).
- "/opt rationale" extended: Feynman follows the same rule as uv/CPython; curl installer targets ~/.local (volume-shadowed → vanishes); npm -g is correct.
- Push instructions updated: `coder templates push research`, `coder templates edit research` with Feynman in description; note that `./scripts/push-templates.sh` auto-discovers templates/research/ with no edits and no --variable flags.
- DEFERRED LIVE-VERIFICATION CHECKLIST: all python-ai items (adjusted to `research` template name) plus four Feynman-specific items.

## Verification Results

All automated checks from the plan passed:

| Check | Result |
|-------|--------|
| `test -f templates/research/main.tf` | PASS |
| `test -f templates/research/Dockerfile` | PASS |
| `test -f templates/research/README.md` | PASS |
| `grep 'npm install -g @companion-ai/feynman' Dockerfile` | PASS |
| `grep 'feynman --version' Dockerfile` | PASS |
| `! grep 'feynman.is/install' Dockerfile` | PASS |
| `grep 'setup_lts.x' Dockerfile` (Node.js layer present) | PASS |
| Node.js layer (line 28) before Feynman layer (line 292) | PASS |
| `terraform fmt -check main.tf` | PASS |
| `grep '# templates/research/main.tf' main.tf` | PASS |
| `grep '# templates/research/Dockerfile' Dockerfile` | PASS |
| `grep -i 'feynman' main.tf` | PASS |
| `grep 'python_version' main.tf` | PASS |
| Image name uses `coder_workspace.me.id` | PASS |
| `grep -i 'feynman' README.md` | PASS |
| `grep 'feynman setup' README.md` | PASS |
| `grep 'feynman serve' README.md` | PASS |
| `grep 'port-forward' README.md` | PASS |
| `grep 'templates push research' README.md` | PASS |
| `! grep 'feynman.is/install' README.md` | PASS |
| `git status` — only `templates/research/` modified | PASS |
| `templates/python-ai/` unchanged | PASS |
| `scripts/push-templates.sh` unchanged | PASS |

## Deviations from Plan

**1. [Rule 1 - Bug] Comment wording adjusted to avoid false-positive in verify check**

- Found during: Task 1
- Issue: The initial comment text included `feynman.is/install` literally, causing `! grep -q 'feynman.is/install' Dockerfile` to fail (the check detects the curl installer pattern). The comment was documenting WHY the curl installer is not used, but the grep can't distinguish documentation from usage.
- Fix: Reworded to reference the curl pattern differently (`curl -fsSL https://feynman.is | bash` without the `/install` suffix), which accurately conveys the same information without triggering the check.
- Files modified: `templates/research/Dockerfile`
- Commit: 824b9a3

## Deferred Live Verification Gate

Per project memory "infra-needs-live-deploy-gate": static HCL validation passes; real verification requires a running Coder server:

- `./scripts/push-templates.sh` or `coder templates push research --directory templates/research/ -y` succeeds
- Workspace builds for python_version 3.13, 3.12, 3.11
- All python-ai capabilities work (editors, JupyterLab, Claude Code + MCP + GSD, MemPalace, DooD, tmux)
- `feynman --version` succeeds in a fresh login shell (system PATH; not shadowed by home volume)
- `feynman setup` config persists across workspace stop/start
- `feynman serve` workbench reachable via `coder port-forward` on the port it prints

## Known Stubs

None — the template is a complete, self-consistent copy of python-ai with the Feynman layer added. No placeholder data flows to any UI. The deferred live-verification checklist is an explicit, documented gate (not a stub).

## Self-Check: PASSED

- `templates/research/main.tf`: present, verified
- `templates/research/Dockerfile`: present, verified
- `templates/research/README.md`: present, verified
- `templates/research/.terraform.lock.hcl`: present (copied from python-ai)
- Commit 824b9a3: confirmed via `git log`
- `templates/python-ai/` and `scripts/push-templates.sh`: unmodified, confirmed via git status
