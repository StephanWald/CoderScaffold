---
phase: 260713-mlt
plan: 01
subsystem: templates/bbj-services
tags: [terraform, docker, coder-template, bbj, combo-selector]
status: complete

dependency_graph:
  requires: [quick-260713-m12]
  provides: [bbj_stack combo selector, combinations.json fallback, bbj-build-combos.sh pre-warm]
  affects: [templates/bbj-services/main.tf, templates/bbj-services/Dockerfile, scripts/bbj-build-combos.sh]

tech_stack:
  added: [combinations.example.json, bbj-build-combos.sh]
  patterns: [try(jsondecode(file(...)), local.default_combinations), dynamic option block, combo-derived build args]

key_files:
  created:
    - templates/bbj-services/combinations.example.json
    - scripts/bbj-build-combos.sh
  modified:
    - templates/bbj-services/main.tf
    - templates/bbj-services/Dockerfile
    - templates/bbj-services/README.md
    - .env.example

decisions:
  - "bbj_stack dropdown replaces standalone jdk coder_parameter; JDK is derived, not picked independently"
  - "combinations.json read via try(jsondecode(file(...)), local.default_combinations) so terraform validate passes without the file"
  - "mutable = false on bbj_stack: a different combo = a new workspace (foundational choice)"
  - "bbj-build-combos.sh uses same build args as main.tf to maximise BuildKit cache hit rate"

metrics:
  duration: ~20 minutes
  completed: 2026-07-13
  tasks_completed: 3
  files_changed: 6
---

# Phase 260713-mlt Plan 01: BBj stack combo selector Summary

BBj services template migrated from standalone `jdk` coder_parameter + single-jar glob to a
single `bbj_stack` dropdown backed by an admin-curated `combinations.json`; combo-derived build
args feed both the Terraform docker_image build and the new `bbj-build-combos.sh` pre-warm script.

## What Was Built

### Task 1: Migrate main.tf + Dockerfile (commit b42d1da)

**main.tf changes:**
- Removed `data "coder_parameter" "jdk"` block entirely (with adoptium-21/25 options).
- Added `default_combinations` / `bbj_combinations` / `combos_by_id` / `selected` locals.
  The read is exactly: `try(jsondecode(file("${var.bbj_context_path}/combinations.json")), local.default_combinations)`
  — `terraform validate` passes with NO combinations.json present (the try() fallback to
  `local.default_combinations` keeps the template usable/validatable in this repo).
- Added `data "coder_parameter" "bbj_stack"` with `mutable = false`, `default = local.bbj_combinations[0].id`,
  and a `dynamic "option"` block over `local.bbj_combinations`.
- Updated `docker_image.main`: name uses `bbj_stack.value`; build_args include `JDK = local.selected.jdk`
  and `BBJ_JAR_NAME = local.selected.jar`; triggers use `stack`, `jdk`, and
  `try(filesha1("${var.bbj_context_path}/${local.selected.jar}"), "no-jar")`.
- Zero dangling `data.coder_parameter.jdk` references remain.

**Dockerfile changes:**
- Added `BBJ_JAR_NAME` to build-args comment header.
- Replaced `ADD BBj*.jar /tmp/BBj.jar` (glob — ambiguous with multiple jars) with:
  ```dockerfile
  ARG BBJ_JAR_NAME=BBj.jar
  ADD ${BBJ_JAR_NAME} /tmp/BBj.jar
  ```
- JDK install case logic (adoptium-21/adoptium-25) unchanged.

### Task 2: combinations.example.json + bbj-build-combos.sh (commit 502f200)

**combinations.example.json:** Two example combos (valid JSON, no trailing commas):
- `bbj-26.01-jdk25`: BBj 26.01 + adoptium-25, jar = BBj-26.01.jar
- `bbj-25.12-jdk21`: BBj 25.12 + adoptium-21, jar = BBj-25.12.jar

**bbj-build-combos.sh:** Non-interactive pre-warm script, mode 0755, matching backup.sh conventions:
- `#!/usr/bin/env bash` + `set -euo pipefail`
- SCRIPT_DIR / PROJECT_ROOT resolution via BASH_SOURCE
- Sourcing `.env` with `set -a; source; set +a` pattern; WARN if absent
- Defaults: BBJ_ASSETS_PATH=./bbj-assets, BBJ_LICENSE_SERVER=, BASE_IMAGE (matching template), MAVEN_VERSION
- Requires `jq` (exit 2 with clear message if absent)
- Falls back to combinations.example.json if BBJ_ASSETS_PATH/combinations.json absent (WARN)
- Per-combo: verifies jar exists (records FAIL + continues; does not abort loop); runs `docker build` with
  JDK/BBJ_JAR_NAME/BASE_IMAGE/MAVEN_VERSION/LICENSE_SERVER args; tags `bbj-services:<id>`
- Per-combo PASS/FAIL summary; exits 0 only if all combos pass

### Task 3: README.md + .env.example (commit 1f8251f)

**README.md:**
- Step 1: replaced single-jar instruction with multi-jar staging + `cp combinations.example.json ./bbj-assets/combinations.json` + edit workflow
- Step 5: updated to reference BBj stack dropdown (JDK derived, no separate picker)
- FLAG-02: reframed from "JDK 25 experimental option" to "enforced by curation — admin lists only valid combos"
- FLAG-03: updated "change the JDK selection" to "select a different BBj stack combo"
- New "Pre-warming images with bbj-build-combos.sh" section: documents the pre-warm approach, on-demand fallback, requirements, exit codes
- Live verification: added Step 0 (optional bbj-build-combos.sh run) + updated Step 1 to "per-combo image build"
- Architecture tree: shows `combinations.json`, multiple `BBj-<ver>.jar` files, and `combinations.example.json`

**.env.example:**
- Extended `BBJ_ASSETS_PATH` comment to note the folder now holds `combinations.json` (copied from
  combinations.example.json), multiple named version jars (one per combo), alongside the existing assets.
  No new variables added (BBJ_ASSETS_PATH and BBJ_LICENSE_SERVER already defined).

## Mandatory Verification Gate Results

All static gates ran and passed in this repo with NO `combinations.json` present:

```
terraform init -backend=false    → Terraform has been successfully initialized!
terraform validate               → Success! The configuration is valid.
terraform fmt -check             → (no output = clean, exit 0)
grep -nE 'coder_parameter\.jdk'  → (no matches — PASS: no dangling refs)
bash -n bbj-build-combos.sh      → PASS
shellcheck bbj-build-combos.sh   → PASS
jq empty combinations.example.json → PASS (valid JSON)
```

The `try(jsondecode(file(...)), local.default_combinations)` fallback is confirmed working:
`terraform validate` succeeds with the file absent.

## Live Verification (Operator Step — Cannot Run Here)

The following CANNOT be verified in this repository — no real BBj jars, certificate.bls,
or reachable BLS license server are present:

- **Per-combo image build**: each combo in `combinations.json` must build successfully via
  `coder templates push` or `scripts/bbj-build-combos.sh`. The BBj silent install
  (`java -jar BBj.jar -p playback.properties`) is the critical gate — requires a valid jar,
  certificate, and reachable BLS server.
- **Port 8888 E2E**: for each combo, create a workspace, confirm BBjServices starts (port 8888),
  and click the BBjServices button in the Coder dashboard.
- **bbj-build-combos.sh end-to-end**: verified only by `bash -n` (syntax) and `shellcheck` in
  this repo. The script cannot be run end-to-end without real assets. This is the operator's
  live-deploy step.

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. `combinations.example.json`
contains only placeholder jar names and no secrets. The `try()` wrapper (T-mlt-01) and
`combinations.json` kept in the gitignored asset folder (T-mlt-02) are correctly implemented.

## Self-Check

**Files exist:**
- `templates/bbj-services/main.tf` — FOUND (modified)
- `templates/bbj-services/Dockerfile` — FOUND (modified)
- `templates/bbj-services/combinations.example.json` — FOUND (created)
- `scripts/bbj-build-combos.sh` — FOUND (created, executable)
- `templates/bbj-services/README.md` — FOUND (modified)
- `.env.example` — FOUND (modified)

**Commits exist:**
- b42d1da — feat(260713-mlt-01): migrate bbj-services to bbj_stack combo selector
- 502f200 — feat(260713-mlt-01): add combinations.example.json and bbj-build-combos.sh
- 1f8251f — docs(260713-mlt-01): update README and .env.example for combo workflow

## Self-Check: PASSED
