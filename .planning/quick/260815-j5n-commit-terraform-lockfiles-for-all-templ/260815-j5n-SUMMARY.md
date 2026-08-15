---
phase: quick-260815-j5n
plan: "01"
subsystem: workspace-templates
tags: [terraform, lockfile, coder, docker, provider-pinning, push-templates]
status: complete

dependency_graph:
  requires: []
  provides:
    - templates/bbj-services/.terraform.lock.hcl (regenerated, 3-platform)
    - templates/coderscaffold/.terraform.lock.hcl (new)
    - templates/docker/.terraform.lock.hcl (new)
    - templates/java-fullstack/.terraform.lock.hcl (regenerated, 3-platform)
    - templates/python-ai/.terraform.lock.hcl (new)
    - scripts/push-templates.sh ensure_template_lockfile() guard
  affects:
    - scripts/update-coder.sh (--push-templates path benefits from the same guard, unchanged)

tech_stack:
  added: []
  patterns:
    - Dockerized terraform (hashicorp/terraform:1.9, --user uid:gid) used for lockfile
      generation instead of installing terraform on the host
    - Non-blocking guard pattern in push-templates.sh — a missing prerequisite (lockfile)
      warns and self-heals opportunistically but never turns exit 0 into exit 1

key_files:
  created:
    - templates/coderscaffold/.terraform.lock.hcl
    - templates/docker/.terraform.lock.hcl
    - templates/python-ai/.terraform.lock.hcl
  modified:
    - templates/bbj-services/.terraform.lock.hcl
    - templates/java-fullstack/.terraform.lock.hcl
    - scripts/push-templates.sh

decisions:
  - "Regenerated bbj-services and java-fullstack lockfiles even though they were already committed — their existing files only had a single h1 hash per provider (one platform), insufficient for the prod linux_amd64 provisioner"
  - "Lockfile guard in push-templates.sh is advisory-only by design (threat T-j5n-03, disposition accept): docker missing or generation failing warns and pushes anyway, matching the script's existing non-fatal-per-template failure pattern"
  - "Generated lockfile left untracked after guard auto-generation (not auto-committed) — the untracked git diff on the host is the intended nudge for the operator to review and commit it"
  - "No .gitignore change — .terraform/ was already ignored and the comment already documents that .terraform.lock.hcl is intentionally tracked"

metrics:
  duration: ~13min
  completed: "2026-08-15T12:09:10Z"
  tasks_completed: 2
  files_created: 3
  files_modified: 3
---

# Phase quick-260815-j5n Plan 01: Terraform Lockfiles for All Templates Summary

**One-liner:** Committed three-platform (linux_amd64/linux_arm64/darwin_arm64) `.terraform.lock.hcl` for all five Coder workspace templates and added a non-blocking dockerized auto-generation guard to `scripts/push-templates.sh`.

## What Was Built

Generated and committed `.terraform.lock.hcl` for every template under `templates/` using dockerized Terraform (`hashicorp/terraform:1.9`, no host install required), and added a defensive guard function to the bulk-push script so a missing lockfile self-heals during a future push instead of silently degrading provider caching on the Coder server.

### Lockfile generation (Task 1)

For each of `templates/bbj-services`, `templates/coderscaffold`, `templates/docker`, `templates/java-fullstack`, `templates/python-ai`:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "<abs-dir>:/tf" -w /tf hashicorp/terraform:1.9 init -backend=false -input=false
docker run --rm --user "$(id -u):$(id -g)" -v "<abs-dir>:/tf" -w /tf hashicorp/terraform:1.9 providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64
```

- `coderscaffold`, `docker`, `python-ai` had **no** lockfile before this task — all three now carry one.
- `bbj-services` and `java-fullstack` already had a committed lockfile, but each provider block held only a single `h1:` hash (one platform). Both were regenerated so every provider (`coder/coder`, `kreuzwerker/docker`, `hashicorp/http`) carries 3 `h1:` hashes (9 total per file, verified via `grep -c 'h1:'`).
- Every template resolved to the same provider versions: `coder/coder 2.18.0`, `kreuzwerker/docker 4.5.0`, `hashicorp/http 3.6.0` or `3.6.1` (module registry downloads pulled the currently-published patch at generation time; no `-var` input was needed by `init` for any template).
- `--user "$(id -u):$(id -g)"` (uid 501, gid 20 on this host) prevented any root-owned files from landing in the repo — confirmed via `ls -la` on the generated files.
- All `templates/*/.terraform` cache dirs created by `init` were deleted after generation (`rm -rf`), leaving only the lockfile as the tracked deliverable.
- `.gitignore` already ignores `.terraform/` and documents that `.terraform.lock.hcl` is intentionally tracked — no change needed.
- No failures occurred; no Terraform errors to record verbatim; the `-e HOME=/tmp` fallback was **not** needed (the `--user` container wrote its CLI config without complaint).
- `git status --porcelain` after generation showed exactly the five expected lockfile changes and nothing else.

### push-templates.sh lockfile guard (Task 2)

Added `ensure_template_lockfile()` above the template push loop (after the auth block):

- No-op (return 0) when `<dir>/.terraform.lock.hcl` already exists — the common healthy path.
- Otherwise: loud `WARN` to stderr, then checks for `docker` on `PATH` — if absent, warns and returns 0 (push proceeds without a lockfile).
- If docker is present, runs the same two dockerized `init` + `providers lock` commands used in Task 1. Each is wrapped in `if ! ...; then warn; cleanup; return 0; fi` so a generation failure under `set -euo pipefail` cannot abort the script.
- `rm -rf "${dir}/.terraform"` runs on every exit path after invoking docker (success or failure) — the provider/module cache is never left behind for `coder templates push` to upload.
- On success, echoes a note that the file was generated and should be committed; the file is deliberately left untracked (not auto-`git add`ed) so it surfaces as a visible nudge.
- Wired into the loop immediately after the `compgen -G "${dir}*.tf"` skip check and before `push_args=(...)`; call is its own statement, not the tail of an `&&` chain.
- Header comment block and the `LIVE VERIFICATION DEFERRED` banner updated to describe the guard's behavior and note that only the dockerized generation path was spot-checked in isolation — the full script (auth + push with the guard inline) remains part of the existing deferred-to-live-environment scope.

## Task Commits

1. **Task 1: Generate and commit three-platform lockfiles for all five templates** - `6f9f024` (feat)
2. **Task 2: Add a non-blocking lockfile guard to scripts/push-templates.sh** - `ff17260` (feat)

## Files Created/Modified
- `templates/coderscaffold/.terraform.lock.hcl` - new, 3-platform lockfile (coder/coder, kreuzwerker/docker, hashicorp/http)
- `templates/docker/.terraform.lock.hcl` - new, 3-platform lockfile
- `templates/python-ai/.terraform.lock.hcl` - new, 3-platform lockfile
- `templates/bbj-services/.terraform.lock.hcl` - regenerated from single-platform to 3-platform
- `templates/java-fullstack/.terraform.lock.hcl` - regenerated from single-platform to 3-platform
- `scripts/push-templates.sh` - added `ensure_template_lockfile()` guard function + wiring + updated header/DEFERRED docs

## Decisions Made
- Regenerated (not left alone) the two pre-existing lockfiles because they were missing 2 of 3 required platforms — leaving them as-is would have failed the plan's own `must_haves` truth ("every provider block has >= 3 h1: hashes").
- Guard is intentionally non-blocking per the plan's threat register (T-j5n-03, disposition `accept`): a lockfile problem must never turn a working push into a failure.
- Left the guard's auto-generated lockfile uncommitted by design — auto-committing on the operator's behalf during a push felt riskier than surfacing it as an obvious untracked-file nudge.

## Deviations from Plan

None - plan executed exactly as written. All canonical commands, platform flags, and cleanup steps matched the plan's `<canonical_commands>` and task `<action>` blocks verbatim; the `-e HOME=/tmp` fallback described as conditional was not triggered.

## Verification

- `ls templates/*/.terraform.lock.hcl | wc -l` → 5
- `grep -c 'h1:'` on each of the 5 lockfiles → 9 (3 providers × 3 platforms) for every file
- `ls -d templates/*/.terraform` → no matches (cache dirs removed)
- `/bin/bash -n scripts/push-templates.sh` → clean (no syntax errors)
- `shellcheck` not installed in this environment — skipped per the plan's automated-check fallback (`echo "shellcheck not installed - skipped"`)
- Guard spot-check: removed `templates/python-ai/.terraform.lock.hcl`, ran the extracted `ensure_template_lockfile()` function standalone against the absolute template path — it regenerated the lockfile via dockerized terraform, printed the commit-nudge note, and left no `.terraform/` cache dir behind. Repo state was restored from a scratchpad backup and verified identical to the committed version (`git diff --quiet`).
- `git status --porcelain` after both tasks → only the five lockfiles + `scripts/push-templates.sh` (no `.terraform` paths, no root-owned files, no other drift)

**NOT verifiable here (deferred, matching the script's existing convention):** a real `coder templates push` run confirming the "No .terraform.lock.hcl file found" warning is gone — the `coder` CLI is not installed in this environment.

## Issues Encountered

None.

## Next Phase Readiness

- All templates now push with committed, three-platform provider pins; future template `terraform init` runs will reuse these locks instead of re-resolving.
- If a new template is added under `templates/<name>/` without a lockfile, the guard in `push-templates.sh` will auto-generate one on the next `./scripts/push-templates.sh` run (assuming Docker is available) rather than silently degrading provider caching.

---
*Phase: quick-260815-j5n*
*Completed: 2026-08-15*

## Self-Check: PASSED

- FOUND: templates/bbj-services/.terraform.lock.hcl
- FOUND: templates/coderscaffold/.terraform.lock.hcl
- FOUND: templates/docker/.terraform.lock.hcl
- FOUND: templates/java-fullstack/.terraform.lock.hcl
- FOUND: templates/python-ai/.terraform.lock.hcl
- FOUND commit: 6f9f024
- FOUND commit: ff17260
