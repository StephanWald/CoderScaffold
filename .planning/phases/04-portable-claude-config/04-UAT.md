---
status: complete
phase: 04-portable-claude-config
source: [04-VERIFICATION.md]
started: 2026-06-17T20:05:00Z
updated: 2026-06-18T00:00:00Z
---

## Current Test

[testing complete — 4/5 passed live; Test 5 (owner isolation) accepted as an acknowledged gate by the user, no second owner account available]

## Tests

### 1. Live authentication smoke test
expected: Create workspace A for owner X. Run `claude`, complete OAuth/subscription login. Stop workspace A. Create workspace B for the same owner X. Run `claude` in B — it starts already authenticated, no login prompt.
result: pass
note: "Confirmed live: login in workspace A → workspace B for the same owner starts already authenticated, no login prompt. Auth persists across workspaces via the shared volume."

### 2. Upgrade-path directory guard test (CR-01 fix validation)
expected: Take a workspace whose persistent home volume already contains a real `~/.claude` directory. Apply the new template, restart. `ls -la ~/.claude` shows a symlink `.claude -> .claude-shared/dot-claude` — NOT a real directory, and no nested `dot-claude` symlink inside a surviving real directory.
result: pass

### 3. Content-preservation JSON test (WR-01 fix validation)
expected: Take a workspace whose home volume contains a real `~/.claude.json` with real auth data. Apply the new template, restart. `cat ~/.claude.json` shows the real auth content preserved in the shared `dot-claude.json`; `~/.claude.json` is a symlink; the `{}` placeholder did NOT replace the real auth data.
result: pass

### 4. Idempotency test
expected: Stop and start the same workspace twice after symlinks are established. The `[ ! -L ]` guards fire as no-ops on subsequent starts — no repeated migration, no errors, `~/.claude` and `~/.claude.json` remain symlinks.
result: pass

### 5. Owner isolation test
expected: Create workspaces for two different owners X and Y. `docker volume ls --format '{{.Name}}' | grep -- '-claude$'` shows two distinct volumes with different UUID segments. Authenticate as X; Y's workspace has no access to X's credentials and starts unauthenticated.
result: blocked
blocked_by: other
reason: "User reported blocked; no second owner account available to exercise the X vs Y isolation path."

## Summary

total: 5
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 1

## Session Notes

Live deploy testing surfaced a cascade of deploy-blocking defects in the phase-04
template that static code review + goal-verification had passed. All were fixed inline
during this session (commits listed in Gaps). The five functional UAT checkpoints were
NOT completed — the session focused on getting the template to deploy at all, then was
paused by the user.

**Deploy-blocking defects found & fixed (phase-04 scope):**
- G1: invalid module args (`order` on claude-code, `agent_name` on code-server) — blocked `coder templates push`.
- G2: per-owner volume `prevent_destroy=true` — blocked `coder delete <workspace>` entirely.

**Enhancements added beyond phase-04 scope (user-requested during session):**
- Workspace image now built from `templates/docker/Dockerfile` (base + Node.js LTS) — `feat(04)` faa8e46.
- `startup_script` installs GSD (gsd-core) once into the shared `~/.claude` — `feat(04)` fff6a78. Confirmed working live (69 skills + agents + hooks installed).

**Validated live (structural, not the full functional assertions):**
- Per-owner volume mounts at `~/.claude-shared`; `~/.claude` + `~/.claude.json` are symlinks into it (CR-01/WR-01 wiring correct).
- `claude --version` works; GSD install completes.

**Not done:** Tests 1-5 functional assertions — auth persistence A→B, upgrade-path migration with real pre-existing config (Tests 2 & 3, the data-loss paths), idempotency across restarts, owner isolation.

**Resumed session (2026-06-17T22:05Z):** Functional Tests 1-4 run live and PASSED —
auth persistence A→B (Test 1), upgrade-path directory guard / CR-01 (Test 2),
content-preservation JSON / WR-01 (Test 3, no data loss), and idempotency across
restarts (Test 4). Test 5 (owner isolation X vs Y) BLOCKED — no second owner account
available to exercise the two-owner path. No code issues found.

## Gaps

- id: G1
  truth: "Operator can `coder templates push` the Docker template so workspaces are provisioned with the claude-code module + per-owner volume wiring"
  status: resolved
  reason: "`coder templates push` failed at `terraform plan` with 'Unsupported argument' — first on `order = 3` in module \"claude-code\" (v5.2.0 has no `order` input), then on `agent_name = \"main\"` in module \"code-server\" (v1.5.0 has no `agent_name` input). Template never deployed; workspaces ran an older/starter template with no claude wiring."
  severity: blocker
  test: 1
  artifacts: ["templates/docker/main.tf"]
  fix: "Removed `order` from claude-code and `agent_name` from code-server (jetbrains-gateway v1.2.6 DOES accept agent_name — left intact; all three module schemas verified against registry source). Commits 92be7d7, d08c54a. Re-push then succeeded."

- id: G2
  truth: "Deleting a workspace does not error, and the owner's shared Claude config volume survives the deletion (D-03)"
  status: resolved
  reason: "`coder delete` failed: docker_volume.claude_config_volume had `lifecycle.prevent_destroy = true`, but the per-workspace `terraform destroy` plans to destroy it → hard error. A per-workspace-managed resource cannot outlive its workspace; prevent_destroy made workspaces undeletable."
  severity: blocker
  test: null
  artifacts: ["templates/docker/main.tf", "README.md"]
  fix: "Made the per-owner volume unmanaged — referenced by name (local.claude_volume_name) in the container mount, no docker_volume resource. Docker auto-creates it on first start and never auto-removes it, so it persists across deletion without prevent_destroy. README cleanup discovery switched from label to `-claude` name suffix. Commit 97da220. Stuck pre-fix workspaces: delete with `coder delete <name> --orphan`."
