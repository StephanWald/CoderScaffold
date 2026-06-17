# Project Research Summary

**Project:** Coder Production Scaffold — v1.1 Portable Claude Code Setup
**Domain:** Docker Compose / Terraform Coder workspace template
**Researched:** 2026-06-17
**Confidence:** HIGH (stack, features, pitfalls); MEDIUM (one open architecture decision)

## Executive Summary

V1.1 adds portable Claude Code configuration to the existing Coder Docker workspace template. The goal is that a user authenticates with Claude Code once and finds their credentials, global settings, personal skills, and user-scoped MCP servers available in every subsequent workspace — including newly created ones — without re-authenticating. The implementation is confined entirely to `templates/docker/main.tf` and the README operator runbook; no changes to `compose.yaml` or backup scripts are required.

The recommended approach uses three coordinated elements: (1) a per-owner Docker named volume keyed on the immutable owner UUID (`data.coder_workspace_owner.me.id`), (2) a startup-script block that runs before any module to establish correct ownership and create the symlink/directory structure that routes Claude Code's two config roots (`~/.claude/` directory and `~/.claude.json` file) into the shared volume, and (3) the `coder/claude-code` registry module at `5.2.0` to install the CLI and inject environment variables. The devcontainer in this repo already proves the core pattern (named volume at `~/.claude`); v1.1 extends it with per-owner isolation and a solution for the `~/.claude.json` problem the devcontainer leaves unresolved.

The primary risk is a confirmed upstream concurrency issue: Claude Code performs uncoordinated read-modify-write operations on `~/.claude.json` and `~/.claude/.credentials.json`. When two of the same owner's workspaces run simultaneously, the last writer silently wins and can corrupt JSON or clobber a just-refreshed OAuth token. There is no upstream fix. The mitigation for v1.1 is documentation ("one active workspace per owner at a time"); a flock-guard enhancement is deferred to v2. A second, more fundamental risk is an unresolved technical disagreement in the research about *how* to get `~/.claude.json` onto the shared volume — see the Open Decision below.

---

## OPEN DECISION: How to Share ~/.claude.json

**This is the most important unresolved question in the research. It must be decided before implementation begins.**

### The Problem

Claude Code's config spans two roots:
- `~/.claude/` — a directory (credentials, settings, skills, agents, session memory)
- `~/.claude.json` — a JSON file at `$HOME` root (OAuth session state, MCP servers, onboarding flags)

Docker named volumes always mount as **directories**. Mounting a named volume at `/home/coder/.claude.json` causes Docker to create a directory at that path, which Claude Code cannot parse. Both config roots must land on the shared volume — the question is how.

### Option A: CLAUDE_CONFIG_DIR (recommended by STACK.md and PITFALLS.md)

Set `CLAUDE_CONFIG_DIR=/home/coder/.claude` in `coder_agent.env`. Mount the per-owner volume at `/home/coder/.claude`. When this variable is set, Claude Code writes its global config file inside the directory rather than at `~/.claude.json`, colocating everything under one volume mount.

**Evidence for:**
- Community-confirmed workaround (GitHub issue #14313, #3833): `export CLAUDE_CONFIG_DIR=~/.claude` causes `claude.json` to be written inside the directory
- Claude Code auth docs document the variable for credential relocation
- Simpler implementation: one volume mount, no symlinks, no startup-script complexity
- Devcontainer community pattern (Medium article, devcontainer field notes)

**Evidence against:**
- `CLAUDE_CONFIG_DIR` is not listed in the official Claude Code env-var docs
- GitHub issue #25762 (enhancement request to make it work fully) is open with no activity
- Related bug #3833 was closed "not planned" — partial implementation, no guarantee
- Known to have edge-case failures with IDE integration (issue #4739; irrelevant for terminal CLI use)
- ARCHITECTURE.md explicitly investigated and concluded: "Do not rely on it."

### Option B: Neutral Mount Point + Startup-Script Symlinks (recommended by ARCHITECTURE.md)

Mount the per-owner volume at `/home/coder/.claude-shared` (a neutral path). In `coder_agent.startup_script`, before the `claude-code` module runs, create:
- `mkdir -p ~/.claude-shared/dot-claude`
- `ln -sfn ~/.claude-shared/dot-claude ~/.claude`
- `ln -sf ~/.claude-shared/dot-claude.json ~/.claude.json`

Both canonical Claude Code paths (`~/.claude` and `~/.claude.json`) resolve through symlinks into the shared volume.

**Evidence for:**
- No dependency on undocumented behavior — works with Claude Code's documented, stable config locations
- POSIX symlink semantics are reliable; Claude Code follows symlinks normally
- ARCHITECTURE.md investigated CLAUDE_CONFIG_DIR specifically and found it unreliable
- Anti-pattern 5 in ARCHITECTURE.md explicitly warns against CLAUDE_CONFIG_DIR
- Startup-script ordering (runs before module) prevents the module from writing `~/.claude.json` to the wrong location

**Evidence against:**
- Adds startup-script complexity (5-6 extra lines vs. one env var)
- Symlinks must be idempotent and ordered correctly relative to module execution
- If Claude Code ever does not follow symlinks in a particular code path, config writes silently miss the shared volume

### Option C: Lightweight Hybrid (FEATURES.md suggestion)

Mount the volume at `~/.claude` (directory) and add `ln -sf ~/.claude/.claude.json ~/.claude.json` in the startup script. Simpler than full Option B but still requires startup-script symlink logic and does not independently address the empty-volume root-ownership problem.

### Recommendation for Phase Planning

**Default to Option B (symlink approach).** The reasoning: Option A depends on behavior that one researcher specifically investigated and found to be unsupported, with the upstream enhancement request open and the related bug closed as "not planned." The risk of shipping production infrastructure on an undocumented env var is higher than the cost of 5-6 startup-script lines. Option B has no dependency on undocumented behavior and is fully reversible.

However, the phase planner should validate this decision by checking the current state of GitHub issue #25762 and testing `CLAUDE_CONFIG_DIR` in a throwaway workspace before committing to either approach. If testing confirms Option A works reliably with the current Claude Code CLI version, it is architecturally simpler and should be preferred.

---

## Key Findings

### Recommended Stack

The v1.0 stack (Coder v2.33.8, postgres:17, kreuzwerker/docker ~> 4.4, coder/coder ~> 2.18) requires no changes. V1.1 adds one new component.

**Core technologies (new in v1.1):**
- `coder/claude-code` module `5.2.0` — installs Claude Code CLI, injects auth env vars — use v5 (not v4) because Tasks wiring is deferred; v5 is the current maintained release
- Per-owner `docker_volume` — named `coder-<owner-uuid>-claude`, keyed on immutable `data.coder_workspace_owner.me.id`; `prevent_destroy = true`; `ignore_changes = [name]`
- Nested Docker volume mount — volume B at `/home/coder/.claude-shared` overlays volume A at `/home/coder`; standard Linux mount namespace semantics, confirmed working

**Module configuration for v1.1:**

```hcl
module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  install_claude_code = true
  disable_autoupdater = true
  workdir             = "/home/coder"
  # anthropic_api_key left empty -- interactive OAuth first-run login
}
```

### Expected Features

**Must have (table stakes):**
- Claude Code CLI installed in workspace — `coder/claude-code` module handles this
- Auth persists across workspace stop/start — requires shared volume covering `~/.claude/.credentials.json` AND `~/.claude.json`
- Auth shared across all of a user's workspaces — per-owner volume keyed on `owner.id`
- Global settings (permissions, model, CLAUDE.md) carry across workspaces — covered by `~/.claude/settings.json` and `~/.claude/CLAUDE.md` in shared volume
- User-scoped MCP servers available in every workspace — `~/.claude.json` `mcpServers` key must be on shared volume
- Personal skills available everywhere — `~/.claude/skills/` in shared volume
- First-run login prompts once, then auth persists — empty volume, user runs `claude`, OAuth flow, tokens written, persist
- Concurrent-write caveat documented — README operator runbook

**Should have (v1.x, after validation):**
- Zero-touch auth via `CLAUDE_CODE_OAUTH_TOKEN` seeded via Coder secrets — eliminates first-run login prompt entirely
- Module-injected team MCP servers via the `mcp` variable
- `managed_settings` policy enforcement

**Defer (v2+):**
- Coder Tasks integration (`coder_ai_task`)
- In-workspace MCP servers provisioned by the template
- Cross-template portability (Kubernetes, VM templates)
- flock-guard to prevent concurrent Claude Code writes across workspaces

### Architecture Approach

The implementation is a pure `templates/docker/main.tf` modification. One new `docker_volume` resource (per-owner, `prevent_destroy = true`) is added alongside the existing per-workspace home volume. A second `volumes {}` block in `docker_container.workspace` mounts the new volume at a neutral path. The `coder_agent.main.startup_script` is extended with a block that (1) chowns the volume mount point to `coder:coder` on first use, (2) creates the internal directory structure, and (3) establishes symlinks. The `claude-code` module block follows the established `count = start_count` pattern used by `code-server` and `jetbrains-gateway`.

**Major components:**
1. `docker_volume.claude_config_volume` — per-owner persistent store; `prevent_destroy = true`; lifecycle-independent of individual workspace
2. `coder_agent.main startup_script` extension — ownership fix + symlink/directory setup; must run before `claude-code` module
3. `module.claude-code` — CLI install, env var injection, workdir trust bypass

**Build order (Terraform dependency-driven):**
1. `data.coder_workspace_owner.me` (read-only)
2. `coder_agent.main` (always-present, no count)
3. `docker_volume.home_volume` + `docker_volume.claude_config_volume` (no count, created before container)
4. `docker_container.workspace` (count = start_count, mounts both volumes)
5. `module.claude-code` (count = start_count, parallel with code-server and jetbrains-gateway)

### Critical Pitfalls

1. **File-vs-directory mount for `~/.claude.json`** — Docker cannot mount a named volume at a file path; it creates a directory, breaking Claude Code's JSON parsing. Solution: CLAUDE_CONFIG_DIR (Option A) or symlink approach (Option B). Never attempt `container_path = "/home/coder/.claude.json"` directly.

2. **Concurrent write clobbering** — Claude Code performs uncoordinated read-modify-write on `~/.claude.json` and `~/.claude/.credentials.json`. Two simultaneous workspaces for the same owner will corrupt JSON or clobber OAuth tokens. Upstream has no fix (confirmed GitHub #28992, #28847, #56339). Mitigation: document "one active workspace per owner at a time" in the README.

3. **Empty volume owned by root** — A freshly created Docker named volume has root:root ownership. The `coder` user (UID 1000) cannot write to it. Claude login silently fails. Fix: add a `startup_script` step that `chown`s the mount point before the module runs. Must be in `coder_agent.startup_script`, not a module post-install hook.

4. **Volume keyed on owner name (mutable)** — Keying on `data.coder_workspace_owner.me.name` (username) instead of `.id` (UUID) means a Coder admin rename triggers Terraform to destroy and recreate the volume, losing all auth and settings. Always use the UUID. Add the username as a Docker label for readability.

5. **Symlink/startup-script ordering** — The `claude-code` module writes to `~/.claude.json` during workdir trust setup. If symlinks are not in place before the module runs, it writes the real file on the per-workspace home volume rather than the shared volume. The chown + symlink block must appear in `coder_agent.startup_script`, which runs before module install scripts.

6. **Skel shadowing** — If `/etc/skel/.claude/` contains any files, the existing `cp -rT /etc/skel ~` startup step writes them into the shared Claude volume on first use, polluting it with template defaults. Keep `/etc/skel` free of Claude paths.

---

## Implications for Roadmap

V1.1 is a single-phase, focused template extension. The research identifies one pre-implementation decision and no complex sequencing requirements.

### Phase 1: Template Wiring + Operator Documentation

**Rationale:** All work is in one file (`templates/docker/main.tf`) plus the README. No dependencies on external services; no new Coder server features required beyond what v1.0 already uses. The phase is blocked only by the Open Decision on CLAUDE_CONFIG_DIR vs symlinks, which should be resolved at the start of phase planning.

**Delivers:**
- Per-owner `docker_volume.claude_config_volume` with correct lifecycle guards
- Nested volume mount in `docker_container.workspace`
- Extended `coder_agent.startup_script` with ownership fix and config routing (symlinks or CLAUDE_CONFIG_DIR)
- `module.claude-code` wired at `5.2.0`
- README operator runbook section covering: first-run login UX, concurrent-workspace caveat, volume naming, manual volume cleanup procedure

**Addresses (from FEATURES.md):** All P1 table stakes — install, auth persistence, cross-workspace auth sharing, settings/skills sharing, first-run OAuth flow, `~/.claude.json` persistence, concurrent-write caveat documentation

**Avoids (from PITFALLS.md):** All 8 identified pitfalls — file-vs-directory mount, root ownership, name keying, ordering, skel shadowing, concurrent writes, credential location split, module version

**Must resolve before coding:**
- Open Decision: CLAUDE_CONFIG_DIR vs symlinks — test empirically in a throwaway workspace or accept architectural recommendation (symlinks)
- Audit current `/etc/skel` contents in `codercom/enterprise-base:ubuntu` for Claude paths
- Confirm `coder/claude-code 5.2.0` module's `~/.claude.json` write is idempotent on a pre-populated shared volume (read `install.sh.tftpl` in the registry)

### Phase Ordering Rationale

There is only one logical phase because:
- All changes are in one file with no external integrations
- Every pitfall is a "must be correct from the first commit" constraint; there is no safe incremental rollout of a broken volume design
- The README runbook must ship with the template change, not after it — users will hit the concurrent-write issue on day one without documentation

### Research Flags

**Phase 1 needs targeted validation before coding:**
- Resolve Open Decision (CLAUDE_CONFIG_DIR reliability) — check issue #25762 current status, test empirically
- Confirm `claude-code` module 5.2.0 startup behavior is idempotent when `~/.claude.json` already exists on the shared volume (FEATURES.md identified this as a conflict risk)
- Verify `ln -sfn` behavior when `~/.claude` already exists as a directory on the home volume (edge case on volume lifecycle transitions)

**Standard patterns (no additional research needed):**
- Per-owner volume keying on UUID — established pattern, all four researchers agree
- `prevent_destroy = true` lifecycle guard — well-documented Coder pattern
- Nested Docker volume mounts — confirmed working via Linux mount namespace semantics
- `module.claude-code` variable wiring — module source fully read, variables documented

---

## Points of Agreement Across All Researchers

Despite the Open Decision, all four research files agree on:

1. **Volume key:** `data.coder_workspace_owner.me.id` (UUID, immutable) — not `.name`
2. **Volume lifecycle:** `ignore_changes = [name]` + `prevent_destroy = true`
3. **Module version:** `coder/claude-code 5.2.0` — v5 is correct for install+auth; v4 is only needed for `coder_ai_task` module wiring (deferred)
4. **Root ownership fix:** Empty volume starts root-owned; `startup_script` must `chown` before Claude runs
5. **Concurrent-write caveat:** Known, unfixed upstream issue; document as "one active workspace per owner" in README
6. **Scope:** Changes confined to `templates/docker/main.tf` + README; `compose.yaml` unchanged
7. **Auth method:** Interactive OAuth first-run login; no operator-seeded API key required for v1.1

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Module source read directly; provider versions confirmed via GitHub API; version compatibility matrix validated |
| Features | HIGH | Official Claude Code docs for file paths and auth; first-party module source for behavior; GitHub issue tracking for gaps |
| Architecture | HIGH (with caveat) | All patterns confirmed except the Open Decision; symlink approach has no dependency on undocumented behavior and is architecturally sound |
| Pitfalls | HIGH | Concurrent-write issues confirmed via multiple GitHub issues; Docker volume semantics are well-established |

**Overall confidence:** HIGH for implementation, MEDIUM for the Open Decision specifically.

### Gaps to Address

- **CLAUDE_CONFIG_DIR reliability:** The two most implementation-specific researchers (STACK.md and PITFALLS.md) recommend it; the architect (ARCHITECTURE.md) specifically investigated and rejected it. Must be resolved empirically before coding. Safest default: symlink approach; switch to CLAUDE_CONFIG_DIR if testing proves it reliable.
- **Module idempotency on pre-populated volume:** FEATURES.md flags a risk that the `claude-code` module's `jq`-based patch to `~/.claude.json` may conflict with existing user config. Verify the module guards this write by reading `install.sh.tftpl` in the registry source during phase planning.
- **devcontainer gap:** The current `.devcontainer/devcontainer.json` mounts only `/home/node/.claude` (directory) and does not persist `/home/node/.claude.json`. This is a known gap, out of v1.1 scope, but should be noted in the README so users are not confused by different behavior between devcontainer and Coder workspace.

---

## Sources

### Primary (HIGH confidence)
- `github.com/coder/registry` — `registry/coder/modules/claude-code/main.tf` and `install.sh.tftpl` — module variables, install behavior, `~/.claude.json` writes
- `code.claude.com/docs/en/authentication` — credential storage on Linux, `CLAUDE_CONFIG_DIR` for credentials, OAuth flow
- `code.claude.com/docs/en/claude-directory` — authoritative file tree for `~/.claude/` and `~/.claude.json`
- `code.claude.com/docs/en/settings` — settings file taxonomy, MCP server scope
- `code.claude.com/docs/en/env-vars` — official env var list (no `CLAUDE_CONFIG_DIR` listed)
- `github.com/coder/terraform-provider-coder` docs — `workspace_owner` data source; `id` is UUID (immutable)
- `.devcontainer/devcontainer.json` (this repo) — confirms named volume at `~/.claude` (directory) works in practice
- `templates/docker/main.tf` (this repo) — existing `ignore_changes`, skel-seeding pattern, `owner.id` data source
- GitHub issues #28992, #28847, #56339 (anthropics/claude-code) — concurrent-write corruption confirmed
- `github.com/coder/coder` discussions #7610 — per-owner `prevent_destroy` volume pattern

### Secondary (MEDIUM confidence)
- GitHub issue #25762 (anthropics/claude-code) — `CLAUDE_CONFIG_DIR` enhancement, open, no activity
- GitHub issue #3833 (anthropics/claude-code) — `CLAUDE_CONFIG_DIR` bug, closed "not planned"
- GitHub issue #14313 (anthropics/claude-code) — `CLAUDE_CONFIG_DIR=~/.claude` workaround confirmed
- GitHub issue #24479 (anthropics/claude-code) — `~/.claude.json` move enhancement, open, no implementation
- Medium: "Using Claude Code Safely with Dev Containers" — `CLAUDE_CONFIG_DIR` + volume pattern
- Docker Forums / Taesun Lee (Medium) — nested Docker volume mount behavior confirmed

---
*Research completed: 2026-06-17*
*Ready for roadmap: yes*
