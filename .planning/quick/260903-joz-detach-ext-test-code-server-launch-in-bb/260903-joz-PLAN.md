---
phase: quick-260903-joz
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
autonomous: true
requirements: [QUICK-260903-joz]
estimate:
  tokens: 30000
  raw_tokens: 15000
  tasks: 1
  confidence: high
must_haves:
  truths:
    - "coder_script.ext_test_ide launches code-server-test detached and EXITS, so the agent lifecycle reaches ready and no 'workspace didn't build completely' banner appears"
    - "ext-test code-server is reachable on 127.0.0.1:13338 after the script completes"
  artifacts:
    - "/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf (ext_test_ide script + comment block rewritten)"
  key_links:
    - "detached nohup child with all three FDs redirected (</dev/null >>log 2>&1) → coder_script pipes close on exit → agent reaches ready"
    - "port-13338 readiness poll gates exit 0 (up) vs exit 1 (timeout + log tail)"
---

<objective>
Fix the "workspace didn't build completely" banner in the CoderPrivate `bbj-ls-dev` template by detaching the ext-test code-server launch in `coder_script.ext_test_ide`.

Purpose: The script currently ends with `exec code-server-test … "$FOLDER"` — it BECOMES the code-server daemon and never exits, so the coder agent lifecycle never reaches "ready" and Coder shows the banner. The proven fix (already applied to `coder_script.bbjservices` in the same file, lines ~424-477) is to launch detached with all three FDs redirected inside a backgrounded child, poll the port for readiness, then exit 0/1.

Output: `coder_script.ext_test_ide` rewritten to launch detached + poll :13338 + exit; its comment block rewritten to describe the detached shape; terraform validate + fmt clean.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/workspaces/coder/.planning/STATE.md
@/workspaces/coder/CLAUDE.md

# Target file (SEPARATE git repo — code commits go to CoderPrivate, planning artifacts stay in /workspaces/coder/.planning):
@/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf

# Reference pattern already in the same file — coder_script.bbjservices, lines ~424-477:
#   detached `sudo sh -c 'nohup … </dev/null >>/tmp/bbjservices-launch.log 2>&1 &'`
#   then a 120s POSIX `:8888` readiness loop → exit 0 on success / exit 1 + `tail -n 40 log` on timeout.
# The ext_test_ide fix mirrors this EXCEPT no sudo (ext-test runs as the agent user),
# port 13338, log /tmp/ext-test-code-server.log, and a ~60s bound (code-server starts in seconds).
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Detach ext_test_ide code-server launch + rewrite its comment block</name>
  <files>/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf</files>
  <action>
In `coder_script.ext_test_ide` (script heredoc ~lines 511-557), replace ONLY the final launch stanza. Currently:
  - `echo "Starting ext-test code-server (foreground) on :13338 — folder: $FOLDER"`
  - `exec code-server-test --auth none --disable-telemetry --bind-addr 127.0.0.1:13338 --user-data-dir … --extensions-dir … "$FOLDER"`

Replace with a DETACHED launch + readiness poll mirroring `coder_script.bbjservices` (~lines 460-475), but with NO sudo wrapper (ext-test runs as the agent user — bbjservices needs root, this does not):
  1. echo that it is starting detached with launcher output going to /tmp/ext-test-code-server.log
  2. `nohup code-server-test --auth none --disable-telemetry --bind-addr 127.0.0.1:13338 --user-data-dir "$HOME/.ext-test/data" --extensions-dir "$HOME/.ext-test/extensions" "$FOLDER" </dev/null >>/tmp/ext-test-code-server.log 2>&1 &`
  3. A POSIX readiness loop bounded ~60 iterations (1s sleep each): `i=0; while [ $i -lt 60 ]; do if ss -tlnp 2>/dev/null | grep -q ':13338'; then echo "ext-test code-server up on :13338"; exit 0; fi; i=$((i + 1)); sleep 1; done`
  4. On timeout: `echo "ERROR: ext-test code-server did not come up on :13338 within 60s" >&2`; `tail -n 40 /tmp/ext-test-code-server.log >&2 || true`; `exit 1`

The `</dev/null >>log 2>&1` redirects on the backgrounded child are LOAD-BEARING: a bare `nohup … &` child inherits the coder_script's stdout/stderr pipe FDs and the agent's pipe reader never reaches EOF, so the script never registers as finished (documented in the bbjservices comment block ~lines 430-440). Redirecting all three FDs on the child lets the script's pipes close the instant it exits.

KEEP UNCHANGED everything else in the heredoc: the port-13338 idempotency guard at the top (~lines 513-516), the `EXAMPLES_DIR`/`FOLDER` 5-minute (`seq 1 60` × sleep 5) wait loop for the bbj-language-server examples checkout (~lines 518-526), the `$HOME` fallback WARN (~lines 528-530), the `mkdir -p …/.ext-test/…` line, and the settings-seeding block (~lines 534-550).

Terraform interpolation guard: this is a `<<-EOT` template. `${local.repos_dir}` already interpolates on line 518 and must stay. Any NEW shell you add must be plain `$VAR` / `$(...)` (Terraform ignores those) — do NOT introduce shell `${…}` brace forms; if one is ever needed, escape it as `$${…}`. The new stanza uses only `$HOME`, `$FOLDER`, `$i`, `$((…))` — all safe.

Then rewrite the comment block directly above the resource (~lines 497-503). The current text claims "Foreground under this script (exec), same shape as coder_script.bbjservices" — that is WRONG (bbjservices detaches). Rewrite it to state: the script launches code-server-test DETACHED (nohup + all-three-FD redirect on the backgrounded child) and then EXITS, because the script must exit for the coder agent lifecycle to reach "ready" (a never-exiting `exec` daemon caused the "workspace didn't build completely" banner). Note it runs as the agent user (no sudo, unlike bbjservices), polls :13338 for readiness, and keeps the idempotency guard / 5-minute examples-checkout wait / $HOME fallback / one-time settings seed. Keep the existing accurate lines about the 5-minute examples wait, the $HOME fallback, and why `--auth none` is safe (coder_app tunnels through the agent, share = "owner").
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-ls-dev && \
      grep -q 'nohup code-server-test' main.tf && \
      grep -q '/tmp/ext-test-code-server.log' main.tf && \
      grep -q "grep -q ':13338'" main.tf && \
      ! grep -q 'exec code-server-test' main.tf && \
      terraform fmt -check main.tf</automated>
  </verify>
  <done>
The `exec code-server-test …` line is gone; `ext_test_ide` launches `nohup code-server-test … </dev/null >>/tmp/ext-test-code-server.log 2>&1 &`, polls :13338 (~60s), exits 0 on up / exit 1 + log tail on timeout; the idempotency guard, examples-checkout wait, $HOME fallback, and settings-seed block are unchanged; the comment block describes the detached shape and why. `terraform fmt -check main.tf` is clean.
  </done>
</task>

</tasks>

<verification>
Validate exactly as the sibling bbj-dev executor did (quick task 260902-kio): the template consumes the repo-root `modules/bbj-base` module (staged into the template dir by push-templates.sh at push time), so `terraform validate` needs it present locally.

1. `terraform fmt -check /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf` — style clean.
2. Temporarily stage the shared module, then init + validate, then clean up:
   - Copy the repo-root `modules/bbj-base` into `templates/bbj-ls-dev/modules/bbj-base` (mirroring push-templates.sh).
   - `cd /workspaces/CoderPrivate/templates/bbj-ls-dev && terraform init -backend=false && terraform validate` → must report the configuration is valid.
   - Remove the temporarily-staged `templates/bbj-ls-dev/modules/` and the `.terraform*` init artifacts so the working tree matches what push-templates.sh expects (only main.tf changed).
3. Confirm `git status` in /workspaces/CoderPrivate shows only `templates/bbj-ls-dev/main.tf` modified.
</verification>

<success_criteria>
- `coder_script.ext_test_ide` no longer contains `exec code-server-test` and instead launches detached (`nohup … </dev/null >>/tmp/ext-test-code-server.log 2>&1 &`) + polls :13338 + exits 0/1.
- Idempotency guard, 5-minute examples-checkout wait, $HOME fallback WARN, and one-time settings-seed block are byte-for-byte unchanged.
- Comment block above the resource describes the detached shape (script must exit for the agent to reach "ready"; FD redirects close the script's pipes) and the no-sudo distinction.
- `terraform fmt -check` + staged-module `terraform validate` PASS; working tree shows only main.tf changed.
- Live verification DEFERRED to operator (infra-needs-live-deploy-gate): push template, rebuild a bbj-ls-dev workspace, confirm no banner and ext-test IDE reachable on :13338.
</success_criteria>

<output>
Create `/workspaces/coder/.planning/quick/260903-joz-detach-ext-test-code-server-launch-in-bb/260903-joz-SUMMARY.md` when done.
Code commit goes to the /workspaces/CoderPrivate repo (main.tf); planning artifacts stay in /workspaces/coder/.planning.
</output>
