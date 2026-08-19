---
phase: quick-260819-dq6
plan: "01"
subsystem: templates/java-fullstack
status: complete
tags:
  - dockerfile
  - graalvm
  - native-image
  - java-fullstack
dependency_graph:
  requires: []
  provides:
    - zlib1g-dev system-wide in java-fullstack workspace image
  affects:
    - templates/java-fullstack/Dockerfile
tech_stack:
  added:
    - "zlib1g-dev (apt, system-wide under /usr)"
  patterns:
    - "Dedicated apt block per logical purpose: box-drawing header + prose comment + chained apt-get update/install/clean/rm idiom"
key_files:
  modified:
    - templates/java-fullstack/Dockerfile
decisions:
  - "Dedicated block (not folded into MemPalace or Node block) — file uses one-purpose-per-block convention; folding would bury a native-linker dependency under an unrelated header"
  - "Placed after MemPalace block and before GitHub CLI block — among root-owned system blocks, after USER root and before final USER coder"
metrics:
  duration: "2 min"
  completed: "2026-08-19"
  tasks: 1
  commits: 1
actuals:
  tokens: 3000
  tasks: 1
  commits: 1
---

# Phase quick-260819-dq6 Plan 01: Add zlib1g-dev to java-fullstack Dockerfile Summary

**One-liner:** Added dedicated `zlib1g-dev` apt block to java-fullstack Dockerfile so GraalVM `native-image` can resolve the `-lz` linker dependency via the `/usr/lib/x86_64-linux-gnu/libz.so` dev symlink.

## What Was Built

A dedicated apt install block for `zlib1g-dev` was inserted into `/workspaces/coder/templates/java-fullstack/Dockerfile` between the MemPalace CLI block (line 126) and the GitHub CLI block. The block follows the file's existing idiom:

- Box-drawing `# ── zlib (libz.so dev symlink for GraalVM native-image) ──` header
- 5-line prose comment explaining: base image ships `libz.so.1` runtime but not the dev symlink; GraalVM `native-image` passes `-lz` to the linker; `zlib1g-dev` provides the dev symlink; installs to `/usr` (outside the volume-shadowed `/home/coder` mount)
- Chained `RUN apt-get update && apt-get install -y --no-install-recommends zlib1g-dev && apt-get clean && rm -rf /var/lib/apt/lists/*` command

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Add zlib1g-dev apt block to java-fullstack Dockerfile | 7ea9782 | templates/java-fullstack/Dockerfile |

## Verification

Static verification passed (image build is a live-deploy concern deferred per the "Infra needs a live deploy gate" project memory):

1. `grep -n 'zlib1g-dev' templates/java-fullstack/Dockerfile` — found on lines 132 and 136
2. `grep -c 'native-image' templates/java-fullstack/Dockerfile` — count: 2 (header comment + prose comment)
3. `grep -q 'apt-get install -y --no-install-recommends zlib1g-dev' templates/java-fullstack/Dockerfile && echo PLACEMENT_OK` — PLACEMENT_OK

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- `/workspaces/coder/templates/java-fullstack/Dockerfile` modified: FOUND
- Commit `7ea9782` exists: FOUND
- `zlib1g-dev` in Dockerfile: FOUND (lines 132, 136)
- `native-image` mention in Dockerfile: FOUND (count: 2)
- Block placed after MemPalace, before GitHub CLI: CONFIRMED
- Block installs to `/usr` (not `/home/coder`): CONFIRMED
