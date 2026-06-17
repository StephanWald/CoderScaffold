---
phase: 03-docker-workspace-template
fixed_at: 2026-06-17T00:00:00Z
review_path: .planning/phases/03-docker-workspace-template/03-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-06-17
**Source review:** .planning/phases/03-docker-workspace-template/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3
- Fixed: 3
- Skipped: 0

## Fixed Issues

### WR-01: `replace()` regex rewrites every `localhost`/`127.0.0.1` in the init script, not just the access-URL host

**Files modified:** `templates/docker/main.tf`
**Commit:** 011748f
**Applied fix:** Anchored the `replace()` regex to the URL scheme/host boundary
(`/(https?://)(localhost|127\.0\.0\.1)/`) with replacement `$${1}host.docker.internal`,
so only the access-URL host is rewritten and any other in-container loopback references
in the init script are left intact. Backreference `$1` is escaped as `$${1}` to survive
Terraform interpolation.

### WR-02: `ignore_changes = all` is broader than needed and the comment misattributes rename-safety to it

**Files modified:** `templates/docker/main.tf`
**Commit:** 5436277
**Applied fix:** Changed `ignore_changes = all` to `ignore_changes = [name]` on the home
volume `lifecycle` block, and corrected the comment to attribute rename-safety to the
UUID-keyed volume name rather than to the lifecycle block. The owner/owner_id labels are
now free to reconcile (e.g. on workspace ownership transfer) instead of being permanently
frozen.

### WR-03: Container name can collide for names differing only in case (casing applied asymmetrically)

**Files modified:** `templates/docker/main.tf`
**Commit:** e822ddf
**Applied fix:** Applied `lower()` symmetrically to both the owner name and the workspace
name in the container `name` (`coder-${lower(owner)}-${lower(workspace)}`), removing the
asymmetric casing and the latent container-name collision/conflict risk.

## Skipped Issues

None — all in-scope findings were fixed. Info-level findings (IN-01..IN-04) were out of
scope per `fix_scope: critical_warning` and were intentionally left unchanged.

---

_Fixed: 2026-06-17_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
