---
phase: 04-portable-claude-config
plan: "02"
subsystem: documentation
tags: [readme, claude-code, operator-runbook, portable-config]
dependency_graph:
  requires: [04-01]
  provides: [claude-code-operator-runbook]
  affects: [README.md]
tech_stack:
  added: []
  patterns:
    - "H3 subsection nested inside existing H2 Workspace Template section"
    - "Operator runbook: prose + fenced bash + > **Note:** blockquote"
key_files:
  modified:
    - README.md
decisions:
  - "Volume name cited as coder-<owner-uuid>-claude matching the exact expression from Plan 01"
  - "No API key required by default — OAuth is the documented first-run path"
  - "Concurrent-write caveat documented as > **Note:** blockquote (no engineering fix — documented accept)"
  - "Manual cleanup only — no script, consistent with v1.1 documented-caveat posture"
  - "Devcontainer gap noted in single sentence at end; devcontainer not modified (out of scope)"
metrics:
  duration: 1min
  completed_date: "2026-06-17"
  tasks: 1
  files_modified: 1
---

# Phase 4 Plan 02: README Claude Code Operator Runbook Summary

**One-liner:** Added `### Claude Code` subsection to README Workspace Template section covering first-run OAuth login, the four shared items (auth/settings/skills/MCP servers), per-owner volume seeding, concurrent-write caveat, and manual orphaned-volume cleanup.

## What Was Built

Added a focused operator runbook subsection (`### Claude Code`) to `README.md` inside the `## Workspace Template` section (after `### Home directory persistence`, at line 400). This satisfies CLAUDE-07.

### Artifacts Produced

| Symbol | File | Description |
|--------|------|-------------|
| `### Claude Code` subsection | README.md (line 400) | Operator runbook covering login, sharing, seeding, caveat, cleanup |
| First-run login walkthrough | README.md | `claude` in terminal, OAuth by default, no API key required |
| Shared-surface list | README.md | Auth, settings, personal skills, user-scoped MCP servers |
| Empty-volume seeding explanation | README.md | Volume starts empty; first login writes; subsequent workspaces pre-authenticated |
| Concurrent-write caveat | README.md | `> **Note:**` blockquote: one active workspace per owner; no file locking on `~/.claude.json` |
| Volume cleanup commands | README.md | `docker volume ls -f label=coder.purpose=claude-config` + `docker volume rm` |
| Devcontainer gap note | README.md | Single sentence noting the `.devcontainer` omits `~/.claude.json`; not modified |

### Volume Name Cited

The README references `coder-<owner-uuid>-claude`, matching the exact template expression from Plan 01:

```
coder-${data.coder_workspace_owner.me.id}-claude
```

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: Claude Code operator runbook subsection | 8c68d11 | 51 lines added to README.md |

## Verification

All automated grep assertions from Task 1 passed:

```
grep -q '^### Claude Code' README.md                            # PASS (1 match)
grep -q 'claude' README.md                                      # PASS
grep -q 'label=coder.purpose=claude-config' README.md           # PASS
grep -q 'docker volume rm' README.md                            # PASS
grep -qi 'concurrent\|one active workspace\|simultaneously' README.md  # PASS
grep -qi 'MCP' README.md                                        # PASS
grep -c '^### Claude Code' README.md                            # 1 (PASS)
```

Acceptance criteria confirmed:

- Heading inside `## Workspace Template`, after `### Home directory persistence`
- Mentions `claude` first-run and states no API key required by default
- Lists auth, settings, skills, and MCP servers as shared items
- Explains empty-volume seeding with `coder-<owner-uuid>-claude` volume name
- `> **Note:**` blockquote for concurrent-write caveat
- Both `docker volume ls -f label=coder.purpose=claude-config` and `docker volume rm` present

## Requirements Coverage

| Requirement | Status | How Satisfied |
|-------------|--------|---------------|
| CLAUDE-07 | Done | README `### Claude Code` subsection covering all four SC-mandated topics plus D-10 cleanup |

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. The README section is complete operator documentation — no placeholder text.

## Threat Flags

No new security-relevant surface beyond what was planned and accepted in the threat model:

- T-04D-01 (Tampering via `docker volume rm`): mitigated by pairing with `docker volume ls -f label=coder.purpose=claude-config` discovery command so operators target volumes by label.
- T-04D-02 (Concurrent write / data loss): accepted and documented via `> **Note:**` callout.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| README.md | FOUND |
| `### Claude Code` heading at line 400 | FOUND |
| 04-02-SUMMARY.md | FOUND |
| Commit 8c68d11 (Task 1) | FOUND |
| `label=coder.purpose=claude-config` | FOUND |
| `docker volume rm` | FOUND |
| Concurrent-write caveat | FOUND |
| MCP servers mentioned | FOUND |
