---
phase: quick-260920-osn
plan: "01"
subsystem: documentation
tags: [readme, bbj-services, documentation, operator-guide]
status: complete

dependency_graph:
  requires: []
  provides:
    - README BBj / BBjServices template operator documentation
  affects:
    - README.md

tech_stack:
  added: []
  patterns:
    - Operator runbook section matching existing README subsection style

key_files:
  created: []
  modified:
    - README.md

decisions:
  - Placed new subsection after Python AI template and before Docker Socket Permissions, matching plan placement spec
  - Used a table for required file contents (consistent with README style elsewhere)
  - Referenced the exact compose.yaml bind-mount syntax verbatim to ground the documentation
  - Omitted coder templates edit display-metadata boilerplate (not part of the BBj asset publish flow)

metrics:
  duration: "5 min"
  completed: "2026-09-20"
  tasks_completed: 1
  tasks_total: 1

actuals:
  tokens: 3500
  tasks: 1
  commits: 1
  plan_head_before: 02167b3104cb56df927cb5d62a872d8b05978840
---

# Phase quick-260920-osn Plan 01: Add BBj / BBjServices README Section Summary

One-liner: Added a `### BBj / BBjServices template` operator runbook section to README.md covering the asset folder layout, publish command, jars.json snapshot mechanism, and new-jar refresh workflow.

## What Was Done

Added a new `### BBj / BBjServices template` subsection to `README.md` under the `## Workspace Template` section, placed after the "Python AI template" subsection and before `### Docker Socket Permissions`.

The section covers:

1. **Purpose** — `templates/bbj-services/` builds a BBjServices workspace image from operator-supplied assets bind-mounted read-only into the coder service.

2. **Where the files go** — `bbj-assets/` at repo root (default `BBJ_ASSETS_PATH=./bbj-assets`), bind-mounted at `/mnt/bbj-assets:ro`. Operators may override `BBJ_ASSETS_PATH` in `.env`.

3. **Required file contents** — BBj installer `*.jar` files, `certificate.bls`, `playback.properties`. The `Dockerfile` is staged automatically by the publish script.

4. **Publishing** — `./scripts/push-templates.sh` (a) stages `templates/bbj-services/Dockerfile` into `bbj-assets/` to prevent image-context drift, and (b) generates `jars.json` (a sorted JSON array of `*.jar` basenames) into the template directory so Coder >= 2.25's dynamic-parameters form can populate the `bbj_installer` dropdown.

5. **Refresh note** — re-run `./scripts/push-templates.sh` after adding a new jar to regenerate `jars.json` and expose the new jar in the dropdown.

6. **Warn-and-continue behavior** — if `BBJ_ASSETS_PATH` is unset or contains no `*.jar` files, the script warns and skips `jars.json` generation without blocking other template pushes.

## Verification

All automated checks passed:

```
grep -n '### BBj / BBjServices template' README.md  -> line 593
grep -n '### Docker Socket Permissions' README.md    -> line 654
593 < 654 -- correct placement order confirmed
```

All required artifact references verified in the new section:
- `bbj-assets/`, `BBJ_ASSETS_PATH`, `/mnt/bbj-assets`, `jars.json`, `bbj_installer`, `certificate.bls`, `playback.properties`, `./scripts/push-templates.sh`

## Commits

| Hash | Message |
|------|---------|
| d9d1dde | docs(quick-260920-osn): add BBj / BBjServices template section to README |

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None -- this is a documentation-only change.

## Self-Check: PASSED

- README.md modified: FOUND (verified via git log)
- Commit d9d1dde exists: FOUND
- Section placement: BBj line 593 < Docker Socket line 654 -- CORRECT
- All 8 required artifact references present in the section
