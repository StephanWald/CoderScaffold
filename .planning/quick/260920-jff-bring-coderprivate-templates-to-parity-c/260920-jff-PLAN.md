---
phase: quick-260920-jff
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /workspaces/CoderPrivate/modules/bbj-base/main.tf
  - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
  - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
  - /workspaces/CoderPrivate/scripts/claude-share-selftest.sh
  - /workspaces/CoderPrivate/scripts/push-templates.sh
autonomous: true
requirements: [PARITY-CODEX, PARITY-MEMPALACE, PARITY-SELFTEST]
estimate:
  tokens: 70000
  raw_tokens: 45000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "codex CLI is baked system-wide (npm -g, ARG-pinned 0.155.1) into both bbj-dev and bbj-ls-dev final images, before USER coder"
    - "on workspace start, both bbj templates migrate a pre-existing ~/.codex onto the per-owner shared volume and symlink ~/.codex → $CLAUDE_SHARED/codex"
    - "both bbj templates export CODEX_HOME=/home/coder/.claude-shared/codex in the agent env"
    - "on workspace start, both bbj templates migrate a pre-existing ~/.mempalace onto the shared volume and symlink ~/.mempalace → $CLAUDE_SHARED/mempalace"
    - "the shared-knowledge self-test is baked at /usr/local/bin/claude-share-selftest in both bbj images and exposed as a Self-Test coder_app"
    - "push-templates.sh stages the canonical selftest script into the BBj asset build context on every push"
    - "template-dev is untouched (no node/claude/mempalace prerequisites) and the exclusion is recorded"
  artifacts:
    - /workspaces/CoderPrivate/modules/bbj-base/main.tf
    - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/CoderPrivate/scripts/claude-share-selftest.sh
    - /workspaces/CoderPrivate/scripts/push-templates.sh
  key_links:
    - "Codex/MemPalace sharing blocks live in modules/bbj-base (shared by both templates) — a single edit reaches bbj-dev and bbj-ls-dev"
    - "selftest_sha1 must hash the copy in the BBj asset build context (var.bbj_context_path), NOT path.module — the bbj build context is the asset folder, not the template dir"
    - "the selftest COPY in each Dockerfile resolves against the asset-folder build context, so push-templates.sh must stage the script into ${BBJ_ASSETS_PATH}"
---

<objective>
Bring the CoderPrivate templates (`/workspaces/CoderPrivate`) to parity with `/workspaces/coder`'s
fleet for three recent changes: (1) OpenAI Codex CLI + shared `~/.codex`, (2) MemPalace palace on
the per-owner shared volume, (3) shared-knowledge self-test bake + Self-Test coder_app.

Purpose: same-owner CoderPrivate workspaces (bbj-dev, bbj-ls-dev) gain Codex (one ChatGPT sign-in
per owner across workspaces), a shared MemPalace palace (memory crosses workspaces), and an
operator-facing Self-Test diagnostic — matching the public fleet.

Output: edited bbj-base module + both bbj templates (Dockerfile + main.tf), a committed canonical
selftest script, and an extended push script. All code commits land in the CoderPrivate repo.

Scope decisions (live-verified at planning time against /workspaces/CoderPrivate):
- The Codex sharing block, the MemPalace relocation block, and CODEX_HOME belong in the SHARED
  `modules/bbj-base/main.tf` (owns `coder_agent.main`, the startup_script, and
  `env = merge({...static...}, var.extra_env)`) — ONE edit covers both bbj-dev and bbj-ls-dev.
- NO `mempalace init` exists in bbj-base or either template (only MCP-server registration). So the
  MemPalace item is the relocation/symlink block ONLY — there is no init guard to rewrite.
- The GSD `mempalace.enabled` config flip is SKIPPED: neither bbj-dev (clones BASIS `components`,
  not GSD) nor bbj-ls-dev (clones `bbj-language-server` + `bbj-ls`, not GSD) clones a
  GSD-managed `.planning/config.json` repo. Nothing to enable. Rationale recorded here + in SUMMARY.
- template-dev is EXCLUDED from Codex, MemPalace, and self-test: its lean image has NO Node, NO
  `claude` CLI, and NO `mempalace` CLI (verified: `templates/template-dev/Dockerfile` header says
  "no Node/GSD/MemPalace"). The self-test's node-based JSON/fingerprint checks, the `claude -p`
  knowledge arm, and the whole MemPalace probe would all fail — it is not part of this fleet by
  design. Its own `~/.claude-shared` volume wiring stays as-is.
- CRITICAL build-context difference from the public repo: the bbj images build with
  `context = var.bbj_context_path` (the operator asset folder bind-mounted at /mnt/bbj-assets),
  reading `Dockerfile.bbj-dev` / `Dockerfile.bbj-ls-dev`. COPY directives resolve against that
  asset folder — so the selftest script must be staged into the ASSET FOLDER (not the template
  dir, unlike coderscaffold), and `selftest_sha1` must hash the asset-folder copy.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

Canonical patterns (read the exact diffs before editing):
- `git -C /workspaces/coder show c8667b5` — Codex tracer (Dockerfile install + startup_script sharing block + CODEX_HOME env)
- `git -C /workspaces/coder show 5c0783c -- templates/coderscaffold/Dockerfile templates/coderscaffold/main.tf` — selftest COPY + Self-Test coder_app + selftest_sha1 trigger
- `/workspaces/coder/scripts/claude-share-selftest.sh` — canonical selftest source to copy verbatim into CoderPrivate

CoderPrivate files being edited:
@/workspaces/CoderPrivate/modules/bbj-base/main.tf
@/workspaces/CoderPrivate/templates/bbj-dev/main.tf
@/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
@/workspaces/CoderPrivate/scripts/push-templates.sh

Landmarks (live-verified):
- bbj-base startup_script: existing `~/.claude` shared block (CLAUDE_SHARED), mempalace MCP
  registration at lines ~132-158, GSD block ~160-168, then `${var.extra_startup_script}`. The
  Codex + MemPalace-relocation blocks go inside this heredoc. `env = merge({...}, var.extra_env)`
  static map ends with `CLAUDE_CONFIG_DIR` (line ~187) — add `CODEX_HOME` there.
- bbj-dev Dockerfile: multi-stage; `FROM base AS final` line ~420, `USER coder` line ~470.
  Node LTS installed in `base` (~48-50), inherited by final. Codex install + selftest COPY go in
  the final stage, before `USER coder`.
- bbj-ls-dev Dockerfile: multi-stage; `FROM base AS final` line ~366, `USER coder` line ~403.
  Node in `base` (~80-81). Codex install + selftest COPY go in final, before `USER coder`.
- bbj-dev docker_image `main`: `context = var.bbj_context_path`, `dockerfile = "Dockerfile.bbj-dev"`,
  triggers block lines ~279-288. bbj-ls-dev equivalent at ~283-307 (`Dockerfile.bbj-ls-dev`).
- bbj-dev existing command coder_apps use `agent_id = module.base.agent_id`, plain `order` (no
  `count`), max order 7. bbj-ls-dev orders 2,3.
- push-templates.sh: asset-staging block copies both Dockerfiles into `${ASSETS}` (lines ~85-89,
  inside `if [[ -n "${ASSETS}" ]]`). Extend this block to also stage the selftest script.
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Shared bbj-base module — Codex sharing + MemPalace relocation + CODEX_HOME (reaches both templates)</name>
  <files>/workspaces/CoderPrivate/modules/bbj-base/main.tf</files>
  <action>
Edit the shared module so BOTH bbj-dev and bbj-ls-dev inherit the changes (PARITY-CODEX,
PARITY-MEMPALACE). Read `git -C /workspaces/coder show c8667b5 -- templates/coderscaffold/main.tf`
first for the exact Codex block shape, and the STATE.md 260920-cw8 entry for the MemPalace
relocation shape.

In `coder_agent.main`'s `startup_script` heredoc, insert two blocks after the MemPalace MCP
registration block and before `${var.extra_startup_script}`:

1. MemPalace palace relocation (WR-01 migrate + WR-03 non-fatal): mkdir "$CLAUDE_SHARED/mempalace";
   if `$HOME/.mempalace` is a real dir (not a symlink), cp -an its contents into
   "$CLAUDE_SHARED/mempalace" and remove the original ONLY if the copy succeeded OR the source was
   empty (masked-copy-failure guard — never rm a non-empty dir after a failed copy); then
   `ln -sfn "$CLAUDE_SHARED/mempalace" "$HOME/.mempalace"`. Every step warns-and-continues under
   set -e. NOTE: do NOT add a `mempalace init` — none exists here; the MCP server is already
   registered by the existing block. Do NOT rewrite any init guard (there is none).

2. Codex CLI sharing (verbatim shape from c8667b5): mkdir "$CLAUDE_SHARED/codex"; migrate a
   pre-existing real `$HOME/.codex` with the same cp -an + remove-only-on-success-or-empty guard;
   `ln -sfn "$CLAUDE_SHARED/codex" "$HOME/.codex"`. All WR-03 non-fatal.

Then in the static `env = merge({ ... }, var.extra_env)` map, add after the `CLAUDE_CONFIG_DIR`
line (per c8667b5): `CODEX_HOME = "/home/coder/.claude-shared/codex"` (physical symlink-free path,
mirroring CLAUDE_CONFIG_DIR). It must land inside the FIRST argument of `merge(...)` (the static
object), not in `var.extra_env`.

This is the tracer: it wires the shared module (the layer both templates depend on) end-to-end for
two of the three parity items. Prose comments only — no fenced code.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate && grep -q 'CLAUDE_SHARED/codex' modules/bbj-base/main.tf && grep -q 'CLAUDE_SHARED/mempalace' modules/bbj-base/main.tf && grep -q 'CODEX_HOME = "/home/coder/.claude-shared/codex"' modules/bbj-base/main.tf && grep -vc '^[[:space:]]*#' modules/bbj-base/main.tf >/dev/null && ! grep -q 'mempalace init' modules/bbj-base/main.tf && echo GATE_PASS</automated>
  </verify>
  <done>bbj-base startup_script contains both the `~/.codex` and `~/.mempalace` migrate+symlink blocks (WR-01/WR-03), the static env map exports `CODEX_HOME`, and no `mempalace init` was introduced.</done>
</task>

<task type="auto">
  <name>Task 2: bbj-dev + bbj-ls-dev Dockerfiles — Codex install + selftest COPY (final stage, before USER coder)</name>
  <files>/workspaces/CoderPrivate/templates/bbj-dev/Dockerfile, /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile</files>
  <action>
For EACH of the two multi-stage Dockerfiles, in the FINAL stage (`FROM base AS final`), immediately
before the `USER coder` line, insert two additions (read `git -C /workspaces/coder show c8667b5 --
templates/coderscaffold/Dockerfile` and `5c0783c -- templates/coderscaffold/Dockerfile` for the
exact shapes; PARITY-CODEX, PARITY-SELFTEST):

1. Codex CLI: `ARG CODEX_VERSION=0.155.1` then `RUN npm install -g @openai/codex@${CODEX_VERSION}`.
   node/npm are present (installed in the `base` stage, inherited by `final` via `FROM base`).
   System path (`/usr/local`) survives the home-volume shadow per the volume-shadowed-home rule.
   Include the box-drawing comment header explaining the system-path rationale.

2. Self-test bake: `COPY claude-share-selftest.sh /usr/local/bin/claude-share-selftest` then
   `RUN chmod 0755 /usr/local/bin/claude-share-selftest`, with the comment noting the script is
   staged into the BBj ASSET build context (var.bbj_context_path) by push-templates.sh — the docker
   build context here is the asset folder, so the COPY resolves against `${BBJ_ASSETS_PATH}/`, not
   the template dir. Canonical reviewed source lives at scripts/claude-share-selftest.sh in the repo.

Placement must be in the `final` stage (bbj-dev `FROM base AS final` ~line 420, USER coder ~470;
bbj-ls-dev `FROM base AS final` ~line 366, USER coder ~403) so both land in the runtime image.
Do NOT touch template-dev's Dockerfile (excluded — no Node/claude/mempalace). Prose comments only.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate && for d in bbj-dev bbj-ls-dev; do f=templates/$d/Dockerfile; grep -q 'ARG CODEX_VERSION=0.155.1' "$f" && grep -q 'npm install -g @openai/codex@' "$f" && grep -q 'COPY claude-share-selftest.sh /usr/local/bin/claude-share-selftest' "$f" && grep -q 'chmod 0755 /usr/local/bin/claude-share-selftest' "$f" || { echo "FAIL $d"; exit 1; }; done; grep -qc 'claude-share-selftest' templates/template-dev/Dockerfile && { echo "FAIL template-dev touched"; exit 1; }; echo GATE_PASS</automated>
  </verify>
  <done>Both bbj Dockerfiles install ARG-pinned @openai/codex 0.155.1 via npm -g and COPY+chmod the selftest into /usr/local/bin, all in the final stage before USER coder; template-dev is untouched.</done>
</task>

<task type="auto">
  <name>Task 3: bbj main.tf Self-Test apps + selftest_sha1 triggers, commit canonical selftest, extend push script</name>
  <files>/workspaces/CoderPrivate/templates/bbj-dev/main.tf, /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf, /workspaces/CoderPrivate/scripts/claude-share-selftest.sh, /workspaces/CoderPrivate/scripts/push-templates.sh</files>
  <action>
Four edits (PARITY-SELFTEST):

1. Commit the canonical selftest script: copy `/workspaces/coder/scripts/claude-share-selftest.sh`
   verbatim to `/workspaces/CoderPrivate/scripts/claude-share-selftest.sh` and make it executable
   (chmod 0755). This is the self-contained reviewed source of truth for the private repo; it is
   COMMITTED (unlike the per-template staged copies, which are build artifacts).

2. In BOTH `templates/bbj-dev/main.tf` and `templates/bbj-ls-dev/main.tf`, add a `selftest_sha1`
   entry to the `docker_image "main"` `triggers` map. CRITICAL: hash the copy in the ASSET build
   context, not path.module — mirror the existing `dockerfile_sha1` fallback shape:
   `selftest_sha1 = try(filesha1("${var.bbj_context_path}/claude-share-selftest.sh"), "")`. The
   try() yields "" when the staged copy is absent locally, so terraform validate/fmt pass without it.

3. In BOTH main.tf files, add a command-type `coder_app "self_test"` (read 5c0783c for the field
   set). Match the private repo's existing command-app style: `agent_id = module.base.agent_id`,
   `slug = "self-test"`, `display_name = "Self-Test"`,
   `command = "/usr/local/bin/claude-share-selftest all"`, `icon = "/icon/terminal.svg"`, and a
   trailing `order` (bbj-dev: 8, after the existing max order 7; bbj-ls-dev: 8). Do NOT add a
   `count`, `url`, `share`, or `healthcheck` — the existing bbj command apps use none of those.

4. Extend `scripts/push-templates.sh` asset-staging block (inside `if [[ -n "${ASSETS}" ]]`, where
   Dockerfile.bbj-dev/Dockerfile.bbj-ls-dev are copied into `${ASSETS}`): also stage the canonical
   selftest into the asset build context —
   `cp "${PROJECT_ROOT}/scripts/claude-share-selftest.sh" "${ASSETS}/claude-share-selftest.sh"`
   with an echo, and a guard that warns-and-continues if the canonical source is missing (do not
   abort the push). This is what makes the Dockerfile COPY resolve (build context = asset folder).
   Add `templates/*/claude-share-selftest.sh` and/or `claude-share-selftest.sh` staged copies to
   .gitignore only if the script also stages into template dirs — here it stages into the external
   asset folder, so no .gitignore change is needed; note that in the SUMMARY.

Prose comments only in .tf; the shell edit is directive shell.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate && test -x scripts/claude-share-selftest.sh && cmp -s scripts/claude-share-selftest.sh /workspaces/coder/scripts/claude-share-selftest.sh && for d in bbj-dev bbj-ls-dev; do f=templates/$d/main.tf; grep -q 'selftest_sha1 = try(filesha1("${var.bbj_context_path}/claude-share-selftest.sh"), "")' "$f" && grep -q 'slug         = "self-test"' "$f" && grep -q '/usr/local/bin/claude-share-selftest all' "$f" || { echo "FAIL $d"; exit 1; }; done && grep -q 'claude-share-selftest.sh" "${ASSETS}/claude-share-selftest.sh"' scripts/push-templates.sh && bash -n scripts/push-templates.sh && echo GATE_PASS</automated>
  </verify>
  <done>Canonical selftest committed + byte-identical to source; both bbj main.tf files have the asset-context selftest_sha1 trigger and a Self-Test command coder_app; push-templates.sh stages the script into ${ASSETS} and passes bash -n.</done>
</task>

</tasks>

<verification>
Run from /workspaces/CoderPrivate after all tasks. Terraform for the bbj templates needs the shared
module staged into the template dir (the templates use `source = "./modules/bbj-base"`, staged by
push-templates.sh at push time); stage temporarily, validate, then clean — matching the pattern in
prior CoderPrivate quick-task SUMMARYs. Prefer the dockerized terraform 1.9 image (no local tofu):

1. Codex + MemPalace + CODEX_HOME present in shared module:
   `grep -q 'CLAUDE_SHARED/codex' modules/bbj-base/main.tf && grep -q 'CLAUDE_SHARED/mempalace' modules/bbj-base/main.tf && grep -q 'CODEX_HOME = "/home/coder/.claude-shared/codex"' modules/bbj-base/main.tf`
2. Both Dockerfiles: Codex install + selftest COPY in final stage (Task 2 gate).
3. Both main.tf: selftest_sha1 (asset-context) + Self-Test coder_app (Task 3 gate).
4. Canonical selftest committed, byte-identical, executable (Task 3 gate).
5. push-templates.sh: `bash -n scripts/push-templates.sh` exit 0; selftest staging line present.
6. terraform fmt -check + init -backend=false + validate PASS for templates/bbj-dev and
   templates/bbj-ls-dev (stage modules/ + a jars.json snapshot or rely on fileset fallback; clean
   staged modules/ afterward so they are not committed). template-dev not required (untouched) but
   a fmt -check over it must still pass since it was not modified.

If terraform/tofu is genuinely unavailable and the dockerized image cannot run here, grep + bash -n
gates stand as the authoritative static gate (per 04-01 precedent) and the terraform validate is
recorded as a deferred operator gate in the SUMMARY (infra-needs-live-deploy-gate).
</verification>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| operator host → workspace image | Dockerfile installs (npm -g @openai/codex) and staged asset files (claude-share-selftest.sh) cross into the built image |
| per-owner shared volume → all same-owner workspaces | ~/.codex and ~/.mempalace symlinked onto the shared volume are visible to every workspace of the same owner |
| push script → asset build context | push-templates.sh writes claude-share-selftest.sh into the operator asset folder that becomes the docker build context |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-jff-01 | Tampering | npm install of @openai/codex | high | mitigate | Version pinned (ARG CODEX_VERSION=0.155.1), not floating; identical to the already-reviewed public-fleet install (commit c8667b5). @openai/codex is the official OpenAI package (legitimacy established in prior task 260920-e63). No new/unaudited packages introduced. |
| T-jff-02 | Information Disclosure | shared ~/.codex auth.json across same-owner workspaces | medium | accept | By design and identical to the existing shared ~/.claude model: sharing is scoped to a single owner's per-owner Docker volume (keyed on owner UUID), never across owners. Same trust model already accepted for CLAUDE_CONFIG_DIR. |
| T-jff-03 | Tampering | migration rm of ~/.codex / ~/.mempalace | medium | mitigate | WR-01 guard: rm the original ONLY when cp -an succeeded OR the source dir was empty — a masked copy failure on a non-empty dir never triggers rm (verbatim from the reviewed c8667b5 / 260920-cw8 patterns). |
| T-jff-04 | Denial of Service | startup_script sharing blocks failing under set -e | low | mitigate | Every step is WR-03 warn-and-continue (`|| echo WARN ... >&2`), so a failed mkdir/cp/ln never aborts workspace start. |
| T-jff-SC | Tampering | npm install (@openai/codex) | high | mitigate | No new package beyond the already-audited @openai/codex; RESEARCH package-legitimacy gate satisfied by prior task 260920-e63. Pin prevents silent version drift. No [ASSUMED]/[SUS]/[SLOP] packages introduced. |
</threat_model>

<success_criteria>
- bbj-base module carries the Codex sharing block, the MemPalace relocation block, and CODEX_HOME —
  reaching both bbj-dev and bbj-ls-dev through a single shared edit.
- Both bbj Dockerfiles bake ARG-pinned @openai/codex 0.155.1 and the selftest at /usr/local/bin, in
  the final stage before USER coder.
- Both bbj main.tf files gain an asset-context selftest_sha1 rebuild trigger and a Self-Test
  command coder_app.
- Canonical scripts/claude-share-selftest.sh committed to CoderPrivate (byte-identical to source);
  push-templates.sh stages it into the BBj asset build context.
- template-dev untouched; GSD mempalace.enabled flip skipped — both exclusions recorded in SUMMARY
  with rationale (template-dev lacks node/claude/mempalace; no GSD-managed repo is cloned).
- terraform fmt -check + init -backend=false + validate PASS for bbj-dev and bbj-ls-dev (or the
  static grep + bash -n gate stands with terraform validate deferred as an operator gate);
  bash -n scripts/push-templates.sh exit 0.
- ALL code commits land in /workspaces/CoderPrivate with `feat(quick-260920-jff): ...` messages.
  Live deploy (push templates, rebuild a workspace per template, check `codex --version`,
  `readlink ~/.codex` / `~/.mempalace`, Self-Test button) is the deferred operator gate
  (infra-needs-live-deploy-gate).
</success_criteria>

<output>
Create `/workspaces/coder/.planning/quick/260920-jff-bring-coderprivate-templates-to-parity-c/260920-jff-SUMMARY.md` when done.
</output>
