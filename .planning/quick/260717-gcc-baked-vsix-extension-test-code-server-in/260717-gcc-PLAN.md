---
phase: quick-260717-gcc
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /Users/beff/coder-bbj-private/templates/bbj-ls-dev/Dockerfile
  - /Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf
autonomous: true
requirements: [EXT-TEST-IDE]

must_haves:
  truths:
    - "The base image bakes a standalone code-server-test binary under /opt, separate from the module-managed main editor"
    - "A bbj-ext-install helper packages bbj-vscode to a VSIX and installs it into the isolated ext-test extensions dir"
    - "A second code-server instance runs on :13338 exposed as a 'VS Code (ext test)' coder_app, opening the examples folder"
    - "The ext-test code-server version is a template variable wired to a build_arg and the docker_image triggers"
  artifacts:
    - path: "/Users/beff/coder-bbj-private/templates/bbj-ls-dev/Dockerfile"
      provides: "code-server-test install + bbj-ext-install helper in the base stage"
      contains: "CODE_SERVER_VERSION"
    - path: "/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf"
      provides: "ext_test_ide coder_script + ext_test coder_app + ext_test_code_server_version variable"
      contains: "coder_app \"ext_test\""
  key_links:
    - from: "main.tf docker_image.main.build_args"
      to: "Dockerfile ARG CODE_SERVER_VERSION"
      via: "build_arg passthrough"
      pattern: "CODE_SERVER_VERSION"
    - from: "main.tf coder_app.ext_test"
      to: "coder_script.ext_test_ide on :13338"
      via: "http://localhost:13338"
      pattern: "13338"
---

<objective>
Add a second, isolated code-server instance to the PRIVATE bbj-ls-dev template, dedicated to installing and running the locally built bbj-vscode extension from a VSIX ("extension test IDE"). Browser code-server cannot reliably run the F5 Extension-Development-Host, so testing requires a separate editor with the extension installed from disk.

Purpose: Give the developer a repeatable `edit → bbj-ext-install → reload ext-test tab` loop inside the bbj-ls-dev workspace.
Output: Modified Dockerfile (baked code-server-test + bbj-ext-install helper) and main.tf (variable + coder_script + coder_app) in /Users/beff/coder-bbj-private.

All design decisions are LOCKED in the planning context — implement them exactly; do not re-research versions, ports, or flags.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

# Two repos: planning artifacts live in /Users/beff/coder; ALL code changes go to
# /Users/beff/coder-bbj-private. Use absolute paths for every edit.

<interfaces>
<!-- Established patterns the executor MUST mirror (already read into this plan). -->

Dockerfile base stage (three-stage build) — existing arch-detection pattern used
for JDKs (lines 78-93) uses `dpkg --print-architecture` with a case mapping.
code-server tarballs use amd64/arm64 directly (NOT x64/aarch64), so the case for
code-server maps: amd64) arch=amd64 ;; arm64) arch=arm64. The `final` stage
inherits everything in `base` automatically — do NOT edit bbjinstall/final.

Helper-install pattern (printf → /usr/local/bin, chmod 0755) — mirror the
MemPalace/mvn symlink style already present. Helpers are written with printf,
not COPY.

main.tf coder_script shape (see coder_script.bbjservices lines 352-373 and
coder_script.npm_install_bbj_vscode lines 316-345):
  - agent_id = module.base.agent_id
  - run_on_start = true, start_blocks_login = false
  - script = <<-EOT with `#!/bin/sh` first line
  - port guard: `ss -tlnp 2>/dev/null | grep -q ':PORT'` → echo + exit 0
  - wait loop: `for i in $(seq 1 60); do ... sleep 5; done` (5-minute wait)
  - foreground run via `exec`

main.tf coder_app shape (see coder_app.bbjservices lines 377-391):
  agent_id, slug, display_name, url, icon, subdomain = var.bbj_app_subdomain,
  share = "owner", healthcheck { url; interval; threshold }.

docker_image.main (lines 209-236): build_args map (BASE_IMAGE, JDK, BBJ_JAR_NAME,
MAVEN_VERSION, LICENSE_SERVER) + triggers map. New arg goes in BOTH.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Bake code-server-test + bbj-ext-install helper into the Dockerfile base stage</name>
  <files>/Users/beff/coder-bbj-private/templates/bbj-ls-dev/Dockerfile</files>
  <action>
Edit ONLY the `base` stage of /Users/beff/coder-bbj-private/templates/bbj-ls-dev/Dockerfile (the `final` stage inherits it). Do not touch bbjinstall/final.

1. Add build-arg near the other base ARGs (after `ARG MAVEN_VERSION`): `ARG CODE_SERVER_VERSION=4.129.0` (verified latest; bundles Code 1.129, satisfies bbj-vscode engines.vscode ^1.101.0).

2. Add a RUN block (place it after the MemPalace install, still in the base stage, still USER root) that installs a STANDALONE code-server for the test instance, system-wide, outside /home/coder:
   - Use the existing `dpkg --print-architecture` case pattern, but map to code-server tarball arch names directly: amd64)arch=amd64 ;; arm64)arch=arm64 ;; *) error+exit 1.
   - Download `https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${arch}.tar.gz` to a tmp file.
   - Extract to `/opt/code-server-test` with `--strip-components=1`; rm the tarball.
   - `test -x /opt/code-server-test/bin/code-server`.
   - `ln -sfn /opt/code-server-test/bin/code-server /usr/local/bin/code-server-test` — DELIBERATELY named code-server-test, NOT code-server, so it does not shadow the coder/code-server registry module's binary.
   - Add a rationale comment: separate install so the test IDE and the module-managed main editor cannot interfere and can version-drift independently.

3. Add a RUN block that writes the `bbj-ext-install` helper via printf → /usr/local/bin/bbj-ext-install, chmod 0755. Helper body (exact behavior):
   - `#!/usr/bin/env bash`, `set -euo pipefail`.
   - `SRC="${BBJ_LS_SRC:-$HOME/repos/bbj-language-server}/bbj-vscode"`.
   - Guard: if `$SRC/package.json` missing → echo error "clone not present yet" to stderr, exit 1. If `$SRC/node_modules` missing → echo error "run npm install first (the npm-install coder_script primes it on workspace start)" to stderr, exit 1.
   - `cd "$SRC"; npx vsce package --no-dependencies --out /tmp/bbj-lang.vsix "$@"` — bbj-vscode has @vscode/vsce ^3.7.1 as a devDependency; its vscode:prepublish hook runs the minified esbuild bundle + lint automatically; --no-dependencies because the bundle is esbuilt. Comment that pass-through args go to vsce package (e.g. --pre-release).
   - `code-server-test --install-extension /tmp/bbj-lang.vsix --force --extensions-dir "$HOME/.ext-test/extensions" --user-data-dir "$HOME/.ext-test/data"`.
   - Final echo: extension installed; reload the "VS Code (ext test)" browser tab to pick it up.
   - When emitting the helper via printf, escape `$` so the shell variables ($HOME, $SRC, $@) are literal in the written file, NOT expanded at build time.

4. Update the header comment block's Toolchain list: add a code-server-test entry describing the standalone editor for extension-from-VSIX testing.
  </action>
  <verify>
    <automated>bash -c 'set -e; D=/Users/beff/coder-bbj-private/templates/bbj-ls-dev/Dockerfile; grep -q "ARG CODE_SERVER_VERSION=4.129.0" "$D"; grep -q "code-server-${CODE_SERVER_VERSION}-linux" "$D"; grep -q "/usr/local/bin/code-server-test" "$D"; grep -q "bbj-ext-install" "$D"; grep -q "no-dependencies" "$D"; echo DOCKERFILE_OK'</automated>
  </verify>
  <done>Dockerfile base stage installs /opt/code-server-test (symlinked as code-server-test, not code-server), writes an executable bbj-ext-install helper that packages bbj-vscode to a VSIX and installs it into ~/.ext-test, and the header Toolchain list mentions code-server-test. bbjinstall/final stages untouched.</done>
</task>

<task type="auto">
  <name>Task 2: Wire the ext-test IDE variable, coder_script, and coder_app in main.tf</name>
  <files>/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf</files>
  <action>
Edit /Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf.

1. New variable (place with the other CODER_*/bbj variables): `ext_test_code_server_version`, type string, default "4.129.0", description: "code-server release for the extension-test IDE; must bundle Code >= 1.101 per bbj-vscode engines".

2. In `docker_image.main`:
   - Add to `build_args`: `CODE_SERVER_VERSION = var.ext_test_code_server_version`.
   - Add to `triggers`: `ext_test_code_server = var.ext_test_code_server_version`.

3. Add `resource "coder_script" "ext_test_ide"` mirroring the coder_script.bbjservices shape (agent_id = module.base.agent_id, run_on_start = true, start_blocks_login = false, script = <<-EOT with `#!/bin/sh`):
   - Port guard: if `ss -tlnp 2>/dev/null | grep -q ':13338'` → echo "already running", exit 0.
   - Wait up to 5 minutes (60 × 5s loop, same as npm_install) for `/home/coder/repos/bbj-language-server/examples` to appear. Set `FOLDER` to that examples path when found; if still absent after the loop, fall back to `$HOME` with a WARN echo.
   - `mkdir -p "$HOME/.ext-test/data" "$HOME/.ext-test/extensions"` (home volume → installed VSIX + settings persist across restarts).
   - Foreground: `exec code-server-test --auth none --disable-telemetry --bind-addr 127.0.0.1:13338 --user-data-dir "$HOME/.ext-test/data" --extensions-dir "$HOME/.ext-test/extensions" "$FOLDER"`. --auth none is safe: the coder_app tunnels through the agent, share = "owner" (same model as the registry code-server module).

4. Add `resource "coder_app" "ext_test"` mirroring coder_app.bbjservices: agent_id = module.base.agent_id, slug = "ext-test", display_name = "VS Code (ext test)", url = "http://localhost:13338", icon = "/icon/code.svg", subdomain = var.bbj_app_subdomain, share = "owner". healthcheck { url = "http://localhost:13338/healthz"; interval = 10; threshold = 6 } (code-server exposes /healthz). Place it after the existing bbjservices app.

5. Update the header comment block: add the ext-test IDE to the dev-loop section (loop: `edit → bbj-ext-install → reload ext-test tab`) and mention the ext-test app on :13338 in the Requires/apps notes.

Do NOT touch modules/bbj-base, scripts/push-templates.sh, combinations.json, or the moved blocks.
  </action>
  <verify>
    <automated>bash -c 'set -e; M=/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf; grep -q "ext_test_code_server_version" "$M"; grep -q "CODE_SERVER_VERSION = var.ext_test_code_server_version" "$M"; grep -q "ext_test_code_server = var.ext_test_code_server_version" "$M"; grep -q "coder_script \"ext_test_ide\"" "$M"; grep -q "coder_app \"ext_test\"" "$M"; grep -q "13338" "$M"; grep -q "/healthz" "$M"; echo MAINTF_OK'</automated>
  </verify>
  <done>main.tf declares ext_test_code_server_version wired into both build_args and triggers, a coder_script.ext_test_ide running code-server-test on :13338 opening the examples folder, and a coder_app.ext_test named "VS Code (ext test)". Header dev-loop and apps notes updated. modules/bbj-base and moved blocks untouched.</done>
</task>

</tasks>

<verification>
After both tasks, validate the full template with the Docker-based terraform (terraform/tofu are NOT on PATH):

```
S=$(mktemp -d)
cp -R /Users/beff/coder-bbj-private/templates/bbj-ls-dev/. "$S/"
cp -R /Users/beff/coder-bbj-private/modules "$S/modules"
docker run --rm -v "$S":/tf -w /tf hashicorp/terraform:1.9 init -backend=false -input=false
docker run --rm -v "$S":/tf -w /tf hashicorp/terraform:1.9 validate
```

Both must succeed. Also verify the code-server tarball URL resolves:
```
curl -fsIL -o /dev/null -w '%{http_code}\n' https://github.com/coder/code-server/releases/download/v4.129.0/code-server-4.129.0-linux-amd64.tar.gz
```
(expect 200 — already confirmed at plan time).

Extract the bbj-ext-install helper body and syntax-check it:
```
/bin/bash -n <(extract the printf'd helper body)  # must exit 0
```

Do NOT docker-build the full image (needs the BBj installer jar + license).
</verification>

<success_criteria>
- Dockerfile base stage bakes /opt/code-server-test (symlinked code-server-test) and an executable bbj-ext-install helper; header Toolchain updated.
- main.tf: ext_test_code_server_version variable wired to build_arg + trigger; coder_script.ext_test_ide on :13338 opening examples with $HOME fallback; coder_app.ext_test "VS Code (ext test)" with /healthz healthcheck; header updated.
- `terraform validate` (via Docker) passes; bbj-ext-install helper passes `bash -n`.
- One or two atomic conventional commits in /Users/beff/coder-bbj-private (e.g. `feat(bbj-ls-dev): ...`). Nothing committed in /Users/beff/coder.
- modules/bbj-base, scripts/push-templates.sh, combinations.json, bbjinstall/final stages, and moved blocks are untouched.
</success_criteria>

<output>
Create `.planning/quick/260717-gcc-baked-vsix-extension-test-code-server-in/260717-gcc-SUMMARY.md` when done.
</output>
