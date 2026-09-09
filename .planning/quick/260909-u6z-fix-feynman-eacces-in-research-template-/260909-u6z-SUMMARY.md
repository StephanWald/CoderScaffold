---
phase: quick-260909-u6z
plan: "01"
subsystem: templates/research
tags: [feynman, dockerfile, permissions, eacces, exdev, overlayfs, fix]
status: complete
completed: "2026-09-09"
duration_min: 45

dependency_graph:
  requires: [260908-ig5]
  provides: [feynman-runnable-research-image]
  affects: [templates/research/Dockerfile]

tech_stack:
  added: []
  patterns: [chown-after-npm-install-g, no-baked-runtime-state-on-overlayfs]

key_files:
  modified:
    - templates/research/Dockerfile

decisions:
  - "chown must come AFTER feynman --version: the version check validates the package as root at build time; a broken or renamed package still fails the image build"
  - "FEYNMAN_HOME does not relocate package-local paths (.feynman/ under install root) — confirmed by reading patch-embedded-pi.mjs source (settingsPath/workspaceDir/workspaceSetupLockDir hard-coded to appRoot)"
  - "The baked .feynman/npm runtime workspace must be REMOVED at build time: its integrity marker does not validate in the running container, so every first runtime invocation attempts a transactional workspace replace whose rename() of a lower-layer directory fails on overlayfs with EXDEV. The package ships runtime-workspace.tgz, so the runtime restore is local-only (~15 s, detached worker)"
  - "feynman --version returns rc 0 in ~0.5 s and defers workspace restore to a detached background worker on first run; gate must poll for .runtime-workspace.complete.json before asserting steady state"

actuals:
  tokens: 5500
  tasks: 2
  commits: 2
  plan_head_before: e49d6c7
---

# Quick Task 260909-u6z: Fix Feynman EACCES in Research Template Summary

One-liner: Two Dockerfile fixups make Feynman runnable by the `coder` user — chown the root-owned npm install dir (EACCES on the setup-lock mkdir), and remove the build-baked runtime workspace whose replacement rename() EXDEV-crashes on overlayfs.

## What Was Done

### Defect 1: EACCES on setup lock (reported by user)

Feynman hard-codes its runtime setup state and `.workspace-setup.lock` dir to paths inside its own install root (`/usr/lib/node_modules/@companion-ai/feynman/.feynman/...`); `FEYNMAN_HOME` does NOT relocate them. `npm install -g` runs as root, so the runtime user `coder` got EACCES on every invocation at `acquireRuntimeWorkspaceSetupLock` → `mkdirSync`.

Fix: `chown -R coder:coder /usr/lib/node_modules/@companion-ai/feynman` after the build-time `feynman --version` check.

**Commit:** e526de9

### Defect 2: EXDEV on baked workspace replace (found by the live gate)

With EACCES fixed, actually running `feynman --version` as `coder` (and as root) in a container still crashed:

```
Error: EXDEV: cross-device link not permitted, rename '.../.feynman/npm' -> '.../.feynman/runtime-workspace.backup-...'
```

The build-time `feynman --version` bakes a restored runtime workspace (`.feynman/npm`, 278 packages) into the image layer, but its integrity/completion marker does not validate in the running container, so the first runtime invocation attempts `replaceRuntimeWorkspaceTransactionally`, whose directory `rename()` fails on overlayfs — a directory in a lower image layer cannot be renamed. Not user-dependent (root failed identically).

Fix: `rm -rf /usr/lib/node_modules/@companion-ai/feynman/.feynman/npm` at build time, after the version check. The package ships `.feynman/runtime-workspace.tgz` + sha256, so the first runtime invocation restores the workspace fresh into the container's writable layer — a detached worker, ~15 s, no network — and every rename stays within the upper layer.

**Commit:** 94b93ef

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | e526de9 | fix(quick-260909-u6z): chown Feynman install dir to coder after build-time version check |
| 2 | 94b93ef | fix(quick-260909-u6z): remove baked Feynman runtime workspace to avoid overlayfs EXDEV |

## Verification (live gate on final image)

- [x] `docker build templates/research` succeeded (install + version check + rm + chown layer)
- [x] First `feynman --version` as `coder` (docker exec, like a workspace shell): **rc 0** in ~0.5 s; detached restore worker converged in ~15 s (`.runtime-workspace.complete.json` written, 278 packages in `.feynman/npm/node_modules`)
- [x] Steady-state `feynman --version` as `coder`: **rc 0** in ~0.5 s (no re-restore — completion marker validates)
- [x] No `EACCES`, no `permission denied`, no `EXDEV` in any run
- [x] Throwaway containers and images removed

## Deviations from Plan

- The plan's Task 2 gate (as executed by the original executor) only proved writability with a direct `mkdir` test and misread Feynman's non-TTY exit 1 as expected CLI behavior — it was the EXDEV crash. Re-running the gate with a real `feynman --version` invocation as `coder` exposed defect 2, which required the additional `rm -rf .feynman/npm` fix (commit 94b93ef). This is exactly the failure mode the "infra needs a live deploy gate" lesson warns about: the gate must exercise the actual binary as the actual runtime user.

## Self-Check: PASSED

- [x] `templates/research/Dockerfile` Feynman layer: install → version check → rm baked workspace → chown
- [x] Commits e526de9 and 94b93ef exist in git log
- [x] Live gate on the final image: first run + steady state both rc 0 as `coder`, no EACCES/EXDEV
- [x] Throwaway images removed
