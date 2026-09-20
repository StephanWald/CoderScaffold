---
phase: quick-260920-osn
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - README.md
autonomous: true
requirements:
  - QUICK-osn
estimate:
  tokens: 22000
  raw_tokens: 12000
  tasks: 1
  confidence: high
must_haves:
  truths:
    - "README documents that BBj installer files go into the bbj-assets/ directory at the repo root"
    - "README documents the exact command to publish templates after staging assets: ./scripts/push-templates.sh"
    - "README explains that re-running the publish script refreshes the bbj_installer dropdown after adding a new jar"
  artifacts:
    - "README.md contains a BBj / BBjServices template subsection under ## Workspace Template"
  key_links:
    - "bbj-assets/ contents (BBj*.jar, certificate.bls, playback.properties) → BBJ_ASSETS_PATH → /mnt/bbj-assets bind mount → jars.json snapshot → bbj_installer dropdown"
---

<objective>
Add a README section documenting how to make BBj install files available to the bbj-services workspace template: place the installer files in the `bbj-assets/` directory, then run the publish-templates script.

Purpose: Operators currently have no documented workflow for the BBj asset → template flow. The mechanics exist in code (compose bind mount, `scripts/push-templates.sh` jars.json generation, `templates/bbj-services/main.tf`) but are undocumented in the README, which only covers docker/java-fullstack/python-ai templates and never mentions BBj.
Output: A new `### BBj / BBjServices template` subsection in README.md.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md

# Verified source of truth for the documented workflow (read before writing):
@compose.yaml
@.env.example
@scripts/push-templates.sh
@templates/bbj-services/main.tf
@README.md
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Add BBj asset publishing section to README</name>
  <files>README.md</files>
  <action>
Insert a new `### BBj / BBjServices template` subsection into README.md under the `## Workspace Template` section, placed immediately AFTER the "Python AI template" subsection (which ends with the line referencing `templates/python-ai/README.md` and the DEFERRED LIVE-VERIFICATION CHECKLIST) and BEFORE the `### Docker Socket Permissions` subsection. Match the existing README voice, heading depth (`###`), and fenced-bash-block style used by the other template subsections.

Document ONLY the real, verified workflow (do not invent options or paths). The section must cover:

1. Purpose: the `templates/bbj-services/` template builds a BBjServices workspace image from operator-supplied BBj installer assets. The build context is the asset folder, bind-mounted read-only into the coder service.

2. Where the files go: the `bbj-assets/` directory at the repo root. This is the default value of `BBJ_ASSETS_PATH` in `.env` (`BBJ_ASSETS_PATH=./bbj-assets`) and is bind-mounted read-only at `/mnt/bbj-assets` inside the coder service (compose.yaml: `${BBJ_ASSETS_PATH:-./bbj-assets}:/mnt/bbj-assets:ro`). Operators may override `BBJ_ASSETS_PATH` in `.env` to point at a different host folder.

3. What files belong in the directory (verified from .env.example and templates/bbj-services/main.tf):
   - one or more BBj installer `*.jar` files (e.g. `BBj-25.12.jar`, `BBj-26.01.jar`) — each becomes a selectable option in the `bbj_installer` dropdown at workspace creation
   - `certificate.bls` — the BBj license certificate
   - `playback.properties`
   The `Dockerfile` is staged into the asset folder automatically by the publish script, so operators do NOT need to copy it manually.

4. The publish command (this is the "PublishTemplates script" the request names): run from the repo root, with the `coder` CLI logged in:
   `./scripts/push-templates.sh`
   Explain what this script does relevant to BBj assets, drawn verbatim in meaning from the script's own comments: it (a) stages `templates/bbj-services/Dockerfile` into the asset folder so the image build context is refreshed, and (b) generates a `jars.json` snapshot (a sorted JSON array of the `*.jar` basenames in the asset folder) into each template dir whose `main.tf` references `jars.json`. The snapshot is what populates the `bbj_installer` dropdown in the Create-Workspace form — Coder >= 2.25 evaluates parameter HCL against the PUSHED TEMPLATE FILES only and cannot read the `/mnt/bbj-assets` bind mount at form-evaluation time, so `fileset()` alone would degrade the parameter to a free-text box.

5. The refresh note: after adding a NEW installer jar to `bbj-assets/`, re-run `./scripts/push-templates.sh` to refresh the `jars.json` snapshot so the new jar appears in the `bbj_installer` dropdown. (Sourced from templates/bbj-services/main.tf line ~218 and the script's jars.json comment block.)

6. A short note that if `BBJ_ASSETS_PATH` is unset/missing or contains no `*.jar` files, the publish script warns and skips jars.json generation without blocking the push (the dropdown falls back to free-text). This is warn-and-continue behavior verified in scripts/push-templates.sh.

Do NOT add `coder templates edit` display-metadata boilerplate unless it is genuinely part of the BBj flow — keep the section focused on the asset → publish workflow the request asks for. You MAY reference `templates/bbj-services/main.tf` for the full parameter set rather than re-documenting every parameter.

Ground every path, variable name, and command against the files read in context — do not paraphrase paths from memory. Verify `bbj-assets` (not `bbj_assets`), `BBJ_ASSETS_PATH`, `/mnt/bbj-assets`, `jars.json`, and `./scripts/push-templates.sh` are spelled exactly as they appear in the source files.
  </action>
  <verify>
    <automated>grep -q 'BBj / BBjServices template' README.md && grep -q 'bbj-assets' README.md && grep -q './scripts/push-templates.sh' README.md && grep -q 'jars.json' README.md && grep -q 'BBJ_ASSETS_PATH' README.md && grep -n '### Docker Socket Permissions' README.md && grep -n '### BBj / BBjServices template' README.md && echo "OK: section present and anchors verified"</automated>
  </verify>
  <done>
README.md contains a `### BBj / BBjServices template` subsection placed after the Python AI template subsection and before `### Docker Socket Permissions`. The section states that BBj installer files (`*.jar` + `certificate.bls` + `playback.properties`) go into `bbj-assets/`, gives `./scripts/push-templates.sh` as the publish command, explains that the script generates the `jars.json` snapshot that populates the `bbj_installer` dropdown, and instructs operators to re-run the script after adding a new jar. All paths and variable names match the source files verbatim.
  </done>
</task>

</tasks>

<verification>
- `grep -n '### BBj / BBjServices template' README.md` returns a line number that is LESS than the line number from `grep -n '### Docker Socket Permissions' README.md` (correct placement order).
- The section references only verified artifacts: `bbj-assets/`, `BBJ_ASSETS_PATH`, `/mnt/bbj-assets`, `jars.json`, `bbj_installer`, `certificate.bls`, `playback.properties`, `./scripts/push-templates.sh`.
- No invented flags, paths, or script names (the request's "PublishTemplates script" maps to the real `scripts/push-templates.sh`).
</verification>

<success_criteria>
An operator reading the new README section can: (1) identify that BBj installer files go into `bbj-assets/`, (2) know which files to place there, (3) run the exact publish command, and (4) understand they must re-run it after adding a new jar to update the workspace-creation dropdown — all without reading the template source.
</success_criteria>

<output>
Update `README.md` in place. No SUMMARY file required for this quick task beyond the standard quick-task commit.
</output>
