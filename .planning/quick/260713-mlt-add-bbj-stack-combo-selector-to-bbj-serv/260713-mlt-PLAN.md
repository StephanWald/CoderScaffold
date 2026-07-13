---
phase: 260713-mlt
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/bbj-services/main.tf
  - templates/bbj-services/Dockerfile
  - templates/bbj-services/combinations.example.json
  - scripts/bbj-build-combos.sh
  - templates/bbj-services/README.md
  - .env.example
autonomous: true
requirements: []

must_haves:
  truths:
    - "The Coder create-workspace form shows a single 'BBj stack' dropdown listing curated (BBj version + JDK) combos; there is no standalone JDK picker."
    - "Selecting a combo derives the JDK and jar; an unsupported BBj×JDK pairing cannot be selected."
    - "`terraform validate` passes in this repo with NO combinations.json present (try() falls back to local.default_combinations)."
    - "`scripts/bbj-build-combos.sh` pre-builds one image per combo from the same context + build args and exits non-zero if any build fails."
    - "No dangling reference to the removed jdk coder_parameter remains in main.tf."
  artifacts:
    - path: "templates/bbj-services/main.tf"
      provides: "bbj_stack coder_parameter + combinations locals + combo-derived image build"
      contains: "coder_parameter\" \"bbj_stack\""
    - path: "templates/bbj-services/Dockerfile"
      provides: "named-jar ADD via BBJ_JAR_NAME build arg"
      contains: "ARG BBJ_JAR_NAME"
    - path: "templates/bbj-services/combinations.example.json"
      provides: "version-controlled example combo list for operators to copy"
      contains: "adoptium-25"
    - path: "scripts/bbj-build-combos.sh"
      provides: "non-interactive per-combo image pre-warm script"
      contains: "set -euo pipefail"
  key_links:
    - from: "templates/bbj-services/main.tf"
      to: "combinations.json (var.bbj_context_path)"
      via: "try(jsondecode(file(...)), local.default_combinations)"
      pattern: "jsondecode\\(file"
    - from: "templates/bbj-services/main.tf"
      to: "templates/bbj-services/Dockerfile"
      via: "BBJ_JAR_NAME build_arg = local.selected.jar"
      pattern: "BBJ_JAR_NAME"
    - from: "scripts/bbj-build-combos.sh"
      to: "combinations.json (asset folder)"
      via: "jq reads the SAME combinations.json the template reads"
      pattern: "combinations"
---

<objective>
Replace the standalone `jdk` coder_parameter + single-jar build in `templates/bbj-services/`
with an admin-curated "BBj stack" dropdown. The curated (BBj version + JDK) combos come from
`combinations.json` in the operator asset folder, read at plan time and wrapped in
`try(..., local.default_combinations)`. Both build paths are kept: on-demand in-template build
(fallback) plus a new `scripts/bbj-build-combos.sh` pre-warm script that builds every combo
against the same host Docker daemon/context so subsequent in-template builds are cache hits.

Purpose: kill the invalid-BBj×JDK-pairing risk (operator curates only valid combos; JDK is
derived, never separately picked) while keeping the template usable and `terraform validate`-clean
in this repo where no real combinations.json exists.

Output: migrated main.tf + Dockerfile, new combinations.example.json, new bbj-build-combos.sh,
updated README.md and .env.example note.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/quick/260713-mlt-add-bbj-stack-combo-selector-to-bbj-serv/260713-mlt-CONTEXT.md
@templates/bbj-services/main.tf
@templates/bbj-services/Dockerfile
@templates/bbj-services/README.md
@scripts/backup.sh
@CLAUDE.md

NOTE on .env.example: it is Read-blocked. View it with `git show HEAD:.env.example`, then
Edit/append. It already contains a `## BBjServices template` section defining BBJ_ASSETS_PATH
and BBJ_LICENSE_SERVER — extend the comment there; do NOT duplicate those variables.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Migrate main.tf + Dockerfile to the bbj_stack combo selector</name>
  <files>templates/bbj-services/main.tf, templates/bbj-services/Dockerfile</files>
  <action>
In `templates/bbj-services/main.tf`:
  1. REMOVE the entire `data "coder_parameter" "jdk"` block (lines defining name/display_name/
     description/default/mutable/icon/order and both adoptium-21/adoptium-25 `option` blocks).
  2. In the existing top-of-file header comment, update the "Workspace parameters" list: replace
     the `jdk` line with a `bbj_stack` line ("which curated (BBj version + JDK) combo to build").
  3. ADD a `data "coder_parameter" "bbj_stack"` block AFTER the git_repo parameter: type string,
     display_name "BBj stack", icon "/icon/java.svg", order 2, `mutable = false` (a different combo
     is a new workspace, per D-locked decision), `default = local.bbj_combinations[0].id`, and a
     `dynamic "option" { for_each = local.bbj_combinations; content { name = option.value.display; value = option.value.id } }`.
     Add a short description noting the JDK is derived from the combo (no separate JDK picker) so
     unsupported pairings cannot be selected.
  4. ADD the combinations locals. Put them where they are valid HCL (a `locals {}` block that can
     reference var.bbj_context_path and data.coder_parameter.bbj_stack.value — the existing
     `locals` block near the data sources is fine, or a new locals block). The read MUST be exactly:
       bbj_combinations = try(jsondecode(file("${var.bbj_context_path}/combinations.json")), local.default_combinations)
     with `default_combinations` a small built-in list (at least the bbj-25.12-jdk21 entry with
     fields id/display/jar/jdk), `combos_by_id = { for c in local.bbj_combinations : c.id => c }`,
     and `selected = local.combos_by_id[data.coder_parameter.bbj_stack.value]`.
  5. MIGRATE EVERY reference to the removed parameter. Grep the file for `jdk` and for
     `coder_parameter.jdk` and replace ALL:
       - docker_image `name`  -> "coder-${data.coder_workspace.me.id}-bbj-${data.coder_parameter.bbj_stack.value}"
       - build_args `JDK`     -> local.selected.jdk ; ADD build_arg `BBJ_JAR_NAME = local.selected.jar`
         (keep BASE_IMAGE, MAVEN_VERSION, LICENSE_SERVER build_args unchanged).
       - triggers: replace `jdk = data.coder_parameter.jdk.value` with `stack = data.coder_parameter.bbj_stack.value`
         AND `jdk = local.selected.jdk`; change bbj_jar_sha1 to
         `try(filesha1("${var.bbj_context_path}/${local.selected.jar}"), "no-jar")`; keep
         dockerfile_sha1, maven_version, license_server triggers.
     Leave NO dangling `data.coder_parameter.jdk` reference anywhere. The agent env
     JAVA_HOME=/opt/java/default and MAVEN_HOME=/opt/maven stay unchanged (fixed paths, combo-independent).
  6. Update the docker_image header comment block that mentions "the JDK selection" to say
     "the selected BBj stack (BBj version + JDK)".

In `templates/bbj-services/Dockerfile`:
  1. Replace `ADD BBj*.jar /tmp/BBj.jar` with two lines:
       ARG BBJ_JAR_NAME=BBj.jar
       ADD ${BBJ_JAR_NAME} /tmp/BBj.jar
     Keep the existing `ADD playback.properties` and `ADD certificate.bls` lines around it.
  2. Add BBJ_JAR_NAME to the "Build args" comment header near the top (alongside JDK/MAVEN_VERSION/
     LICENSE_SERVER), noting it is the named jar filename staged in the asset folder.
  3. Do NOT touch the `ARG JDK` block or the adoptium-21/adoptium-25 install case logic — unchanged.

Provider pins (coder ~> 2.18, kreuzwerker/docker ~> 4.4, terraform >= 1.9) unchanged. Do NOT
inline any fenced literal in the .tf/Dockerfile that a later grep gate would negate.
  </action>
  <verify>
    <automated>cd templates/bbj-services && terraform init -backend=false >/dev/null && terraform validate && terraform fmt -check && ! grep -nE 'coder_parameter\.jdk' main.tf && grep -q 'ARG BBJ_JAR_NAME' Dockerfile</automated>
  </verify>
  <done>
`terraform validate` passes with no combinations.json present; `terraform fmt -check` clean; no
`coder_parameter.jdk` reference remains in main.tf; Dockerfile ADDs the jar via BBJ_JAR_NAME.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add combinations.example.json + bbj-build-combos.sh pre-warm script</name>
  <files>templates/bbj-services/combinations.example.json, scripts/bbj-build-combos.sh</files>
  <action>
Create `templates/bbj-services/combinations.example.json` (version-controlled). A JSON array of
combo objects, at least the two from CONTEXT.md:
  - { "id": "bbj-26.01-jdk25", "display": "BBj 26.01 · JDK 25 (Adoptium)", "jar": "BBj-26.01.jar", "jdk": "adoptium-25" }
  - { "id": "bbj-25.12-jdk21", "display": "BBj 25.12 · JDK 21 (Adoptium)", "jar": "BBj-25.12.jar", "jdk": "adoptium-21" }
Field contract: `id` unique + safe as a docker image tag; `jar` = filename staged in the asset
folder; `jdk` MUST be one of the Dockerfile-supported values (adoptium-21 | adoptium-25); `display`
is the human-readable dropdown label. Valid JSON (jsondecode must parse it) — no trailing commas,
no comments.

Create `scripts/bbj-build-combos.sh`, matching the conventions in scripts/backup.sh:
  - `#!/usr/bin/env bash` shebang; `set -euo pipefail`.
  - SCRIPT_DIR / PROJECT_ROOT resolution via BASH_SOURCE (works from cron/absolute path).
  - Source `.env` with the `set -a; source; set +a` pattern (guard on file existence, WARN to
    stderr if absent). Apply defaults: BBJ_ASSETS_PATH="${BBJ_ASSETS_PATH:-./bbj-assets}",
    BBJ_LICENSE_SERVER="${BBJ_LICENSE_SERVER:-}", and a BASE_IMAGE default matching the template
    (codercom/enterprise-base:ubuntu) plus MAVEN_VERSION default (3.9.16) for build-arg parity.
  - Resolve the combos file: prefer "$BBJ_ASSETS_PATH/combinations.json"; if absent, fall back to
    the version-controlled templates/bbj-services/combinations.example.json with a WARN to stderr.
  - Require `jq`: if not on PATH, print a clear error to stderr and exit non-zero (e.g. exit 2).
  - Iterate combos with jq (read id/jar/jdk per entry). For each combo:
      * fail-fast: verify "$BBJ_ASSETS_PATH/<jar>" exists; if missing, record a FAIL for that combo
        with a clear message and continue (do not abort the whole loop on a missing jar — collect
        results so the summary is complete).
      * run: docker build --build-arg JDK=<jdk> --build-arg BBJ_JAR_NAME=<jar>
        --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg MAVEN_VERSION="$MAVEN_VERSION"
        --build-arg LICENSE_SERVER="$BBJ_LICENSE_SERVER" -t "bbj-services:<id>" "$BBJ_ASSETS_PATH"
      * record pass/fail per combo.
  - Print a per-combo PASS/FAIL summary at the end. Exit 0 only if every combo built; exit non-zero
    (e.g. 1) if any combo failed or its jar was missing.
  - Do not disable `set -e` blindly around the docker build — capture its status explicitly (e.g.
    `if docker build ...; then ... else ... fi`) so one failure does not abort the summary.
  - Document at the top (comment header): non-interactive, exit-code meanings, and that it cannot
    be run end-to-end in this repo (no real jars / no BLS reachable) — that is the operator step.
  - `chmod +x scripts/bbj-build-combos.sh` after creating it (mode 0755 like the other scripts).
  </action>
  <verify>
    <automated>bash -n scripts/bbj-build-combos.sh && python3 -c "import json,sys; json.load(open('templates/bbj-services/combinations.example.json'))" && test -x scripts/bbj-build-combos.sh && { command -v shellcheck >/dev/null 2>&1 && shellcheck scripts/bbj-build-combos.sh || echo 'shellcheck not present — skipped'; }</automated>
  </verify>
  <done>
combinations.example.json parses as valid JSON and lists both example combos; bbj-build-combos.sh
passes `bash -n`, is executable (0755), follows the backup.sh env/exit-code conventions, requires
jq, verifies each jar exists, and exits non-zero on any failure. shellcheck (if installed) passes.
  </done>
</task>

<task type="auto">
  <name>Task 3: Update README.md and .env.example note for the combo workflow</name>
  <files>templates/bbj-services/README.md, .env.example</files>
  <action>
In `templates/bbj-services/README.md`:
  1. Setup Step 1: replace the single-jar instruction ("cp .../BBj.jar ./bbj-assets/BBj.jar")
     with: stage ALL version jars side-by-side in the asset folder using the exact filenames the
     combos reference (e.g. BBj-26.01.jar, BBj-25.12.jar); then
     `cp templates/bbj-services/combinations.example.json ./bbj-assets/combinations.json` and edit
     it — list only VALID (BBj version + JDK) combos. Note the dropdown lists exactly these combos
     and JDK is chosen by the combo (no separate JDK picker).
  2. Add combinations.json to the "ship the template's own files" list / the Architecture ASCII tree
     (the /mnt/bbj-assets contents block) alongside BBj*.jar, certificate.bls, Dockerfile,
     playback.properties — show `combinations.json` and multiple `BBj-<ver>.jar` files, and add
     `combinations.example.json` under the templates/bbj-services/ tree.
  3. Step 5 (create a workspace): replace "Choose a JDK at creation time (Adoptium 21 default)"
     with "Choose a BBj stack (combo) from the dropdown — the JDK is derived from it."
  4. Add a subsection documenting `scripts/bbj-build-combos.sh`: it pre-warms one image per combo
     (`./scripts/bbj-build-combos.sh`), reads the SAME combinations.json the template reads (never
     drifts), warms the BuildKit layer cache so on-demand in-template builds become near-instant
     cache hits; and note on-demand build remains the always-works fallback (first user of an
     un-warmed combo waits for the build). State it requires jq and real jars, and cannot run in
     this repo (operator live step).
  5. Keep the three existing FLAGS. Update FLAG-02: JDK-25 risk is now enforced by curation (the
     operator only lists combos whose BBj version supports the paired JDK), so an unsupported
     pairing is not selectable — reframe accordingly rather than deleting the flag. Update FLAG-03
     mentions of "change the JDK selection" to "select a different BBj stack combo".
  6. Update the "Live verification (operator step)" section to reference the combo image build and,
     optionally, running bbj-build-combos.sh to pre-warm — keep the 8888 E2E as the operator step.

In `.env.example` (view via `git show HEAD:.env.example`, then Edit — do NOT overwrite the file):
  - In the existing `## BBjServices template` section, extend the BBJ_ASSETS_PATH comment to note
    the folder now ALSO holds `combinations.json` (copied from combinations.example.json) and
    MULTIPLE version jars (one per combo), not a single BBj.jar. Do NOT add new variables — the
    build script reuses BBJ_ASSETS_PATH and BBJ_LICENSE_SERVER already defined there.
  Use the Edit tool for the scoped comment change; never Write the whole file.
  </action>
  <verify>
    <automated>grep -q 'combinations.json' templates/bbj-services/README.md && grep -q 'bbj-build-combos.sh' templates/bbj-services/README.md && git show HEAD:.env.example | grep -q 'BBJ_ASSETS_PATH' && grep -q 'combinations.json' .env.example</automated>
  </verify>
  <done>
README documents staging multiple jars + copying combinations.example.json to combinations.json,
the combo dropdown, the bbj-build-combos.sh pre-warm step, and the on-demand fallback; FLAG-02/03
reframed for curation; .env.example BBJ_ASSETS_PATH comment mentions combinations.json + multiple jars.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| operator asset folder → Docker build | combinations.json + jar filenames are operator-controlled; jsondecode/build-arg values cross into the image build |
| this repo → committed files | no secrets may enter tracked files (combinations.example.json + README only) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-mlt-01 | Tampering | jsondecode(file(combinations.json)) | mitigate | wrap in try(..., local.default_combinations) so a missing/malformed file cannot break plan/validate; file is operator-owned + bind-mounted read-only |
| T-mlt-02 | Information disclosure | committed combinations.example.json / README | mitigate | example uses placeholder jar names only; no license server, no secrets; real combinations.json lives only in the gitignored asset folder |
| T-mlt-03 | Denial of service | bbj-build-combos.sh loop | accept | script is operator-run on their own host; fail-fast on missing jar + non-zero exit prevents silent partial pre-warm |
| T-mlt-SC | Tampering | package installs | accept | no new npm/pip/cargo installs introduced by this task; requires only `jq` (system package, operator-provided) |
</threat_model>

<verification>
Static (runs in THIS repo — mandatory gate, "infra needs a live deploy gate" lesson):
- `cd templates/bbj-services && terraform init -backend=false && terraform validate && terraform fmt -check` — MUST pass with NO combinations.json present (try() fallback to local.default_combinations).
- `! grep -nE 'coder_parameter\.jdk' templates/bbj-services/main.tf` — no dangling jdk-param reference.
- `bash -n scripts/bbj-build-combos.sh`; `shellcheck scripts/bbj-build-combos.sh` if installed.
- `templates/bbj-services/combinations.example.json` parses as valid JSON.

Live (operator step — CANNOT run here; document in SUMMARY, unchanged from m12):
- Full per-combo image build (real jars + certificate.bls + reachable BLS) and port-8888 E2E per
  combo. Optionally run `scripts/bbj-build-combos.sh` to pre-warm all combos first.
</verification>

<success_criteria>
- Single `bbj_stack` dropdown replaces the jdk parameter; JDK derived from the selected combo.
- combinations.json read via try(jsondecode(file(...)), local.default_combinations); validate passes with no file present.
- Every former jdk-param reference migrated to combo-derived values; zero dangling references.
- Dockerfile ADDs the jar via BBJ_JAR_NAME build arg (named, not glob).
- combinations.example.json committed; bbj-build-combos.sh committed, executable, non-interactive, meaningful exit codes.
- README + .env.example note updated for the multi-jar + combinations.json workflow; both build paths documented.
- Provider pins + Coder image reference unchanged; no secrets in tracked files.
</success_criteria>

<output>
Create `.planning/quick/260713-mlt-add-bbj-stack-combo-selector-to-bbj-serv/260713-mlt-SUMMARY.md` when done.
In the SUMMARY, explicitly record that the full per-combo image build + 8888 E2E is the operator's
live-deploy step (no real jars / BLS in this repo) and that bbj-build-combos.sh was verified only by
`bash -n` (+ shellcheck), not run end-to-end.
</output>
