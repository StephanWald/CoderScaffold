---
phase: quick-260902-kio
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
autonomous: true
requirements: [QUICK-260902-KIO]
estimate:
  tokens: 22000
  raw_tokens: 15000
  tasks: 1
  confidence: high
must_haves:
  truths:
    - "The bbj-dev workspace UI shows five clickable buttons — one per bbj-* helper command — that open a web terminal running that command"
    - "Buttons are ordered so bbj-build, bbj-gwt, bbj-restart appear before bbj-checkout and bbj-test"
    - "The existing BBjServices app keeps a sensible position among the new apps"
    - "terraform validate (or the dockerized equivalent) passes on the edited template"
  artifacts:
    - "/workspaces/CoderPrivate/templates/bbj-dev/main.tf with five new command-type coder_app resources"
  key_links:
    - "Each new coder_app.agent_id references module.base.agent_id (the agent lives inside the bbj-base module, NOT a local coder_agent resource)"
    - "Each command-type coder_app sets command = \"bbj-<name>\" and omits url/subdomain/share/healthcheck"
---

<objective>
Expose the five bbj-* helper commands (bbj-checkout, bbj-build, bbj-gwt, bbj-test, bbj-restart) — currently baked into /usr/local/bin and discoverable only from a terminal — as clickable command-type coder_app buttons in the bbj-dev workspace UI, replicating the Eclipse menu items they replace.

Purpose: give BBj engineers one-click access to the dev-loop commands (Deploy Jars, Build GWT, Restart, SVN Checkout, Run BBjTest) instead of remembering shell command names.
Output: five new `resource "coder_app"` blocks in /workspaces/CoderPrivate/templates/bbj-dev/main.tf, ordered by priority via the `order` attribute, plus the BBjServices app repositioned sensibly.

NOTE: code commits go to the /workspaces/CoderPrivate repo (a separate git repo from /workspaces/coder). Planning artifacts stay under /workspaces/coder/.planning.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@/workspaces/CoderPrivate/templates/bbj-dev/main.tf
@/workspaces/CoderPrivate/templates/bbj-dev/Dockerfile

# Interface facts already established (from the Read pass during planning — do NOT re-read to rediscover):
# - The coder_agent lives inside module "base" (./modules/bbj-base). This file references it
#   ONLY as `module.base.agent_id` — there is NO local `coder_agent` resource here.
#   (See coder_script.bbj_checkout at main.tf:344, coder_script.bbjservices at :398,
#    coder_app.bbjservices at :437 — all use agent_id = module.base.agent_id.)
# - Existing coder_app.bbjservices (main.tf:436-450): a URL-type app —
#   url = "http://localhost:8888", icon = "/icon/java.svg", subdomain = var.bbj_app_subdomain,
#   share = "owner", plus a healthcheck block. It has NO `order` attribute today.
# - The five helper scripts are defined in Dockerfile lines 142-279 and chmod'd 0755 at line 279:
#     bbj-checkout — svn checkout/update of <branch>/BBj (+ BBjTest)   → "SVN Checkout"
#     bbj-build    — Eclipse "Deploy Jars" (compile + deploy jars)     → "Deploy Jars (bbj-build)"
#     bbj-gwt      — Eclipse "Build GWT JavaScript" (BUI/DWC client)   → "Build GWT JS (bbj-gwt)"
#     bbj-test     — runs the BBjTest suite against built classes      → "Run BBjTest"
#     bbj-restart  — restarts BBjServices to pick up freshly built jars → "Restart BBjServices"
# - Header comment block (main.tf:20-26) describes STRUCTURE and ends
#   "...the checkout + BBjServices coder_scripts, and the BBjServices coder_app." —
#   update the last clause to mention the new helper-command coder_apps.
# - Dev-loop comment (main.tf:28-33) lists the five commands; it is accurate — leave as-is
#   or optionally add a one-line note that these are now also UI buttons.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add five command-type coder_app buttons for the bbj-* helpers, priority-ordered</name>
  <files>/workspaces/CoderPrivate/templates/bbj-dev/main.tf</files>
  <action>
In /workspaces/CoderPrivate/templates/bbj-dev/main.tf, add a new section of five `resource "coder_app"` blocks that surface the baked bbj-* helper commands as clickable UI buttons. Place them alongside the existing `coder_app.bbjservices` (currently the last resource in the file, around line 436) under a new box-drawing section header comment matching the file's existing style (e.g. `# ── BBj dev-loop command buttons ─────...`).

Each helper app is a COMMAND-TYPE coder_app: it MUST set `command = "bbj-<name>"` and MUST NOT set `url`, `subdomain`, `share`, or a `healthcheck` block (a command-type app opens a web terminal that runs the command — those URL-only attributes are invalid on it and will fail validation). Every app's `agent_id` MUST be `module.base.agent_id` (the agent is inside the bbj-base module — there is no local coder_agent resource; confirmed against the existing coder_script/coder_app blocks in this file).

Create exactly these five resources (resource label → slug → display_name → command → icon):
  - "bbj_build"    → slug "bbj-build"    → display_name "Deploy Jars (bbj-build)"  → command "bbj-build"    → icon "/icon/java.svg"
  - "bbj_gwt"      → slug "bbj-gwt"      → display_name "Build GWT JS (bbj-gwt)"   → command "bbj-gwt"      → icon "/icon/code.svg"
  - "bbj_restart"  → slug "bbj-restart"  → display_name "Restart BBjServices"       → command "bbj-restart"  → icon "/icon/java.svg"
  - "bbj_checkout" → slug "bbj-checkout" → display_name "SVN Checkout"              → command "bbj-checkout" → icon "/icon/folder.svg"
  - "bbj_test"     → slug "bbj-test"     → display_name "Run BBjTest"               → command "bbj-test"     → icon "/icon/terminal.svg"

Priority ordering via the `order` attribute (lower = shown first). Assign so the three primary actions lead and BBjServices sits sensibly among them:
  - bbj_build   order = 1
  - bbj_gwt     order = 2
  - bbj_restart order = 3
  - bbjservices order = 4  (ADD an `order = 4` attribute to the EXISTING coder_app.bbjservices resource — it currently has none; do not otherwise change that resource)
  - bbj_checkout order = 5
  - bbj_test    order = 6

Icon choices reuse icons already present in this file's parameter blocks (/icon/java.svg, /icon/folder.svg) plus Coder built-in /icon/code.svg and /icon/terminal.svg. If any of /icon/code.svg or /icon/terminal.svg is not a known Coder built-in, substitute /icon/java.svg or /icon/folder.svg (both confirmed used in this file) — icon is cosmetic and must never block validation.

Also update the STRUCTURE header comment at main.tf:25-26: change the trailing clause "...the checkout + BBjServices coder_scripts, and the BBjServices coder_app." to also mention the new helper-command apps (e.g. "...and the BBjServices + bbj-* dev-loop command coder_apps."). Keep the dev-loop comment at lines 28-33 accurate (it already lists the five commands).

Follow the existing formatting: 2-space indentation, aligned `=` where the file already aligns them, one blank line between resources. No fenced code — write real HCL directly into the file.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && grep -c 'resource "coder_app"' main.tf | grep -qx 6 && echo "6 coder_app blocks OK"</automated>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && for c in bbj-checkout bbj-build bbj-gwt bbj-test bbj-restart; do grep -q "command = \"$c\"" main.tf || { echo "MISSING command $c"; exit 1; }; done && echo "all five commands present"</automated>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && awk '/# ── BBj dev-loop command buttons/,0' main.tf | grep -Eq 'url|subdomain|share|healthcheck' && { echo "FAIL: command-type app has forbidden url/subdomain/share/healthcheck"; exit 1; } || echo "no forbidden attrs on command apps"</automated>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && grep -c 'agent_id     = module.base.agent_id\|agent_id = module.base.agent_id' main.tf | awk '$1>=6{print "agent_id wiring OK"; exit 0} {exit 1}'</automated>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && terraform fmt -check main.tf && echo "fmt OK" || echo "fmt WARN (run terraform fmt to normalize; non-blocking)"</automated>
    <automated>cd /workspaces/CoderPrivate/templates/bbj-dev && (terraform init -backend=false -input=false >/tmp/kio-tfinit.log 2>&1 && terraform validate && echo "terraform validate PASS") || echo "terraform validate DEFERRED — provider fetch/init needs network (no .terraform.lock.hcl here); static grep gates above are authoritative, live push is the deploy gate per infra-needs-live-deploy-gate"</automated>
  </verify>
  <done>
Six `resource "coder_app"` blocks exist in main.tf: the five new command-type helper apps (bbj-build, bbj-gwt, bbj-restart, bbj-checkout, bbj-test) plus the pre-existing bbjservices. Each new app sets `command = "bbj-<name>"`, `agent_id = module.base.agent_id`, a display_name matching its Eclipse menu item, an `order` value, and an icon — and NONE of the command-type apps set url/subdomain/share/healthcheck. The bbjservices app gains `order = 4` and is otherwise unchanged. The STRUCTURE header comment mentions the new helper-command apps. All static grep gates pass; terraform validate passes if provider init succeeds, otherwise is documented as DEFERRED to the live push per the infra-needs-live-deploy-gate convention.
  </done>
</task>

</tasks>

<verification>
- `grep -c 'resource "coder_app"' main.tf` returns 6.
- All five `command = "bbj-<name>"` lines present; none of the command-type apps carry url/subdomain/share/healthcheck.
- Every coder_app `agent_id` is `module.base.agent_id`.
- `order` values 1..6 assigned as specified (build/gwt/restart primary, bbjservices 4, checkout/test trailing).
- `terraform validate` PASS, or DEFERRED-with-reason when provider init cannot fetch over the network.
</verification>

<success_criteria>
The bbj-dev workspace template exposes the five bbj-* dev-loop helpers as priority-ordered, clickable command-type coder_app buttons that each open a web terminal running the command, with the BBjServices app repositioned sensibly among them, and the change passes the available static validation gate. Runtime confirmation (buttons appear and launch their commands in a live workspace) is a live-deploy gate handled by the operator.
</success_criteria>

<output>
Create `.planning/quick/260902-kio-expose-bbj-helper-commands-as-coder-app-/260902-kio-SUMMARY.md` when done.
Code commit goes to the /workspaces/CoderPrivate repo; planning artifacts stay under /workspaces/coder/.planning.
</output>