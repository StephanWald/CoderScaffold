---
phase: quick-260818-myg
plan: "01"
subsystem: workspace-templates
tags: [templates, code-server, vscode-extensions, claude-code, flutter, python-ai, java-fullstack]
status: complete

key-files:
  modified:
    - templates/bbj-services/main.tf
    - templates/coderscaffold/main.tf
    - templates/docker/main.tf
    - templates/java-fullstack/main.tf
    - templates/python-ai/main.tf
    - templates/flutter/main.tf

decisions:
  - "Anthropic.claude-code Open VSX id added to code-server extensions argument in all 6 templates; flutter list order is Dart-Code.dart-code, Dart-Code.flutter, Anthropic.claude-code"
  - "Header resource-map line and inline comment above each code-server block updated to document the pre-installed extension"
  - "No claude-code CLI module blocks were touched; code-server version pin stays 1.5.0"

metrics:
  duration_minutes: 2
  tasks_completed: 2
  commits: 2
  files_modified: 6
  completed_date: "2026-08-18"

actuals:
  tokens: 3000
  tasks: 2
  commits: 2

requirements: [QUICK-260818-myg]
---

# Quick Task 260818-myg: Add Claude Code VS Code extension to all templates — Summary

**One-liner:** Added `Anthropic.claude-code` Open VSX extension to the `code-server` module in all six workspace templates (five gained a new `extensions` line; flutter appended to its existing Dart+Flutter list), with matching header and inline comment updates; `terraform fmt -check` is clean.

## Tasks Completed

| # | Task | Type | Commit | Files |
|---|------|------|--------|-------|
| 1 | Add Anthropic.claude-code extension to all six code-server modules | tracer | e2786c8 | 6 main.tf files |
| 2 | Update header/module comments and run terraform fmt -check | auto | 0b7de48 | 6 main.tf files |

## Changes Made

### Task 1 — Extensions argument

Five templates (bbj-services, coderscaffold, docker, java-fullstack, python-ai) received a new `extensions` argument inserted between `display_name` and `order` in their `module "code-server"` block, with `=` aligned to the surrounding lines' column:

```hcl
  extensions   = ["Anthropic.claude-code"]
```

Flutter already had `extensions = ["Dart-Code.dart-code", "Dart-Code.flutter"]`; the Claude Code id was appended as the third element:

```hcl
  extensions   = ["Dart-Code.dart-code", "Dart-Code.flutter", "Anthropic.claude-code"]
```

### Task 2 — Comment updates

- **Header resource-map lines** (top-of-file `# Resources:` block):
  - bbj-services, java-fullstack: `— browser VS Code` → `— browser VS Code (Claude Code extension pre-installed)`
  - coderscaffold, docker: `— browser VS Code (TPL-02)` → `— browser VS Code (TPL-02, Claude Code extension pre-installed)`
  - python-ai: `— browser VS Code` → `— browser VS Code (Claude Code extension pre-installed)`
  - flutter: `— browser VS Code (Dart + Flutter extensions)` → `— browser VS Code (Dart + Flutter + Claude Code extensions)`

- **Inline comments above `module "code-server"`**:
  - bbj-services, java-fullstack, python-ai: `# Browser VS Code via code-server` → `# Browser VS Code via code-server — pre-installs Anthropic.claude-code extension via extensions argument`
  - coderscaffold, docker: `# Browser VS Code via code-server (TPL-02 / D-05)` → `# Browser VS Code via code-server (TPL-02 / D-05) — pre-installs Anthropic.claude-code extension via extensions argument`
  - flutter: Multi-line [LIVE-VERIFY] comment extended to include `Anthropic.claude-code` in the list of extension ids to confirm at push time.

## Verification

- `grep -rc 'Anthropic.claude-code' templates/*/main.tf | grep -v ':0$' | wc -l` → 6 (all six templates, verified live)
- flutter `extensions` list: `["Dart-Code.dart-code", "Dart-Code.flutter", "Anthropic.claude-code"]` (verified live)
- `terraform fmt -check -recursive templates/` exits 0 — FMT-CLEAN (verified live)
- No `module "claude-code"` block was modified (confirmed via `git diff` — no changes in CLI module blocks)

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] templates/bbj-services/main.tf — modified, committed e2786c8 + 0b7de48
- [x] templates/coderscaffold/main.tf — modified, committed e2786c8 + 0b7de48
- [x] templates/docker/main.tf — modified, committed e2786c8 + 0b7de48
- [x] templates/java-fullstack/main.tf — modified, committed e2786c8 + 0b7de48
- [x] templates/python-ai/main.tf — modified, committed e2786c8 + 0b7de48
- [x] templates/flutter/main.tf — modified, committed e2786c8 + 0b7de48
- [x] Commits e2786c8 and 0b7de48 exist in git log
- [x] terraform fmt -check clean

## Known Stubs

None. The `extensions` argument is wired directly; extension installation occurs at workspace start via code-server (no stubs, no placeholder data).

## Threat Flags

None. This change adds Open VSX extension ids to an argument consumed entirely by the code-server Coder registry module. No new network endpoints, auth paths, file access patterns, or schema changes introduced.
