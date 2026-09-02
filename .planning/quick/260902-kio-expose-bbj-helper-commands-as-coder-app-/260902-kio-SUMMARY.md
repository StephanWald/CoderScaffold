---
phase: quick-260902-kio
plan: 01
subsystem: templates
tags: [coder, terraform, bbj-dev, coder_app, ux]
status: complete
requires: []
provides:
  - "bbj-dev workspace UI: five clickable command-type coder_app buttons for the bbj-* dev-loop helpers"
affects: []
tech-stack:
  added: []
  patterns:
    - "command-type coder_app (command attr, no url/subdomain/share/healthcheck) opens a web terminal running the command"
    - "order attribute for priority-sorting workspace app buttons"
key-files:
  created: []
  modified:
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
decisions:
  - "Icons: /icon/java.svg (build, restart), /icon/code.svg (gwt), /icon/folder.svg (checkout), /icon/terminal.svg (test) — cosmetic, validated fine"
  - "Command-button section placed last in main.tf so the forbidden-attr awk gate scans it cleanly to EOF"
  - "terraform validate run for real (not deferred): repo-root modules/bbj-base staged temporarily into the template dir, mirroring push-templates.sh"
metrics:
  duration: ~4 min
  completed: 2026-09-02
  tasks: 1
  files: 1
actuals:
  tokens: 500
  tasks: 1
  commits: 1
---

# Quick Task 260902-kio: Expose bbj-* Helper Commands as coder_app Buttons Summary

**Five command-type coder_app buttons (bbj-build/bbj-gwt/bbj-restart/bbj-checkout/bbj-test) added to the private bbj-dev template, priority-ordered via `order` with the existing BBjServices app repositioned at order=4 — CoderPrivate commit `04db400`, terraform validate PASS.**

## What Was Done

### Task 1: Add five command-type coder_app buttons for the bbj-* helpers, priority-ordered

**Commit (CoderPrivate repo):** `04db400`

In `/workspaces/CoderPrivate/templates/bbj-dev/main.tf`:

- New `# ── BBj dev-loop command buttons ──…` section (last in the file) with five `resource "coder_app"` blocks. Each sets `agent_id = module.base.agent_id`, a `command = "bbj-<name>"`, a display_name matching the Eclipse menu item it replaces, an icon, and an `order` — and none carry `url`/`subdomain`/`share`/`healthcheck` (invalid on command-type apps):

  | Resource | Slug | Display name | Command | Icon | Order |
  |---|---|---|---|---|---|
  | `bbj_build` | bbj-build | Deploy Jars (bbj-build) | bbj-build | /icon/java.svg | 1 |
  | `bbj_gwt` | bbj-gwt | Build GWT JS (bbj-gwt) | bbj-gwt | /icon/code.svg | 2 |
  | `bbj_restart` | bbj-restart | Restart BBjServices | bbj-restart | /icon/java.svg | 3 |
  | `bbj_checkout` | bbj-checkout | SVN Checkout | bbj-checkout | /icon/folder.svg | 5 |
  | `bbj_test` | bbj-test | Run BBjTest | bbj-test | /icon/terminal.svg | 6 |

- Existing `coder_app.bbjservices` gains `order = 4` (otherwise unchanged) so it sits between the primary build/gwt/restart actions and the trailing checkout/test actions.
- STRUCTURE header comment updated: trailing clause now reads "…the BBjServices + bbj-* dev-loop command coder_apps."

## Verification

| Gate | Result |
|---|---|
| `grep -c 'resource "coder_app"'` = 6 | PASS |
| All five `command = "bbj-<name>"` lines present | PASS (whitespace-tolerant grep — file aligns `=` per its convention, as terraform fmt requires) |
| No url/subdomain/share/healthcheck after the command-buttons section header | PASS |
| ≥6 `agent_id = module.base.agent_id` wirings | PASS (6) |
| `terraform fmt -check main.tf` | PASS |
| `terraform init -backend=false` + `terraform validate` | **PASS** (not deferred — modules/bbj-base staged temporarily from repo root, provider fetch succeeded, staging cleaned up afterward) |

## Deviations from Plan

None - plan executed exactly as written. (The plan allowed a DEFERRED validate outcome; the real validate was achievable and run instead.)

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary changes; the buttons invoke commands already baked into the image and already runnable from any workspace terminal by the same user.

## Live-Deploy Gate (operator)

Per the infra-needs-live-deploy-gate convention, runtime confirmation is on the operator:
1. Re-run the private push script so the template (with staged modules/) is pushed.
2. Open/restart a bbj-dev workspace and confirm the five new buttons render in order: Deploy Jars, Build GWT JS, Restart BBjServices, BBjServices, SVN Checkout, Run BBjTest.
3. Click one (e.g. Deploy Jars) and confirm a web terminal opens running the command.

## Self-Check: PASSED

- /workspaces/CoderPrivate/templates/bbj-dev/main.tf modified: FOUND
- CoderPrivate commit 04db400: FOUND
- Working tree /workspaces/CoderPrivate: clean
