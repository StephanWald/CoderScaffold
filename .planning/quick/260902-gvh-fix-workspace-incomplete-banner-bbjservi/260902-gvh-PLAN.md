---
phase: quick-260902-gvh
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /workspaces/coder/templates/bbj-services/main.tf
  - /workspaces/coder/templates/java-fullstack/main.tf
  - /workspaces/coder/templates/flutter/main.tf
  - /workspaces/coder/templates/coderscaffold/main.tf
  - /workspaces/coder/templates/python-ai/main.tf
  - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
autonomous: true
requirements: []
estimate:
  tokens: 45000
  raw_tokens: 30000
  tasks: 3
  confidence: med

must_haves:
  truths:
    - "The bbjservices coder_script launches BBjServices detached and EXITS (0 on success, 1 on failed start) instead of running forever via exec — so the agent reaches ready and no 'workspace may be incomplete' banner shows."
    - "mempalace init runs non-interactively (--yes) in all five public templates that call it, so init completes without an EOFError traceback."
  artifacts:
    - "/workspaces/coder/templates/bbj-services/main.tf (rewritten bbjservices script + mempalace --yes)"
    - "/workspaces/CoderPrivate/templates/bbj-dev/main.tf (rewritten bbjservices script)"
    - "/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf (rewritten bbjservices script)"
    - "mempalace --yes in java-fullstack, flutter, coderscaffold, python-ai main.tf"
  key_links:
    - "The detached sudo child redirects all three FDs (</dev/null >>file 2>&1) so the coder_script's pipes close on exit — solves BOTH the July pipes-not-closed warning AND the never-ending-script lifecycle problem."
    - "POSIX sh only (#!/bin/sh) — while-loop counter, no seq/[[/bashisms."
---

<objective>
Fix two defects that make BBj workspaces show the "Your workspace may be incomplete" troubleshooting banner and crash mempalace init at startup, both in template source.

Purpose: The bbjservices coder_script currently ends with `exec sudo /opt/bbx/bin/bbjservices --launchd` — a run_on_start script that never exits keeps the agent lifecycle in "starting" until start_timeout, which triggers the banner in every terminal. Separately, newer mempalace releases prompt interactively during `init`, so `input()` hits EOFError in the non-interactive startup script and init never completes.

Output: bbjservices script rewritten to launch detached + wait for readiness + exit, across bbj-services (public) and bbj-dev/bbj-ls-dev (private); `mempalace init --yes` in all five public templates.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/workspaces/coder/.planning/STATE.md
@/workspaces/coder/CLAUDE.md
@/workspaces/coder/templates/bbj-services/main.tf
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Rewrite bbjservices coder_script to launch detached, wait for readiness, then exit (public bbj-services)</name>
  <files>/workspaces/coder/templates/bbj-services/main.tf</files>
  <precondition>The `resource "coder_script" "bbjservices"` block exists in bbj-services/main.tf and its script ends with `exec sudo /opt/bbx/bin/bbjservices --launchd` (confirmed ~line 697).</precondition>
  <action>In the `coder_script "bbjservices"` script heredoc, replace the final two lines (the "Starting BBjServices (foreground...)" echo and the `exec sudo /opt/bbx/bin/bbjservices --launchd` line) with a detached launch + readiness-wait + exit sequence. Keep the two existing pre-checks unchanged (missing `/opt/bbx/bin/bbjservices` → warn + exit 0; port 8888 already active → exit 0). The replacement: echo a "Starting BBjServices (detached, as root via sudo)" line noting launcher output goes to /tmp/bbjservices-launch.log; then `sudo sh -c 'nohup /opt/bbx/bin/bbjservices --launchd </dev/null >>/tmp/bbjservices-launch.log 2>&1 &'`; then a POSIX while-loop counter (i=0, while [ $i -lt 120 ]) that checks `ss -tlnp 2>/dev/null | grep -q ':8888'`, echoes an up-message and `exit 0` on success, else increments i and `sleep 1`; after the loop echo an ERROR to stderr, tail the launch log to stderr (guarded with `|| true`), and `exit 1`. Update the block's leading comment (currently describing the exec/foreground design) to explain the new detached model and WHY the FD redirects matter: the July pipes-not-closed problem happened because the backgrounded child INHERITED the script's stdout/stderr pipe FDs; the explicit `</dev/null >>file 2>&1` inside the sudo child detaches all three FDs, so the coder_script's pipes close the moment the script exits — this fixes BOTH the pipes warning AND the never-ending-script lifecycle that caused the banner. Note that exit 1 on failed start is deliberate (a genuinely failed BBjServices SHOULD surface as a script error). POSIX sh only — no bashisms. Do NOT put a literal `exec sudo /opt/bbx/bin/bbjservices --launchd` string anywhere in the file after this edit.</action>
  <verify>
    <automated>cd /workspaces/coder/templates/bbj-services && awk '/script = <<-EOT/{f=1} f{print} /^  EOT/{if(f)exit}' main.tf | sed '1d;$d' > /tmp/gvh-bbjsvc-pub.sh && sh -n /tmp/gvh-bbjsvc-pub.sh && ! grep -q 'exec sudo /opt/bbx/bin/bbjservices' main.tf && grep -q "nohup /opt/bbx/bin/bbjservices --launchd </dev/null" main.tf && grep -q "i -lt 120" main.tf && terraform validate</automated>
  </verify>
  <done>bbj-services/main.tf bbjservices script passes `sh -n`, contains the detached nohup launch + 120s readiness loop, no longer contains `exec sudo /opt/bbx/bin/bbjservices`, and `terraform validate` passes.</done>
</task>

<task type="auto">
  <name>Task 2: Apply the same detached-launch rewrite to private bbj-dev and bbj-ls-dev</name>
  <files>/workspaces/CoderPrivate/templates/bbj-dev/main.tf, /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf</files>
  <precondition>Both private templates contain a `coder_script "bbjservices"` block ending in `exec sudo /opt/bbx/bin/bbjservices --launchd` (grep to confirm before editing). bbj-ls-dev may also contain a second `coder_script` running code-server (ext-test) — confirm whether that one already backgrounds/exits and leave it unchanged if so.</precondition>
  <action>First grep both files for `coder_script` and `bbjservices` to locate the exact block(s) and confirm the current `exec sudo /opt/bbx/bin/bbjservices --launchd` ending. Apply the identical rewrite from Task 1 to each bbjservices script (same detached nohup launch, same 120s POSIX readiness loop, same exit 0/1 semantics, same updated rationale comment). Preserve each file's existing pre-checks and surrounding structure. For bbj-ls-dev's second (ext-test / code-server) coder_script: inspect its exit behavior — if it already exits or backgrounds correctly, DO NOT touch it; only change it if it too ends with a non-exiting `exec`. POSIX sh only. Do NOT leave any literal `exec sudo /opt/bbx/bin/bbjservices --launchd` in either file.</action>
  <verify>
    <automated>for d in bbj-dev bbj-ls-dev; do cd /workspaces/CoderPrivate/templates/$d && ! grep -q 'exec sudo /opt/bbx/bin/bbjservices' main.tf && grep -q "nohup /opt/bbx/bin/bbjservices --launchd </dev/null" main.tf && grep -q "i -lt 120" main.tf || { echo "FAIL grep $d"; exit 1; }; done; echo grep-ok</automated>
  </verify>
  <done>Both private bbjservices scripts contain the detached launch + readiness loop and no longer contain `exec sudo /opt/bbx/bin/bbjservices`. terraform validate for both is deferred to Task 3 (needs the transient bbj-base symlink).</done>
</task>

<task type="auto">
  <name>Task 3: mempalace init --yes in all five public templates, then terraform validate the two private BBj templates</name>
  <files>/workspaces/coder/templates/bbj-services/main.tf, /workspaces/coder/templates/java-fullstack/main.tf, /workspaces/coder/templates/flutter/main.tf, /workspaces/coder/templates/coderscaffold/main.tf, /workspaces/coder/templates/python-ai/main.tf</files>
  <precondition>Each of the five public templates contains a line `mempalace init "$PROJECT_DIR" \` (with the trailing line continuation and a following `|| echo "WARN..."` guard). The private BBj templates depend on a `modules/bbj-base` module resolvable via a symlink to /workspaces/CoderPrivate/modules/bbj-base for `terraform init`.</precondition>
  <action>In each of the five public templates, change `mempalace init "$PROJECT_DIR" \` to `mempalace init --yes "$PROJECT_DIR" \` — keep the existing line-continuation style and the following `|| echo "WARN: mempalace init failed; continuing" >&2` guard exactly as-is. The `--yes` flag auto-accepts detected entities (non-interactive), preventing the EOFError from the newer interactive prompt. Then validate the two private BBj templates: for each of bbj-dev and bbj-ls-dev, create a transient symlink `modules/bbj-base` → /workspaces/CoderPrivate/modules/bbj-base (if the template references a bbj-base module by a local path — confirm the expected module path first), run `terraform init -backend=false` then `terraform validate`, then clean up by removing the symlink, `.terraform/`, and `.terraform.lock.hcl`. Do not commit any of the transient init artifacts.</action>
  <verify>
    <automated>c=$(grep -rl 'mempalace init --yes "$PROJECT_DIR"' /workspaces/coder/templates/bbj-services/main.tf /workspaces/coder/templates/java-fullstack/main.tf /workspaces/coder/templates/flutter/main.tf /workspaces/coder/templates/coderscaffold/main.tf /workspaces/coder/templates/python-ai/main.tf | wc -l); test "$c" -eq 5 && ! grep -rq 'mempalace init "$PROJECT_DIR"' /workspaces/coder/templates/*/main.tf && echo "mempalace-yes-ok x$c"</automated>
  </verify>
  <done>All five public templates use `mempalace init --yes "$PROJECT_DIR"` and none use the old bare form; both private BBj templates pass `terraform validate` and all transient init artifacts (symlink, .terraform/, .terraform.lock.hcl) are removed.</done>
</task>

</tasks>

<verification>
- `sh -n` passes on the extracted bbjservices script body for bbj-services (and manually for the two private templates if extractable).
- `terraform validate` passes for bbj-services, bbj-dev, and bbj-ls-dev.
- Exactly five `mempalace init --yes "$PROJECT_DIR"` occurrences across public templates; zero bare `mempalace init "$PROJECT_DIR"` remaining.
- No literal `exec sudo /opt/bbx/bin/bbjservices --launchd` remains in any of the three BBj templates.
- Two atomic commits: one in /workspaces/coder (public), one in /workspaces/CoderPrivate (private).
</verification>

<success_criteria>
- Both defects fixed in template source: bbjservices script exits cleanly after readiness; mempalace init runs non-interactively.
- All static gates pass (sh -n, terraform validate ×3, grep counts).
- SUMMARY flags the LIVE gate (per the infra-live-deploy-gate memory): static passing is NOT sufficient — operator must re-run push-templates.sh, restart/rebuild a BBj workspace, and confirm (a) no "workspace may be incomplete" banner, (b) the BBjServices dashboard script shows "up on :8888" and COMPLETES, (c) the startup log shows mempalace init finishing without a traceback.
</success_criteria>

<output>
Create `.planning/quick/260902-gvh-fix-workspace-incomplete-banner-bbjservi/260902-gvh-SUMMARY.md` when done.
</output>
