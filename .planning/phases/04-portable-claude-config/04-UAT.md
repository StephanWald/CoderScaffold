---
status: testing
phase: 04-portable-claude-config
source: [04-VERIFICATION.md]
started: 2026-06-17T20:05:00Z
updated: 2026-06-17T20:05:00Z
---

## Current Test

number: 1
name: Live authentication smoke test
expected: |
  claude starts already authenticated in workspace B — no login prompt.
  Credentials from the per-owner volume are present transparently.
awaiting: user response

## Tests

### 1. Live authentication smoke test
expected: Create workspace A for owner X. Run `claude`, complete OAuth/subscription login. Stop workspace A. Create workspace B for the same owner X. Run `claude` in B — it starts already authenticated, no login prompt.
result: issue
reported: "claude: command not found in workspace; root cause: `coder templates push` fails with 'Unsupported argument' on the claude-code module's `order = 3` (module v5.2.0 does not accept `order`). Template never deployed, so the workspace ran an older/starter template with no claude wiring (no ~/.claude-shared, no CLI)."
severity: blocker

### 2. Upgrade-path directory guard test (CR-01 fix validation)
expected: Take a workspace whose persistent home volume already contains a real `~/.claude` directory. Apply the new template, restart. `ls -la ~/.claude` shows a symlink `.claude -> .claude-shared/dot-claude` — NOT a real directory, and no nested `dot-claude` symlink inside a surviving real directory.
result: [pending]

### 3. Content-preservation JSON test (WR-01 fix validation)
expected: Take a workspace whose home volume contains a real `~/.claude.json` with real auth data. Apply the new template, restart. `cat ~/.claude.json` shows the real auth content preserved in the shared `dot-claude.json`; `~/.claude.json` is a symlink; the `{}` placeholder did NOT replace the real auth data.
result: [pending]

### 4. Idempotency test
expected: Stop and start the same workspace twice after symlinks are established. The `[ ! -L ]` guards fire as no-ops on subsequent starts — no repeated migration, no errors, `~/.claude` and `~/.claude.json` remain symlinks.
result: [pending]

### 5. Owner isolation test
expected: Create workspaces for two different owners X and Y. `docker volume ls -f label=coder.purpose=claude-config` shows two distinct volumes with different UUID segments. Authenticate as X; Y's workspace has no access to X's credentials and starts unauthenticated.
result: [pending]

## Summary

total: 5
passed: 0
issues: 1
pending: 4
skipped: 0
blocked: 0

## Gaps

- truth: "Operator can `coder templates push` the Docker template so workspaces are provisioned with the claude-code module + per-owner volume wiring"
  status: failed
  reason: "User reported: `coder templates push` fails at `terraform plan` — 'Unsupported argument' on main.tf:424 `order = 3` in module \"claude-code\". The claude-code module v5.2.0 does not accept an `order` input (code-server/jetbrains-gateway modules do). Template never deployed; workspace had no ~/.claude-shared and no claude CLI."
  severity: blocker
  test: 1
  artifacts: ["templates/docker/main.tf"]
  missing: []
  fix: "Two invalid module arguments removed from main.tf: (1) `order = 3` on the claude-code module (v5.2.0 has no `order` input); (2) `agent_name = \"main\"` on the code-server module (v1.5.0 has no `agent_name` input — verified against the registry source; jetbrains-gateway v1.2.6 DOES accept agent_name, so it was left intact). Re-push required to deploy. Tests 1-5 blocked on a successful push + a workspace created from the deployed `docker` template."
