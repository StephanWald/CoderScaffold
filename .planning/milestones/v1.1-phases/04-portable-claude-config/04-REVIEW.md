---
phase: 04-portable-claude-config
reviewed: 2026-06-17T18:46:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - templates/docker/main.tf
findings:
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-06-17T18:46:00Z
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

Reviewed `templates/docker/main.tf` at standard depth, with adversarial focus on the
gap-closure shell logic (CR-01 / WR-01) in `coder_agent.main.startup_script` — the
migrate-then-symlink guards for `~/.claude` and `~/.claude.json`.

The Terraform interpolation-vs-shell escaping is clean (every `${...}` in the heredoc is a
legitimate Terraform reference; the shell body uses `$VAR` / `$(...)` which Terraform passes
through literally, and the unrelated metadata script on line 190 correctly double-escapes
`$${HOME}`). Idempotency on re-run is also sound — the `[ ! -L ... ]` gates correctly turn
both guards into no-ops once the symlinks exist, including for dangling symlinks.

However, the headline WR-01 "content-preservation fix" **does not preserve content** and
silently destroys real auth data on the exact upgrade path it was written to protect. This is
a reproduced data-loss BLOCKER. A second data-loss path exists where a masked copy failure is
followed by an unconditional `rm -rf`. Together these defeat the core portability goal of the
phase. All findings below were validated by executing the shell sequences with the file's exact
ordering.

## Critical Issues

### CR-01: WR-01 "content-preservation" guard silently discards real `~/.claude.json` auth on the upgrade path

**File:** `templates/docker/main.tf:139-141, 155-158`
**Issue:**
The placeholder guard (lines 139-141) **always creates** `$CLAUDE_SHARED/dot-claude.json`
(`echo '{}' > ...`) *before* the WR-01 migration guard (lines 155-158) runs. By the time
`cp -n "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"` executes, the destination already
exists, so `cp -n` (no-clobber) **silently skips the copy and still returns exit 0** (GNU
coreutils behavior — verified). The very next line, `rm -f "$HOME/.claude.json"`, then deletes
the developer's real `~/.claude.json`.

Net effect on a workspace whose home volume already holds a real `~/.claude.json` (the exact
"ran `claude` before this template" upgrade scenario WR-01 targets): the real auth/config is
deleted and the shared file remains `{}`. **The fix preserves nothing.** Reproduced end-to-end:
a `~/.claude.json` containing `{"oauth":"REAL_AUTH_TOKEN"}` results in shared `dot-claude.json`
== `{}` after the sequence, and the original is gone.

This is silent data loss of authentication material — must be fixed before ship.

**Fix:** The migration must win over the placeholder. Either (a) move the migration guard
*before* the `echo '{}'` placeholder, or (b) make the placeholder conditional on the migration
not having supplied content, or (c) drop `-n` and copy when the existing shared file is just the
placeholder. Simplest correct ordering — run migration first, placeholder only as a last resort:

```sh
# Migrate a pre-existing real ~/.claude.json into the shared volume FIRST,
# before the placeholder can shadow it. Force-overwrite the (possibly-placeholder)
# shared file with the real content.
if [ ! -L "$HOME/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then
  cp -f "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"
  rm -f "$HOME/.claude.json"
fi

# Only create the {} placeholder if neither a real file nor a prior shared file exists.
if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then
  echo '{}' > "$CLAUDE_SHARED/dot-claude.json"
fi

ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
```

Note: a naive `cp -n` can never work here as long as the placeholder runs first — the
destination is guaranteed to exist. The overwrite must be intentional (`cp -f`), guarded by the
`[ ! -L ] && [ -f ]` test which already proves the source is the developer's real file.

## Warnings

### WR-01: `~/.claude` directory migration: masked copy failure followed by unconditional `rm -rf` = data loss

**File:** `templates/docker/main.tf:146-147`
**Issue:**
The migration copy `cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null || true`
deliberately swallows all errors (stderr hidden, `|| true`), and the next line
`rm -rf "$HOME/.claude"` runs **unconditionally**. If the copy fails for any reason (shared
volume full, permission/ownership problem on the mount, the dest path not being a directory due
to a mount-shadowing race), the real `~/.claude` directory is deleted while nothing was
preserved. Reproduced: forcing the copy to fail leaves the original deleted and the shared dest
empty. The `|| true` exists to tolerate an empty source (so `set -e` doesn't abort), but it also
masks genuine failures.

**Fix:** Only delete the original if the copy actually succeeded. Separate "empty source is OK"
from "copy failed":

```sh
if [ ! -L "$HOME/.claude" ] && [ -e "$HOME/.claude" ]; then
  if cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null \
     || [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; then
    rm -rf "$HOME/.claude"
  fi
  # else: copy failed on a non-empty dir — leave original in place, do NOT rm.
fi
```

(At minimum, do not `rm -rf` when `cp` returned non-zero on a non-empty source.)

### WR-02: `cp -n` for the JSON guard cannot report a clobber-skip — wrong tool for a "preserve" intent

**File:** `templates/docker/main.tf:156`
**Issue:**
Even independent of the ordering bug in CR-01, `cp -n` is the wrong primitive for a
content-preservation step: it returns exit 0 whether it copied or skipped, so the script can
never tell whether the developer's content actually landed in the shared volume. There is no
detection of, or recovery from, the silent-skip case. This is the underlying reason CR-01 is
silent rather than loud.

**Fix:** Make the migration intent explicit (overwrite a known-placeholder, or compare before
copying) and verify the result, e.g. after `cp -f`, optionally assert the destination is no
longer the literal `{}` placeholder before removing the source. See CR-01 fix.

### WR-03: `set -e` + first-run `sudo chown` can abort the entire startup before symlinks are created

**File:** `templates/docker/main.tf:115, 130-132`
**Issue:**
With `set -e` active, if the first-run ownership fix `sudo chown -R coder:coder "$CLAUDE_SHARED"`
(line 131) returns non-zero — e.g. no passwordless sudo in a custom `workspace_image`, or a
busy/locked file under the mount — the startup_script aborts immediately. Because this chown sits
*before* the `mkdir`, migration guards, and `ln` commands, an abort here leaves `~/.claude` and
`~/.claude.json` unconfigured (no symlinks), and the claude-code module then runs against a
broken layout. The stat-based guard only narrows *when* chown runs; it does nothing to make the
chown itself non-fatal.

**Fix:** Make the ownership fix non-fatal and log instead of aborting:

```sh
if [ "$(stat -c '%U' "$CLAUDE_SHARED")" != "coder" ]; then
  sudo chown -R coder:coder "$CLAUDE_SHARED" \
    || echo "WARN: could not chown $CLAUDE_SHARED; continuing" >&2
fi
```

### WR-04: `stat` failure on a missing mount point yields an unconditional `chown -R` that aborts under `set -e`

**File:** `templates/docker/main.tf:130-131`
**Issue:**
If `$CLAUDE_SHARED` does not exist (e.g. the second `volumes{}` block was omitted by an operator
copying the [REUSABLE] block, or a mount failure), `stat -c '%U' "$CLAUDE_SHARED"` prints nothing
to stdout (error to stderr). The condition `[ "" != "coder" ]` is then **true**, so
`sudo chown -R coder:coder "$CLAUDE_SHARED"` runs against a nonexistent path, fails, and aborts
the whole startup_script under `set -e`. This is a confusing failure mode for the documented
"copy the [REUSABLE] block" workflow. Confirmed: the condition is taken when the path is absent.

**Fix:** Gate the whole Claude block on the mount existing, per the plan's optional WR-02
hardening (which was skipped):

```sh
if [ -d "$CLAUDE_SHARED" ]; then
  # chown / mkdir / migration / symlink steps ...
else
  echo "WARN: $CLAUDE_SHARED not mounted; skipping Claude shared-config setup" >&2
fi
```

## Info

### IN-01: `coalesce` on `full_name` assumes null-vs-empty-string semantics

**File:** `templates/docker/main.tf:165, 167`
**Issue:**
`coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)` relies on
`full_name` being `null` (not `""`) when unset for the fallback to engage. Coder commonly returns
an **empty string** for an unset full name; `coalesce` skips only `null`, so `GIT_AUTHOR_NAME`
could be set to `""` rather than falling back to `name`. Not a correctness blocker, but the
fallback may not fire as intended.
**Fix:** Use a length check, e.g.
`data.coder_workspace_owner.me.full_name != "" ? ...full_name : ...name`, or `try`-based handling.

### IN-02: Redundant interpolation wrapping on email env values

**File:** `templates/docker/main.tf:166, 168`
**Issue:**
`GIT_AUTHOR_EMAIL = "${data.coder_workspace_owner.me.email}"` wraps a single reference in a string
template. It is harmless but inconsistent with the bare-reference style used two lines up for the
`_NAME` values. Minor style/consistency nit.
**Fix:** Drop the quotes/`${}`: `GIT_AUTHOR_EMAIL = data.coder_workspace_owner.me.email`.

---

_Reviewed: 2026-06-17T18:46:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
