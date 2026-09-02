---
phase: quick-260902-jfn
plan: "01"
subsystem: scripts / templates/bbj-services
status: complete
tags: [bbj-services, push-templates, dockerfile-staging, image-context-drift]
completed: "2026-09-02"
duration: ~10min
tasks_completed: 2
commits: 1
key_files:
  modified:
    - scripts/push-templates.sh
    - templates/bbj-services/README.md
decisions:
  - "Warn-and-continue (not fail-fast) for unset/missing BBJ_ASSETS_PATH — public script must never block non-BBj template pushes"
  - "Informational prereq check for certificate.bls + playback.properties is WARN-only; script never stages operator-supplied files"
  - "ASSETS outer-scope var name avoids collision with _generate_jars_json's local assets variable"
actuals:
  tokens: 9000
  tasks: 2
  commits: 1
live_gate: deferred
---

# Quick Task 260902-jfn: push-templates.sh must stage BBj Dockerfile — Summary

Auto-stage `templates/bbj-services/Dockerfile` into `${BBJ_ASSETS_PATH}/Dockerfile` on every `push-templates.sh` run, closing the image-context drift that caused today's workspace rebuild to produce an image without tmux (the staged Dockerfile was dated Jul 16; the repo Dockerfile had since gained tmux auto-attach, `/etc/tmux.conf`, the Playwright layer, and bash-default-shell).

## What was built

**scripts/push-templates.sh** — new Dockerfile asset-staging block inserted between the auth step and the `jars.json` staging section:

- Copies `templates/bbj-services/Dockerfile` to `${BBJ_ASSETS_PATH}/Dockerfile` when the path is valid.
- Three warn-and-continue conditions: `BBJ_ASSETS_PATH` unset, path does not exist, or repo Dockerfile missing.
- Informational prereq check warns when `certificate.bls` or `playback.properties` are absent from the asset folder (operator-supplied; the script never stages them).
- Block comment records the drift rationale and the `dockerfile_sha1` rebuild trigger.

**templates/bbj-services/README.md** — two corrections:

1. Step 1 rewritten: the script now stages the Dockerfile automatically on every push; a manual `cp` is only needed for out-of-script builds (e.g. manual `docker build` to pre-warm the cache). `playback.properties` + `certificate.bls` remain documented as operator-supplied manual steps.
2. Architecture diagram: `Dockerfile` annotation updated from "operator copies into BBJ_ASSETS_PATH" to "staged into BBJ_ASSETS_PATH by push-templates.sh" in both the `/mnt/bbj-assets` context listing and the `templates/bbj-services/` listing.

## Verification

| Check | Result |
|-------|--------|
| `bash -n scripts/push-templates.sh` | PASS |
| `shellcheck scripts/push-templates.sh` | PASS |
| Dry-run: `cp Dockerfile scratchpad/assets-test/` + `cmp` | PASS (STAGING-DRY-RUN-OK) |
| `grep -qE 'operator copies into BBJ_ASSETS_PATH' README.md` returns no match | PASS (README-MANUAL-COPY-CORRECTED) |

## Commits

| Commit | Message |
|--------|---------|
| 5dc7caa | feat(quick-260902-jfn): auto-stage bbj-services Dockerfile in push-templates.sh |

## Deviations from Plan

None — plan executed exactly as written. The public script uses warn-and-continue (not fail-fast) as specified; the private CoderPrivate script's fail-fast approach was used only as a style reference.

## Live Gate (DEFERRED — operator required)

**This change cannot be fully verified in this dev container.** The `coder` CLI is not installed here and there is no live Coder server. Per project memory "Infra needs a live deploy gate":

1. On the live host, run `scripts/push-templates.sh` with `BBJ_ASSETS_PATH` set.
2. Confirm `${BBJ_ASSETS_PATH}/Dockerfile` mtime is refreshed (newer than Jul 16).
3. Restart the `bbj-services` workspace — the `dockerfile_sha1` trigger in `main.tf` should detect the changed staged Dockerfile and rebuild the image.
4. After rebuild, open the workspace web terminal and confirm the session lands in `tmux` (the tmux auto-attach layer that was missing from the Jul 16 staged copy is now in the image).

Until this live gate is completed, the image-context drift is fixed in the script logic but not yet confirmed in production.

## Self-Check: PASSED

- `/workspaces/coder/scripts/push-templates.sh` — FOUND, modified
- `/workspaces/coder/templates/bbj-services/README.md` — FOUND, modified
- Commit `5dc7caa` — FOUND in `git log`
- No changes outside the two specified files
