---
phase: quick-260820-r9b
plan: 01
status: complete
date: 2026-08-20
commits:
  - f3d45f6
  - 5dc8dc7
  - 46e026f
files_modified:
  - templates/java-fullstack/Dockerfile
  - templates/python-ai/Dockerfile
  - templates/bbj-services/Dockerfile
  - templates/java-fullstack/main.tf
  - templates/python-ai/main.tf
  - templates/bbj-services/main.tf
---

# Summary — Playwright MCP browser-testing in three workspace templates

Gives Claude Code inside the `java-fullstack`, `python-ai`, and `bbj-services`
workspaces a self-serve browser-testing loop: a registered Playwright MCP server
backed by a real chromium baked into the image. Resolves the "No Playwright MCP
in this container" gap.

## What changed

**Task 1 — chromium baked into the 3 Dockerfiles (`f3d45f6`)**
A `RUN npx -y playwright@latest install --with-deps chromium` layer added after
each image's Node.js LTS layer (in the root-owned region; for the multi-stage
`bbj-services` image, in the final runtime stage that inherits Node from `base`).
`--with-deps` pulls the OS shared libs (libnss3, libatk, …) chromium needs to
launch headless.

**Task 2 — Playwright MCP registered in the 3 startup_scripts (`5dc8dc7`)**
A node-merge block added immediately after the existing webforJ block in each
`main.tf`, registering `cfg.mcpServers.playwright = { command: "npx", args:
["-y", "@playwright/mcp@latest"] }` into the shared `$CLAUDE_SHARED/dot-claude.json`.
Mirrors the existing pattern exactly: `command -v node` guard, idempotent
re-assert on every start, WR-03 warn-and-continue, heredoc-correct `$`-escaping.

**Fix — PLAYWRIGHT_BROWSERS_PATH (`46e026f`, orchestrator-applied)**
Verification surfaced a deploy-blocking defect the static plan missed: the install
layer runs as **root**, so chromium landed in `/root/.cache/ms-playwright` —
invisible to the `coder` user (volume-mounted `$HOME`) that actually runs
`@playwright/mcp` at runtime. Fixed by pinning `ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`
(a world-readable system path inherited by the runtime process) + `chmod -R o+rX`.

## Verification

**Statically verified (in this container):**
- `terraform fmt -check` passed on all 3 `main.tf` — heredoc parses, `$`-escaping intact.
- `docker build` of `python-ai` succeeded end-to-end (chromium + apt deps).
- Post-fix rebuild confirmed: `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright` present in
  image env; chromium binaries at `/ms-playwright/chromium-1234/…`, world-readable;
  `/root/.cache` empty.
- As the **`coder`** user: launched `headless_shell --version` → `Chromium 151.0.7922.34`,
  exit 0 (proves executable bit + OS libs resolve for the non-root runtime user).
- `@playwright/mcp@latest` resolves and runs via `npx`/`npm exec` as `coder`.

**NOT verified (out of scope — requires a live Coder deploy; per `infra-needs-live-deploy-gate`):**
- A booted workspace executing the startup_script MCP registration.
- End-to-end MCP handshake from Claude Code → the Playwright server → chromium.
- `bbj-services` multi-stage build (needs operator-supplied BBj installer assets;
  only its Dockerfile/heredoc were statically checked, not built).

## Known caveats

- **Version drift**: the baked chromium revision matches `playwright@latest` at
  **build** time; a much newer `@playwright/mcp@latest` fetched at runtime could
  expect a different revision and attempt a re-download into `/ms-playwright`
  (not writable by `coder`). Rebuild the image to refresh, or pin both to matching
  versions if this becomes a problem. Documented inline in each Dockerfile.
- **Image size**: chromium + deps adds ~400–500 MB per image.

## Follow-up

To fully close the loop, do a live workspace boot of one template (python-ai) and
confirm Claude Code sees the `playwright` MCP and can drive a page. That is the
only check that exercises the startup_script registration + MCP handshake.
