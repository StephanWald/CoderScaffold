---
phase: quick-260902-jfn
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/push-templates.sh
  - templates/bbj-services/README.md
autonomous: true
requirements: [QUICK-260902-jfn]
estimate:
  tokens: 28000
  raw_tokens: 20000
  tasks: 2
  confidence: high
must_haves:
  truths:
    - "Running push-templates.sh with BBJ_ASSETS_PATH set to an existing dir stages templates/bbj-services/Dockerfile to ${BBJ_ASSETS_PATH}/Dockerfile"
    - "Running push-templates.sh with BBJ_ASSETS_PATH unset or missing warns and continues (never blocks the push loop)"
    - "The staging block echoes what it staged and records the image-context drift rationale in a comment"
    - "bash -n and shellcheck pass on the modified script"
    - "README no longer instructs the operator to manually copy Dockerfile into the asset folder as a required pre-push step"
  artifacts:
    - "scripts/push-templates.sh (with Dockerfile asset-staging block)"
    - "templates/bbj-services/README.md (manual-copy instruction corrected)"
  key_links:
    - "cp templates/bbj-services/Dockerfile -> ${BBJ_ASSETS_PATH}/Dockerfile: the docker build context is the asset folder, so the STAGED Dockerfile (not the repo copy) is what builds the image"
    - "dockerfile_sha1 trigger in main.tf picks up the refreshed staged copy and forces the image rebuild on next workspace start"
---

<objective>
Add a Dockerfile asset-staging block to the public scripts/push-templates.sh so every push refreshes ${BBJ_ASSETS_PATH}/Dockerfile from templates/bbj-services/Dockerfile — closing the image-context drift where a stale, once-manually-copied staged Dockerfile silently builds outdated images even though the repo Dockerfile is current.

Purpose: The bbj-services workspace image is docker-built with var.bbj_context_path (the operator asset folder, bind-mounted at /mnt/bbj-assets) as the BUILD CONTEXT, using the `Dockerfile` INSIDE that folder — not the repo copy. The live staged copy drifted (dated Jul 16) while the repo Dockerfile gained tmux auto-attach, /etc/tmux.conf, the Playwright layer, and bash-default-shell. Today's rebuild therefore produced an image without tmux. Auto-staging keeps the two in lockstep; the existing `dockerfile_sha1 = try(filesha1("${var.bbj_context_path}/Dockerfile"), ...)` trigger already forces a rebuild when the staged copy changes — no main.tf change needed.

Output: A single atomic commit in /workspaces/coder modifying scripts/push-templates.sh and templates/bbj-services/README.md.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@scripts/push-templates.sh
@templates/bbj-services/README.md

# Reference implementation (read-only, DO NOT modify — separate private repo):
# /workspaces/CoderPrivate/scripts/push-templates.sh lines ~68-92 (asset-staging block)
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Add Dockerfile asset-staging block to scripts/push-templates.sh</name>
  <files>scripts/push-templates.sh</files>
  <action>
Insert a new asset-staging section AFTER the authentication step (after the closing `fi` at line ~116) and BEFORE the existing jars.json staging section header (the box-drawing comment beginning "jars.json staging" at line ~118). Match the script's existing style: a box-drawing section header (rows of `# ----`), prose-comment rationale, WARN-and-continue philosophy.

Behavior of the block:
- Read `ASSETS="${BBJ_ASSETS_PATH:-}"` (do NOT collide with the later `_generate_jars_json` function's `local assets`; use an outer-scope name and keep the jars.json function untouched — it reads BBJ_ASSETS_PATH directly via its own `local assets`).
- If `ASSETS` is non-empty AND the directory exists AND `${PROJECT_ROOT}/templates/bbj-services/Dockerfile` exists: `cp "${PROJECT_ROOT}/templates/bbj-services/Dockerfile" "${ASSETS}/Dockerfile"` and echo a line naming the source and destination staged (e.g. reporting the repo Dockerfile was staged into the asset folder).
- If `ASSETS` is empty: WARN to stderr that BBJ_ASSETS_PATH is not set and staging is skipped, then continue (never exit). Match the wording pattern of the existing jars.json unset-warning.
- If `ASSETS` is set but the directory does not exist: WARN to stderr that the path does not exist and staging is skipped, then continue (never exit). Do NOT `exit 1` here — unlike the private script, the public script must never block pushes of the non-BBj templates.
- If `ASSETS` and its directory exist but `templates/bbj-services/Dockerfile` is missing: WARN to stderr and continue.
- Optionally (recommended, informational only — NEVER blocking): for each of `certificate.bls` and `playback.properties`, if the file is absent from `${ASSETS}`, emit a WARN noting the bbj-services image build will need it. Do NOT copy or create these files (operator-supplied prerequisites, not staged artifacts).

The section comment MUST record the drift rationale in prose: the docker build uses the STAGED copy in the asset folder as the build-context Dockerfile; a stale staged copy silently builds outdated images even though the repo Dockerfile is current; and the template's `dockerfile_sha1` trigger picks up the refreshed staged copy and forces an image rebuild on next workspace start.

Preserve `set -euo pipefail` correctness: no unguarded array expansions, no unbound variables (use `${BBJ_ASSETS_PATH:-}`).
  </action>
  <verify>
    <automated>bash -n /workspaces/coder/scripts/push-templates.sh && command -v shellcheck >/dev/null 2>&1 && shellcheck /workspaces/coder/scripts/push-templates.sh || echo "shellcheck-unavailable-bash-n-passed"</automated>
  </verify>
  <done>bash -n passes; shellcheck passes (or is unavailable); the new section sits between the auth step and the jars.json section; the block copies templates/bbj-services/Dockerfile to ${BBJ_ASSETS_PATH}/Dockerfile when the path is valid and warns-and-continues otherwise.</done>
</task>

<task type="auto">
  <name>Task 2: Dry-run staging test + README manual-copy correction</name>
  <files>templates/bbj-services/README.md</files>
  <action>
Part A — Dry-run staging test (verification only, no committed artifact):
Simulate ONLY the staging-block logic against a scratchpad asset dir. Create `/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test/` containing dummy `certificate.bls` and `playback.properties` files. Then exercise the copy logic in isolation — set BBJ_ASSETS_PATH to that dir and run the equivalent of `cp templates/bbj-services/Dockerfile "$BBJ_ASSETS_PATH/Dockerfile"` — and confirm the staged Dockerfile lands there and matches the repo copy (e.g. `cmp`). Do NOT run the full push-templates.sh (it requires the coder CLI login + a live Coder server, which are absent here — per the LIVE VERIFICATION DEFERRED note in the script header and project memory "Infra needs a live deploy gate"). This is a dry test of the staging logic only; do not commit anything under scratchpad.

Part B — README correction (templates/bbj-services/README.md):
Update the two places that instruct the operator to MANUALLY copy the Dockerfile into the asset folder as a required pre-push step:
1. Setup Step 1 (around lines 56-67): the block reading "Then ship the template's build files into the asset folder ... cp templates/bbj-services/Dockerfile ./bbj-assets/ ... cp templates/bbj-services/playback.properties ./bbj-assets/" and the following blockquote "Only Dockerfile + playback.properties need copying into BBJ_ASSETS_PATH before a push". Rewrite so it states that scripts/push-templates.sh stages the Dockerfile into BBJ_ASSETS_PATH automatically on every push; a manual copy is only needed when building the image OUTSIDE the script (e.g. a manual host `docker build` to pre-warm the cache). Keep the playback.properties guidance accurate: the script does NOT stage playback.properties or certificate.bls (operator-supplied prerequisites) — if the current Step-1 text tells the operator to copy playback.properties, keep that as a manual step (the script never stages it), and clarify the Dockerfile is now automatic while playback.properties + certificate.bls remain operator-supplied.
2. Architecture diagram (around line 389): the annotation `Dockerfile  <- version-controlled; operator copies into BBJ_ASSETS_PATH` — change the annotation to reflect that push-templates.sh stages it automatically (e.g. "staged into BBJ_ASSETS_PATH by push-templates.sh").

Do not alter unrelated README sections. Do not touch /workspaces/coder/bbj-assets/, .planning/ history, or .env.example.
  </action>
  <verify>
    <automated>mkdir -p "/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test" && : > "/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test/certificate.bls" && : > "/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test/playback.properties" && cp /workspaces/coder/templates/bbj-services/Dockerfile "/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test/Dockerfile" && cmp /workspaces/coder/templates/bbj-services/Dockerfile "/tmp/claude-1000/-workspaces-coder/7915fb5e-34f3-4f37-a162-1b7e0a309b39/scratchpad/assets-test/Dockerfile" && echo "STAGING-DRY-RUN-OK" && ! grep -qE 'operator copies into BBJ_ASSETS_PATH' /workspaces/coder/templates/bbj-services/README.md && echo "README-MANUAL-COPY-CORRECTED"</automated>
  </verify>
  <done>The dry-run stages the Dockerfile into the scratchpad asset dir and it matches the repo copy (STAGING-DRY-RUN-OK); the README no longer instructs a required manual Dockerfile copy in Step 1 nor in the Architecture diagram; playback.properties/certificate.bls remain documented as operator-supplied.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| script → operator asset folder | The script writes ${BBJ_ASSETS_PATH}/Dockerfile from a repo-controlled source |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-jfn-01 | Tampering | staged Dockerfile source | low | accept | Source is the version-controlled templates/bbj-services/Dockerfile in the same repo; no external download; cp is a straight copy of a git-tracked file. |
| T-jfn-02 | Denial of Service | push loop for non-BBj templates | low | mitigate | Staging block is warn-and-continue only; an unset/missing BBJ_ASSETS_PATH or missing Dockerfile never exits, so non-BBj template pushes are never blocked. |
| T-jfn-SC | Tampering | package installs | low | accept | No package-manager installs in this change (pure bash edit + README). No legitimacy gate required. |
</threat_model>

<verification>
- `bash -n scripts/push-templates.sh` exits 0
- `shellcheck scripts/push-templates.sh` exits 0 (or shellcheck unavailable → bash -n is the gate)
- Dry-run: staging logic copies templates/bbj-services/Dockerfile into a scratchpad asset dir; `cmp` confirms identical
- README: `grep -qE 'operator copies into BBJ_ASSETS_PATH'` returns no match; Step 1 now says the script stages the Dockerfile automatically
- No changes outside scripts/push-templates.sh and templates/bbj-services/README.md
</verification>

<success_criteria>
- scripts/push-templates.sh stages templates/bbj-services/Dockerfile into ${BBJ_ASSETS_PATH}/Dockerfile on every run when the path is valid
- Unset/missing BBJ_ASSETS_PATH or missing repo Dockerfile → WARN + continue (never blocks the push)
- The block's comment records the image-context drift rationale and the dockerfile_sha1 rebuild trigger
- README no longer instructs a required manual Dockerfile copy; playback.properties + certificate.bls stay documented as operator-supplied prerequisites
- One atomic commit in /workspaces/coder only (no CoderPrivate changes)
</success_criteria>

<live_gate>
LIVE DEPLOY GATE (operator, deferred — per project memory "Infra needs a live deploy gate"):
On the live host, run scripts/push-templates.sh, confirm ${BBJ_ASSETS_PATH}/Dockerfile mtime is refreshed, restart the bbj-services workspace, confirm the image rebuilds (dockerfile_sha1 trigger fires), and confirm the web terminal lands in tmux. This cannot be verified in the dev container (no coder CLI, no live Coder server). SUMMARY must flag this gate.
</live_gate>

<output>
Create `.planning/quick/260902-jfn-public-push-templates-sh-must-stage-bbj-/260902-jfn-SUMMARY.md` when done
</output>
