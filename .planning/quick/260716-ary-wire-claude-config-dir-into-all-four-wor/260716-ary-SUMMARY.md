---
phase: quick-260716-ary
plan: 01
subsystem: infra
tags: [terraform, coder, claude-code, gsd, workspace-template]

# Dependency graph
requires:
  - phase: private bbj-ls-dev template (reference, out of repo)
    provides: "Verified CLAUDE_CONFIG_DIR + legacy dot-claude.json migration pattern"
provides:
  - "CLAUDE_CONFIG_DIR env var wired into coder_agent.main for all four public templates"
  - "One-time migration of legacy dot-claude.json into dot-claude/.claude.json, with a symlink kept for backward compatibility"
affects: [gsd-update, claude-code-config, workspace-templates]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLAUDE_CONFIG_DIR points Claude Code / GSD at the physical shared config dir instead of the ~/.claude symlink, avoiding GSD's write-confinement guard"
    - "Legacy dot-claude.json path preserved as a symlink into dot-claude/.claude.json so old references keep working"

key-files:
  created: []
  modified:
    - templates/docker/main.tf
    - templates/coderscaffold/main.tf
    - templates/java-fullstack/main.tf
    - templates/bbj-services/main.tf

key-decisions:
  - "Copied the two additions verbatim from the already-merged private reference implementation (bbj-ls-dev/main.tf) rather than reinventing them, to keep behavior identical across all templates"
  - "Preserved reference alignment style (CLAUDE_CONFIG_DIR gets a single space before '=' since it starts its own blank-line-separated alignment group under terraform fmt)"

patterns-established:
  - "Pattern: CLAUDE_CONFIG_DIR migration block goes after the legacy ln -sf symlink line and before the bypassPermissions comment in startup_script; env var goes immediately after GIT_COMMITTER_EMAIL in coder_agent.main env"

requirements-completed: [QUICK-260716-ary]

# Metrics
duration: 12min
completed: 2026-07-16
---

# Quick Task 260716-ary: Wire CLAUDE_CONFIG_DIR into all four workspace templates Summary

**Mirrored the private bbj-ls-dev reference implementation into all four public templates (docker, coderscaffold, java-fullstack, bbj-services), adding a CLAUDE_CONFIG_DIR env var plus a one-time legacy dot-claude.json migration so GSD >= 1.7.0's write-confinement guard no longer blocks install/update inside workspaces.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-16T05:38:00Z
- **Completed:** 2026-07-16T05:50:58Z
- **Tasks:** 1 completed
- **Files modified:** 4

## Accomplishments
- Added `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"` to `coder_agent.main.env` in all four public templates, right after `GIT_COMMITTER_EMAIL`.
- Added the guarded one-time migration of `dot-claude.json` into `dot-claude/.claude.json` (with an `echo '{}'` fallback) plus the final `ln -sf "dot-claude/.claude.json" "$CLAUDE_SHARED/dot-claude.json"`, placed after the legacy symlink line and before the bypassPermissions block, in all four `startup_script`s.
- Verified via grep that all four required markers (`CLAUDE_CONFIG_DIR` env line, the migration comment header, and the final symlink line) are present in each file, and that each file's diff is exactly two hunks (env addition + startup_script addition) with zero unrelated changes.

## Task Commits

Each task was committed atomically:

1. **Task 1: Mirror the two CLAUDE_CONFIG_DIR additions into all four public templates** - `4fcc693` (feat)

**Plan metadata:** left uncommitted for orchestrator to commit (per constraints)

## Files Created/Modified
- `templates/docker/main.tf` - added CLAUDE_CONFIG_DIR env var + config-dir migration block
- `templates/coderscaffold/main.tf` - added CLAUDE_CONFIG_DIR env var + config-dir migration block
- `templates/java-fullstack/main.tf` - added CLAUDE_CONFIG_DIR env var + config-dir migration block (inserted before JAVA_HOME/MAVEN_HOME, matching reference position)
- `templates/bbj-services/main.tf` - added CLAUDE_CONFIG_DIR env var + config-dir migration block (inserted before JAVA_HOME/MAVEN_HOME, matching reference position)

## Deviations from Plan

None - plan executed exactly as written. The two additions were copied verbatim from `/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf` into all four target files at the exact anchor points specified in the plan.

`terraform fmt`/`terraform validate` were skipped per the execution constraints (terraform not installed on this host); the orchestrator validates formatting/syntax afterward with dockerized terraform. Grep assertions confirm the required markers are present, the diff is exactly two hunks per file, and the env-map alignment matches the reference file's style (CLAUDE_CONFIG_DIR starts its own alignment group after the blank line, so it gets a single space before `=`, consistent with what `terraform fmt` would produce).

## Known Stubs

None.

## Threat Flags

None. This change only adds an environment variable and a config-file migration/symlink step inside the per-owner shared volume already used for Claude Code config in all four templates — no new network endpoints, auth paths, or trust-boundary changes.

## Self-Check: PASSED

- FOUND: templates/docker/main.tf contains `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"`
- FOUND: templates/coderscaffold/main.tf contains `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"`
- FOUND: templates/java-fullstack/main.tf contains `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"`
- FOUND: templates/bbj-services/main.tf contains `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"`
- FOUND: commit 4fcc693 exists in git log
