---
phase: quick-260818-myg
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/bbj-services/main.tf
  - templates/coderscaffold/main.tf
  - templates/docker/main.tf
  - templates/java-fullstack/main.tf
  - templates/python-ai/main.tf
  - templates/flutter/main.tf
autonomous: true
requirements: [QUICK-260818-myg]
estimate:
  tokens: 22000
  raw_tokens: 14000
  tasks: 2
  confidence: high
must_haves:
  truths:
    - "Every workspace template's code-server module installs the Claude Code VS Code extension (Anthropic.claude-code) on workspace start."
    - "flutter's code-server keeps its Dart + Flutter extensions AND adds Anthropic.claude-code."
    - "Each main.tf header comment for the code-server module notes the Claude Code extension is pre-installed."
  artifacts:
    - templates/bbj-services/main.tf
    - templates/coderscaffold/main.tf
    - templates/docker/main.tf
    - templates/java-fullstack/main.tf
    - templates/python-ai/main.tf
    - templates/flutter/main.tf
  key_links:
    - "code-server module extensions argument -> Open VSX id Anthropic.claude-code (browser VS Code extension, distinct from the claude-code CLI module already present)."
---

<objective>
Add the Claude Code VS Code extension (Open VSX id `Anthropic.claude-code`) to every workspace template's browser VS Code (code-server module), so newly started workspaces open with the extension already installed. This is the browser-VS-Code extension only; every template already installs the Claude Code CLI via the separate `claude-code` module — that stays untouched.

Purpose: Give developers the Claude Code editor extension out of the box in code-server, matching the CLI that is already pre-wired.
Output: 6 edited `main.tf` files (5 gain a new `extensions` line; flutter appends to its existing list) plus updated header comments; `terraform fmt -check` clean.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Add Anthropic.claude-code extension to all six code-server modules</name>
  <files>templates/bbj-services/main.tf, templates/coderscaffold/main.tf, templates/docker/main.tf, templates/java-fullstack/main.tf, templates/python-ai/main.tf, templates/flutter/main.tf</files>
  <action>
In each of the five templates WITHOUT an existing extensions argument (bbj-services, coderscaffold, docker, java-fullstack, python-ai), insert a new line into the `module "code-server"` block between the `display_name` line and the `order` line. All five blocks share identical `=` alignment, so the new line is exactly (two leading spaces, `extensions` padded to align the `=`): the argument name `extensions`, three spaces, `=`, one space, then the single-element list containing the id `Anthropic.claude-code`. Match the surrounding lines' column alignment exactly — the `=` for `extensions` lands in the same column as `display_name`/`source`/`agent_id` in that block.

For flutter, which already has an `extensions` line listing the Dart + Flutter ids, append the `Anthropic.claude-code` id as a third element of that existing list (keep the two Dart ids first, add the Claude id last). Do not add a second extensions line.

Do NOT touch any `module "claude-code"` block — that is the CLI module and is orthogonal. Do NOT change the code-server `version` (stays 1.5.0) or any other argument.

The extension id casing is the canonical Open VSX namespace form `Anthropic.claude-code` (verified available on Open VSX, the marketplace code-server installs from) — use that exact casing.
  </action>
  <verify>
    <automated>cd /workspaces/coder && grep -rc 'Anthropic.claude-code' templates/*/main.tf | grep -v ':0$' | wc -l | grep -qx 6 && echo OK-6-templates</automated>
  </verify>
  <done>All six templates' code-server modules reference `Anthropic.claude-code`; flutter's list has all three ids (two Dart + Claude); no `claude-code` CLI module was altered.</done>
</task>

<task type="auto">
  <name>Task 2: Update header/module comments and run terraform fmt -check</name>
  <files>templates/bbj-services/main.tf, templates/coderscaffold/main.tf, templates/docker/main.tf, templates/java-fullstack/main.tf, templates/python-ai/main.tf, templates/flutter/main.tf</files>
  <action>
Update the descriptive comments so they reflect the pre-installed Claude Code extension.

Top-of-file resource map: each main.tf has a header line describing the code-server module (e.g. `#   module code-server        — browser VS Code`, and in flutter/python-ai variants with parenthetical notes). Amend that line to note the Claude Code extension is pre-installed — for the five templates whose line currently reads `browser VS Code` (or `browser VS Code (TPL-02)` / `browser VS Code (TPL-02 / D-05)`), append a parenthetical such as `(Claude Code extension pre-installed)` while preserving any existing tag like `(TPL-02)`. For flutter, whose header already reads `browser VS Code (Dart + Flutter extensions)`, extend the parenthetical to also mention Claude Code (e.g. `(Dart + Flutter + Claude Code extensions)`).

Inline comment directly above the `module "code-server"` block: for the five templates it is a single line (`# Browser VS Code via code-server` possibly with a `(TPL-02 / D-05)` tag) — extend it to note the Claude Code VS Code extension is pre-installed via the extensions argument. For flutter, which already has a multi-line Open VSX comment listing the Dart/Flutter ids and a [LIVE-VERIFY] note, add `Anthropic.claude-code` to that comment's list of pre-installed / to-verify ids so the [LIVE-VERIFY] note covers it too.

Keep comment wording concise and consistent with each file's existing tone; do not restructure unrelated comments.

After editing, run terraform fmt -check across all six template dirs to confirm no formatting drift was introduced. terraform is at /usr/local/bin/terraform. If any file reports as needing formatting, run terraform fmt on it and re-check so the tree is fmt-clean.
  </action>
  <verify>
    <automated>cd /workspaces/coder && terraform fmt -check -recursive templates/ && echo FMT-CLEAN</automated>
  </verify>
  <done>Header resource-map line and the inline comment above the code-server block in all six templates mention the pre-installed Claude Code extension; `terraform fmt -check -recursive templates/` exits 0.</done>
</task>

</tasks>

<verification>
- `grep -rc 'Anthropic.claude-code' templates/*/main.tf` shows a non-zero count for all six templates.
- flutter's code-server extensions list contains all three ids: `Dart-Code.dart-code`, `Dart-Code.flutter`, `Anthropic.claude-code`.
- `terraform fmt -check -recursive templates/` exits 0 (no formatting drift).
- No `module "claude-code"` block was modified (git diff shows changes only in code-server blocks + comments).
</verification>

<success_criteria>
Every workspace template's code-server module pre-installs `Anthropic.claude-code`; flutter retains its Dart/Flutter extensions; comments document the addition; terraform formatting is clean.
</success_criteria>

<output>
Create `.planning/quick/260818-myg-add-claude-code-vs-code-extension-to-all/260818-myg-SUMMARY.md` when done.
</output>
