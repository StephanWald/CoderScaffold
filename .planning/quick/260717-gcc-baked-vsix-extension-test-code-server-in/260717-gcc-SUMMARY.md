---
task: 260717-gcc
description: Baked VSIX extension-test code-server instance in bbj-ls-dev (private repo)
date: 2026-07-17
status: complete
repo: /Users/beff/coder-bbj-private
commits:
  - eccb6fc feat(bbj-ls-dev): bake code-server-test + bbj-ext-install helper into base stage
  - badaf09 feat(bbj-ls-dev): wire ext-test IDE variable, coder_script, and coder_app
---

# Quick Task 260717-gcc: Extension-test IDE for bbj-ls-dev

## What was built

A second, fully isolated code-server instance in the private `bbj-ls-dev`
template, dedicated to installing and running the locally built `bbj-vscode`
extension from a VSIX. Browser code-server cannot reliably run the F5
Extension-Development-Host, so extension testing gets its own editor with the
extension installed from disk, exactly as an end user would install it.

## Changes (all in /Users/beff/coder-bbj-private)

### templates/bbj-ls-dev/Dockerfile (`eccb6fc`)

- New `CODE_SERVER_VERSION` build-arg (default **4.129.0**, bundles Code
  1.129 — satisfies bbj-vscode `engines.vscode ^1.101.0`). Installs a
  standalone code-server tarball (arch-aware) to `/opt/code-server-test`,
  symlinked as **`code-server-test`** — deliberately not `code-server`, so it
  can never shadow the registry module's main-editor binary.
- New **`bbj-ext-install`** helper (`/usr/local/bin`): guards for the clone and
  `node_modules`, runs `npx vsce package --no-dependencies` (bbj-vscode ships
  `@vscode/vsce` as a devDependency; `vscode:prepublish` runs the minified
  esbuild bundle + lint), installs the VSIX into the isolated
  `~/.ext-test/{extensions,data}` dirs via
  `code-server-test --install-extension --force`, then prints the reload hint.
  Pass-through args go to `vsce package`.

### templates/bbj-ls-dev/main.tf (`badaf09`)

- New variable `ext_test_code_server_version` (default 4.129.0) wired as the
  `CODE_SERVER_VERSION` build-arg and into `docker_image.main` triggers.
- `coder_script.ext_test_ide` — same foreground-exec + port-guard shape as
  `coder_script.bbjservices`: guards :13338, waits up to 5 minutes for
  `~/repos/bbj-language-server/examples` (the user-chosen default folder;
  falls back to `$HOME` with a WARN), creates the persistent `~/.ext-test`
  dirs on the home volume, then
  `exec code-server-test --auth none --bind-addr 127.0.0.1:13338 ...`.
  `--auth none` is safe: the app tunnels through the agent, owner-only.
- `coder_app.ext_test` — "VS Code (ext test)" on :13338, `/healthz`
  healthcheck, subdomain per `var.bbj_app_subdomain`, `share = "owner"`.
- Header comments document the dev loop:
  **edit → `bbj-ext-install` → reload the "VS Code (ext test)" tab**.

## Verification

- `terraform validate` (Terraform 1.9 in Docker, `modules/bbj-base` staged the
  way push-templates.sh does): **Success! The configuration is valid.**
  (Run by the orchestrator; the executor agent was cut off by a connection
  error after its final commit, before writing this summary.)
- code-server release tarball URL (v4.129.0 linux-amd64): HTTP **200**.
- `modules/bbj-base`, `combinations.json`, `scripts/push-templates.sh`, and the
  `moved` blocks are untouched (verified in the diffs).

## Not done / notes

- No full `docker build` (needs the BBj installer jar + license server at
  build time) — the new layers are toolchain-only and pattern-match the
  existing verified blocks.
- Roll out with `./scripts/push-templates.sh` in the private repo (no new push
  variables needed).
