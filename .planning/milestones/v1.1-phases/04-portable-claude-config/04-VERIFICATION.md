---
phase: 04-portable-claude-config
verified: 2026-06-18T00:00:00Z
status: verified
score: 5/5 must-haves verified
human_verification_result: "4/5 live smoke tests PASSED in UAT (auth-persistence, upgrade-path directory guard, content-preservation JSON, idempotency). Owner-isolation (#5) accepted as an acknowledged gate — no second owner account available to exercise it. See ## Acknowledged Gaps and 04-UAT.md."
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "Pre-existing real ~/.claude directory migrated before ln -sfn so symlink is never nested inside surviving real dir (CR-01)"
    - "Pre-existing real ~/.claude.json preserved into shared volume with cp -f BEFORE {} placeholder can shadow it (WR-01)"
    - "Unconditional rm -rf after masked copy failure eliminated — rm now conditional on copy success or empty source (WR-01/04-REVIEW WR-01)"
    - "First-run chown made non-fatal under set -e (WR-03/04-REVIEW WR-03)"
    - "README volume-cleanup comment no longer claims deletion is 'not data-unsafe'; now warns permanently destroys auth, settings, skills, MCP config (WR-03 prose)"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Live authentication smoke test: create workspace A for owner X. Open terminal, run 'claude', complete OAuth/subscription login. Stop workspace A. Create workspace B for the same owner X. Open terminal in B and run 'claude'."
    expected: "claude starts already authenticated in workspace B — no login prompt. Credentials from the per-owner volume are present transparently."
    why_human: "Requires a running Coder server and Docker host. Cannot be verified statically."
  - test: "Upgrade-path smoke test (CR-01 fix validation): take a workspace whose persistent home volume already contains a real ~/.claude directory (pre-phase-04 workspace or any workspace where claude was run before this template applied). Apply the new template, restart the workspace. Run 'ls -la ~/.claude' in the workspace terminal."
    expected: "~/.claude is a symlink: .claude -> .claude-shared/dot-claude. It is NOT a real directory, and there is no nested dot-claude symlink inside a surviving real directory."
    why_human: "Requires a workspace with a pre-existing real ~/.claude directory on its persistent home volume. The static code review confirms the guard logic is correct, but live execution in an upgrade scenario is required to confirm no regression."
  - test: "Content-preservation smoke test (WR-01 fix validation): take a workspace whose home volume contains a real ~/.claude.json with real auth data. Apply the new template, restart. Run 'cat ~/.claude.json' in the workspace terminal and check the shared volume contents."
    expected: "The real auth content is preserved in the shared dot-claude.json on the shared volume. ~/.claude.json is a symlink. The {} placeholder was NOT substituted for real auth data."
    why_human: "Requires a workspace with a pre-existing real ~/.claude.json containing auth material. The cp -f ordering fix is verified by code inspection, but live execution confirms no edge case."
  - test: "Idempotency test: stop and start the same workspace twice after the symlinks are established."
    expected: "The [ ! -L ] guards fire as no-ops on the second and subsequent starts. No repeated migration, no errors, ~/.claude and ~/.claude.json remain symlinks."
    why_human: "Requires a running workspace. Static analysis confirms the guard condition (! -L) is a no-op once symlinks exist."
  - test: "Owner isolation test: create workspaces for two different Coder owners X and Y. Run 'docker volume ls -f label=coder.purpose=claude-config' on the Docker host. Authenticate as X in X's workspace. Open Y's workspace and run 'claude'."
    expected: "Two distinct volumes with different UUID segments in their names. Y's workspace has no access to X's credentials and starts unauthenticated."
    why_human: "Requires a running Coder server with two distinct owner accounts."
---

# Phase 04: Portable Claude Config — Re-Verification Report

**Phase Goal:** A developer authenticates with Claude Code once and finds their credentials, settings, skills, and MCP servers waiting in every subsequent workspace — including newly created ones.
**Verified:** 2026-06-17T20:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (previous status: gaps_found, score 4/5)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | On a workspace whose persistent home volume already holds a real `~/.claude` directory (upgrade-from-prior-template path), the startup_script removes/migrates that real directory so `~/.claude` ends up as a symlink pointing into the shared per-owner volume — the symlink is NOT nested inside a surviving real directory (CR-01) | VERIFIED | `main.tf` line 147: `if [ ! -L "$HOME/.claude" ] && [ -e "$HOME/.claude" ]; then` guards the rm. Line 148-149: `cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null \|\| [ -z "$(ls -A "$HOME/.claude" 2>/dev/null)" ]` — rm only fires if copy succeeds or source is empty. Line 150: `rm -rf "$HOME/.claude"` runs only inside the conditional. Line 156: `ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"` runs AFTER the guard at a now-clear path. Commits 5a63ada (conditional rm) and 71d4256 (guard insertion). |
| 2 | On a workspace whose home volume already holds a real `~/.claude.json` file, the startup_script preserves that file's content into the shared dot-claude.json BEFORE the {} placeholder can shadow it — first-time-migration auth/config is not silently discarded (WR-01/CR-01) | VERIFIED | `main.tf` line 164-167: migration guard `if [ ! -L "$HOME/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then cp -f "$HOME/.claude.json" "$CLAUDE_SHARED/dot-claude.json"; rm -f "$HOME/.claude.json"; fi` runs at line 164. The `{}` placeholder guard `if [ ! -f "$CLAUDE_SHARED/dot-claude.json" ]; then echo '{}' > ...; fi` runs AFTER at line 172. Order: migrate (164) → placeholder-as-last-resort (172) → symlink (177). The critical fix: `cp -f` (force-overwrite) prevents the previous bug where `cp -n` (no-clobber) silently skipped once placeholder existed. Commit 6a21803. |
| 3 | Re-running the startup_script on every subsequent start stays idempotent: once `~/.claude` and `~/.claude.json` are symlinks, the `[ ! -L ]` guards are no-ops with no repeated migration and no data loss | VERIFIED | Both guards are gated on `! -L` (not a symlink). Once symlinks are established, `! -L` is false for both paths; neither guard body executes. The `ln -sfn` and `ln -sf` commands are themselves idempotent (update-in-place for existing symlinks). `set -e` is active but all paths within the guards are safe; the chown non-fatal guard (commit 0ddef8a, line 134-135) prevents startup_script abort if chown fails. |
| 4 | The README volume-cleanup comment no longer claims deletion is "not data-unsafe"; it warns that deleting the volume permanently destroys the owner's auth, settings, personal skills, and MCP config (WR-03 prose) | VERIFIED | `README.md` line 444: `# Remove a specific orphaned volume. WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.` Confirmed: `grep -c 'not data-unsafe' README.md` returns 0. "permanently", "WARNING", "skills", "MCP config" all present on line 444. Commit ca38655. |
| 5 | Per-owner volume infrastructure: volume declared with correct name, lifecycle, and isolation properties; symlinks wired into shared volume; `[REUSABLE]` drop-in block documented | VERIFIED | `docker_volume.claude_config_volume` at line 253: name `coder-${data.coder_workspace_owner.me.id}-claude` (owner UUID keying), `prevent_destroy = true`, `ignore_changes = [name]`, `coder.purpose = "claude-config"` label. Volume mounted at `/home/coder/.claude-shared` (line 357) after home volume (line 347-350) — correct parent-before-child ordering. `module "claude-code"` at line 417: v5.2.0, `install_claude_code = true`, `anthropic_api_key = var.anthropic_api_key`, `count = data.coder_workspace.me.start_count`. `[REUSABLE]` marker at line 49, `[END REUSABLE]` at line 427. |

**Score: 5/5 truths verified**

### Deferred Items

None. All five success criteria are within scope of this phase and are now verified by code inspection.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `templates/docker/main.tf` | CR-01/WR-01 guards before ln commands; placeholder as last resort; chown non-fatal; per-owner volume; claude-code module; [REUSABLE] block | VERIFIED | All elements present. Guard A (line 147-153) before `ln -sfn` (line 156). Guard B with `cp -f` (line 164-167) before placeholder (line 172-174) before `ln -sf` (line 177). Chown non-fatal (line 134-135). Volume resource (line 253-277). Module (line 417-425). REUSABLE markers (lines 49, 427). |
| `README.md` | `### Claude Code` operator runbook with first-run login, what is shared, seeding behavior, concurrent-write caveat, and accurate cleanup warning | VERIFIED | Section at line 400. First-run login at line 406-410. Four shared items at lines 415-418. Seeding/volume name at lines 425-429. Concurrent-write `> Note:` blockquote at lines 431-433. Cleanup with `WARNING: permanently...` at line 444. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `startup_script` dir guard (line 147) | `ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"` (line 156) | `[ ! -L ] && [ -e ]` gate; conditional rm-after-copy at 148-152 | WIRED | Guard at 147 < ln-sfn at 156; correct ordering confirmed |
| `startup_script` json migration (line 164) | `ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"` (line 177) | `cp -f` migration at 165, rm at 166, placeholder at 172-174 | WIRED | Migration (164) < placeholder (172) < ln-sf (177); correct ordering confirmed |
| `docker_container.workspace volumes{}` | `docker_volume.claude_config_volume` | `volume_name = docker_volume.claude_config_volume.name` at line 358 | WIRED | Confirmed at line 357-358 |
| `module.claude-code` | `variable.anthropic_api_key` | `anthropic_api_key = var.anthropic_api_key` | WIRED | Line 422 confirmed |
| `README.md Claude Code subsection` | `templates/docker/main.tf claude_config_volume` | references `coder-<owner-uuid>-claude` and `label=coder.purpose=claude-config` | WIRED | Lines 442-444 confirmed |

### Data-Flow Trace (Level 4)

Not applicable — this phase produces infrastructure configuration (Terraform HCL and shell), not a component that renders dynamic data. The runtime data-flow (Docker volume → symlink → Claude CLI reads/writes credentials) requires a live environment and is covered by human verification items.

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points. The artifacts are Terraform HCL and shell heredocs; no binary, service, or test suite can be exercised statically. Runtime behavior requires a live Coder server and Docker host (deferred to human verification items above).

### Probe Execution

Step 7c: No probe scripts declared or found. `find scripts -path '*/tests/probe-*.sh'` produced no results for this phase.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| CLAUDE-01 | 04-01-PLAN.md | Claude Code installed via `coder/claude-code` module v5.2.0 | SATISFIED | `module "claude-code"` at main.tf line 417 with `source = "registry.coder.com/coder/claude-code/coder"`, `version = "5.2.0"`, `install_claude_code = true` |
| CLAUDE-02 | 04-01-PLAN.md | Per-owner Docker volume (UUID-keyed, rename-safe, destroy-protected) | SATISFIED | `docker_volume.claude_config_volume` (line 253): `name = "coder-${data.coder_workspace_owner.me.id}-claude"`, `prevent_destroy = true`, `ignore_changes = [name]` |
| CLAUDE-03 | 04-01-PLAN.md / 04-03-PLAN.md | Full Claude config surface (`~/.claude/` + `~/.claude.json`) reliably migrated to and accessible from the shared volume, including the upgrade path | SATISFIED | Guards at lines 147-153 and 164-167 handle pre-existing real paths. `cp -f` ordering (6a21803) ensures real content is preserved before placeholder. `cp -an` + conditional rm (5a63ada) ensures directory is only removed after successful copy. Both paths end with the shared-volume symlinks established. |
| CLAUDE-04 | 04-01-PLAN.md / 04-03-PLAN.md | Shared volume writable by `coder` user; startup_script steps idempotent and safe to re-run | SATISFIED | `stat`-guarded `chown -R coder:coder "$CLAUDE_SHARED"` with non-fatal `\|\| echo "WARN..."` at lines 133-136 (commit 0ddef8a). Both `[ ! -L ]` guards are no-ops once symlinks exist. |
| CLAUDE-05 | 04-01-PLAN.md | First-run login works on empty volume; no API key required by default | SATISFIED | `anthropic_api_key` defaults to `""` (line 82-85); OAuth is the default path. On an empty home volume, both guards skip (no pre-existing paths), `dot-claude/` is mkdir'd, `{}` placeholder is created, symlinks established — Claude CLI finds a clean shared config location. |
| CLAUDE-06 | 04-01-PLAN.md | Reusable drop-in snippet documented in-file | SATISFIED | `[REUSABLE]` at line 49, `[END REUSABLE]` at line 427. Spans `anthropic_api_key` variable, `docker_volume.claude_config_volume`, mount in container resource, startup_script Claude block, and `module "claude-code"` with WHAT/HOW TO USE/OPERATOR NOTES/MOUNT LAYOUT sections. |
| CLAUDE-07 | 04-02-PLAN.md / 04-03-PLAN.md | README operator runbook covering first-run, what is shared, seeding, concurrent-write caveat, and accurate cleanup blast-radius warning | SATISFIED | `### Claude Code` at README.md line 400. All four required topics present. Cleanup comment at line 444 now reads `WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.` — "not data-unsafe" removed (commit ca38655). |

**All 7 requirement IDs (CLAUDE-01 through CLAUDE-07) are accounted for. No orphaned requirements.**

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `templates/docker/main.tf` | 148-149 | `cp -an ... 2>/dev/null \|\| [ -z "$(ls -A ...)" ]` — stderr suppressed on cp | INFO | Intentional design: `2>/dev/null` prevents noise on empty source directories while `\|\| [ -z "$(ls -A ...)" ]` separates "empty source is OK" from "copy failure on non-empty source". The else branch (line 152) documents leaving the original in place on genuine failure. This is not a stub — it is a deliberate error-handling pattern from the WR-01 fix (commit 5a63ada). |

No `TBD`, `FIXME`, or `XXX` markers found in modified files. No stub patterns. No hardcoded empty data flowing to user-visible output.

**Note on SUMMARY vs. live code discrepancy:** The 04-03-SUMMARY.md describes Guard B as using `cp -n` (no-clobber), but the live code uses `cp -f` (force-overwrite). This is not a regression — it is expected. The REVIEW-FIX commits (6a21803) were applied after the 04-03 SUMMARY was written. The SUMMARY documented the initial gap-closure attempt; the REVIEW correctly identified that `cp -n` was still wrong (it is the no-clobber primitive that cannot report a skip, the original bug), and commit 6a21803 upgraded it to `cp -f`. The live code is correct and supersedes the SUMMARY narrative.

### Human Verification Required

#### 1. Live Authentication Smoke Test (SC-1, SC-2, SC-3)

**Test:** Create workspace A for owner X on the updated template. Open a terminal and run `claude`. Complete the interactive OAuth/subscription login. Stop workspace A. Create workspace B for the same owner X. Open a terminal in B and run `claude`.
**Expected:** `claude` starts already authenticated in workspace B — no login prompt. Credentials from the per-owner volume are present transparently.
**Why human:** Requires a running Coder server and Docker host. Cannot be automated statically.

#### 2. Upgrade-Path Smoke Test — Directory Guard (CR-01 Fix Validation)

**Test:** Take a workspace whose persistent home volume already contains a real `~/.claude` directory (pre-phase-04 workspace, or any workspace where `claude` was run before this template applied). Apply the updated template, restart the workspace. Run `ls -la ~/.claude` in the workspace terminal.
**Expected:** `~/.claude` is a symlink: `.claude -> .claude-shared/dot-claude`. The path is NOT a real directory, and there is no nested `dot-claude` symlink inside a surviving real directory.
**Why human:** Requires a workspace with a pre-existing real `~/.claude` directory on its persistent home volume. Code inspection confirms the guard logic is correct; live execution in an upgrade scenario confirms no runtime edge case.

#### 3. Content-Preservation Smoke Test — JSON Guard (WR-01 Fix Validation)

**Test:** Take a workspace whose home volume contains a real `~/.claude.json` with real auth data. Apply the updated template, restart the workspace. Run `cat ~/.claude.json` and check the shared volume's `dot-claude.json`.
**Expected:** The real auth content is preserved in the shared `dot-claude.json`. `~/.claude.json` is a symlink. The `{}` placeholder was NOT substituted for the real auth data.
**Why human:** Requires a workspace with a pre-existing real `~/.claude.json` containing auth material. The `cp -f` ordering fix is verified by code inspection; live execution confirms the fix under real conditions.

#### 4. Idempotency Test

**Test:** Stop and start the same workspace twice after the symlinks are established. Observe no errors in the startup log and run `ls -la ~/.claude ~/.claude.json` to confirm both remain symlinks.
**Expected:** The `[ ! -L ]` guards fire as no-ops on the second and subsequent starts. No repeated migration, no errors, `~/.claude` and `~/.claude.json` remain symlinks.
**Why human:** Requires a running workspace. Static analysis confirms the guard condition (`! -L`) is a no-op once symlinks exist; runtime confirmation is best practice.

#### 5. Owner Isolation Test (SC-4)

**Test:** Create workspaces for two different Coder owners X and Y. Run `docker volume ls -f label=coder.purpose=claude-config` on the Docker host. Authenticate as X in X's workspace. Open Y's workspace and run `claude`.
**Expected:** Two distinct volumes with different UUID segments in their names. Y's workspace has no access to X's credentials and starts unauthenticated.
**Why human:** Requires a running Coder server with two distinct owner accounts.

### Live UAT Results (2026-06-18)

The five human-verification items above were exercised against a live Coder + Docker
deploy during `/gsd-verify-work 04`. Results:

| # | Human verification item | Result |
|---|--------------------------|--------|
| 1 | Live authentication smoke test (SC-1/2/3) — login in A → B pre-authenticated | ✅ PASS |
| 2 | Upgrade-path directory guard (CR-01) — real `~/.claude` dir → symlink, no nesting | ✅ PASS |
| 3 | Content-preservation JSON (WR-01) — real `~/.claude.json` survives, no `{}` clobber | ✅ PASS |
| 4 | Idempotency — `[ ! -L ]` guards no-op across restarts, symlinks stable | ✅ PASS |
| 5 | Owner isolation (SC-4) — two owners X/Y, distinct volumes, no cross-access | ⛔ ACKNOWLEDGED GATE |

Both data-loss paths (#2, #3) and the core auth-persistence promise (#1) passed live.

### Acknowledged Gaps

- gate: "Owner isolation (SC-4): two distinct owners X and Y get distinct per-owner
  `-claude` volumes, and Y's workspace cannot read X's credentials / starts unauthenticated."
  status: not_exercised
  reason: "No second owner account available in the test environment to drive the two-owner
  path. Accepted by the user (stephan@wald.tv) on 2026-06-18 as an acknowledged gate; phase
  marked complete without it. Isolation logic is verified by code inspection (per-owner volume
  keyed on `data.coder_workspace_owner.me.id` UUID — truth #5, Requirement CLAUDE-02)."
  follow_up: "Re-run `/gsd-verify-work 04` once a second owner account exists to close live."

### Re-Verification Summary

**Previous status:** `gaps_found` (4/5 must-haves, one structural BLOCKER: CR-01 — ln -sfn nesting symlink inside surviving real directory; WR-01 — cp -n preceded by placeholder creation silently discarded real .claude.json auth data)

**Gaps closed in this re-verification:**

1. **CR-01 (BLOCKER — directory):** `main.tf` lines 147-153 now have a proper `[ ! -L ] && [ -e ]` guard with migrate-then-conditional-rm before `ln -sfn`. The `rm -rf` is inside a conditional that only fires when the `cp -an` succeeded OR the source was empty — addressing the WR-01 (REVIEW) masked-copy-failure risk simultaneously. Commits 71d4256 + 5a63ada.

2. **CR-01 (BLOCKER — json/ordering):** `main.tf` lines 164-177 now run migration (`cp -f`) FIRST, placeholder-as-last-resort SECOND, symlink THIRD. The `cp -f` ensures a real file force-overwrites any placeholder already in the shared volume. Commit 6a21803.

3. **WR-03 (chown non-fatal):** `main.tf` line 134-135: `sudo chown ... || echo "WARN: ..."`. Commit 0ddef8a.

4. **WR-03 (README prose):** `README.md` line 444: `WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.` Commit ca38655.

**All 5/5 must-haves from the gap-closure plan (04-03-PLAN.md) are verified by code inspection.** No regressions found against previously-passing truths (volume infrastructure, isolation, README structure).

**Status:** `human_needed` — all automated checks pass. Live smoke tests (authentication, upgrade-path, content-preservation, idempotency, isolation) require a running Coder + Docker environment and cannot be verified statically.

---

_Verified: 2026-06-17T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — after CR-01/WR-01/WR-03 gap closure_
