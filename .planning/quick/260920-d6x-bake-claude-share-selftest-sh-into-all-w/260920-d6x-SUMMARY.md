---
phase: quick-260920-d6x
plan: 01
subsystem: templates
tags: [claude-shared-volume, mempalace, self-test, coder-app, push-staging, devcontainer]
requires: []
provides:
  - canonical claude-share-selftest.sh at scripts/ (0755)
  - self-test baked at /usr/local/bin/claude-share-selftest in six public template images
  - "Self-Test" command-type coder_app button in six public templates
  - selftest_sha1 image-rebuild trigger keyed on the push-staged script copy
  - GSD mempalace.enabled auto-flip for cloned GSD-managed repos (five templates)
  - mempalace CLI + MCP registration in the operator devcontainer
affects: [push-templates.sh, all six public templates, .devcontainer]
tech-stack:
  added: []
  patterns:
    - push-time asset staging into template build contexts (jars.json idiom extended)
    - try(filesha1(...)) trigger for gitignored push-staged files
key-files:
  created:
    - scripts/claude-share-selftest.sh
  modified:
    - scripts/push-templates.sh
    - .gitignore
    - templates/coderscaffold/Dockerfile
    - templates/coderscaffold/main.tf
    - templates/docker/Dockerfile
    - templates/docker/main.tf
    - templates/flutter/Dockerfile
    - templates/flutter/main.tf
    - templates/java-fullstack/Dockerfile
    - templates/java-fullstack/main.tf
    - templates/python-ai/Dockerfile
    - templates/python-ai/main.tf
    - templates/research/Dockerfile
    - templates/research/main.tf
    - .devcontainer/devcontainer.json
decisions:
  - "Self-Test coder_app placed at end of each main.tf with the next free order (coderscaffold/docker/java-fullstack: 3, flutter: 4, python-ai/research: 5); share=\"owner\" accepted by provider on command apps (terraform validate PASS)"
  - "Staging auto-scopes by grepping each template Dockerfile for the literal filename — bbj-services never staged, no hardcoded template list to drift"
  - "MCP registration inlined in the devcontainer postCreateCommand (node merge into ~/.claude.json) — proved trivially expressible, smoke-tested against a scratch HOME"
metrics:
  duration: ~15 min
  completed: 2026-09-20
status: complete
commits: 3
plan_head_before: 73ec68d33362b92a3167d46227903b5aadbb8828
actuals:
  tokens: 9854
  tasks: 3
  commits: 3
---

# Quick Task 260920-d6x: Bake claude-share-selftest.sh into all workspace templates Summary

Shared-Claude/MemPalace self-test baked at /usr/local/bin in all six public templates with a "Self-Test" web-terminal button, push-time staging + rebuild trigger, GSD mempalace.enabled auto-flip for cloned GSD repos in five templates, and mempalace CLI+MCP in the operator devcontainer.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (tracer) | Canonical script + push staging + .gitignore | e929d07 | scripts/claude-share-selftest.sh, scripts/push-templates.sh, .gitignore |
| 2 | Bake into six Dockerfiles + Self-Test coder_app + trigger + Piece-2 config-set | 5c0783c | 12 files (six Dockerfile + six main.tf) |
| 3 | Operator devcontainer mempalace CLI + MCP registration | 979979d | .devcontainer/devcontainer.json |

## What was built

**Piece 1 — self-test everywhere.** `scripts/claude-share-selftest.sh` is a verbatim copy of the validated source (cmp-verified, 0755); modes `plumbing|seed|knowledge|mempalace|all|cleanup`, exit 0 = all pass. `push-templates.sh` gained `_stage_selftest_script` (called right after `_generate_jars_json`): it copies the canonical script into every template dir whose Dockerfile references `claude-share-selftest.sh` — auto-scoping to exactly the six wired templates, never bbj-services — warn-and-continue if the source is missing (WR-03). The staged per-template copies are gitignored (`templates/*/claude-share-selftest.sh`, sibling of the jars.json rule). Each of the six Dockerfiles COPYs the staged script to `/usr/local/bin/claude-share-selftest` + `chmod 0755` immediately before the final `USER coder` (system path — volume-shadowed /home/coder cannot hide it). Each `docker_image.main` triggers map adds `selftest_sha1 = try(filesha1("${path.module}/claude-share-selftest.sh"), "")` so a script-content change forces an image rebuild; `try()` tolerates the copy's absence during local validate. Each main.tf gained a command-type `coder_app "self_test"` (slug `self-test`, `/icon/terminal.svg`, `share = "owner"`, count-gated on start_count, next-free order) that opens a web terminal running `claude-share-selftest all`.

**Piece 2 — GSD MemPalace on by default for cloned GSD repos.** Five templates (coderscaffold, flutter, java-fullstack, python-ai, research; docker excluded — clones no project) gained a startup_script step directly after `mempalace init`: guarded on `gsd-tools.cjs` existing on the shared ~/.claude volume AND `.planning/config.json` in the project dir (`$PROJECT_DIR`, or `$HOME/CoderScaffold` for coderscaffold), config-get first (skip-if-already-true), config-set non-fatal with WARN fallback. Disclosed trade-off (dirtying the cloned repo's working tree) documented in a code comment.

**Piece 3 — operator devcontainer.** `postCreateCommand` extended (single chained string, JSONC preserved): python3-guarded venv install of mempalace at `$HOME/.mempalace-venv` symlinked to `/usr/local/bin/mempalace`, then a node merge of `mcpServers.mempalace = {command:"mempalace", args:["mcp","serve"]}` into `~/.claude.json`. Both steps warn-and-continue. The MCP merge snippet was extracted from the committed JSON and executed against a scratch HOME — produced correct output.

## Verification (static gates — all PASS)

- `bash -n` on scripts/claude-share-selftest.sh + scripts/push-templates.sh
- `terraform fmt -check` AND `terraform init -backend=false` + `terraform validate` on all six templates (with the staged script absent — try() yields "")
- devcontainer.json parses as JSON after JSONC comment stripping; embedded postCreateCommand passes `bash -n`; MCP merge smoke-tested
- Negative gate: zero `claude-share-selftest` matches under templates/bbj-services/
- Lockfiles unchanged; no file deletions; no new untracked repo files

## Deviations from Plan

None - plan executed exactly as written. (`share = "owner"` on command apps was flagged risky by precedent 260902-kio but terraform validate confirmed the provider accepts it, so the plan's literal spec was kept.)

## LIVE VERIFICATION CHECKLIST (operator, deferred per infra-needs-live-deploy-gate)

- [ ] Run `scripts/push-templates.sh` on the host — confirm "claude-share-selftest.sh staged: 6 template dir(s) updated"
- [ ] Rebuild one workspace per changed template; click **Self-Test** → web terminal runs `claude-share-selftest all`, exit 0
- [ ] Edit the script content, re-push → confirm `selftest_sha1` forces an image rebuild on next workspace start
- [ ] Open a rebuilt workspace with a cloned GSD repo → `.planning/config.json` has `mempalace.enabled: true`
- [ ] Rebuild the devcontainer → `mempalace` on PATH and `mcpServers.mempalace` in `~/.claude.json`

## Self-Check: PASSED

- scripts/claude-share-selftest.sh: FOUND (0755)
- All 16 changed files present; commits e929d07, 5c0783c, 979979d FOUND in git log
- `git rev-list --count 73ec68d..HEAD` = 3 (matches frontmatter `commits: 3`)
