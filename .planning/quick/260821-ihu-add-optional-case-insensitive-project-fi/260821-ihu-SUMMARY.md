---
phase: quick-260821-ihu
plan: "01"
subsystem: bbj-services template
tags: [terraform, docker, filesystem, casefold, ext4, bbj-services]
status: complete
completed: "2026-08-21"
duration: ~20min

dependency_graph:
  requires: []
  provides:
    - templates/bbj-services/main.tf case_insensitive_project parameter
    - templates/bbj-services/main.tf casefold startup_script block
    - templates/bbj-services/main.tf dynamic capabilities SYS_ADMIN block
    - templates/bbj-services/Dockerfile e2fsprogs + util-linux apt block
    - templates/bbj-services/README.md FLAG-04 section
  affects:
    - bbj-services workspace creation flow (new optional parameter)

tech_stack:
  added:
    - ext4 casefold (kernel-native case-insensitive filesystem via loop-mount)
    - e2fsprogs (mkfs.ext4 -O casefold, chattr)
    - util-linux (mount, losetup)
  patterns:
    - WR-03 warn-and-continue non-fatal startup_script block
    - dynamic for_each conditional block pattern (mirrors dynamic "ports")
    - sparse loopback image on persistent home volume

key_files:
  modified:
    - templates/bbj-services/main.tf
    - templates/bbj-services/Dockerfile
    - templates/bbj-services/README.md

decisions:
  - mutable=false on both parameters: the casefold filesystem type and image size are create-time decisions; resizing an existing loop-mounted image would require unmount/resize2fs/remount — out of scope for startup_script
  - SYS_ADMIN (not privileged=true): minimum necessary capability for loop mount; privileged documented as fallback only
  - sparse truncate (not dd): no upfront disk allocation; the size parameter is a ceiling
  - chattr +F on mount root (not mkfs-time): applied after mount so the directory is guaranteed empty; documented runtime fallback if unsupported
  - WR-03 warn-and-continue throughout: a casefold mount failure must not abort the full workspace startup

actuals:
  tokens: 9800
  tasks: 3
  commits: 3
---

# Quick Task 260821-ihu: Optional case-insensitive project filesystem Summary

**One-liner:** Added opt-in ext4 casefold loopback mount to bbj-services template — two coder_parameters (bool + size), idempotent WR-03 startup_script block before git clone, dynamic SYS_ADMIN capability block, e2fsprogs+util-linux in Dockerfile, and a FLAG-04 README section with mandatory live-deploy caveat.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (tracer) | Parameters + startup_script block + capabilities | 445f337 | templates/bbj-services/main.tf |
| 2 | Bake casefold tooling into image | a3246da | templates/bbj-services/Dockerfile |
| 3 | Document feature in README | 8f3a65a | templates/bbj-services/README.md |

## Verification Gate Results

| Gate | Result |
|------|--------|
| Task 1 GREP_PASS (case_insensitive_project, case_insensitive_size_gb, mkfs.ext4 -O casefold, mountpoint -q, chattr +F, add=["SYS_ADMIN"], dynamic "capabilities") | PASS |
| Task 2 DOCKERFILE_PASS (e2fsprogs + util-linux, comment-filtered) | PASS |
| Task 3 README_PASS (case_insensitive_project, casefold, SYS_ADMIN, CarIT) | PASS |
| Ordering assertion: casefold block (line 458) precedes "Optional project repo clone" (line 518) | PASS |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. The feature is fully wired (parameters → startup_script → capability). Runtime behavior (whether the loop mount actually works inside a Docker container with SYS_ADMIN on the operator's host kernel) cannot be verified statically — this is the documented live-deploy caveat in the README FLAG-04 section and is an expected property of this template, not a stub.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries introduced beyond what the plan's threat_model already covers (T-ihu-01: SYS_ADMIN capability accepted; T-ihu-02: sparse image size accepted; T-ihu-03: apt packages only, no new registry installs).

## Self-Check

- [x] templates/bbj-services/main.tf modified and committed (445f337)
- [x] templates/bbj-services/Dockerfile modified and committed (a3246da)
- [x] templates/bbj-services/README.md modified and committed (8f3a65a)
- [x] All three grep gates print PASS
- [x] Ordering: casefold block before git clone block
- [x] Non-opt-in workspaces: no capabilities block, no casefold block runs (dynamic for_each = false ? [] : [] → empty)

## Self-Check: PASSED
