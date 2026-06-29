---
gsd_artifact: quick-plan
quick_id: 260629-9k5
slug: enable-mempalace-by-default-in-coderscaf
date: 2026-06-29
---

# Quick Task: Enable MemPalace by default in workspace templates

## Goal

Every Coder workspace provisioned by the `coderscaffold` and `java-fullstack`
templates comes up with **MemPalace** available out of the box: the `mempalace`
CLI installed system-wide, its MCP server registered in the workspace's Claude
Code config, the palace initialized for the cloned repo, and GSD's MemPalace
capability flag flipped on so GSD recall/capture/curator hooks fire.

## Background

MemPalace (https://github.com/MemPalace/mempalace, PyPI `mempalace`) is a
Python 3.9+ local-first memory CLI. It exposes an MCP server via
`mempalace mcp serve`, defaults to a local ChromaDB backend (no API key), and
stores data in `~/.mempalace/`. This mirrors the existing webforJ-MCP + GSD
wiring already present in both templates (precedent: quick task 260619-93j).

**Scope guard:** touch ONLY `templates/coderscaffold/` and
`templates/java-fullstack/` plus the repo-root `.planning/config.json`. Do NOT
modify the `docker` template, `compose.yaml`, or `.devcontainer/`.

## Tasks

### Task 1 — Dockerfile: system-wide `mempalace` install (both templates)

Files: `templates/coderscaffold/Dockerfile`, `templates/java-fullstack/Dockerfile`

In the existing `USER root` section, BEFORE the final `USER coder`, add a
MemPalace install layer. Install into a venv under `/opt` (outside the
`/home/coder` runtime volume that shadows home — both Dockerfiles already
document this rationale; reuse that framing in the comment):

```dockerfile
# ── MemPalace CLI (Python) ───────────────────────────────────────────────────
# Local-first AI memory CLI (https://github.com/MemPalace/mempalace). Installed
# into a venv under /opt — OUTSIDE the /home/coder volume that shadows home at
# runtime — and symlinked onto the system PATH, so it survives every workspace
# start with no per-boot cost. Its MCP server is registered in the agent
# startup_script; data persists under ~/.mempalace on the home volume.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && python3 -m venv /opt/mempalace \
 && /opt/mempalace/bin/pip install --no-cache-dir mempalace \
 && ln -sf /opt/mempalace/bin/mempalace /usr/local/bin/mempalace \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
```

Match each file's existing comment density/heading style. In java-fullstack,
place it alongside the other `/opt` system-install layers.

### Task 2 — startup_script: register MemPalace MCP server (both templates)

Files: `templates/coderscaffold/main.tf`, `templates/java-fullstack/main.tf`

Immediately AFTER the existing webforJ MCP-registration block, add a sibling
block mirroring it exactly (same `command -v node` guard, same
`CLAUDE_JSON=... node -e '...'` pattern, same WR-03 warn-and-continue under
`set -e`). It must set, on the shared `~/.claude.json`:

```js
cfg.mcpServers.mempalace = { command: "mempalace", args: ["mcp", "serve"] };
```

Comment it to explain it registers MemPalace's stdio MCP server so every
workspace for this owner has memory available out of the box; idempotent.

### Task 3 — startup_script: `mempalace init` after repo clone (both templates)

Files: `templates/coderscaffold/main.tf`, `templates/java-fullstack/main.tf`

After the repo-clone step, add an idempotent, non-fatal init step:
- guard on `command -v mempalace` present AND `~/.mempalace` absent
- run `mempalace init "<cloned-repo-path>"` (coderscaffold: `$HOME/CoderScaffold`;
  java-fullstack: the same cloned-repo path that template uses)
- warn-and-continue on failure / missing binary, matching the clone step's style.

Note java-fullstack's clone is governed by an optional `git_repo` parameter — if
the clone is conditional/absent, init against `$HOME` (or the repo path when
present) without failing the script. Keep it best-effort.

### Task 4 — Flip GSD MemPalace capability in repo config

File: `.planning/config.json` (git-tracked → reaches workspace clones)

Add a top-level `mempalace` block:

```json
"mempalace": {
  "enabled": true,
  "memory_mode": "augment",
  "wing": "",
  "recall_on_discuss": true,
  "recall_on_plan": true,
  "capture_artifacts": true,
  "mirror_kg": true,
  "cross_project_tunnels": false,
  "diary_journal": true
}
```

Keep the file valid JSON (insert as a sibling of the existing top-level keys).

## Verification

- `terraform fmt -check` (or `fmt`) clean for both `templates/coderscaffold` and
  `templates/java-fullstack` if terraform is available; otherwise eyeball HCL.
- `python3 -c 'import json,sys; json.load(open(".planning/config.json"))'` parses.
- Both Dockerfiles still end with `USER coder`.
- Both startup_scripts contain a `mcpServers.mempalace` registration and a
  guarded `mempalace init` step.
- No changes outside the two templates + `.planning/config.json`.

## Notes / caveats

- Workspaces pick up the **GSD config flip (Task 4)** only after these changes
  are committed AND pushed to the upstream repo the workspaces clone
  (`StephanWald/CoderScaffold`). The image-baked CLI + MCP wiring (Tasks 1–3)
  take effect on the next workspace image rebuild.
- The image rebuild is triggered by the `dockerfile_sha1` change in each
  template's `docker_image.triggers`, so editing the Dockerfile forces a rebuild.
- MemPalace data (`~/.mempalace`) lives on the per-workspace home volume, so
  memory persists across stop/start (per-workspace, not per-owner).
