---
phase: quick-260902-bgt
plan: 01
type: execute
wave: 1
depends_on: []
autonomous: true
requirements: [QUICK-BGT]
files_modified:
  - /workspaces/coder/scripts/push-templates.sh
  - /workspaces/CoderPrivate/scripts/push-templates.sh
  - /workspaces/coder/templates/bbj-services/main.tf
  - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
  - /workspaces/coder/.gitignore
  - /workspaces/CoderPrivate/.gitignore
  - /workspaces/coder/templates/bbj-services/README.md
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/README.md
estimate:
  tokens: 55000
  raw_tokens: 30000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "Both push scripts generate a sorted jars.json (array of *.jar basenames) into each template dir whose main.tf references jars.json"
    - "Missing/empty BBJ_ASSETS_PATH warns, removes stale jars.json, and does NOT block the push"
    - "All three main.tf files prefer jars.json (readable by the dynamic-parameters preview engine) with fileset() as fallback"
    - "jars.json is gitignored in both repos"
    - "terraform validate passes in all three template dirs"
  artifacts:
    - /workspaces/coder/scripts/push-templates.sh
    - /workspaces/CoderPrivate/scripts/push-templates.sh
    - /workspaces/coder/templates/bbj-services/main.tf
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/coder/.gitignore
    - /workspaces/CoderPrivate/.gitignore
  key_links:
    - "push script jars.json generation -> local.bbj_jar_options in main.tf -> bbj_installer dynamic options + default"
---

<objective>
Make the BBj installer dropdown work under Coder's dynamic-parameters form by snapshotting the jar list into the template files at push time.

Coder >=2.25 renders the workspace-creation form with the dynamic-parameters preview engine, which evaluates parameter HCL against the PUSHED TEMPLATE FILES ONLY. It cannot read the provisioner's /mnt/bbj-assets bind mount, so `fileset(var.bbj_context_path, "*.jar")` returns empty in the form and the `bbj_installer` parameter degrades to a free-text box. The sanctioned fix (Coder docs) is to snapshot the jar list into a JSON file inside the template files at push time and read it with `jsondecode(file(...))`, keeping `fileset()` as the provisioner-side fallback.

Purpose: Restore a working dropdown of staged jars in the workspace-create form without relying on the deprecated classic-flow opt-out.
Output: Push-time jars.json generation in both push scripts; jars.json consumption in all three main.tf; gitignore + README + verification.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@/workspaces/coder/.planning/STATE.md
@/workspaces/coder/CLAUDE.md
@/workspaces/coder/scripts/push-templates.sh
@/workspaces/CoderPrivate/scripts/push-templates.sh
@/workspaces/coder/templates/bbj-services/main.tf
@/workspaces/CoderPrivate/templates/bbj-dev/main.tf
@/workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf

# Design notes (already confirmed with the user):
# - jars.json is a sorted JSON array of the basenames of ${BBJ_ASSETS_PATH}/*.jar
# - No jq dependency (deliberately removed with bbj-build-combos.sh); build JSON with plain bash
# - Escape backslash and double-quote in jar names for correctness
# - The public push script (/workspaces/coder) already sources .env with BBJ_ASSETS_PATH? NO —
#   it only reads CODER_ACCESS_URL/CODER_SESSION_TOKEN today. The .env set -a source at lines
#   60-67 already loads ALL .env vars into the environment, so BBJ_ASSETS_PATH is available if
#   present in that repo's .env. Reference it as ${BBJ_ASSETS_PATH:-}.
# - The private push script already defines ASSETS="${BBJ_ASSETS_PATH:-}" at line 74.
# - The private repo already gitignores templates/*/modules/ — follow that pattern for jars.json.
# - Real jars for standalone testing: /workspaces/coder/bbj-assets has 2 *.jar files.
# - terraform and shellcheck are both on PATH.
# - Module for private-template init: /workspaces/CoderPrivate/modules/bbj-base
</context>

<tasks>

<task type="tracer">
  <name>Task 1: jars.json generation in both push scripts (end-to-end tracer)</name>
  <files>/workspaces/coder/scripts/push-templates.sh, /workspaces/CoderPrivate/scripts/push-templates.sh</files>
  <action>
Add a generic push-time jars.json staging step to BOTH push scripts, matching each script's existing comment-block + warn-and-continue style.

Shared logic (implement once per script, before the discover-and-push loop):
- Determine the assets path from the environment: use `${BBJ_ASSETS_PATH:-}`. In the public script the .env `set -a` source (lines 60-67) already exports it if present; in the private script reuse the existing `ASSETS="${BBJ_ASSETS_PATH:-}"` variable (defined ~line 74).
- Write a helper that produces a sorted JSON array of the basenames of `${assets}/*.jar` using PLAIN BASH (no jq): collect matches with a nullglob-safe glob into an array; sort with `printf '%s\n' "${arr[@]}" | LC_ALL=C sort`; build the JSON string with a printf loop. For each name, escape a literal backslash first, then a literal double-quote, so names remain valid JSON. Emit `[]` when there are no jars.
- For EACH template dir under `templates/*/` whose `main.tf` contains the token `jars.json` (grep -q for the literal filename token), generate `${dir}jars.json` with the array above and echo which template got a generated jars.json (e.g. "Generated <name>/jars.json (N jars)").
- If `BBJ_ASSETS_PATH` is unset/empty OR the folder exists but contains no *.jar: WARN to stderr, and for each matching template dir REMOVE any stale `${dir}jars.json` (so the template falls back to fileset()). Do NOT block the push (no exit). Echo a summary of which stale files were removed / that generation was skipped.
- Place this step to fit each script's structure: in the public script, after the .env source / cd and before or alongside the push loop; in the private script, after the existing module-staging block (~line 116) and before the push loop, reusing the `ASSETS` variable so the missing-path behavior is consistent with the existing asset-staging warn.
- Add a summary line consistent with each script's existing summary style noting how many template jars.json files were generated.

Do NOT introduce jq. Do NOT change auth, lockfile, asset-staging, module-staging, or push-loop logic beyond adding this step.
  </action>
  <verify>
    <automated>bash -n /workspaces/coder/scripts/push-templates.sh && bash -n /workspaces/CoderPrivate/scripts/push-templates.sh && shellcheck /workspaces/coder/scripts/push-templates.sh && shellcheck /workspaces/CoderPrivate/scripts/push-templates.sh</automated>
  </verify>
  <done>Both scripts pass `bash -n` and `shellcheck`; each contains a jars.json generation step gated on a main.tf `jars.json` token check, builds JSON with plain bash (no jq), and warns+removes-stale+continues when BBJ_ASSETS_PATH is unset or has no jars.</done>
</task>

<task type="auto">
  <name>Task 2: Consume jars.json in all three main.tf files</name>
  <files>/workspaces/coder/templates/bbj-services/main.tf, /workspaces/CoderPrivate/templates/bbj-dev/main.tf, /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf</files>
  <action>
In each of the three main.tf files, wire the `bbj_installer` parameter to prefer a push-time jars.json snapshot, falling back to fileset() over the bind mount.

1. Add a local to the existing `locals { ... }` block in each file:
   `bbj_jar_options = try(sort(jsondecode(file("${path.module}/jars.json"))), sort(fileset(var.bbj_context_path, "*.jar")))`
   (bbj-services locals ~line 301-330; bbj-dev locals ~line 212-229; bbj-ls-dev locals ~line 242-250). jsondecode already yields the sorted array the script wrote, but wrap in sort() for determinism; the try() falls back to fileset() when jars.json is absent (provisioner-side plans still see the mount).

2. In each `data "coder_parameter" "bbj_installer"` block:
   - Change `default` to `try(local.bbj_jar_options[0], "")`.
   - Change the `dynamic "option"` `for_each` to `local.bbj_jar_options`.
   (bbj-services ~lines 213-230; bbj-dev ~lines 157-174; bbj-ls-dev ~lines 187-204.)

3. Update the surrounding comments (the block comment above each bbj_installer parameter, and the "JAR options come from fileset()" locals comment in bbj-services ~lines 315-323) to state: the PRIMARY source is the push-script-generated jars.json snapshot, which the dynamic-parameters preview engine can read because it only sees template files; fileset() over the bind mount remains the FALLBACK when jars.json is absent (provisioner-side plans still see the mount, and the form then degrades to free text). KEEP the existing caveat comment about deleting a jar orphaning workspaces that selected it.

Leave everything else unchanged — the BBJ_JAR_NAME build arg, bbj_slug, triggers, and every other parameter. The parameter VALUE is still the raw jar filename.
  </action>
  <verify>
    <automated>cd /workspaces/coder/templates/bbj-services && terraform init -backend=false >/dev/null 2>&1 && terraform validate && cd /workspaces/CoderPrivate/templates/bbj-dev && ln -sfn /workspaces/CoderPrivate/modules/bbj-base ./modules && terraform init -backend=false >/dev/null 2>&1 && terraform validate; RC1=$?; rm -f ./modules; rm -rf .terraform .terraform.lock.hcl; cd /workspaces/CoderPrivate/templates/bbj-ls-dev && mkdir -p modules && ln -sfn /workspaces/CoderPrivate/modules/bbj-base ./modules/bbj-base && terraform init -backend=false >/dev/null 2>&1 && terraform validate; RC2=$?; rm -rf ./modules .terraform .terraform.lock.hcl; test $RC1 -eq 0 && test $RC2 -eq 0</automated>
  </verify>
  <done>All three template dirs pass `terraform validate`. Each `bbj_installer` uses `local.bbj_jar_options` for both `default` and the dynamic option `for_each`; each locals block defines `bbj_jar_options` with the jsondecode-then-fileset try(); comments explain the jars.json-primary / fileset-fallback rationale and keep the orphaning caveat. Transient private-template `modules` symlink and `.terraform*` artifacts are removed afterward.</done>
</task>

<task type="auto">
  <name>Task 3: Gitignore, docs, standalone JSON test, and per-repo commits</name>
  <files>/workspaces/coder/.gitignore, /workspaces/CoderPrivate/.gitignore, /workspaces/coder/templates/bbj-services/README.md, /workspaces/CoderPrivate/templates/bbj-ls-dev/README.md</files>
  <action>
1. Gitignore (jars.json is a generated build artifact):
   - /workspaces/coder/.gitignore: add `templates/*/jars.json` under the Terraform-noise section (near the other generated-artifact entries), with a one-line comment noting it is the push-script-generated jar snapshot.
   - /workspaces/CoderPrivate/.gitignore: add `templates/*/jars.json` right below the existing `templates/*/modules/` entry (line 12), following that same "build artifacts, never commit" pattern/comment.

2. Docs — update both READMEs (bbj-services README "Step 5: Create a workspace" area ~lines 102-107 and its Architecture section jar-discovery note ~line 373; bbj-ls-dev README "What's in the box" BBj bullet ~lines 15-20):
   - The installer dropdown is populated from a push-time jars.json snapshot generated by scripts/push-templates.sh.
   - Staging a NEW jar requires RE-RUNNING the push script for it to appear in the dropdown (it is immediately buildable via free-text / API either way).
   - Briefly note the dynamic-parameters rationale: Coder >=2.25's form preview engine reads only pushed template files, not the bind mount, so the jar list must be snapshotted into the template.

3. Standalone JSON-generation test (verify only — do not commit test output): run the bash JSON-building logic against /workspaces/coder/bbj-assets (2 real jars) and confirm the output is valid JSON with `python3 -m json.tool`. This proves the plain-bash JSON builder emits a valid sorted array before relying on it at push time.

4. Commits — one atomic conventional commit per repo:
   - In /workspaces/coder: commit push-templates.sh, templates/bbj-services/main.tf, .gitignore, templates/bbj-services/README.md. Message e.g. `feat(templates): snapshot jar list into jars.json at push time for dynamic-parameters dropdown`.
   - In /workspaces/CoderPrivate: commit scripts/push-templates.sh, templates/bbj-dev/main.tf, templates/bbj-ls-dev/main.tf, .gitignore, templates/bbj-ls-dev/README.md. Same conventional style.
   - Ensure NO jars.json, no `modules/` symlink, and no `.terraform*` artifacts are staged in either commit (they are gitignored / removed in Task 2).
  </action>
  <verify>
    <automated>grep -q 'templates/\*/jars.json' /workspaces/coder/.gitignore && grep -q 'templates/\*/jars.json' /workspaces/CoderPrivate/.gitignore && grep -qi 'jars.json' /workspaces/coder/templates/bbj-services/README.md && grep -qi 'jars.json' /workspaces/CoderPrivate/templates/bbj-ls-dev/README.md && test -z "$(git -C /workspaces/coder status --porcelain templates/bbj-services/jars.json 2>/dev/null)" && test -z "$(git -C /workspaces/coder ls-files templates/*/jars.json)" && test -z "$(git -C /workspaces/CoderPrivate ls-files 'templates/*/jars.json')"</automated>
  </verify>
  <done>Both .gitignore files ignore `templates/*/jars.json`; both READMEs document the jars.json snapshot + re-run-push requirement + dynamic-parameters rationale; the plain-bash JSON builder produced valid JSON for the 2 real jars in /workspaces/coder/bbj-assets; one conventional commit landed per repo with no jars.json / modules symlink / .terraform artifacts staged.</done>
</task>

</tasks>

<verification>
- `bash -n` + `shellcheck` clean on both push scripts.
- `terraform validate` passes in bbj-services, bbj-dev, bbj-ls-dev (private templates via a transient modules symlink that is removed afterward, along with .terraform/.terraform.lock.hcl).
- Standalone JSON builder emits valid JSON (`python3 -m json.tool`) for the 2 real jars in /workspaces/coder/bbj-assets.
- Both .gitignore files ignore `templates/*/jars.json`; no jars.json is tracked in either repo.
- One atomic conventional commit per repo.
</verification>

<success_criteria>
- Both push scripts generate a sorted, plain-bash (no jq) jars.json into each template dir whose main.tf references jars.json, and warn+remove-stale+continue when BBJ_ASSETS_PATH is unset or empty.
- All three main.tf files prefer `local.bbj_jar_options` (jsondecode of jars.json) with fileset() fallback, for both the dropdown options and the default.
- jars.json is gitignored in both repos and left untracked.
- READMEs explain the snapshot mechanism, the re-run-push-to-refresh requirement, and the dynamic-parameters rationale.
- terraform validate passes for all three templates.
</success_criteria>

<live_gate>
STATIC VERIFICATION ONLY in this environment (no coder CLI, no running Coder server; per project memory "infra-needs-live-deploy-gate"). The SUMMARY MUST flag the live gate: the operator re-runs scripts/push-templates.sh on the live host (BBJ_ASSETS_PATH populated) and confirms the workspace-create form's "BBj installer JAR" parameter renders a DROPDOWN listing the staged jars (not a free-text box) — for bbj-services (public) and bbj-dev + bbj-ls-dev (private).
</live_gate>

<output>
Create /workspaces/coder/.planning/quick/260902-bgt-generate-jars-json-snapshot-at-template-/260902-bgt-SUMMARY.md when done
</output>
