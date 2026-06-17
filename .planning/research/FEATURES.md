# Feature Research

**Domain:** Portable Claude Code config across Coder workspaces (v1.1 milestone)
**Researched:** 2026-06-17
**Confidence:** HIGH (official Claude Code docs, first-party module source, confirmed GitHub issues)

---

## Config-Location Inventory

The most important output of this research. Every file/directory that must be covered by the shared volume is listed here.

### The Two-Root Problem

Claude Code's config spans **two distinct root locations** that must both be mounted:

| Root | Path | Nature |
|------|------|--------|
| Config directory | `~/.claude/` | Directory — all user-scoped config, skills, commands, session history, auto-memory |
| State file | `~/.claude.json` | Single JSON file at `$HOME` root — auth state, user-scoped MCP servers, UI preferences, onboarding flags |

The devcontainer in this repo mounts only `~/.claude` (the directory) and misses `~/.claude.json`. That gap means MCP servers, OAuth session state, and onboarding flags do NOT persist across workspace rebuilds — the user is prompted to log in again even if credentials are in `~/.claude/.credentials.json`.

### Full Config Surface

#### (a) Auth / Credentials

| Path | What It Holds | Notes |
|------|--------------|-------|
| `~/.claude/.credentials.json` | OAuth access token, refresh token, expiry, scopes | **Linux only** — macOS uses Keychain instead. File mode `0600`. Structure: `{ "claudeAiOauth": { "accessToken": "...", "refreshToken": "...", "expiresAt": <ms>, "scopes": [...] } }` |
| `~/.claude.json` (partial) | `oauthAccount` key, `hasCompletedOnboarding`, `customApiKeyResponses` (approved API key fingerprints) | Without `hasCompletedOnboarding: true` in this file, the CLI re-prompts onboarding even with valid credentials in `.credentials.json` |

Both files are required together for a workspace to wake up already authenticated. Neither alone is sufficient.

#### (b) Global Settings

| Path | What It Holds | Notes |
|------|--------------|-------|
| `~/.claude/settings.json` | Global permissions, allowed/denied tools, hooks, model preference, env vars, outputStyle | Lowest in the settings precedence stack; project `settings.json` overrides it |
| `~/.claude/keybindings.json` | Custom keyboard shortcuts | Optional; only present if user customizes |
| `~/.claude/CLAUDE.md` | Global instructions loaded into every session, every project | Plain markdown; personal conventions and preferences |

#### (c) Skills (and legacy Commands)

| Path | What It Holds | Notes |
|------|--------------|-------|
| `~/.claude/skills/` | Personal skills — each is a subdirectory with `SKILL.md` plus optional supporting files | Invoked as `/skill-name` in any project. Skills supersede commands; new workflows should use skills |
| `~/.claude/commands/` | Legacy single-file commands (markdown) | Still supported but skills are preferred; skills take precedence on name conflict |

Skills and commands in `~/.claude/` are "user-scoped" — available in every project the user opens.

#### (d) User-Scoped MCP Servers

| Path | What It Holds | Notes |
|------|--------------|-------|
| `~/.claude.json` (top-level `mcpServers` key) | User-scoped MCP server definitions — available across all projects | Added by `claude mcp add --scope user` or `claude mcp add-json --scope user`. The `coder/claude-code` module uses `claude mcp add-json --scope user` to write its `mcp` variable here |
| `~/.claude.json` (per-project `projects.<path>.mcpServers`) | Local-scoped MCP servers (project-specific, not committed) | Written by `claude mcp add --scope local` |

**Critical:** There is no separate MCP config file. Both user-scoped and local-scoped MCP servers live inside `~/.claude.json`. Project-scoped (team-shared) MCP servers live in `.mcp.json` at the project root — that is a per-repo file, not in the shared volume.

#### (e) Memory, Projects, History

| Path | What It Holds | Notes |
|------|--------------|-------|
| `~/.claude/projects/` | Auto-memory per project, keyed by encoded project path | Structure: `~/.claude/projects/<encoded-path>/memory/MEMORY.md` + topic files. Claude writes and updates these automatically across sessions |
| `~/.claude/agent-memory/` | Cross-project subagent persistent memory (subagents with `memory: user`) | Only present if user uses subagents with user-scoped memory |

Session history (`.jsonl` transcripts from older Claude Code versions) was historically in `~/.claude/projects/<path>/` but current versions use auto-memory markdown files instead. History is machine-generated and low-value to share — it is workspace-path-encoded, so per-workspace entries diverge naturally.

#### Additional Directories (Present If Used)

| Path | What It Holds |
|------|--------------|
| `~/.claude/themes/` | Custom color theme JSON files |
| `~/.claude/output-styles/` | Custom output-style markdown files |
| `~/.claude/agents/` | Personal subagent definitions available in all projects |
| `~/.claude/workflows/` | Personal dynamic workflow scripts |
| `~/.claude/rules/` | Global rules (markdown, optionally path-gated) loaded in every project |
| `~/.claude/statsig/` | Analytics / feature-flag cache; autogenerated; safe to not persist |

---

## How the coder/claude-code Module Behaves

Source: module Terraform (`main.tf`) + install script (`install.sh.tftpl`), confirmed via Coder Registry.

### What It Installs

- Writes `claude` binary to `$HOME/.local/bin` (skipped if `install_claude_code = false` or binary already in PATH)
- Writes `/etc/claude-code/managed-settings.d/10-coder.json` when `managed_settings` is set — this is a **system-level policy file** with highest precedence, cannot be overridden by user config

### What It Writes to ~/.claude.json

When `workdir` is specified, the module's install script uses `jq` to patch `~/.claude.json`:

```json
{
  "autoUpdaterStatus": "disabled",
  "hasAcknowledgedCostThreshold": true,
  "hasCompletedOnboarding": true,
  "projects": {
    "<workdir>": {
      "hasCompletedProjectOnboarding": true,
      "hasTrustDialogAccepted": true
    }
  }
}
```

**Conflict risk:** If `~/.claude.json` is already populated from the shared volume (user has previously logged in), the module's `jq` patch is a read-modify-write that will merge non-destructively. However, if the volume is brand-new and `~/.claude.json` does not yet exist, the module creates it with the onboarding-bypass structure. This is safe — it is what we want on first run.

### What It Writes for MCP Servers

The module calls `claude mcp add-json --scope user "$server_name" "$server_json"` for each entry in the `mcp` variable. This writes MCP entries into the `mcpServers` top-level key of `~/.claude.json`. If `~/.claude.json` is on the shared volume, these MCP server entries persist and are available in every workspace automatically.

### Authentication the Module Configures

The module does **not** call `claude login` or any interactive auth command. It sets environment variables:

| Variable | When Set | Auth Precedence |
|----------|----------|-----------------|
| `ANTHROPIC_API_KEY` | When `anthropic_api_key` variable provided | #3 in Claude Code auth chain |
| `CLAUDE_CODE_OAUTH_TOKEN` | When `claude_code_oauth_token` variable provided | #5 in Claude Code auth chain |
| `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` | When `enable_ai_gateway = true` | #2 in Claude Code auth chain |

When none of these is set, the module prints a warning: "No authentication configured, skipping onboarding bypass." Claude Code is installed but will require the user to run `/login` manually on first launch.

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Claude Code installed in workspace | Developer expects to type `claude` and have it work | LOW | `coder/claude-code` module handles install via `install_claude_code = true` (default) |
| Auth persists across workspace stop/start | Starting a stopped workspace should not force re-login | MEDIUM | Requires shared volume covering both `~/.claude/.credentials.json` AND `~/.claude.json` |
| Auth shared across all of a user's workspaces | Creating a second workspace should not force re-login | MEDIUM | Per-owner Docker volume; both `~/.claude/` directory AND `~/.claude.json` must be in scope |
| Global settings carry across workspaces | Permissions, preferred model, CLAUDE.md instructions should not need re-configuration | LOW | Covered by sharing `~/.claude/settings.json` and `~/.claude/CLAUDE.md` |
| User-scoped MCP servers available in every workspace | MCP servers configured once should appear in all workspaces | MEDIUM | MCP config lives in `~/.claude.json` `mcpServers` key; must be on shared volume |
| Personal skills available in every workspace | Skills defined once should be invocable in every project | LOW | `~/.claude/skills/` directory; covered by sharing `~/.claude/` |
| First-run login prompts user once, then auth persists | New user should be guided through auth without operator pre-seeding | MEDIUM | Empty volume → workspace starts → user runs `claude` → OAuth flow → tokens written → persist |
| Onboarding bypass on subsequent workspaces | After logging in once, new workspaces should not re-prompt onboarding dialogs | LOW | `hasCompletedOnboarding: true` in `~/.claude.json` persists via shared volume |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Zero-touch auth propagation via `CLAUDE_CODE_OAUTH_TOKEN` | Operator seeds a long-lived token; all user workspaces pre-authenticated, no login prompt ever | MEDIUM | `claude setup-token` generates a 1-year token; operator stores it in Coder secrets; module sets env var. Requires Pro/Max/Team/Enterprise subscription. Token is inference-only, cannot establish remote control sessions |
| Per-owner volume isolation | Each user's Claude config is isolated from other users' configs | LOW | Docker volume named `coder-claude-<owner-id>` pattern; existing `docker_volume` pattern in template |
| Module-injected MCP servers via `mcp` variable | Operator can provision team-standard MCP servers into every workspace without user action | MEDIUM | Module calls `claude mcp add-json --scope user`; persists to shared volume `~/.claude.json` so all workspaces get them |
| Reusable pattern documented for any template | Future templates (Kubernetes, VMs) can follow the same two-mount pattern | LOW | Documentation only; no code complexity |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Share `~/.claude/projects/` auto-memory across workspaces | "I want Claude to remember what it learned in one project across workspaces" | Auto-memory is keyed by encoded project path (`-home-coder-myproject`). Different workspaces have different home volumes with different encoded paths — entries never match. Sharing this directory gives the illusion of shared memory with no actual benefit, while adding unnecessary write volume to the shared mount | Leave `projects/` in the per-workspace home volume; auto-memory works correctly per workspace |
| Share `~/.claude/statsig/` | Avoid re-fetching feature flags | Directory is an analytics/feature-flag cache; stale entries can cause unexpected feature rollout mismatches across Claude Code versions; not meaningful to share | Let it be regenerated per workspace; it rebuilds in seconds |
| Share `.credentials.json` without also sharing `~/.claude.json` | "Credentials are the sensitive part, just copy that" | Without `hasCompletedOnboarding: true` in `~/.claude.json`, the CLI re-runs onboarding on first launch even with valid credentials. Both files are required together | Mount the entire `~/.claude/` directory AND `~/.claude.json` as the shared surface |
| Mount ONLY `~/.claude/` (directory) without `~/.claude.json` (file at home root) | Simpler to mount one path | User-scoped MCP servers, OAuth session state, onboarding flags, and UI preferences all live in `~/.claude.json` outside the directory. Current devcontainer in this repo makes exactly this mistake | Mount `~/.claude/` via volume AND ensure `~/.claude.json` is on the same shared volume |
| Use a single volume for both home and Claude config | "Fewer volumes to manage" | The per-workspace home volume is workspace-scoped (code checkouts, shell history, project files). The Claude config volume is owner-scoped (crosses workspaces). Conflating them means creating a new workspace does not start with the user's existing Claude setup — it starts fresh each time | Two separate volumes with nested mounts: workspace home + owner Claude config overlaid on top |
| Run multiple concurrent workspaces sharing `~/.claude.json` without mitigation | Users sometimes have 2-3 active workspaces simultaneously | `~/.claude.json` has a confirmed race condition (GitHub issues #28992, #28847, #29198, #28829): concurrent Claude Code processes do uncoordinated read-modify-write on the file, producing JSON corruption. The credentials file has a separate race: concurrent token refresh can cascade-invalidate all sessions (issue #56339). These are known-unfixed upstream issues | Document the concurrent-workspace write caveat in the operator README. Recommend users avoid running Claude Code in multiple workspaces simultaneously. Short-term mitigation: serialize writes using the shared volume's Docker filesystem as the consistency boundary |
| Sharing `~/.claude/agent-memory/` unless the user specifically uses cross-project subagents | Pre-emptive sharing | This directory only exists if the user configures subagents with `memory: user`. For most users it is absent. Including it in the shared surface is harmless but not needed | Share the full `~/.claude/` directory which naturally includes it if present |

---

## Feature Dependencies

```
Install Claude Code binary (`coder/claude-code` module)
    └──required by──> First-run login flow
                          └──required by──> Persistent credentials (shared volume)
                                                └──required by──> Cross-workspace auth propagation

Per-owner shared Docker volume
    └──required by──> Persistent credentials
    └──required by──> Persistent MCP servers
    └──required by──> Persistent skills / commands / settings

Nested volume mount (home + Claude config layered)
    └──requires──> Per-workspace home volume (already built in v1.0 template)
    └──requires──> Per-owner Claude config volume (new in v1.1)
```

### Dependency Notes

- **Install before volume**: the module's `install.sh` may try to write to `~/.claude.json`. The volume must be mounted before the module's startup script runs — this is naturally handled by Docker mount ordering (volumes mount before entrypoint).
- **Volume must exist before container starts**: an empty volume causes first-run login; that is the intended v1.1 behavior. The module's onboarding-bypass patch creates `~/.claude.json` with `hasCompletedOnboarding: true` on an empty volume.
- **`~/.claude.json` lives at `$HOME` root, not inside `~/.claude/`**: these are two distinct mount targets. A single volume covering `~/.claude/` does NOT cover `~/.claude.json`. Two separate strategies are possible: (A) mount the owner volume at `$HOME` level (catches both, but conflicts with per-workspace home volume), or (B) symlink `~/.claude.json` into `~/.claude/` on workspace startup and mount only the directory. Strategy (B) is cleaner for nested-mount scenarios.

---

## MVP Definition (v1.1 Scope)

### Launch With

- [x] `coder/claude-code` module wired into `templates/docker/main.tf` — installs Claude Code binary
- [x] Per-owner `docker_volume` for Claude config — named by owner ID, not workspace ID
- [x] Volume mounted to cover `~/.claude/` (directory) in the workspace container
- [x] `~/.claude.json` persistence — via symlink from `~/.claude/.claude.json` → `$HOME/.claude.json` created in startup script, or by mounting the owner volume at a level that covers both paths
- [x] First-run login UX: empty volume → user runs `claude` → OAuth browser/code flow → credentials written → subsequent workspaces skip login
- [x] Module's `workdir` set to `/home/coder` to bypass trust dialog on first project open
- [x] Concurrent-write caveat documented in README operator runbook

### Add After Validation (v1.x)

- [ ] `CLAUDE_CODE_OAUTH_TOKEN` seeded via Coder secrets — eliminates first-run login; requires operator action, optional
- [ ] Module-injected MCP servers via `mcp` variable — for teams wanting standard MCP servers in every workspace
- [ ] `managed_settings` policy file — for team-enforced permissions

### Future Consideration (v2+)

- [ ] Coder Tasks integration (`coder_ai_task`) — deferred per PROJECT.md
- [ ] In-workspace MCP servers — deferred per PROJECT.md
- [ ] Cross-template portability testing (Kubernetes, VM templates) — beyond current Docker-only scope

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Claude Code installed via module | HIGH | LOW | P1 |
| Per-owner volume covering `~/.claude/` + `~/.claude.json` | HIGH | MEDIUM | P1 |
| First-run OAuth login flow in workspace | HIGH | LOW (no code needed; just UX documentation) | P1 |
| `~/.claude.json` symlink to keep both paths on one volume mount | HIGH | LOW (startup script one-liner) | P1 |
| Concurrent-write caveat in README | MEDIUM | LOW | P1 |
| `CLAUDE_CODE_OAUTH_TOKEN` seeding via Coder secrets | MEDIUM | MEDIUM (operator setup) | P2 |
| Module `mcp` variable for team MCP servers | MEDIUM | LOW | P2 |
| `managed_settings` for team policy enforcement | LOW | LOW | P3 |

---

## Template Integration Notes (Dependency on Existing v1.0 Template)

The existing `templates/docker/main.tf` provides:
- `docker_volume.home_volume` keyed on `data.coder_workspace.me.id` (workspace-scoped, correct)
- `docker_container.workspace` with `volumes { container_path = "/home/coder"; volume_name = home_volume.name }`
- `data.coder_workspace_owner.me` data source (provides owner ID for keying the new volume)

For v1.1, the template needs:
1. A new `docker_volume` resource keyed on `data.coder_workspace_owner.me.id` (owner-scoped), with `ignore_changes = [name]` lifecycle
2. A second `volumes {}` block in `docker_container.workspace` mounting the owner volume at `~/.claude` (container path `/home/coder/.claude`)
3. A startup script line creating the `~/.claude.json` symlink: `ln -sf ~/.claude/.claude.json ~/.claude.json` run before any Claude Code commands
4. The `coder/claude-code` module block with `count = data.coder_workspace.me.start_count`, `agent_id = coder_agent.main.id`, `workdir = "/home/coder"`

The module's `count = start_count` pattern (same as code-server and jetbrains-gateway modules) ensures the app only registers when the workspace is running.

---

## Sources

- [Claude Code Authentication docs (official)](https://code.claude.com/docs/en/authentication) — credential storage on Linux (`~/.claude/.credentials.json`), OAuth flow for headless environments, `claude setup-token`, auth precedence chain — HIGH confidence
- [Claude Code .claude directory explorer (official)](https://code.claude.com/docs/en/claude-directory) — authoritative file tree for both `~/.claude/` and `~/.claude.json`, including skills, commands, agents, workflows, rules, output-styles, projects (auto-memory), keybindings — HIGH confidence
- [Claude Code settings docs (official)](https://code.claude.com/docs/en/settings) — `~/.claude/settings.json` vs `~/.claude.json` key taxonomy; MCP server scope distinction — HIGH confidence
- [coder/registry module source `main.tf`](https://raw.githubusercontent.com/coder/registry/refs/heads/main/registry/coder/modules/claude-code/main.tf) — module variables, env vars set, managed-settings path, AI gateway behavior — HIGH confidence
- [coder/registry module install script `install.sh.tftpl`](https://raw.githubusercontent.com/coder/registry/refs/heads/main/registry/coder/modules/claude-code/scripts/install.sh.tftpl) — `~/.claude.json` onboarding-bypass writes, `claude mcp add-json --scope user` MCP injection, no-auth warning — HIGH confidence
- [inventivehq.com Claude Code config guide](https://inventivehq.com/knowledge-base/claude/where-configuration-files-are-stored) — file path inventory corroboration — MEDIUM confidence
- [GitHub issue #56339 — credentials.json token refresh race](https://github.com/anthropics/claude-code/issues/56339) — confirmed concurrent-session token refresh clobber; unresolved — HIGH confidence (primary source)
- [GitHub issue #28992 — claude.json concurrent corruption](https://github.com/anthropics/claude-code/issues/28992) — confirmed JSON corruption from concurrent instances; closed as duplicate — HIGH confidence (primary source)
- [GitHub issue #28847 — race condition claude.json](https://github.com/anthropics/claude-code/issues/28847) — additional concurrent-write corruption evidence — HIGH confidence (primary source)
- [devcontainer field notes issue #10](https://github.com/tfvchow/field-notes-public/issues/10) — both `.credentials.json` AND `.claude.json` required together for persistence; minimal `hasCompletedOnboarding` skeleton — MEDIUM confidence (community notes, consistent with official docs)

---

*Feature research for: Portable Claude Code setup across Coder workspaces*
*Researched: 2026-06-17*
