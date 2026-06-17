---
phase: 04-portable-claude-config
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - templates/docker/main.tf
  - README.md
findings:
  critical: 1
  warning: 3
  info: 3
  total: 7
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the two phase-04 changes: the portable Claude Code config additions to
`templates/docker/main.tf` (anthropic_api_key variable, per-owner
`claude_config_volume` with `prevent_destroy`, the `.claude-shared` mount, the
startup_script symlink/seed block, and the `claude-code` v5.2.0 module) and the
`### Claude Code` README operator runbook.

The secret-handling (`sensitive = true`), volume lifecycle (`prevent_destroy` +
`ignore_changes = [name]`), owner-UUID keying, mount-ordering, and Terraform
heredoc escaping are all correct. No Terraform interpolation leaks into the shell
block, and the `set -e` / `stat` guard does not mis-abort on a missing path.

The dominant defect is in the symlink-seeding logic: `ln -sfn` does **not**
replace a pre-existing real `~/.claude` **directory** — it creates a symlink
*nested inside* it, silently leaving the shared volume unused for `~/.claude`.
This breaks the core portability guarantee on any workspace whose persistent home
volume already contains a real `~/.claude` (the exact upgrade/re-provision path
this template is built to support). Secondary findings cover silent data loss on
`~/.claude.json`, a stderr-noise path in the chown guard, and a README/behavior
mismatch on what "data-unsafe" cleanup means.

## Critical Issues

### CR-01: `ln -sfn` does not replace a pre-existing real `~/.claude` directory — shared volume silently bypassed

**File:** `templates/docker/main.tf:144`
**Issue:**
The symlink seed runs:
```sh
ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"
```
This is only correct when `$HOME/.claude` does not yet exist (or is already a
symlink). If `$HOME/.claude` already exists as a **real directory**, `ln -sfn`
does NOT replace it — it creates the link *inside* the directory at
`$HOME/.claude/dot-claude`, and `$HOME/.claude` stays a real directory. Verified:

```
$ mkdir .claude; echo x > .claude/settings.json
$ ln -sfn /shared/dot-claude .claude
$ ls .claude
dot-claude -> /shared/dot-claude   # nested symlink
settings.json                       # original dir still real
```

`/home/coder` is a **persistent** volume that survives stop/start. So whenever a
workspace's home volume already holds a real `~/.claude` directory, this block
leaves `~/.claude` pointing at local home-volume storage, NOT the shared
per-owner volume. Claude then reads/writes settings, skills, and MCP config to the
non-shared path. The portability guarantee (CLAUDE-01/02/03 — "carries across
every workspace … with no manual copy step") silently fails, and nothing in the
script detects it.

This is not hypothetical: it is the upgrade path. Any workspace created under the
phase-03 template (or any earlier image where `claude`/code-server seeded
`~/.claude`) carries a real `~/.claude` in its persistent home volume; pushing
this template as an update hits the bug on the very next start. The chown guard
will even report `coder` and skip, so there is no remediation signal.

**Fix:** Replace the existing real path before symlinking, idempotently and only
when it is not already the correct symlink:
```sh
# ~/.claude → shared dir. Remove a pre-existing real dir/file first; the
# -L test ensures we never delete an already-correct symlink (idempotent).
if [ ! -L "$HOME/.claude" ]; then
  rm -rf "$HOME/.claude"
fi
ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"
```
If preserving any pre-existing real `~/.claude` content matters on migration,
seed it into the shared volume before removal:
```sh
if [ -d "$HOME/.claude" ] && [ ! -L "$HOME/.claude" ]; then
  cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null || true
  rm -rf "$HOME/.claude"
fi
```

## Warnings

### WR-01: `~/.claude.json` symlink silently discards a pre-existing real config file

**File:** `templates/docker/main.tf:147`
**Issue:**
```sh
ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
```
Unlike the directory case, `ln -sf` on a pre-existing real **file** succeeds and
replaces it with the symlink — but the original file content is silently
discarded. On any home volume that already contains a real `~/.claude.json`
(prior template version, prior interactive `claude` run), the operator's existing
settings/session state are thrown away in favor of the `{}` placeholder, with no
warning. Combined with CR-01 this produces an inconsistent state: `~/.claude.json`
flips to shared (losing local data) while `~/.claude` stays local — the two
diverge.
**Fix:** Migrate before linking, guarding on `-L` for idempotency:
```sh
if [ -f "$HOME/.claude.json" ] && [ ! -L "$HOME/.claude.json" ]; then
  # seed the shared file from the existing real file only if shared is still the placeholder
  cp -n "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json" 2>/dev/null || true
  rm -f "$HOME/.claude.json"
fi
ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
```

### WR-02: chown `stat` guard emits a stderr error and an empty comparison on first run if the mount is unexpectedly absent

**File:** `templates/docker/main.tf:130`
**Issue:**
```sh
if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
```
If `$CLAUDE_SHARED` does not exist for any reason (mount not yet present, mount
path typo, future refactor), `stat` writes `stat: cannot statx … No such file or
directory` to stderr (surfaced in the agent startup log as a scary error) and the
substitution yields an empty string, which is `!= "coder"`, so `chown -R` then
runs against a nonexistent path and fails. Under `set -e`, the `chown` failure on
line 131 (not inside a substitution) would abort the whole startup_script,
blocking the skel/symlink steps that follow. The script never asserts the mount
exists.
**Fix:** Assert the mount up front (fail fast with a clear message) or guard the
stat:
```sh
if [ ! -d "$CLAUDE_SHARED" ]; then
  echo "ERROR: $CLAUDE_SHARED not mounted — claude_config_volume mount missing" >&2
  exit 1
fi
if [ "$(stat -c '%U' "$CLAUDE_SHARED" 2>/dev/null)" != "coder" ]; then
  sudo chown -R coder:coder "$CLAUDE_SHARED"
fi
```

### WR-03: README claims volume deletion is "not data-unsafe" — but it destroys auth credentials and session tokens

**File:** `README.md:444`
**Issue:**
```
# Remove a specific orphaned volume (deletion forces re-login for that owner — not data-unsafe)
```
The per-owner volume stores, per the same README (lines 414-418) and the threat
model, "Auth credentials and session tokens", global settings, **personal skills
(`.claude/` skill files)**, and user-scoped MCP server config. Deleting it does
not merely force a re-login — it permanently destroys any user-authored skills and
MCP configuration that live only on that volume. Calling this "not data-unsafe"
understates the blast radius and could lead an operator to delete a still-active
owner's volume believing only a cheap re-login is at stake. The whole point of
`prevent_destroy` is that this data is precious.
**Fix:** Reword to reflect the real cost, e.g.:
```
# Remove a specific orphaned volume. WARNING: this permanently deletes that
# owner's Claude auth, settings, personal skills, and MCP config. Only run on
# volumes belonging to deleted owners.
```

## Info

### IN-01: chown guard misses the case where the mount-point is `coder`-owned but inner files are root-owned

**File:** `templates/docker/main.tf:130-132`
**Issue:** The guard checks ownership of `$CLAUDE_SHARED` only. If the top-level
mount point is later `coder`-owned but a subtree entry (e.g. `dot-claude/`) is
root-owned (a stray root write, a future seed step), the `-R` chown is skipped and
`claude` may hit permission errors writing into the subtree.
**Fix:** Either accept (low likelihood, documented elsewhere) or stat the
concrete write target (`$CLAUDE_SHARED/dot-claude`) rather than the mount root.

### IN-02: `dot-claude.json` placeholder seeds `{}` but the script never ensures the symlink chain is valid before the module runs

**File:** `templates/docker/main.tf:139-147`
**Issue:** The flow assumes the agent startup_script always completes before the
`claude-code` module's run-on-start scripts execute. That ordering holds today
(agent init precedes module scripts), but it is an undocumented invariant the
correctness depends on. If a future module gains an earlier hook, `claude` could
write `~/.claude.json` as a real file before the symlink exists (the exact
anti-pattern the placeholder is meant to prevent).
**Fix:** Add a one-line comment at line 387 (`module "claude-code"`) noting it
must run after the agent startup_script, so the invariant is explicit.

### IN-03: README "What carries across workspaces" omits that a pre-existing real `~/.claude` will NOT carry (see CR-01)

**File:** `README.md:412-429`
**Issue:** The runbook presents portability as unconditional ("available in every
subsequent workspace … no manual copy step"). Given CR-01, that is only true for
home volumes that never held a real `~/.claude`. Until CR-01 is fixed the docs
overpromise; after it is fixed (with migration), a one-line note on the
upgrade-from-old-workspace behavior would still help operators.
**Fix:** After CR-01 is resolved, add a sentence noting first-start migration of
any pre-existing `~/.claude`/`~/.claude.json` into the shared volume.

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
