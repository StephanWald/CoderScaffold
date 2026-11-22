---
phase: quick-261122-cs3
plan: 01
subsystem: workspace-templates
tags: [herdr-core, hc, dockerfile, templates]
requires: []
provides:
  - herdr-core (hc) 0.1.21 baked at /usr/local/bin in all 7 public template images
affects: [templates/*/Dockerfile, README.md]
tech-stack:
  added: [herdr-core 0.1.21]
  patterns: [ARG-pinned vendor installer, download-then-run with version assertion]
key-files:
  created: []
  modified:
    - templates/docker/Dockerfile
    - templates/bbj-services/Dockerfile
    - templates/coderscaffold/Dockerfile
    - templates/flutter/Dockerfile
    - templates/java-fullstack/Dockerfile
    - templates/python-ai/Dockerfile
    - templates/research/Dockerfile
    - README.md
decisions:
  - "Download-then-run installer (not piped) because dash has no pipefail"
  - "HC_INSTALL_DIR=/usr/local/bin so hc sits outside the volume-shadowed /home/coder"
metrics:
  duration: ~10m
  completed: 2026-11-22
status: complete
actuals:
  tokens: 6000
  tasks: 3
  commits: 3
plan_head_before: 0f7944f37946ef94486851516ae39a6d7a010cba
plan_head_after: c5ee0b3bd3b48670e771830214ed95ac37c45a9a
---

# Phase quick-261122-cs3 Plan 01: herdr-core (hc) in every template Summary

One byte-identical, ARG-pinned (`HC_VERSION=0.1.21`) herdr-core block installed system-wide to /usr/local/bin in all 7 public template Dockerfiles, with the README herdr paragraph documenting the preinstalled hc, its pin and the upgrade path.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Canonical block in templates/docker + real image build proving coder can run hc | 520cc59 |
| 2 | bbj-services (final stage), coderscaffold, flutter | 848aaae |
| 3 | java-fullstack, python-ai, research + README herdr paragraph | c5ee0b3 |

## Verification

- Task 1 tracer: real `docker build --no-cache` of the exact block on codercom/enterprise-base:ubuntu succeeded; build log shows install into /usr/local/bin/herdr-core, `hc 0.1.21`, and `/usr/local/bin/hc` as the coder user. TRACER-OK.
- Fleet gate: placed=7, unique=1 (region between Codex RUN and final `USER coder` byte-identical), one `ARG HC_VERSION=` and one `USER coder` per file, `docker build --check` clean x7.
- README gate: mentions /usr/local/bin/hc and HC_VERSION, keeps the `hc machine add` line, no private template names.
- Live deploy gate (operator, not run here): push-templates.sh, rebuild a docker and a bbj-services workspace, check `hc --version`, then `hc machine add` from the laptop.

## Deviations from Plan

None - plan executed exactly as written. main.tf untouched.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

Commits 520cc59, 848aaae, c5ee0b3 present; all 7 Dockerfiles and README.md modified as listed.
