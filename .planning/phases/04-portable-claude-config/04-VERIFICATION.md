---
phase: 04-portable-claude-config
verified: 2026-06-17T00:00:00Z
status: gaps_found
score: 4/5 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Operator runs claude in a fresh workspace; after authenticating once, a second workspace for the same owner starts already authenticated with no login prompt (SC-1) — AND two of the same owner's workspaces share one authenticated Claude session via ~/.claude and ~/.claude.json on the per-owner volume (SC-2 and SC-3)"
    status: failed
    reason: "ln -sfn does not replace a pre-existing real ~/.claude directory. If the home volume (persistent across stop/start) already contains a real ~/.claude directory — the exact situation for any workspace upgraded from phase-03 or any workspace where Claude was run before this template applied — ln -sfn nests the symlink inside the existing directory rather than replacing it. The shared volume is then silently bypassed for ~/.claude. The portability guarantee fails with no error signal. The ~/.claude.json case is worse: ln -sf replaces the file with the symlink but discards the original content silently (WR-01). CR-01 from the code review is independently confirmed: no guard (if [ ! -L ]; then rm -rf) or migration (cp -an) appears anywhere in templates/docker/main.tf."
    artifacts:
      - path: "templates/docker/main.tf"
        issue: "Lines 143-147: ln -sfn \"$CLAUDE_SHARED/dot-claude\" \"$HOME/.claude\" does not remove a pre-existing real directory; ln -sf \"$CLAUDE_SHARED/dot-claude.json\" \"$HOME/.claude.json\" silently discards pre-existing real file content"
    missing:
      - "Guard for existing ~/.claude directory before symlinking: if [ ! -L \"$HOME/.claude\" ]; then rm -rf \"$HOME/.claude\"; fi (optionally preceded by cp -an migration into shared volume)"
      - "Guard for existing ~/.claude.json file before symlinking: if [ -f \"$HOME/.claude.json\" ] && [ ! -L \"$HOME/.claude.json\" ]; then cp -n ... ; rm -f ...; fi"
human_verification:
  - test: "Verify README WR-03 wording: the cleanup comment says 'not data-unsafe' but deleting the volume permanently destroys personal skills and MCP config"
    expected: "The comment in README.md line 444 should warn that deletion permanently destroys auth, settings, personal skills, and MCP config — not merely forces a re-login"
    why_human: "This is a prose accuracy judgment about blast-radius framing that goes beyond grep; a code reviewer (CR WR-03) flagged it as misleading but it does not rise to a programmatic FAIL"
  - test: "Live workspace smoke test: create workspace A for owner X, run claude and complete OAuth login. Stop workspace A. Create workspace B for the same owner X. Open a terminal in B and run claude — confirm no login prompt appears"
    expected: "claude starts already authenticated in workspace B; credentials from the per-owner volume are present"
    why_human: "Requires a running Coder server and Docker host; cannot be automated statically"
  - test: "Upgrade-path smoke test (CR-01 risk surface): use a workspace whose home volume already contains a real ~/.claude directory (pre-phase-04 workspace). Apply the new template, restart the workspace, and verify that ~/.claude is a symlink pointing to the shared volume — not a real directory with a nested dot-claude symlink inside it"
    expected: "After restart, ls -la ~/.claude shows a symlink to .claude-shared/dot-claude. This test will FAIL until the CR-01 fix is applied."
    why_human: "Requires a workspace with a pre-existing real ~/.claude directory on its persistent home volume"
  - test: "Isolation check: create workspaces for two different owners X and Y. Confirm docker volume ls -f label=coder.purpose=claude-config shows two distinct volumes with different UUIDs in their names. Confirm X's credentials do not appear in Y's workspace."
    expected: "Two separate coder-<uuid>-claude volumes; each owner sees only their own Claude session"
    why_human: "Requires a running Coder server with two distinct owner accounts"
---

# Phase 04: Portable Claude Config — Verification Report

**Phase Goal:** A developer authenticates with Claude Code once and finds their credentials, settings, skills, and MCP servers waiting in every subsequent workspace — including newly created ones.
**Verified:** 2026-06-17
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Operator runs `claude` in fresh workspace; after authenticating once, second workspace starts already authenticated (SC-1) AND two workspaces share one authenticated session on a single per-owner Docker volume (SC-2, SC-3) | FAILED (BLOCKER) | `ln -sfn` on line 144 of main.tf does NOT replace a pre-existing real `~/.claude` directory — it nests the symlink inside it. No `rm -rf` guard or `-L` check appears anywhere in the file. This silently bypasses the shared volume on any workspace with a persistent home volume that already holds a real `~/.claude` (upgrade path, prior template, any prior interactive `claude` run). The portability guarantee fails with no error signal. CR-01 from the code review is confirmed unaddressed. |
| 2 | Owner's global settings, personal skills, and user-scoped MCP servers carry into a newly created workspace with no manual copy step (SC-3) | FAILED (BLOCKER) | Same root cause as Truth 1 — the symlink for `~/.claude` may not be established on workspaces with a pre-existing home volume. Additionally, `ln -sf` for `~/.claude.json` silently discards any pre-existing real file content (WR-01), creating an inconsistent state where `~/.claude` stays local and `~/.claude.json` points to the shared `{}` placeholder. |
| 3 | A different owner's workspaces are isolated — their Claude config volume is distinct (SC-4) | VERIFIED | Volume named `coder-${data.coder_workspace_owner.me.id}-claude` (owner UUID keying confirmed at main.tf line 224). Each owner gets a distinct volume. `prevent_destroy = true` and `ignore_changes = [name]` confirmed (lines 231-233). No cross-owner mount possible by construction. |
| 4 | README contains an operator runbook covering first-run login, what is shared, and the concurrent-workspace write caveat (SC-5) | VERIFIED | `### Claude Code` heading at README.md line 400, inside `## Workspace Template` (line 294) after `### Home directory persistence` (line 394). Covers: first-run OAuth login, four shared items (auth/settings/skills/MCP servers), empty-volume seeding with `coder-<owner-uuid>-claude` volume name, `> **Note:**` blockquote for concurrent-write caveat with file locking explanation, and `docker volume ls -f label=coder.purpose=claude-config` + `docker volume rm` cleanup commands. Note: contains WR-03 wording issue ("not data-unsafe" comment at line 444 understates blast radius — see Human Verification). |
| 5 | Per-owner volume infrastructure (SC-2 prerequisite): volume declared with correct name, lifecycle, and isolation properties | VERIFIED | `docker_volume.claude_config_volume` present with exact name expression `coder-${data.coder_workspace_owner.me.id}-claude`, `prevent_destroy = true`, `ignore_changes = [name]`, `coder.purpose = "claude-config"` label, no `count` argument. Mount declared at `/home/coder/.claude-shared` after the `/home/coder` home-volume mount (correct parent-before-child ordering). `claude-code` module wired at v5.2.0, `order = 3`, `install_claude_code = true`, `anthropic_api_key = var.anthropic_api_key`, `count = data.coder_workspace.me.start_count`. `[REUSABLE]` and `[END REUSABLE]` markers present. |

**Score: 3/5 truths verified** (Truths 1 and 2 are the same root-cause blocker; counted as one structural gap affecting two SCs)

### Deferred Items

None. All five success criteria are within scope of this phase.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `templates/docker/main.tf` | anthropic_api_key variable, claude_config_volume resource, .claude-shared mount, startup_script symlink block, claude-code module, [REUSABLE] block | STUB (partial) | All structural elements exist and are wired. The startup_script Claude block is substantively implemented but contains a defect that defeats the core portability goal for the upgrade path (pre-existing `~/.claude` directory not removed before `ln -sfn`). |
| `README.md` | `### Claude Code` operator runbook subsection | VERIFIED | Section exists at line 400 with all required content. One prose accuracy issue (WR-03) flagged for human review. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `docker_container.workspace volumes{}` | `docker_volume.claude_config_volume` | `volume_name = docker_volume.claude_config_volume.name` | WIRED | Line 328 confirmed |
| `module.claude-code` | `variable.anthropic_api_key` | `anthropic_api_key = var.anthropic_api_key` | WIRED | Line 392 confirmed |
| `coder_agent.main.startup_script` | `/home/coder/.claude-shared` | symlinks `~/.claude` and `~/.claude.json` into the shared volume | PARTIAL | The link code exists and runs. It works correctly for empty/new home volumes. It silently fails for home volumes with a pre-existing real `~/.claude` directory (CR-01). |
| `README.md Claude Code subsection` | `templates/docker/main.tf claude_config_volume` | references `coder-<owner-uuid>-claude` and discovery label | WIRED | `label=coder.purpose=claude-config` confirmed at README.md line 442; volume name expression matches |

### Data-Flow Trace (Level 4)

Not applicable — this phase produces infrastructure configuration (Terraform), not a component that renders dynamic data. The relevant data-flow is at runtime (Docker volume → symlink → Claude CLI reads credentials), which requires a live environment to verify (see Human Verification section).

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points. The artifacts are Terraform HCL; no binary or service can be exercised statically. Runtime behavior requires a live Coder server and Docker host (deferred to Human Verification).

### Probe Execution

Step 7c: No probe scripts declared or found. `find scripts -path '*/tests/probe-*.sh'` produced no results.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| CLAUDE-01 | 04-01-PLAN.md | Claude Code installed via `coder/claude-code` module v5.2.0 | SATISFIED | `module "claude-code"` at main.tf line 387 with `source = "registry.coder.com/coder/claude-code/coder"`, `version = "5.2.0"`, `install_claude_code = true` |
| CLAUDE-02 | 04-01-PLAN.md | Per-owner Docker volume (UUID-keyed, rename-safe, destroy-protected) | SATISFIED | `docker_volume.claude_config_volume` with owner UUID name, `prevent_destroy = true`, `ignore_changes = [name]` |
| CLAUDE-03 | 04-01-PLAN.md | Full Claude config surface (`~/.claude/` + `~/.claude.json`) on shared volume | PARTIAL | The mechanism is implemented (neutral mount + symlinks). Defective for home volumes with a pre-existing real `~/.claude` directory — the symlink nests inside rather than replacing. Works correctly only for new/empty home volumes. |
| CLAUDE-04 | 04-01-PLAN.md | Shared volume writable by `coder` user (ownership resolved in startup_script) | SATISFIED | `stat`-guarded `chown -R coder:coder "$CLAUDE_SHARED"` at lines 130-132. Note: WR-02 (unguarded `stat` if mount absent) is an edge-case robustness issue, not a correctness blocker for the primary path. |
| CLAUDE-05 | 04-01-PLAN.md | First-run login works on empty volume; no API key required by default | SATISFIED | `anthropic_api_key` defaults to `""` (line 86); OAuth is the default path. For a genuinely empty home volume this works correctly. |
| CLAUDE-06 | 04-01-PLAN.md | Reusable drop-in snippet documented in-file | SATISFIED | `[REUSABLE]` at line 49, `[END REUSABLE]` at line 397. Spans variable + volume resource + module with WHAT/HOW TO USE/OPERATOR NOTES/MOUNT LAYOUT sections. |
| CLAUDE-07 | 04-02-PLAN.md | README operator runbook covering first-run, what is shared, seeding, concurrent-write caveat | SATISFIED | `### Claude Code` at README.md line 400 covers all four required topics plus cleanup. Minor WR-03 prose accuracy issue (human review item). |

**All 7 requirement IDs (CLAUDE-01 through CLAUDE-07) are accounted for. No orphaned requirements.**

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `templates/docker/main.tf` | 144 | `ln -sfn` without pre-existing-directory guard | BLOCKER | On any home volume that already holds a real `~/.claude` directory, `ln -sfn` nests the symlink inside the directory instead of replacing it. `~/.claude` stays a real directory pointing at local home-volume storage, not the shared per-owner volume. The portability guarantee (SC-1/2/3) silently fails. This is the CR-01 finding from the code review, confirmed independently. |
| `templates/docker/main.tf` | 147 | `ln -sf` without content-preservation guard for existing real file | WARNING | On any home volume that already holds a real `~/.claude.json` file, `ln -sf` silently overwrites it with a symlink to the `{}` placeholder, discarding the existing content. Combines with the CR-01 failure to produce inconsistent state: `~/.claude` stays local, `~/.claude.json` flips to shared `{}`. This is the WR-01 finding. |
| `README.md` | 444 | "not data-unsafe" inline comment overstates safety of `docker volume rm` | WARNING | Deleting the volume destroys personal skills and MCP configuration permanently, not merely forces a re-login. Misleading to operators. This is the WR-03 finding. |

No `TBD`, `FIXME`, or `XXX` markers found in either modified file.

### Human Verification Required

#### 1. README WR-03 Wording

**Test:** Read README.md line 444. The inline code comment states `# Remove a specific orphaned volume (deletion forces re-login for that owner — not data-unsafe)`.
**Expected:** The comment should warn that deletion permanently destroys the owner's Claude auth, settings, personal skills, and MCP config — not merely forces a re-login. Suggested rewording: `# Remove a specific orphaned volume. WARNING: permanently deletes auth, settings, skills, and MCP config for that owner.`
**Why human:** Prose accuracy judgment. The wording is factually misleading (WR-03) but not a programmatic blocker — it requires a human editor decision on rewording.

#### 2. Live Authentication Smoke Test

**Test:** Create workspace A for owner X on the updated template. Open a terminal and run `claude`. Complete the interactive OAuth/subscription login. Stop workspace A. Create workspace B for the same owner X. Open a terminal in B and run `claude`.
**Expected:** `claude` starts already authenticated in workspace B — no login prompt. This confirms SC-1, SC-2, SC-3 for fresh home volumes.
**Why human:** Requires a running Coder server + Docker host.

#### 3. Upgrade-Path Test (CR-01 Risk Surface)

**Test:** Take a workspace whose home volume already contains a real `~/.claude` directory (created under a prior template version or by running `claude` manually before this phase applied). Apply the new template, restart the workspace. Run `ls -la ~/.claude` in the workspace terminal.
**Expected (if CR-01 is fixed):** `~/.claude` is a symlink: `.claude -> .claude-shared/dot-claude`.
**Expected (current code — will FAIL):** `~/.claude` is a real directory, and inside it is `dot-claude -> .claude-shared/dot-claude`. The shared volume is silently bypassed.
**Why human:** Requires a workspace with a pre-existing real `~/.claude` on its persistent home volume.

#### 4. Owner Isolation Test

**Test:** Create workspaces for two different Coder owners X and Y. Run `docker volume ls -f label=coder.purpose=claude-config` on the Docker host. Authenticate as X in X's workspace. Open Y's workspace and run `claude`.
**Expected:** Two distinct volumes with different UUID segments in their names. Y's workspace has no access to X's credentials and starts unauthenticated.
**Why human:** Requires a running Coder server with two distinct owner accounts.

### Gaps Summary

**One structural blocker (CR-01), confirmed independently of the code review:**

The startup_script uses `ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"` to establish the symlink. The `-sfn` flag behaves correctly when `$HOME/.claude` does not exist or is already a symlink — it creates or updates the symlink atomically. However, when `$HOME/.claude` already exists as a real directory (the persistent home volume carries it from a prior workspace start or prior template), `-sfn` does NOT remove the directory. Instead, it creates a new symlink named `dot-claude` inside the existing real directory. The result: `~/.claude` remains a real directory backed by the home volume, not the shared per-owner volume. Claude reads and writes to the non-shared path. The authentication state, settings, skills, and MCP config go to the workspace-local home volume, not the shared volume. The portability guarantee fails invisibly.

This is not a hypothetical edge case. It is the expected upgrade path: any workspace that was running before this template was pushed will have a real `~/.claude` in its persistent home volume. The very first time the updated template provisions the container, the startup_script runs and silently bypasses the shared volume.

The fix is two or three lines:
```sh
if [ ! -L "$HOME/.claude" ]; then
  rm -rf "$HOME/.claude"  # or: cp -an "$HOME/.claude/." "$CLAUDE_SHARED/dot-claude/" 2>/dev/null || true && rm -rf "$HOME/.claude"
fi
ln -sfn "$CLAUDE_SHARED/dot-claude" "$HOME/.claude"
```

A parallel fix is needed for `~/.claude.json` (WR-01).

Until this is resolved, SC-1, SC-2, and SC-3 are conditionally met only for home volumes that have never held a real `~/.claude` (i.e., brand-new workspaces on a fresh home volume with no prior Claude use). The core phase goal — portability "including newly created ones" — is partially met but the upgrade-from-prior-template path is broken.

---

_Verified: 2026-06-17_
_Verifier: Claude (gsd-verifier)_
