---
phase: quick-260902-8mp
plan: "01"
subsystem: bbj-templates
tags: [bbj, terraform, template, refactor]
status: complete
completed: "2026-09-02"
duration: ~33 minutes

dependency_graph:
  requires: []
  provides:
    - Ad-hoc jar+JDK workspace parameter pair across all three BBj templates
  affects:
    - templates/bbj-services/main.tf
    - templates/bbj-services/Dockerfile
    - templates/bbj-services/README.md
    - templates/bbj-services/combinations.json (deleted)
    - templates/bbj-services/combinations.example.json (deleted)
    - scripts/bbj-build-combos.sh (deleted)
    - .gitignore
    - CoderPrivate/templates/bbj-dev/main.tf
    - CoderPrivate/templates/bbj-dev/combinations.json (deleted)
    - CoderPrivate/templates/bbj-ls-dev/main.tf
    - CoderPrivate/templates/bbj-ls-dev/Dockerfile
    - CoderPrivate/templates/bbj-ls-dev/README.md
    - CoderPrivate/templates/bbj-ls-dev/combinations.json (deleted)
    - CoderPrivate/README.md
    - CoderPrivate/templates/template-dev/Dockerfile (stray reference cleanup)

tech_stack:
  patterns:
    - Terraform fileset() for dynamic coder_parameter options
    - Docker-tag-safe bbj_slug local for distinct per-jar/JDK image naming
    - Two-parameter (bbj_installer + jdk) workspace creation flow

key_files:
  modified:
    - /workspaces/coder/templates/bbj-services/main.tf
    - /workspaces/coder/templates/bbj-services/Dockerfile
    - /workspaces/coder/templates/bbj-services/README.md
    - /workspaces/coder/.gitignore
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/README.md
    - /workspaces/CoderPrivate/README.md
    - /workspaces/CoderPrivate/templates/template-dev/Dockerfile
  deleted:
    - /workspaces/coder/templates/bbj-services/combinations.json
    - /workspaces/coder/templates/bbj-services/combinations.example.json
    - /workspaces/coder/scripts/bbj-build-combos.sh
    - /workspaces/CoderPrivate/templates/bbj-dev/combinations.json
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/combinations.json

decisions:
  - Replace single bbj_stack combo param with bbj_installer (fileset-discovered jars) + jdk (Adoptium 21/25)
  - bbj_slug local derives docker-tag-safe image name from jar filename + jdk value
  - JDK defaults preserved: bbj-services adoptium-25, bbj-dev adoptium-21, bbj-ls-dev adoptium-25
  - Images build ad hoc on first workspace start per jar/JDK pairing (no pre-warm script)
  - Template-specific build args/triggers preserved (ANT_VERSION in bbj-dev, CODE_SERVER_VERSION in bbj-ls-dev)

actuals:
  tokens: 22000
  tasks: 3
  commits: 3
---

# Phase quick-260902-8mp Plan 01: Replace combinations.json with Ad-hoc Jar+JDK Selection

Ad-hoc BBj jar+JDK selection via `fileset()` + Adoptium 21/25 picker replaces the curated `combinations.json` combo selector across all three BBj templates (bbj-services, bbj-dev, bbj-ls-dev), with the five manifest/script files deleted and all documentation updated.

## What Was Built

Replaced the single `bbj_stack` combo parameter (backed by a curated JSON manifest) with two independent parameters across all three BBj templates:

- `bbj_installer` (order 2) — dynamic JAR list via `sort(fileset(var.bbj_context_path, "*.jar"))`. Each `*.jar` staged in the bind-mounted asset folder appears automatically as a workspace creation option. No manifest to maintain.
- `jdk` (order 3) — static Adoptium 21/25 picker (`mutable = false`). Default preserved per template: bbj-services = adoptium-25, bbj-dev = adoptium-21, bbj-ls-dev = adoptium-25.

A `bbj_slug` local computes a docker-tag-safe identifier from the jar filename and JDK value, used in the image name and as a rebuild trigger so each jar/JDK pairing caches as a distinct image.

## Commits

| Repo | Hash | Message |
|------|------|---------|
| /workspaces/coder | a1c8d19 | feat(quick-260902-8mp): rework bbj-services to ad-hoc jar+JDK parameters |
| /workspaces/coder | f7a96fa | refactor(bbj): replace combinations.json combo selector with ad-hoc jar+JDK parameters |
| /workspaces/CoderPrivate | 8f086c8 | refactor(bbj): replace combinations.json combo selector with ad-hoc jar+JDK parameters |

## Verification Results

All verification gates passed:

- `terraform validate` SUCCESS in bbj-services (/workspaces/coder)
- `terraform validate` SUCCESS in bbj-dev (/workspaces/CoderPrivate)
- `terraform validate` SUCCESS in bbj-ls-dev (/workspaces/CoderPrivate)
- All five target files confirmed deleted
- Zero `combinations` / `bbj-build-combos` references remain in committed files (excluding `.env.example` — see Operator Follow-up below)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stray combination reference in template-dev/Dockerfile**
- **Found during:** Task 3 orphan grep
- **Issue:** `templates/template-dev/Dockerfile` L10 had `jq — poke at combinations.json / Coder API responses`. This file was not in the plan's listed files but contained an orphan reference.
- **Fix:** Rewrote the jq comment to `jq — parse Coder API responses and template JSON`
- **Files modified:** CoderPrivate/templates/template-dev/Dockerfile
- **Included in:** CoderPrivate commit 8f086c8

**2. [Rule 3 - Blocking] Module symlinks required for terraform validate**
- **Found during:** Task 2 verify step
- **Issue:** The `./modules/bbj-base` module path does not exist in bbj-dev or bbj-ls-dev template dirs locally — it is staged by `scripts/push-templates.sh` before `coder templates push`. Without it, `terraform init` and `validate` fail with "Module not installed".
- **Fix:** Created temporary symlinks `templates/bbj-dev/modules/bbj-base -> /workspaces/CoderPrivate/modules/bbj-base` and equivalently for bbj-ls-dev for the duration of validation. These are untracked by git (`.terraform/` dirs from init were not committed).
- **Impact:** Validate succeeded. The symlinks are transient; push-templates.sh handles staging the real module.

### .env.example — Operator Follow-up Required (NOT Blocking)

`/workspaces/coder/.env.example` is **permission-denied** in this sandbox environment (tool access denied). An earlier grep flagged a `combinations` reference in this file. The operator must manually remove it:

1. Open `.env.example` on the host.
2. Find and remove any line/comment referencing `combinations.json` or `combinations.example.json`.
3. This file is not committed to git from this task; the change is cosmetic documentation only.

## Must-Haves Verification

| Truth | Status |
|-------|--------|
| No combinations.json / combinations.example.json / bbj-build-combos.sh files remain | PASS |
| Each template prompts bbj_installer + jdk instead of bbj_stack | PASS |
| Docker build args feed jar filename + jdk directly | PASS |
| Image name/tag and triggers derive from jar+jdk slug | PASS |
| No remaining references to combinations.json or bbj-build-combos.sh in committed files | PASS (except .env.example — permission-denied, operator follow-up) |
| terraform validate passes in all three template dirs | PASS |

## Live-Deploy Gate — MANDATORY Operator Verification

> **IMPORTANT: `terraform validate` is NOT the real gate.**
>
> Per project memory (`infra-needs-live-deploy-gate`): static Terraform validation
> confirms syntax and provider schema only. It does NOT verify that images actually
> build, that BBjServices starts, or that the fileset() discovery works against real
> assets in the bind-mounted folder.
>
> **The operator MUST live-verify by pushing each template and starting a workspace
> per jar/JDK pairing:**
>
> 1. Stage the desired jar(s) in `BBJ_ASSETS_PATH` and confirm `ls /mnt/bbj-assets/*.jar` lists them from inside the coder container.
> 2. `coder templates push bbj-services` — confirm the template push completes.
> 3. Create a workspace, select each staged jar + each JDK (21 and 25) and confirm:
>    - The image build completes (BBj silent install succeeds).
>    - BBjServices starts on port 8888 (check the BBjServices script log in the dashboard).
>    - The BBjServices app button opens the HTTP interface.
> 4. Repeat for bbj-dev and bbj-ls-dev in CoderPrivate.
> 5. Confirm that the image name contains the jar/JDK slug (e.g. `coder-<id>-bbj-bbjbaristademos2601_06-30-2026_1027-adoptium-25`).
> 6. Confirm that changing the JDK on a new workspace produces a DIFFERENT image (distinct slug = distinct cache).

## Self-Check: PASSED

- All three main.tf files have bbj_installer + jdk params (no bbj_stack): VERIFIED
- Five deleted files confirmed absent: VERIFIED
- No orphan references: VERIFIED (grep returned NO_ORPHANS)
- All three terraform validate: PASSED
- Commits exist in git log: a1c8d19, f7a96fa (coder) and 8f086c8 (CoderPrivate): VERIFIED
