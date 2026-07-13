# Quick Task 260713-mlt: BBj stack combo selector - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning
**Builds on:** quick task 260713-m12 (created `templates/bbj-services/`)

<domain>
## Task Boundary

Evolve the existing `templates/bbj-services/` template so the Coder end-user picks, at
workspace-create time, from an ADMIN-CURATED set of prepared **(BBj version + JDK) combinations**
(e.g. "BBj 26.01 · JDK 25", "BBj 25.12 · JDK 21") via a single dropdown — instead of the current
standalone `jdk` parameter + single `BBj*.jar`.

This replaces the multi-template-push idea. ONE template, one selector. The admin lists only
VALID combos, so an unsupported BBj×JDK pairing is impossible to select (kills the JDK-25
compatibility risk).

</domain>

<decisions>
## Implementation Decisions (LOCKED — from user)

### Approach — single template + `bbj_stack` dropdown
- Replace the `jdk` coder_parameter with a `bbj_stack` coder_parameter whose options are the
  curated combos. JDK is DERIVED from the selected combo (no separate JDK picker), so invalid
  pairings cannot be selected.

### Combo source — `combinations.json` in the asset folder
- The curated list lives in a JSON file in the operator's asset folder (var.bbj_context_path,
  mounted at /mnt/bbj-assets), read at plan time via
  `jsondecode(file("${var.bbj_context_path}/combinations.json"))`.
- MUST be wrapped in `try(..., local.default_combinations)` with a small built-in default list,
  so (a) the template stays usable/validatable when the file is absent and (b) `terraform
  validate` in this repo (where /mnt/bbj-assets/combinations.json does NOT exist) still passes.
  The file, when present, is authoritative and overrides the default.
- Ship a version-controlled `combinations.example.json` in the template for operators to copy.

### Build timing — BOTH
- Keep the in-template `docker_image` build (on-demand: first workspace of a combo builds it,
  cached after) as the always-works fallback.
- ALSO ship `scripts/bbj-build-combos.sh` that pre-warms every combo ahead of time by running
  `docker build` per combo against the same context + build args. Because it builds on the SAME
  host Docker daemon with the SAME context/args, it warms the BuildKit layer cache, so the
  subsequent in-template build for that combo is a near-instant cache hit (effectively instant
  workspace start). The script may also tag each image `bbj-services:<combo-id>` for clarity.
  The script and the template read the SAME combinations.json → they never drift.

</decisions>

<specifics>
## Concrete changes

### 1. `templates/bbj-services/main.tf`
- REMOVE the `data "coder_parameter" "jdk"` block (with its oracle-free adoptium-21/25 options).
- ADD locals:
  ```hcl
  locals {
    default_combinations = [
      { id = "bbj-25.12-jdk21", display = "BBj 25.12 · JDK 21 (Adoptium)", jar = "BBj.jar", jdk = "adoptium-21" },
    ]
    bbj_combinations = try(
      jsondecode(file("${var.bbj_context_path}/combinations.json")),
      local.default_combinations,
    )
    combos_by_id = { for c in local.bbj_combinations : c.id => c }
    selected     = local.combos_by_id[data.coder_parameter.bbj_stack.value]
  }
  ```
- ADD `data "coder_parameter" "bbj_stack"` with `default = local.bbj_combinations[0].id`,
  `mutable = false` (foundational; a different combo = a new workspace), and a
  `dynamic "option" { for_each = local.bbj_combinations; content { name = option.value.display; value = option.value.id } }`.
- docker_image: `name = "coder-${data.coder_workspace.me.id}-bbj-${data.coder_parameter.bbj_stack.value}"`;
  build_args `JDK = local.selected.jdk`, `BBJ_JAR_NAME = local.selected.jar`,
  `LICENSE_SERVER = var.bbj_license_server`; triggers include `stack = data.coder_parameter.bbj_stack.value`,
  `jdk = local.selected.jdk`, `bbj_jar_sha1 = try(filesha1("${var.bbj_context_path}/${local.selected.jar}"), "no-jar")`,
  keep the license_server + dockerfile_sha1 triggers.
- Everywhere the OLD `data.coder_parameter.jdk.value` was referenced (image name, triggers,
  agent env, etc.), switch to the combo-derived values. Grep the file for `jdk` and fix ALL refs.
- JAVA_HOME/MAVEN_HOME agent env stay the same (/opt/java/default is fixed regardless of combo).

### 2. `templates/bbj-services/Dockerfile`
- Replace `ADD BBj*.jar /tmp/BBj.jar` with:
  ```dockerfile
  ARG BBJ_JAR_NAME=BBj.jar
  ADD ${BBJ_JAR_NAME} /tmp/BBj.jar
  ```
  (Named source, not a glob — removes the multi-jar ambiguity: the operator stages every
  version jar side-by-side and the combo picks the exact one.)
- Keep the existing `ARG JDK` + adoptium-21/25 install case logic unchanged.

### 3. `templates/bbj-services/combinations.example.json` (new, version-controlled)
- Example the operator copies into the asset folder and edits:
  ```json
  [
    { "id": "bbj-26.01-jdk25", "display": "BBj 26.01 · JDK 25 (Adoptium)", "jar": "BBj-26.01.jar", "jdk": "adoptium-25" },
    { "id": "bbj-25.12-jdk21", "display": "BBj 25.12 · JDK 21 (Adoptium)", "jar": "BBj-25.12.jar", "jdk": "adoptium-21" }
  ]
  ```
  `jdk` must be one of the Dockerfile-supported values (`adoptium-21` | `adoptium-25`); `jar` is
  the filename staged in the asset folder; `id` must be unique and safe for a docker image tag.

### 4. `scripts/bbj-build-combos.sh` (new)
- Non-interactive, meaningful exit codes (CLAUDE.md operability constraint — like the existing
  backup/restore scripts under scripts/).
- Sources `.env` (or reads env) for `BBJ_ASSETS_PATH` (default ./bbj-assets) and
  `BBJ_LICENSE_SERVER`; resolves the combinations.json from `$BBJ_ASSETS_PATH/combinations.json`
  (fall back to combinations.example.json with a warning if absent).
- Requires `jq` (or a documented fallback) to parse the JSON; for each combo run:
  `docker build --build-arg JDK=<jdk> --build-arg BBJ_JAR_NAME=<jar> --build-arg LICENSE_SERVER=$BBJ_LICENSE_SERVER -t bbj-services:<id> "$BBJ_ASSETS_PATH"`
  Also pass `--build-arg BASE_IMAGE` default matching the template if you want parity.
- Exit non-zero if any build fails; print a per-combo pass/fail summary. Verify the referenced
  jar exists in the asset folder before building (fail-fast with a clear message).
- Follow the style/shebang/`set -euo pipefail` conventions of the existing scripts in scripts/
  (read one first).

### 5. `templates/bbj-services/README.md` (update)
- Replace the single-jar instructions with: stage ALL version jars side-by-side in the asset
  folder; copy `combinations.example.json` → `combinations.json` there and edit; the dropdown
  lists those combos; JDK is chosen by the combo.
- Document `scripts/bbj-build-combos.sh` (pre-warm images) AND that on-demand build is the
  fallback (first user of an un-warmed combo waits for the build).
- Keep the three existing FLAGS (subdomain routing, JDK-25 compat now enforced by curation,
  /opt/bbx not persisted).

### 6. `.env.example` (update if needed)
- BBJ_ASSETS_PATH / BBJ_LICENSE_SERVER already added in m12. Add a one-line note that the folder
  now also holds `combinations.json` + multiple version jars. (.env.example is Read-blocked;
  use `git show HEAD:.env.example` to view, then Edit/append.)

</specifics>

<canonical_refs>
## Canonical References
- Existing template from task m12: templates/bbj-services/{Dockerfile,main.tf,README.md,playback.properties}
- Fork origin: templates/java-fullstack/main.tf (the jdk-param + docker_image build pattern being generalized)
- Existing scripts style: scripts/ (backup/restore) — match shebang, set -euo pipefail, exit codes
- Coder `coder_parameter` dynamic "option" blocks + `jsondecode(file())` — must tolerate a missing file via try()

## VERIFICATION GATE (mandatory — "infra needs a live deploy gate" lesson)
- In templates/bbj-services/: `terraform init -backend=false && terraform validate && terraform fmt -check` MUST pass.
  The `try(jsondecode(file(...)), local.default_combinations)` is REQUIRED for validate to pass
  here (the real combinations.json is absent in this repo) — verify validate passes with NO
  combinations.json present.
- `bash -n scripts/bbj-build-combos.sh` (syntax) + `shellcheck` if available; the script cannot
  be run end-to-end here (no real jars / daemon build), so document that in SUMMARY.
- Full image-build + 8888 E2E per combo remains the operator's live-deploy step (real jars +
  certificate.bls + reachable BLS) — call out explicitly, unchanged from m12.
</canonical_refs>
