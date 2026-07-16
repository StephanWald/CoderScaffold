---
phase: quick-260716-afr
plan: 01
subsystem: workspace-templates
tags: [docker, gh-cli, workspace-images, parity]
dependency-graph:
  requires: []
  provides:
    - "gh CLI baked into all four public workspace images"
  affects:
    - templates/docker/Dockerfile
    - templates/coderscaffold/Dockerfile
    - templates/java-fullstack/Dockerfile
    - templates/bbj-services/Dockerfile
tech-stack:
  added:
    - "GitHub CLI (gh) via official cli.github.com apt repo"
  patterns:
    - "Root-context apt install block placed immediately before final USER coder"
key-files:
  created: []
  modified:
    - templates/docker/Dockerfile
    - templates/coderscaffold/Dockerfile
    - templates/java-fullstack/Dockerfile
    - templates/bbj-services/Dockerfile
decisions:
  - "Copied the gh install block byte-for-byte from the private template-dev
    reference (lines 46-57) rather than retyping, per plan instruction, to
    guarantee identical behavior across all five images (four public + one
    private)."
metrics:
  duration: "~10 minutes"
  completed: 2026-07-16
---

# Phase quick-260716-afr Plan 01: Add GitHub CLI (gh) to all four workspace images Summary

GitHub CLI (`gh`) installed at build time in all four public workspace
Dockerfiles via the official `cli.github.com` apt repo, arch-aware, matching
the private `template-dev` reference byte-for-byte.

## What Was Built

Inserted an identical, self-contained `RUN` block into each of the four
public workspace Dockerfiles:

- `templates/docker/Dockerfile` — after the Node.js RUN, before `USER coder`
- `templates/coderscaffold/Dockerfile` — after the MemPalace RUN, before `USER coder`
- `templates/java-fullstack/Dockerfile` — after the MemPalace RUN, before `USER coder`
- `templates/bbj-services/Dockerfile` — in the `final` stage, after `EXPOSE 8888`,
  before `USER coder` (not in `base` or `bbjinstall` stages)

The block:
1. Creates `/etc/apt/keyrings` (mode 755)
2. Downloads and installs the GitHub CLI archive keyring
3. Registers the `cli.github.com/packages` apt repo (arch-aware via `dpkg --print-architecture`)
4. Installs `gh` via `apt-get install -y --no-install-recommends gh`
5. Cleans apt caches (`apt-get clean`, `rm -rf /var/lib/apt/lists/*`)

Authentication is per-user at workspace runtime (`gh auth login`); the token
persists in `~/.config/gh` on the home volume — no credentials baked into the
image.

## Task Commit

| Task | Description | Commit |
|------|--------------|--------|
| 1 | Insert gh install block before USER coder in all four Dockerfiles | `7452918` |

## Verification

- `git diff` on all four files shows only additions (54 insertions, 0 deletions) — confirmed via `git diff --stat` and `git diff --diff-filter=D`.
- The inserted block is byte-identical across all four files and matches the private `template-dev` reference exactly (verified via `md5` checksum of the block in all five files — all four checksums equal the reference checksum `64f660e0b4c00e8c9438cc0420939ef3`).
- `USER coder` remains the final line in all four Dockerfiles.
- `templates/bbj-services/Dockerfile`: confirmed the gh block appears only after `FROM base AS final` (line 196) and `EXPOSE 8888`, not in the `base` or `bbjinstall` stages.
- No `main.tf` files were touched — `docker_image.triggers.dockerfile_sha1` will pick up the Dockerfile content change automatically on next `terraform apply` / template push.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- FOUND: templates/docker/Dockerfile (contains gh block)
- FOUND: templates/coderscaffold/Dockerfile (contains gh block)
- FOUND: templates/java-fullstack/Dockerfile (contains gh block)
- FOUND: templates/bbj-services/Dockerfile (contains gh block, final stage only)
- FOUND: commit 7452918
