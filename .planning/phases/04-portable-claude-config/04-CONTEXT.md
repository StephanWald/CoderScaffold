# Phase 4: Portable Claude Config - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire portable Claude Code into the Docker workspace template so a developer authenticates **once** and finds their credentials, settings, skills, and user-scoped MCP servers waiting in **every** subsequent workspace — including newly created ones. Delivered entirely as modifications to `templates/docker/main.tf` (per-owner shared Docker volume + neutral-mount symlinks + `claude-code` module) plus a README operator runbook.

**In scope:** CLAUDE-01 (claude-code module v5.2.0), CLAUDE-02 (per-owner volume keyed on owner UUID, `prevent_destroy`, `ignore_changes=[name]`), CLAUDE-03 (full config surface — `~/.claude/` + `~/.claude.json` — on the shared volume), CLAUDE-04 (volume writable by `coder` user, ownership resolved in `startup_script`), CLAUDE-05 (empty-volume first-run login, no API key required by default), CLAUDE-06 (reusable drop-in snippet), CLAUDE-07 (README operator runbook).

**Out of scope (deferred — see REQUIREMENTS §Future / §Out of Scope):** API-key (`ANTHROPIC_API_KEY`) auth as the default (AI-04); Coder Tasks / `coder_ai_task` wiring (AI-01); `coder exp mcp` server + in-workspace MCP provisioning (AI-02/AI-03 — v1.1 shares the user's *existing* MCP config, provisions none); concurrent multi-workspace write coordination / `flock` (documented caveat, not engineered); operator pre-seeding the volume from a host `~/.claude` (empty-volume + first-run login is the chosen model); fixing the repo's own `.devcontainer/devcontainer.json` `~/.claude.json` gap (noted, not corrected this milestone).

</domain>

<decisions>
## Implementation Decisions

### File-vs-directory mount architecture (CLAUDE-02, CLAUDE-03)
- **D-01:** **Lock the neutral-mount + symlink approach** recommended by `ARCHITECTURE.md` (HIGH confidence). Mount the per-owner volume at a neutral path `/home/coder/.claude-shared`; the `coder_agent.main.startup_script` creates `dot-claude/` (dir) and `dot-claude.json` (file) inside it, then symlinks `~/.claude → .claude-shared/dot-claude` and `~/.claude.json → .claude-shared/dot-claude.json`. One volume carries the complete config surface. **No empirical CLAUDE_CONFIG_DIR spike** — that env var is undocumented, requested-but-unimplemented (issue #25762), and a related bug was closed "not planned" (issue #3833). Resolves the roadmap's flagged open architecture decision.
- **D-02:** Symlink/ownership logic lives in **`coder_agent.main.startup_script`** (NOT a module `post_install_script`), so it runs before the `claude-code` module ever writes `~/.claude.json`. All steps idempotent: `stat`-guarded `chown` (volume starts root-owned when empty; passwordless sudo on `codercom/enterprise-base:ubuntu`), `mkdir -p`, `ln -sfn` / `ln -sf`, and `echo '{}' >` only when `dot-claude.json` is missing. Appended after the existing `/etc/skel` seed block.

### Per-owner shared volume (CLAUDE-02)
- **D-03:** `docker_volume "claude_config_volume"` named `coder-${data.coder_workspace_owner.me.id}-claude` (owner **UUID**, never username — a rename would orphan the volume). `lifecycle { ignore_changes = [name]; prevent_destroy = true }` so workspace *deletion* does not destroy shared auth/config. Labels: `coder.owner`, `coder.owner_id`, `coder.purpose = claude-config`. Reuses the immutable-UUID-keyed pattern from Phase 3's home volume (D-07), scoped to owner instead of workspace.
- **D-04:** Second `volumes {}` block on `docker_container.workspace` mounts the volume at `/home/coder/.claude-shared`, declared **after** the existing `/home/coder` home-volume block (parent mount before child mount — nested mount layering confirmed via Linux mount-namespace semantics).

### claude-code module (CLAUDE-01)
- **D-05:** Add `module "claude-code"` — `source registry.coder.com/coder/claude-code/coder`, `version = "5.2.0"`, `count = data.coder_workspace.me.start_count`, `agent_id = coder_agent.main.id`, `order = 3` (after VS Code `order=1`, JetBrains `order=2`). Placed alongside the other editor modules.
- **D-06:** **No `claude_code_version` pin** — `install_claude_code = true`, latest CLI fetched on each workspace start. Chosen for always-current CLI; accepts the non-reproducibility/churn trade-off the research flagged. (Contrasts with the repo's pin-everything ethos for server/module/Postgres versions — this is a deliberate exception for the rapidly-moving CLI.)

### API-key auth posture (CLAUDE-05)
- **D-07:** **Keep the `anthropic_api_key` Terraform variable** (`type=string`, `sensitive=true`, **default `""`**) and pass it to the module, as an inert optional escape hatch. With the default empty value nothing shadows the interactive OAuth/subscription login, so empty-volume first-run login (CLAUDE-05) works as intended. API-key auth as a *default* remains out of scope (AI-04); this only leaves the override wired for operators who later opt in.

### Reusable snippet (CLAUDE-06)
- **D-08:** Ship the reusable pattern as an **inline annotated comment block in `templates/docker/main.tf`** — the `# ── [REUSABLE] … [END REUSABLE] ──` block from `ARCHITECTURE.md` (variable + volume resource + the container `volumes{}` and `startup_script` insert instructions + module). Self-contained, copy-pasteable from the working file, no second file to keep in sync. No separate `.md`/`.tf.example` partial.

### Operator runbook (CLAUDE-07)
- **D-09:** **Focused README operator section** covering exactly the four SC-mandated topics — (1) first-run `claude` login walkthrough, (2) what carries across workspaces (auth, settings, personal skills, user-scoped MCP servers), (3) empty-volume seeding behavior, (4) the "one active workspace per owner" concurrent-write caveat (`~/.claude.json` has no file locking; sequential use is safe). Matches the repo's existing concise README style. No extended troubleshooting/operations appendix.
- **D-10:** **Document the manual volume-cleanup step** in that same README section: because `prevent_destroy = true`, deleting a Coder user leaves an orphaned `coder-<owner-uuid>-claude` volume that Terraform never removes — note the manual `docker volume rm` path (and `docker volume ls -f label=coder.purpose=claude-config` to find it). No cleanup script/tooling — consistent with the v1.1 "document the caveat, don't engineer around it" posture (mirrors the concurrent-write decision).

### Claude's Discretion
- Exact `startup_script` shell wording for the chown guard / mkdir / symlink block, as long as it stays idempotent and runs before the `claude-code` module (per D-02).
- Precise placement/heading of the new README operator subsection and the exact prose of the four runbook topics (D-09) and the cleanup note (D-10).
- Whether the `anthropic_api_key` variable carries a short doc comment pointing operators at console.anthropic.com (D-07 detail).
- Exact ordering and label set of the volume `labels {}` blocks within D-03 (UUID keying and the `coder.purpose` label are fixed; cosmetic label additions are open).
- Header-comment update to `main.tf`'s resources list to mention the `claude-code` module and the new volume.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase architecture (authoritative — read first)
- `.planning/research/ARCHITECTURE.md` — **the implementation blueprint.** Neutral-mount + symlink solution, per-owner volume pattern (`prevent_destroy`, UUID keying), `startup_script` block, claude-code module placement, data-flow for first/subsequent/delete-then-recreate, anti-patterns, and the full `[REUSABLE]` drop-in snippet (D-08 copies this). Confidence HIGH.
- `.planning/research/SUMMARY.md`, `.planning/research/FEATURES.md`, `.planning/research/PITFALLS.md`, `.planning/research/STACK.md` — supporting v1.1 research (features surface, pitfalls, stack pins).

### Project planning docs (this repo)
- `.planning/ROADMAP.md` §"Phase 4: Portable Claude Config" — goal, 5 success criteria, and the "Planning consideration" flagging the architecture decision resolved here (D-01).
- `.planning/REQUIREMENTS.md` §"Claude Code Integration" (CLAUDE-01..05) + §"Reusability & Operator Docs" (CLAUDE-06..07) — the locked requirement set; §"Future Requirements" + §"Out of Scope" bound what stays deferred (AI-01..04, QOL-01..03, the concurrent-write/seeding/devcontainer exclusions).
- `.planning/STATE.md` — milestone v1.1 state, velocity context.
- `.planning/milestones/v1.0-phases/03-docker-workspace-template/03-CONTEXT.md` — Phase 3 decisions this phase builds on: bare create-form (D-03), per-workspace home volume keyed on immutable UUID (D-07, the pattern D-03 here reuses), pinned-but-overridable versions, commented-block + README operator pattern (D-08).

### Pinned stack & anti-patterns (authoritative)
- `CLAUDE.md` §"Coder Registry Modules" / §"Version Compatibility Matrix" — `coder/claude-code 5.2.0` (requires Coder server ≥2.12, Terraform ≥1.9); existing pins `coder/coder ~> 2.18`, `kreuzwerker/docker ~> 4.4`, code-server `1.5.0`, jetbrains-gateway `1.2.6`. **Use these exact pins.**
- `CLAUDE.md` §"What NOT to Use" / §"Terraform Workspace Template Structure" / §"Claude Code Module" — module wiring guidance; note the warning that `claude-code` v5 dropped `coder_ai_task` integration (irrelevant here — Tasks are out of scope) and that `ANTHROPIC_API_KEY` is passed via the module/`coder_agent.env`, not as a Coder server env var.

### Existing artifacts to modify / integrate with
- `templates/docker/main.tf` — **the only file modified for the template.** Add the `anthropic_api_key` variable, `docker_volume.claude_config_volume`, the second container `volumes{}` block, the `startup_script` Claude block, the `claude-code` module, and the inline `[REUSABLE]` snippet (D-08). Existing structure: `coder_agent.main` (startup_script already seeds `/etc/skel`), `docker_volume.home_volume`, `docker_container.workspace`, code-server + jetbrains-gateway modules.
- `README.md` (repo root) — add the operator runbook section (D-09, D-10).
- `.devcontainer/devcontainer.json` (this repo) — reference only: confirms a `claude-code-config` named volume mounted at `/home/node/.claude` works but omits `~/.claude.json` (the exact gap D-01's symlink approach closes). **Do not modify** (out of scope).

### External docs (authoritative — verify at research/plan time)
- `registry.coder.com` module `coder/claude-code` (v5.2.0) — inputs (`install_claude_code`, `anthropic_api_key`, `claude_code_version`, `agent_id`, `order`), source, version constraints.
- `code.claude.com/docs/en/claude-directory` — `~/.claude/` structure and `~/.claude.json` purpose (why one is a dir and one is a file).
- GitHub issues anthropics/claude-code #25762 (CLAUDE_CONFIG_DIR enhancement, open), #3833 (closed "not planned"), #24479 (`~/.claude.json` location) — basis for rejecting CLAUDE_CONFIG_DIR (D-01).
- `kreuzwerker/terraform-provider-docker` (`~> 4.4`) — `docker_volume` lifecycle (`prevent_destroy`, `ignore_changes`), nested `volumes{}` mount ordering.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`docker_volume.home_volume` pattern** (`templates/docker/main.tf`): immutable-UUID-keyed name + `lifecycle { ignore_changes = [name] }` + `coder.owner`/`coder.owner_id` labels — the per-owner `claude_config_volume` (D-03) is this same pattern, re-keyed on `owner.id` and hardened with `prevent_destroy`.
- **`coder_agent.main.startup_script`** already has an idempotent `/etc/skel` seed guarded by `~/.init_done`. The Claude config block (D-02) appends to this same script using the same idempotency discipline.
- **Editor-module convention** (`code-server`, `jetbrains-gateway`): `count = start_count`, `agent_id = coder_agent.main.id`, `agent_name = "main"`, `order = N`. The `claude-code` module (D-05) slots in as `order = 3`.

### Established Patterns
- **`coder_agent` has NO `count`** (always present so token/init_script exist when stopped); volumes have NO `count` (survive stop/start); container + modules gate on `count = start_count`. The new volume follows the no-count rule; the module follows the start_count rule.
- **Pinned-but-overridable** versions across the repo (Coder image, modules, Postgres). D-06 is a deliberate *exception* — the Claude CLI is intentionally unpinned (latest-on-start).
- **Operator-resolved host concerns via commented block + README** (Phase 1 `group_add`, Phase 3 D-08). D-10's manual-cleanup note continues this documented-caveat posture.

### Integration Points
- New `volumes{}` block must be declared **after** the existing `/home/coder` block in `docker_container.workspace` (parent-before-child mount ordering — D-04).
- The Claude `startup_script` block must be appended **after** the `/etc/skel` seed and run **before** the `claude-code` module install (guaranteed by living in `coder_agent.startup_script`, not a module hook — D-02).

</code_context>

<specifics>
## Specific Ideas

- Mount layout is fixed by D-01: `/home/coder/.claude-shared/{dot-claude/, dot-claude.json}` with `~/.claude` and `~/.claude.json` as symlinks into it.
- Volume name format is fixed: `coder-${data.coder_workspace_owner.me.id}-claude`, discoverable via `docker volume ls -f label=coder.purpose=claude-config`.
- The `[REUSABLE] … [END REUSABLE]` comment block in `ARCHITECTURE.md` is the canonical text for D-08 — adapt it to the live `main.tf`.

</specifics>

<deferred>
## Deferred Ideas

- **API-key auth as a first-class default** — keeping `anthropic_api_key` wired but inert (D-07) is the only API-key footprint this phase; making it the default auth path is AI-04 (a later milestone).
- **Automated orphaned-volume cleanup script** — considered for D-10, declined in favor of a documented manual `docker volume rm`. Candidate future QOL item if owner-deletion churn becomes real.
- **Pinning `claude_code_version`** — explicitly declined (D-06) for latest-on-start; revisit if CLI churn causes workspace breakage.
- **Fixing the repo's own `.devcontainer/devcontainer.json` `~/.claude.json` gap** — out of scope per REQUIREMENTS; the template's symlink approach is the production fix, the devcontainer is noted only.
- **Coder Tasks (`coder_ai_task`), `coder exp mcp` server, in-workspace MCP provisioning** — AI-01/02/03, separate future milestone. v1.1 shares existing MCP config, provisions none.

</deferred>

---

*Phase: 4-Portable Claude Config*
*Context gathered: 2026-06-17*
