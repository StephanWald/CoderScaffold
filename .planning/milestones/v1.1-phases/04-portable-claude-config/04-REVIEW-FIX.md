---
phase: 04-portable-claude-config
fixed_at: 2026-06-17T19:00:00Z
review_source: 04-REVIEW.md
fix_scope: critical_warning
findings_in_scope: 5
fixed: 5
skipped: 0
iteration: 1
status: all_fixed
---

# Code Review Fix Report — Phase 04 (portable-claude-config)

_Source review: `04-REVIEW.md` (1 critical, 4 warning, 2 info)_
_Fix scope: critical + warning (info findings out of scope)_

> **Recovery note:** The `gsd-code-fixer` agent applied and committed all fixes in an
> isolated worktree (`gsd-reviewfix/04-50778`) but hit a stream idle timeout during
> merge-back before writing this report. The orchestrator verified the three fix commits,
> fast-forward-merged them onto `master`, removed the orphaned worktree, and authored this
> report from the committed diff.

## Findings Fixed

### CR-01 (BLOCKER) — `~/.claude.json` data loss on upgrade path — FIXED
**Commit:** `6a21803` fix(04): CR-01 migrate real ~/.claude.json before placeholder to prevent auth data loss

The `{}` placeholder init at `main.tf:139-141` ran *before* the WR-01 migration, so
`cp -n` (no-clobber) found the destination already populated, silently skipped the copy,
and `rm -f` then deleted the developer's real `~/.claude.json` — replacing live auth with `{}`.

Fix: the real-file migration now runs **first** and uses `cp -f` (force-overwrite of any
placeholder) instead of `cp -n`. The `{}` placeholder creation moved to a last-resort step
that only fires when no real file was migrated and no prior shared file exists. The
`[ ! -L ] && [ -f ]` guard still proves the source is the developer's real file, so the
overwrite is safe and idempotent (a no-op once the symlink exists).

### WR-01 — unconditional `rm -rf` after masked copy failure — FIXED
**Commit:** `5a63ada` fix(04): WR-01 only rm ~/.claude after successful copy or empty source

`cp -an ... 2>/dev/null || true` masked copy failures, then `rm -rf "$HOME/.claude"` ran
unconditionally — destroying real config on a failed copy of a non-empty source.

Fix: `rm -rf "$HOME/.claude"` now runs only if the copy actually succeeded **or** the source
directory is empty (a legitimate no-op). A copy failure on a non-empty dir leaves the original
in place.

### WR-02 — `cp -n` wrong primitive for a "preserve" intent — FIXED
**Commit:** `6a21803` (folded into the CR-01 fix)

`cp -n` cannot report a clobber-skip, which is the mechanism behind CR-01's silent failure.
Replaced with `cp -f` for the real-file migration, where overwrite is the intended semantics.

### WR-03 — first-run `chown` aborts `startup_script` under `set -e` — FIXED
**Commit:** `0ddef8a` fix(04): WR-03 make first-run chown non-fatal under set -e

A failing `sudo chown` (no passwordless sudo in a custom image, locked file, etc.) aborted the
whole startup before symlinks were created.

Fix: `sudo chown ... || echo "WARN: could not chown ...; continuing" >&2` — logs and continues.

### WR-04 — missing `$CLAUDE_SHARED` mount → `stat` empty → `chown -R` abort — FIXED (mitigated)
**Commit:** `0ddef8a` (covered by the WR-03 non-fatal chown)

When the shared volume is unmounted, `stat -c '%U'` returns empty, the `!= "coder"` branch is
taken, and `chown -R` runs against a nonexistent path. The WR-03 non-fatal guard now catches
that failure and continues instead of aborting the startup_script under `set -e`.

## Findings Skipped (out of scope)

- **IN-01** (`coalesce` only falls back on `null`, not `""`) — Info, out of `critical_warning` scope.
- **IN-02** (redundant `"${...}"` wrapping on email env values) — Info, out of `critical_warning` scope.

## Verification

- `git diff master..gsd-reviewfix/04-50778` touched only `templates/docker/main.tf`.
- Re-traced all four paths: upgrade-with-real-json (auth preserved), fresh workspace (`{}`
  placeholder), idempotent re-run (`[ ! -L ]` guards no-op), and unmounted volume (non-fatal).
- Recommend a re-review (`/gsd-code-review 04`) or phase verification to confirm the BLOCKER is
  closed before marking phase 04 complete.
