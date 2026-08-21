---
task: 260821-ce8
type: quick-fix
status: complete
date: "2026-08-21"
tags: [mempalace, mcp, templates, fix]
key-files:
  modified:
    - templates/coderscaffold/main.tf
    - templates/java-fullstack/main.tf
    - templates/python-ai/main.tf
    - templates/bbj-services/main.tf
    - templates/flutter/main.tf
decisions:
  - Use absolute path /opt/mempalace/bin/mempalace-mcp with empty args instead of relying on PATH
actuals:
  tokens: 800
  tasks: 1
  commits: 1
---

# Quick Task 260821-ce8: Fix MemPalace MCP Registration in 5 Templates

**One-liner:** Replace invalid `mempalace mcp serve` invocation with the absolute path to the real stdio MCP binary `/opt/mempalace/bin/mempalace-mcp` across all 5 workspace templates.

## What Was Done

Fixed the MemPalace MCP server registration in the `startup_script` node one-liners of all 5 workspace templates. The previous registration used `command: "mempalace", args: ["mcp", "serve"]` which is invalid — `mempalace mcp serve` is not a real subcommand (it only prints setup help). The actual stdio MCP entrypoint is the separate binary `/opt/mempalace/bin/mempalace-mcp` installed into the venv by the Dockerfile but never symlinked onto PATH.

**Files changed (5):**

| File | Line | Change |
|------|------|--------|
| `templates/coderscaffold/main.tf` | 292 | `command: "mempalace", args: ["mcp", "serve"]` → `command: "/opt/mempalace/bin/mempalace-mcp", args: []` |
| `templates/java-fullstack/main.tf` | 334 | same |
| `templates/python-ai/main.tf` | 338 | same |
| `templates/bbj-services/main.tf` | 407 | same |
| `templates/flutter/main.tf` | 311 | same |

## Verification

- New form `command: "/opt/mempalace/bin/mempalace-mcp"` appears exactly 5 times (once per file)
- Old form `command: "mempalace", args: ["mcp", "serve"]` appears 0 times
- `git diff --stat` shows exactly 5 files changed, 5 insertions(+), 5 deletions(-)

## Commit

`517b1ed` — `fix(quick-260821-ce8): register MemPalace MCP via /opt/mempalace/bin/mempalace-mcp in 5 templates`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- All 5 files modified with the correct new form
- Old form absent from all files
- Atomic commit covers exactly the 5 specified files
