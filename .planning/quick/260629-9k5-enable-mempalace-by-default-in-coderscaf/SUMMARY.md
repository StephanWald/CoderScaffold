---
gsd_artifact: quick-summary
quick_id: 260629-9k5
slug: enable-mempalace-by-default-in-coderscaf
date: 2026-06-29
status: complete
commits:
  - e459f20  # template wiring (Dockerfiles + main.tf x2)
  - 1b9fd22  # GSD config flip (.planning/config.json)
---

# Quick Task Summary: Enable MemPalace by default in workspace templates

Both the `coderscaffold` and `java-fullstack` workspace templates now bake in
MemPalace: the `mempalace` CLI is installed system-wide in the image, its stdio
MCP server is registered in the shared Claude config on every workspace start,
the palace is initialized for the cloned repo, and GSD's MemPalace capability is
flipped on in the repo config.

## What changed, per file

### `templates/coderscaffold/Dockerfile`
- Added a `# -- MemPalace CLI (Python) --` layer in the `USER root` section,
  immediately before the final `USER coder`. Installs `python3` + `python3-venv`,
  creates a venv at `/opt/mempalace`, `pip install mempalace` into it, and
  symlinks `/opt/mempalace/bin/mempalace` -> `/usr/local/bin/mempalace`. Follows
  the existing `apt-get clean` / `rm -rf /var/lib/apt/lists/*` hygiene. The venv
  lives under `/opt` (outside the `/home/coder` volume that shadows home), so it
  survives every start with no per-boot cost. File still ends with `USER coder`.

### `templates/java-fullstack/Dockerfile`
- Added the same MemPalace `/opt/mempalace` venv layer, placed alongside the
  other system-install layers (after the SSH known-hosts block, before the final
  `USER coder`). Same install/symlink/hygiene pattern. File still ends with
  `USER coder`.

### `templates/coderscaffold/main.tf`
- MCP registration: new block in `coder_agent.main.startup_script` immediately
  after the webforJ MCP block, mirroring it exactly (same `command -v node`
  guard, same `CLAUDE_JSON=... node -e '...'` merge into the shared
  `~/.claude.json`, same WR-03 warn-and-continue). Sets
  `cfg.mcpServers.mempalace = { command: "mempalace", args: ["mcp", "serve"] }`.
- `mempalace init`: new guarded, non-fatal step after the CoderScaffold clone.
  Runs `mempalace init "$HOME/CoderScaffold"` only when the `mempalace` CLI is
  present AND `~/.mempalace` is absent (idempotent); warns and continues on
  failure.

### `templates/java-fullstack/main.tf`
- MCP registration: identical MemPalace MCP block added immediately after the
  webforJ MCP block (it does have a webforJ anchor -- no deviation needed).
- `mempalace init`: new guarded, non-fatal step after the optional `git_repo`
  clone. Runs `mempalace init "$PROJECT_DIR"` where `$PROJECT_DIR` is the existing
  shell var the clone step already uses -- the cloned-repo path when `git_repo`
  was supplied, otherwise `$HOME`. So init is best-effort whether or not a repo
  was cloned, and never aborts the startup_script. Same `command -v mempalace` +
  `~/.mempalace`-absent guard.

### `.planning/config.json`
- Added a top-level `"mempalace"` block (sibling of the existing top-level keys,
  inserted before `"ship"`) with the exact keys/values from PLAN.md Task 4:
  `enabled: true`, `memory_mode: "augment"`, `wing: ""`, `recall_on_discuss: true`,
  `recall_on_plan: true`, `capture_artifacts: true`, `mirror_kg: true`,
  `cross_project_tunnels: false`, `diary_journal: true`. File remains valid JSON.

## Commits

| SHA | Scope |
| --- | --- |
| `e459f20` | Template wiring -- both Dockerfiles + both `main.tf` (Tasks 1-3) |
| `1b9fd22` | GSD MemPalace capability flip -- `.planning/config.json` (Task 4) |

Both committed directly to `main` (this repo's GSD config sets
`quick_branch_template: null`, consistent with prior quick tasks).

## Verification results

- `python3 -c 'import json; json.load(open(".planning/config.json"))'` -> VALID JSON.
- `terraform` is on PATH (v1.15.7). `terraform -chdir=... fmt -check -diff` ->
  exit 0, no diff for both `templates/coderscaffold` and `templates/java-fullstack`
  (no formatting changes needed).
- Both Dockerfiles still end with `USER coder`.
- Both startup_scripts contain a `mcpServers.mempalace` registration and a guarded
  `mempalace init` step (grep-confirmed).
- `git status` confirms only the 5 intended files changed -- no changes to the
  `docker` template, `compose.yaml`, or `.devcontainer/`.

## Deviations from plan

None. java-fullstack had a webforJ MCP block to anchor after, so no fallback
placement was needed.

## Caveats

- The GSD config flip (Task 4) only reaches workspaces after these changes are
  committed AND pushed to the upstream clone repo (`StephanWald/CoderScaffold`),
  since workspaces clone that repo on first start.
- The image-baked CLI + MCP wiring (Tasks 1-3) take effect on the next workspace
  image rebuild, which is forced by the `dockerfile_sha1` trigger in each
  template's `docker_image.triggers` (editing the Dockerfile changes that hash).
- MemPalace data (`~/.mempalace`) lives on the per-workspace home volume -- memory
  persists across stop/start, per-workspace (not per-owner).
