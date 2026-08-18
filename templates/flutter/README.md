# Flutter / Dart Workspace Template

A Coder workspace template for Flutter and Dart development with batteries-included AI
tooling. It mirrors the structure of the `python-ai` and `java-fullstack` templates —
the same Claude Code, MCP, GSD, and MemPalace plumbing — with the language toolchain
replaced by the Flutter SDK (which bundles Dart).

## What it provides

- **Selectable Flutter channel** — `stable` (default) or `beta`. The channel is a
  **build-time** choice (prompted at workspace creation); selecting a different channel
  rebuilds the workspace image and produces a separately-cached layer. Switch at runtime
  without a rebuild via `flutter channel <name> && flutter upgrade`.
- **Flutter + Dart** — `flutter` and `dart` are on the system PATH from the first login.
  Dart ships inside the Flutter SDK; `flutter precache` runs at image build so the Dart
  SDK + platform artifacts are baked in (no multi-hundred-MB per-boot download).
- **Node.js LTS** — `node`, `npm`, `npx` for Claude Code CLI, GSD installs, and the node
  JSON merges in the startup script.
- **VS Code** (browser, via code-server, with the Dart + Flutter extensions pre-installed)
  + **VS Code Desktop** (SSH, local client) + **IntelliJ IDEA Ultimate** (JetBrains
  Gateway; install the Dart + Flutter plugins once from the IDE marketplace).
- **Claude Code** — latest CLI, pre-wired via the per-owner shared volume; first login is
  interactive OAuth — no API key required by default.
- **webforJ MCP server** — `https://mcp.webforj.com/` registered in every workspace for this
  owner automatically (shared cross-template plumbing).
- **MemPalace MCP** — local AI memory; `mempalace mcp serve` wired into the shared Claude
  config, palace initialized on first start.
- **GSD** (gsd-core) — installed once into the per-owner shared Claude volume.
- **docker-outside-of-docker** — the Docker CLI + Compose plugin drive the host daemon via
  the bind-mounted socket (`docker` / `docker compose` available in the workspace).
- **Optional git clone** — prompted at workspace creation; when supplied, the repo is cloned
  on first start and all editors open that checkout.

## Why the toolchain lives in /opt (not /home/coder)

`/home/coder` is a persistent Docker volume that **shadows** anything baked into that path
at image build time. The Flutter SDK is installed to `/opt/flutter` and `flutter`/`dart`
are symlinked into `/usr/local/bin` — outside the volume mount — so the toolchain is present
from the very first shell in every workspace, even after a fresh start. (The pub package
cache, `~/.pub-cache`, intentionally lives *on* the home volume so activated packages and
project dependencies persist per-workspace.)

> The SDK is cloned by root at build time but run by the `coder` user; the Dockerfile sets
> `git config --system --add safe.directory /opt/flutter` and `chown`s the tree to `coder`
> so git does not refuse the checkout with a "dubious ownership" error.

## Cloning a private repository (SSH)

For SSH URLs (`git@github.com:owner/repo.git`), Coder authenticates with a per-user key it
manages for you. Two things make it work:

1. **Host key verification** — handled by the image: GitHub, GitLab, Bitbucket, and Azure
   DevOps are pre-seeded into the system `known_hosts`; any other host is trusted on first use
   (`StrictHostKeyChecking=accept-new`).
2. **Authorize Coder's key with your Git host** — copy the key Coder prints (or run
   `coder publickey`) and add it once at <https://github.com/settings/ssh/new>. The key is
   stored centrally by Coder and covers all your workspaces.

The first-start clone is non-fatal and idempotent — if the key isn't registered yet, restart
the workspace or run the `git clone` manually once.

## Push and configure

```bash
# Push (or use ./scripts/push-templates.sh to push every template automatically)
coder templates push flutter --directory templates/flutter/ -y

# Server-side display metadata (not Terraform-managed — set after the first push)
coder templates edit flutter \
  --display-name "Flutter / Dart" \
  --description "Flutter workspace: selectable channel (stable/beta), Flutter SDK + bundled Dart, Node LTS, VS Code (browser + desktop, Dart/Flutter extensions), IntelliJ IDEA, Claude Code + MCP + GSD + MemPalace." \
  --icon "/icon/flutter.svg"
```

> Re-run `coder templates edit` after every re-push to keep the display metadata — it is not
> preserved automatically on re-push.

`./scripts/push-templates.sh` discovers and pushes every `templates/*/` directory that
contains a `.tf` file. The `flutter` template requires no `--variable` flags at push time
(`anthropic_api_key` defaults to `""` — OAuth is the standard path).

---

## DEFERRED LIVE-VERIFICATION CHECKLIST

The following checks **MUST be run on a real Coder host** with Docker and the `coder` CLI
installed and a running Coder server before trusting this template in production. Static HCL
checks (`terraform fmt -check`, offline `terraform validate`) have been performed. Live
checks are deferred per project memory: "Infra needs a live deploy gate."

- [ ] `docker build` of the `stable` variant succeeds end-to-end (the `flutter precache`
      step is network-heavy; confirm it completes)
- [ ] `coder templates push flutter --directory templates/flutter/ -y` succeeds
- [ ] Workspace builds for each channel: `stable` and `beta`
- [ ] `flutter --version` / `dart --version` succeed in a fresh login shell and report the
      selected channel; `flutter doctor` runs
- [ ] `flutter`, `dart`, `node`, `npm`, `npx`, `git`, `gh`, and `mempalace` are all on PATH
- [ ] `flutter create demo && cd demo && flutter build web` succeeds (end-to-end toolchain)
- [ ] IDE buttons appear and open correctly: VS Code (browser, with Dart + Flutter
      extensions pre-installed), VS Code Desktop, IntelliJ IDEA Ultimate (JetBrains Gateway)
- [ ] Confirm the module source/version pins resolve at push time and bump if newer:
      `code-server @ 1.5.0`, `vscode-desktop @ 1.1.0`, `jetbrains-gateway @ 1.2.6`,
      `claude-code @ 5.2.0`; confirm the code-server `extensions` ids
      (`Dart-Code.dart-code`, `Dart-Code.flutter`) install from Open VSX
- [ ] Confirm the `/icon/flutter.svg` icon resolves in the Coder UI (fallback: `/icon/dart.svg`)
- [ ] Claude Code, webforJ MCP server, MemPalace MCP server, and GSD are all present and
      functional in the owner-shared volume
- [ ] `docker` / `docker compose` reach the host daemon from inside the workspace (verify the
      `docker_group_id` matches the host socket GID: `stat -c '%g' /var/run/docker.sock`)
- [ ] Second/third start emits no startup_script errors (idempotence gate)

> **Note on Android/mobile builds:** this image ships the Flutter SDK with **web** and
> **Linux desktop** targets ready. The Android SDK / NDK are **not** baked in (multi-GB) —
> add them (e.g. via `cmdline-tools` + `sdkmanager`) in a downstream image or at runtime if
> you need `flutter build apk`. `flutter doctor` will flag the missing Android toolchain,
> which is expected.
