---
phase: quick-260618-h3d
plan: "01"
type: quick
subsystem: maintainer-env
tags: [gitignore, devcontainer, coder-template, terraform]
dependency_graph:
  requires: []
  provides:
    - .gitignore (project-appropriate Terraform/OS/editor/Coder noise rules)
    - .devcontainer/devcontainer.json (maintainer dev container with Docker+Terraform+shellcheck)
    - templates/coderscaffold/main.tf (CoderScaffold maintainer workspace template)
    - templates/coderscaffold/Dockerfile (workspace image mirroring templates/docker/)
  affects:
    - scripts/push-templates.sh (now discovers coderscaffold template)
tech_stack:
  added:
    - devcontainer feature: docker-outside-of-docker:1
    - devcontainer feature: terraform:1
  patterns:
    - WR-03 non-fatal startup_script pattern (idempotent git clone with || echo WARN)
    - Pin-everything: all provider/module versions match CLAUDE.md version matrix
key_files:
  created:
    - .devcontainer/devcontainer.json
    - templates/coderscaffold/main.tf
    - templates/coderscaffold/Dockerfile
  modified:
    - .gitignore
decisions:
  - keep-.terraform.lock.hcl-tracked: lock file is NOT ignored — committing it aids reproducibility, consistent with pin-everything ethos
  - devcontainer-base-kept: javascript-node:1-18-bullseye kept; it provides Node.js for GSD toolchain
  - shellcheck-via-postCreate: installed via apt in postCreateCommand (not a separate devcontainer feature) — simpler, no extra registry dependency
  - coderscaffold-mirrors-docker: templates/coderscaffold/main.tf is structurally identical to templates/docker/main.tf; only header comment, startup_script clone block, and editor folder differ
metrics:
  duration: ~12min
  completed: "2026-06-18"
  tasks_completed: 2
  files_changed: 4
---

# Phase quick-260618-h3d Plan 01: Maintainer Gitignore + Devcontainer + CoderScaffold Template Summary

**One-liner:** Project-appropriate `.gitignore`, rewritten maintainer `devcontainer.json` (Docker+Terraform+shellcheck), and new `templates/coderscaffold/` workspace template with idempotent CoderScaffold repo clone.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Update .gitignore and rewrite devcontainer.json | f0ff05d | `.gitignore`, `.devcontainer/devcontainer.json` |
| 2 | Add templates/coderscaffold/ maintainer template | dd53a2e | `templates/coderscaffold/main.tf`, `templates/coderscaffold/Dockerfile` |

## What Was Built

### Task 1: .gitignore + devcontainer.json

**`.gitignore`** — Extended from 3 entries to cover:
- Terraform local noise: `.terraform/`, `*.tfstate`, `*.tfstate.*`, `crash.log`, `crash.*.log`, `*.tfvars`, `*.tfvars.json`, `override.tf`, `override.tf.json`, `*_override.tf`, `*_override.tf.json`
- `.terraform.lock.hcl` is intentionally NOT ignored (comment explains reproducibility rationale)
- OS cruft: `.DS_Store`, `Thumbs.db`
- Editor scratch: `*.swp`, `*.swo`, `.idea/`, `*.code-workspace` (`.vscode/` left unignored — a repo may commit shared settings)
- Coder CLI local config: `.coderv2/`
- `.devcontainer/` is NOT ignored; `.devcontainer/devcontainer.json` and `.devcontainer/devcontainer-lock.json` pass `git check-ignore` as unignored

**`.devcontainer/devcontainer.json`** — Rewritten from generic Node.js project to CoderScaffold Maintainer:
- `name`: "CoderScaffold Maintainer"
- `image`: kept as `mcr.microsoft.com/devcontainers/javascript-node:1-18-bullseye` (provides Node.js for GSD)
- `features`: kept `ghcr.io/anthropics/devcontainer-features/claude-code:1.0` exactly; added `ghcr.io/devcontainers/features/docker-outside-of-docker:1` and `ghcr.io/devcontainers/features/terraform:1`
- `postCreateCommand`: replaced `npm install` with `sudo apt-get update && sudo apt-get install -y shellcheck || echo 'WARN: shellcheck install failed; continuing'`
- `mounts`: kept `source=claude-code-config,target=/home/node/.claude,type=volume` exactly
- JSONC `//` comment above features block notes that feature major pins are best-effort and resolved versions should be verified on first rebuild

### Task 2: templates/coderscaffold/

**`templates/coderscaffold/Dockerfile`** — Mirrors `templates/docker/Dockerfile` verbatim in structure:
- `ARG BASE_IMAGE=codercom/enterprise-base:ubuntu` / `FROM ${BASE_IMAGE}`
- Node.js LTS via NodeSource, USER root / USER coder pattern
- Updated header path comment; added confirmation comment that `git` ships in `codercom/enterprise-base:ubuntu`

**`templates/coderscaffold/main.tf`** — Structurally identical to `templates/docker/main.tf`:
- Same `terraform` required_providers block (`coder ~> 2.18`, `kreuzwerker/docker ~> 4.4`, `required_version = ">= 1.9"`)
- Same `docker_socket`, `workspace_image`, `anthropic_api_key` variables
- Same docker provider, three coder_* data sources, `locals`
- Same `coder_agent.main` with full per-owner Claude config symlink dance, GIT_* env, three metadata blocks
- Same `docker_volume.home_volume` with lifecycle `ignore_changes = [name]` and labels
- Same unmanaged per-owner claude volume comment block
- Same `docker_image.main` (build context = path.module, Dockerfile, BASE_IMAGE arg, filesha1 trigger, keep_locally)
- Same `docker_container.workspace` with count, entrypoint replace, host-gateway, BOTH volume mounts, labels
- Same `code-server` (1.5.0), `jetbrains-gateway` (1.2.6, IUs, default IU), `claude-code` (5.2.0, install_claude_code=true) modules with `count = start_count`

**Distinguishing changes only:**
1. Header comment block describes CoderScaffold maintainer template and repo-clone behavior
2. `startup_script`: added idempotent non-fatal git clone block after GSD block:
   - Guards: `[ ! -d "$HOME/CoderScaffold" ]` (idempotency) + `command -v git` (safety) + `|| echo "WARN: ..."` (WR-03 non-fatal)
   - Clones `https://github.com/StephanWald/CoderScaffold.git` into `$HOME/CoderScaffold`
3. `code-server` module: `folder = "/home/coder/CoderScaffold"` (absolute path; editors open the cloned repo)
4. `jetbrains-gateway` module: `folder = "/home/coder/CoderScaffold"` (absolute path per Pitfall 4)

**push-templates.sh discovery:** `templates/coderscaffold/` contains a `.tf` file, so the push script's `for dir in templates/*/` loop will discover it and push it as template name `coderscaffold`.

## Static Verification Results

| Check | Result |
|-------|--------|
| `git check-ignore .devcontainer/devcontainer.json` | PASS: NOT ignored |
| `git check-ignore .devcontainer/devcontainer-lock.json` | PASS: NOT ignored |
| `git check-ignore foo.tfstate` | PASS: ignored |
| `git check-ignore .terraform/x` | PASS: ignored |
| `git check-ignore .DS_Store` | PASS: ignored |
| `git check-ignore .coderv2/config` | PASS: ignored |
| `git check-ignore .terraform.lock.hcl` | PASS: NOT ignored (intentional) |
| `jq` shape check (name, postCreate, claude-code feature, mount) | PASS |
| files exist: main.tf + Dockerfile | PASS |
| idempotent non-fatal clone (grep) | PASS |
| editors folder = /home/coder/CoderScaffold | PASS |
| version pins (coder ~> 2.18, docker ~> 4.4, 5.2.0, 1.5.0, 1.2.6) | PASS |
| terraform fmt/validate | SKIP — terraform not installed in this dev environment |

## LIVE VERIFICATION DEFERRED

The following could NOT be verified statically and MUST be verified in a live environment before relying on this work in production:

| Item | What to verify | Risk if skipped |
|------|---------------|-----------------|
| **devcontainer rebuild** | Run `Dev Containers: Rebuild Container` in VS Code; confirm features resolve without error; confirm `docker compose version`, `terraform version`, `shellcheck --version` all work inside the container | Feature version pins (`:1`) may resolve to broken releases; shellcheck apt install may fail on the specific bullseye image |
| **devcontainer-lock.json sync** | After rebuild, run `devcontainer upgrade --workspace-folder .` and commit the updated lock if new features resolved | The lock only covers claude-code today; docker-outside-of-docker and terraform resolved digests are not locked |
| **`coder templates push coderscaffold`** | Run `scripts/push-templates.sh` (or `coder templates push --directory templates/coderscaffold --name coderscaffold`) against a live Coder server; confirm no Terraform provider errors | Provider init may fail if Coder registry is unreachable; kreuzwerker/docker 4.4 module signature must be accepted |
| **Workspace provisioning** | Create a workspace from the `coderscaffold` template; confirm the container starts, the Coder agent connects, and the startup_script runs without errors | `set -e` + missing sudo/tools could abort startup; Node.js layer build may fail if NodeSource CDN changes |
| **On-start git clone** | After workspace start, confirm `~/CoderScaffold` exists and contains the repo; confirm `code --folder-uri` opens it in VS Code; confirm JetBrains Gateway opens to that path | Clone may fail if GitHub is unreachable or repo visibility changes; editors open the path before it exists if startup_script hasn't finished |
| **terraform fmt/validate** | Run `terraform -chdir=templates/coderscaffold fmt -check` and `terraform init && terraform validate` in a Terraform-capable environment | HCL formatting drift or provider schema mismatch would block `coder templates push` |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All resources are wired. The CoderScaffold clone path (`/home/coder/CoderScaffold`) is non-empty after startup_script runs; editors open it at runtime, not at template provision time, which is the correct behavior.

## Self-Check: PASSED

- `f0ff05d` exists: confirmed (`git log --oneline -3` shows `f0ff05d chore(quick-260618-h3d): ...`)
- `dd53a2e` exists: confirmed (`git log --oneline -3` shows `dd53a2e feat(quick-260618-h3d): ...`)
- `.gitignore` modified: confirmed
- `.devcontainer/devcontainer.json` created: confirmed
- `templates/coderscaffold/main.tf` created: confirmed
- `templates/coderscaffold/Dockerfile` created: confirmed
