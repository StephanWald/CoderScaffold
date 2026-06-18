---
phase: 04-portable-claude-config
plan: "03"
subsystem: workspace-template
tags: [claude-code, terraform, startup-script, symlinks, idempotent, gap-closure]
dependency_graph:
  requires:
    - phase: 04-01
      provides: startup_script symlink block with ln -sfn / ln -sf
    - phase: 04-02
      provides: README Claude Code operator runbook with volume cleanup comment
  provides:
    - upgrade-path-guard for pre-existing real ~/.claude directory (CR-01)
    - content-preservation guard for pre-existing real ~/.claude.json file (WR-01)
    - corrected README blast-radius wording for docker volume rm (WR-03)
  affects: [templates/docker/main.tf, README.md]
tech_stack:
  added: []
  patterns:
    - "migrate-before-delete: cp -an (no-clobber) then rm -rf for safe directory upgrade"
    - "symlink idempotency gate: [ ! -L path ] prevents repeated migration on re-runs"
    - "WARNING: prefix in operator comments for irreversible destructive actions"
key_files:
  modified:
    - templates/docker/main.tf
    - README.md
key_decisions:
  - "Guard A uses [ ! -L ] && [ -e ] to catch any non-symlink path (file, dir, or broken) before rm -rf"
  - "cp -an (archive + no-clobber) for directory migration — preserves timestamps, never overwrites existing shared content"
  - "cp -n (no-clobber) for .claude.json migration — shared file initialized to {} by prior guard, cp -n skips if already real content exists"
  - "WR-02 (optional chown hardening) skipped — wrapping the existing stat-guarded chown in an additional [ -d $CLAUDE_SHARED ] gate would require restructuring the existing block; plan permitted skipping it cleanly"
  - "terraform/tofu not in env — grep assertions served as the authoritative validation gate (same as 04-01)"
requirements-completed: [CLAUDE-03, CLAUDE-04, CLAUDE-07]
duration: 2min
completed: "2026-06-17"
---

# Phase 4 Plan 03: Gap Closure — Symlink Guards and README Blast-Radius Fix Summary

**Idempotent migrate-before-delete guards added to startup_script (CR-01, WR-01) and README cleanup comment corrected to state permanent data destruction (WR-03) — closes all remaining phase 04 verification gaps.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-06-17T18:38:58Z
- **Completed:** 2026-06-17T18:40:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Inserted Guard A into `coder_agent.main.startup_script`: detects a pre-existing real `~/.claude` directory (upgrade-from-prior-template path), copies contents into the shared volume with `cp -an` (no-clobber), then removes the real directory so the subsequent `ln -sfn` creates a clean symlink — CR-01 fixed
- Inserted Guard B: detects a pre-existing real `~/.claude.json` file, preserves content into the shared volume with `cp -n`, then removes the real file so `ln -sf` creates a clean symlink — WR-01 fixed (first-time-migration auth not silently discarded)
- Both guards are strictly idempotent: the `[ ! -L ]` test is a no-op once the symlinks exist — D-02 discipline preserved
- Corrected the README `docker volume rm` inline comment: removed "not data-unsafe" framing, replaced with `WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.` — WR-03 fixed

## Exact Shell Text Inserted (Task 1)

Guard A (CR-01 — inserted before `ln -sfn`):
```sh
# CR-01 upgrade-path fix: if ~/.claude is a real dir (pre-template workspace),
# migrate contents into the shared volume before replacing with a symlink.
if [ ! -L "$HOME/.claude" ] && [ -e "$HOME/.claude" ]; then
  cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null || true
  rm -rf "$HOME/.claude"
fi
```

Guard B (WR-01 — inserted before `ln -sf`):
```sh
# WR-01 content-preservation fix: if ~/.claude.json is a real file, preserve
# its content into the shared volume before replacing with a symlink.
if [ ! -L "$HOME/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then
  cp -n "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"
  rm -f "$HOME/.claude.json"
fi
```

## Final README Comment Text (Task 2)

Before: `# Remove a specific orphaned volume (deletion forces re-login for that owner — not data-unsafe)`

After: `# Remove a specific orphaned volume. WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.`

## WR-02 Optional Hardening Decision

WR-02 (wrapping the existing stat-guarded `chown` in an additional `[ -d $CLAUDE_SHARED ]` gate) was **skipped**. The plan permitted skipping it if it would require restructuring existing logic. Wrapping the chown would require enclosing the existing multi-line chown/mkdir/symlink sequence in an outer `if` block, restructuring the control flow that was finalized in 04-01. The grep assertions and idempotency properties of the current block already prevent harm if `$CLAUDE_SHARED` is absent, and the mount ensures it is always a directory at container start. No correctness gap — skip is appropriate.

## Terraform/Tofu Validation

`terraform` and `tofu` are not installed in this environment. Per the plan's verification clause, grep assertions served as the authoritative validation gate. All assertions passed:

```
grep -q 'if \[ ! -L "\$HOME/.claude" \]' — PASS
grep -q 'rm -rf "\$HOME/.claude"' — PASS
grep -q 'cp -an "\$HOME/.claude/." "\$CLAUDE_SHARED/dot-claude/"' — PASS
grep -q '\[ ! -L "\$HOME/.claude.json" \]' — PASS
grep -q 'cp -n "\$HOME/.claude.json" "\$CLAUDE_SHARED/dot-claude.json"' — PASS
grep -q 'rm -f "\$HOME/.claude.json"' — PASS
grep -c 'ln -sfn ...' (== 1) — PASS
! grep -q 'not data-unsafe' — PASS
grep -qi 'permanently' — PASS
grep -qi 'WARNING' — PASS
grep -qi 'mcp' — PASS
```

Ordering assertions:
- Guard A (line 145) < `ln -sfn` (line 151) — PASS
- Guard B (line 155) < `ln -sf` (line 161) — PASS
- No `rm -rf "$HOME"` or `rm -rf "$CLAUDE_SHARED"` introduced — PASS

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: startup_script symlink guards (CR-01, WR-01) | 71d4256 | 14 lines inserted into coder_agent.main.startup_script |
| Task 2: README blast-radius correction (WR-03) | ca38655 | 1 comment line updated in Claude Code runbook |

## Files Modified

- `templates/docker/main.tf` — Two guard blocks inserted between `echo '{}'` guard and existing `ln` lines in startup_script
- `README.md` — One inline comment corrected in the `### Claude Code` volume cleanup fenced block

## Decisions Made

- Guard A condition is `[ ! -L ] && [ -e ]` (not just `[ -d ]`) so it catches any non-symlink entity at `$HOME/.claude` — a broken symlink, a plain file placed there unexpectedly, or a directory. This is strictly safer than `[ -d ]`.
- `cp -an` (archive + no-clobber) chosen over plain `cp -r` for directory migration: `-a` preserves timestamps and permissions; `-n` ensures no content in the shared volume is overwritten if the migration is somehow triggered twice.
- `2>/dev/null || true` on the `cp -an` suppresses errors on empty source directories (valid state on a workspace that had no real Claude config) while still completing the `rm -rf`.
- WR-02 optional chown hardening skipped (see above).

## Deviations from Plan

None — plan executed exactly as written. Both guards implemented with the exact patterns specified in the plan's `<action>` blocks. WR-02 was marked optional and was explicitly permitted to be skipped.

## Requirements Coverage

| Requirement | Status | How Satisfied |
|-------------|--------|---------------|
| CLAUDE-03 | Satisfied | Full config surface (real pre-existing `~/.claude` dir + `~/.claude.json` file) reliably migrated to shared volume on upgrade path; both end as symlinks |
| CLAUDE-04 | Satisfied | Idempotency discipline (D-02) preserved: both guards are no-ops once symlinks exist |
| CLAUDE-07 | Satisfied | README cleanup comment accurately states true blast radius (permanent destruction of auth, settings, skills, MCP config); "not data-unsafe" removed |

## Known Stubs

None. All changes are functional shell guards and prose corrections — no placeholder content.

## Threat Flags

No new security-relevant surface introduced. The threat model for T-04-06 (data-loss via mis-scoped `rm`) is fully mitigated: both `rm` operations are gated behind `[ ! -L ]` checks and preceded by no-clobber migrations. Paths are string literals `$HOME/.claude` and `$HOME/.claude.json` — no variable expansion that could widen scope.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| templates/docker/main.tf | FOUND |
| README.md | FOUND |
| 04-03-SUMMARY.md | FOUND |
| Commit 71d4256 (Task 1) | FOUND |
| Commit ca38655 (Task 2) | FOUND |
| Guard A `[ ! -L "$HOME/.claude" ]` | FOUND |
| Guard B `[ ! -L "$HOME/.claude.json" ]` | FOUND |
| `cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/"` | FOUND |
| `cp -n "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"` | FOUND |
| `rm -rf "$HOME/.claude"` | FOUND |
| `rm -f "$HOME/.claude.json"` | FOUND |
| `not data-unsafe` absent from README.md | CONFIRMED |
| `WARNING: permanently` present in README.md | CONFIRMED |
| Guard A before `ln -sfn` (line 145 < 151) | CONFIRMED |
| Guard B before `ln -sf` (line 155 < 161) | CONFIRMED |
