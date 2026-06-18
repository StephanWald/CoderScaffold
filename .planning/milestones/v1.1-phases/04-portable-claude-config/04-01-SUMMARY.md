---
phase: 04-portable-claude-config
plan: "01"
subsystem: workspace-template
tags: [claude-code, docker-volume, terraform, portable-config, oauth]
dependency_graph:
  requires: [03-docker-workspace-template]
  provides: [claude_config_volume, claude-code-module, anthropic_api_key-var, startup-script-symlinks]
  affects: [templates/docker/main.tf]
tech_stack:
  added:
    - "registry.coder.com/coder/claude-code/coder 5.2.0"
    - "docker_volume (per-owner, prevent_destroy)"
  patterns:
    - "neutral-mount + symlink approach for Claude config portability"
    - "owner-UUID-keyed volume for cross-workspace persistence"
    - "idempotent startup_script block with stat-guarded chown"
    - "[REUSABLE] inline drop-in comment block"
key_files:
  modified:
    - templates/docker/main.tf
decisions:
  - "Volume name: coder-${data.coder_workspace_owner.me.id}-claude (owner UUID, never username — rename-safe)"
  - "prevent_destroy=true so workspace deletion never destroys shared auth"
  - "Mount at /home/coder/.claude-shared (neutral) with symlinks to ~/.claude and ~/.claude.json"
  - "anthropic_api_key defaults to empty string (OAuth first-run login is the default path)"
  - "CLI version intentionally unpinned (no claude_code_version arg) — latest-on-start"
  - "terraform/tofu not in env — grep assertions served as the authoritative validation gate"
metrics:
  duration: 28min
  completed_date: "2026-06-17"
  tasks: 3
  files_modified: 1
---

# Phase 4 Plan 01: Add Portable Claude Code Config to Docker Template Summary

**One-liner:** Per-owner Docker volume (UUID-keyed, prevent_destroy) mounted at a neutral path with startup_script symlinks wiring ~/.claude and ~/.claude.json, plus the claude-code module v5.2.0 and anthropic_api_key variable — all wrapped in an inline [REUSABLE] drop-in block.

## What Was Built

Modified `templates/docker/main.tf` to make Claude Code config portable across all workspaces for the same Coder owner. A developer authenticates with Claude once; credentials, settings, skills, and user-scoped MCP servers persist on a per-owner shared Docker volume that survives workspace deletion and is reused by every subsequent workspace.

### Artifacts Produced

| Symbol | File | Description |
|--------|------|-------------|
| `variable "anthropic_api_key"` | templates/docker/main.tf | Sensitive string, default `""` — OAuth login is default |
| `resource "docker_volume" "claude_config_volume"` | templates/docker/main.tf | Per-owner volume: `coder-${data.coder_workspace_owner.me.id}-claude` |
| Second `volumes {}` block | templates/docker/main.tf | Mounts at `/home/coder/.claude-shared`, after home mount |
| Claude startup_script block | templates/docker/main.tf | Idempotent: chown, mkdir, echo {}, ln -sfn ~/.claude, ln -sf ~/.claude.json |
| `module "claude-code"` | templates/docker/main.tf | v5.2.0, order=3, install_claude_code=true, anthropic_api_key wired |
| `# ── [REUSABLE] … [END REUSABLE]` | templates/docker/main.tf | Self-contained drop-in snippet with HOW TO USE, OPERATOR NOTES, MOUNT LAYOUT |
| Runtime paths/symlinks | workspace container | `/home/coder/.claude-shared/{dot-claude/,dot-claude.json}`, symlinks `~/.claude` and `~/.claude.json` |

### Volume Name Expression

```
coder-${data.coder_workspace_owner.me.id}-claude
```

Keyed on the owner's immutable UUID (not username) so a username rename never orphans the volume.

### Mount Path

`/home/coder/.claude-shared` — neutral path (not directly under `~/.claude`) to avoid Docker making a directory when a file is expected (anti-pattern 1 avoided).

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: anthropic_api_key + claude_config_volume | 5abfb3c | Variable, volume resource, [REUSABLE] block open, file header update |
| Task 2: Second volumes{} block + startup_script | e6d9423 | Claude-shared mount and idempotent symlink block |
| Task 3: claude-code module + [END REUSABLE] | c216fdc | Module wired, REUSABLE block closed |

## Validation

**Toolchain availability:** `terraform` and `tofu` are not installed in this environment. Per the plan's verification clause, grep assertions served as the authoritative validation gate.

**All grep assertions passed:**
- `variable "anthropic_api_key"` present (×1), with `sensitive = true` and `default = ""`
- `resource "docker_volume" "claude_config_volume"` with `coder_workspace_owner.me.id` in name
- `lifecycle { ignore_changes = [name]; prevent_destroy = true }` present
- `coder.purpose = "claude-config"` label present, no `count` argument on volume
- `container_path = "/home/coder/.claude-shared"` and `volume_name = docker_volume.claude_config_volume.name` in second volumes{} block
- `CLAUDE_SHARED="$HOME/.claude-shared"` in startup_script
- `stat -c '%U'` chown guard present, scoped to `$CLAUDE_SHARED`
- `mkdir -p "$CLAUDE_SHARED/dot-claude"` and `echo '{}'` placeholder guard present
- `ln -sfn` and `ln -sf` symlinks present
- `module "claude-code"` with source `registry.coder.com/coder/claude-code/coder`, version `"5.2.0"`, `install_claude_code = true`, `order = 3`, `anthropic_api_key = var.anthropic_api_key`
- NO `claude_code_version` argument in module block
- NO `agent_name` or `folder` in claude-code module
- `[REUSABLE]` and `[END REUSABLE]` markers both present (×1 each)
- `count = data.coder_workspace.me.start_count` on module

**Note for next operator:** When `terraform` or `tofu` is available, run:
```bash
terraform fmt -check templates/docker/main.tf
terraform -chdir=templates/docker init -backend=false
terraform -chdir=templates/docker validate
```

## Requirements Coverage

| Requirement | Status | How Satisfied |
|-------------|--------|---------------|
| CLAUDE-01 | ✓ | `module "claude-code"` v5.2.0 with `install_claude_code=true` |
| CLAUDE-02 | ✓ | `docker_volume.claude_config_volume` with UUID name, `prevent_destroy`, `ignore_changes=[name]` |
| CLAUDE-03 | ✓ | Full surface: `~/.claude/` via `dot-claude/` symlink + `~/.claude.json` via `dot-claude.json` symlink |
| CLAUDE-04 | ✓ | `startup_script` stat-guarded `chown` grants coder user write access on first start |
| CLAUDE-05 | ✓ | `anthropic_api_key` defaults to `""` — empty volume + OAuth login is the default path |
| CLAUDE-06 | ✓ | Inline `[REUSABLE]…[END REUSABLE]` drop-in comment block with WHAT/HOW TO USE/OPERATOR NOTES/MOUNT LAYOUT |

## Threat Model Mitigations Applied

| Threat ID | Mitigation Applied |
|-----------|-------------------|
| T-04-01 | Volume name keyed on owner UUID — different owner gets distinct volume, no cross-owner mount |
| T-04-02 | `chown` scoped to `$CLAUDE_SHARED` only, stat-guarded (runs at most once) |
| T-04-03 | Home volume `volumes{}` declared before `.claude-shared` child mount |
| T-04-04 | `sensitive = true` on `anthropic_api_key` — Terraform redacts in plan/state output |
| T-04-05 | Accepted — concurrent write caveat documented in [REUSABLE] block OPERATOR NOTES |
| T-04-SC | Module source pinned to `registry.coder.com/coder/claude-code/coder` version `5.2.0` |

## Deviations from Plan

None — plan executed exactly as written.

The only notable judgment call was that the initial verification command used `'sensitive   *= *true'` (with multiple spaces in the regex), which matched correctly because the actual file has `sensitive   = true` aligned with spaces. Verification confirmed all patterns.

## Known Stubs

None. All wiring is functional:
- Volume resource is real (not mocked)
- `anthropic_api_key` is passed through to the module
- `startup_script` symlink block runs on real workspace start
- The `echo '{}'` initialization is intentional bootstrap behavior, not a stub

## Threat Flags

No new security-relevant surface beyond what was planned and mitigated in the threat model above.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| templates/docker/main.tf | FOUND |
| 04-01-SUMMARY.md | FOUND |
| Commit 5abfb3c (Task 1) | FOUND |
| Commit e6d9423 (Task 2) | FOUND |
| Commit c216fdc (Task 3) | FOUND |
| anthropic_api_key variable | FOUND |
| claude_config_volume resource | FOUND |
| .claude-shared mount | FOUND |
| claude-code module | FOUND |
| [END REUSABLE] marker | FOUND |
