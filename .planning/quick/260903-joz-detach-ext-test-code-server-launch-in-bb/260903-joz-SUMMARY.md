---
phase: quick-260903-joz
plan: 01
subsystem: coder-templates
tags: [coder, terraform, bbj-ls-dev, coder-script, code-server, lifecycle]
requires: []
provides:
  - "coder_script.ext_test_ide detached launch (nohup + FD redirects + :13338 readiness poll + exit)"
affects:
  - CoderPrivate bbj-ls-dev template
tech-stack:
  added: []
  patterns:
    - "Detached coder_script launch: nohup child with </dev/null >>log 2>&1 redirects + bounded port readiness poll + exit 0/1 (bbjservices pattern, no sudo variant)"
key-files:
  created: []
  modified:
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
decisions:
  - "Comment block reworded to say 'foreground `exec` daemon' (not the literal command) so the plan's negative grep for the old launch line stays a valid regression check"
metrics:
  duration: ~4 min
  completed: 2026-09-03
status: complete
actuals:
  tokens: 1200
  tasks: 1
  commits: 1
---

# Quick Task 260903-joz: Detach ext-test code-server launch in bbj-ls-dev Summary

`coder_script.ext_test_ide` now launches code-server-test detached (nohup child with all three FDs redirected to /tmp/ext-test-code-server.log), polls :13338 up to 60s, and exits 0/1 — so the coder agent lifecycle reaches "ready" and the "workspace didn't build completely" banner disappears, mirroring the proven bbjservices fix minus sudo.

## What Changed

**CoderPrivate commit: `3165e8b`** (repo /workspaces/CoderPrivate, branch main)

`templates/bbj-ls-dev/main.tf` (+32/−9, only file touched):

1. **Launch stanza replaced** in the `ext_test_ide` script heredoc:
   - OLD: `exec code-server-test … "$FOLDER"` — the script BECAME the daemon and never exited, so the agent lifecycle never reached "ready" → banner.
   - NEW: `nohup code-server-test --auth none --disable-telemetry --bind-addr 127.0.0.1:13338 --user-data-dir "$HOME/.ext-test/data" --extensions-dir "$HOME/.ext-test/extensions" "$FOLDER" </dev/null >>/tmp/ext-test-code-server.log 2>&1 &`
   - Followed by a POSIX readiness loop (60 × 1s, `ss -tlnp | grep ':13338'`): exit 0 when up; on timeout, ERROR to stderr + `tail -n 40 /tmp/ext-test-code-server.log` + exit 1.
   - The `</dev/null >>log 2>&1` redirects on the backgrounded child are load-bearing: without them the child inherits the coder_script's stdout/stderr pipe FDs and the agent's pipe reader never reaches EOF.

2. **Comment block above the resource rewritten**: old text wrongly claimed "Foreground under this script (exec), same shape as coder_script.bbjservices" (bbjservices detaches since 996827d). New text describes the detached shape, why the script must exit for the agent to reach "ready", the load-bearing FD redirects, and the no-sudo distinction (ext-test runs as the agent user).

**Unchanged (verified byte-for-byte via diff):** port-13338 idempotency guard, 5-minute (`seq 1 60` × sleep 5) examples-checkout wait, `$HOME` fallback WARN, `mkdir -p` for the .ext-test dirs, one-time settings-seed block, and everything else in the file.

## Verification

| Check | Result |
|-------|--------|
| `grep 'nohup code-server-test'` present | PASS |
| `grep '/tmp/ext-test-code-server.log'` present | PASS |
| `grep "grep -q ':13338'"` poll present | PASS |
| `! grep 'exec code-server-test'` (old launch gone) | PASS |
| `terraform fmt -check main.tf` | PASS |
| `terraform init -backend=false && terraform validate` (repo-root `modules/bbj-base` staged temporarily, then removed with `.terraform*` artifacts) | PASS — "the configuration is valid" |
| `sh -n` on extracted script body (with `${local.repos_dir}` substituted) | PASS |
| `git status` in CoderPrivate before commit | only `templates/bbj-ls-dev/main.tf` modified |

Terraform interpolation guard honored: new stanza uses only `$VAR` / `$((…))` forms (ignored by Terraform); the existing `${local.repos_dir}` interpolation is untouched.

## Deviations from Plan

**1. [Rule 1 - Bug] Comment wording tripped the plan's own negative grep**
- **Found during:** Task 1 verification
- **Issue:** First draft of the rewritten comment block quoted the literal old command (`exec code-server-test …`), which made the plan's `! grep -q 'exec code-server-test'` assertion fail.
- **Fix:** Reworded to "the previous never-exiting foreground `exec` daemon" — same meaning, no literal match, and the negative grep remains a valid regression check.
- **Files modified:** same file, same commit
- **Commit:** 3165e8b

No other deviations — plan executed as written.

## Deferred to Operator (infra-needs-live-deploy-gate)

Live verification requires a real deploy: push the template (push-templates.sh stages `modules/bbj-base`), rebuild/restart a bbj-ls-dev workspace, confirm (a) no "workspace didn't build completely" banner, (b) "VS Code (ext test)" script shows Completed, (c) ext-test IDE reachable on :13338 (coder_app healthcheck `/healthz` green).

## Self-Check: PASSED

- /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf — FOUND
- Commit 3165e8b in CoderPrivate — FOUND
