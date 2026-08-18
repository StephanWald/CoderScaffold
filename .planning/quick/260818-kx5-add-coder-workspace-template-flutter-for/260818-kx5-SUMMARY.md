---
quick_id: 260818-kx5
title: flutter/dart workspace template
date: 2026-08-18
status: complete
commit: a73265e
---

# Quick Task 260818-kx5 — Summary

Added a new Coder workspace template, `templates/flutter/`, for Flutter + Dart
development. It mirrors the existing `python-ai` / `java-fullstack` templates
(the same Claude Code + MCP + GSD + MemPalace + docker-outside-of-docker + git
plumbing), with the language toolchain swapped for the Flutter SDK.

## What shipped

`templates/flutter/` — `main.tf` + `Dockerfile` + `README.md` +
`.terraform.lock.hcl` (auto-discovered by `scripts/push-templates.sh`).

**Workspace parameters (prompted at create time):**
- `git_repo` — optional Git URL; when set, cloned on first start into a folder
  derived from the repo name, and all editors open that checkout (else
  `/home/coder`). `mutable = false` (clone-once, create-time decision).
- `flutter_channel` — build-time channel selector: `stable` (default) or `beta`.
  `mutable = true`: the value is part of the image name + triggers + build args,
  so changing it rebuilds (and separately caches) the image. Switch at runtime
  without a rebuild via `flutter channel <name> && flutter upgrade`.

**Toolchain (installed system-wide, NOT in the volume-shadowed `/home/coder`):**
- Flutter SDK `git clone -b ${FLUTTER_CHANNEL}` → `/opt/flutter`; `flutter` and
  the bundled `dart` symlinked into `/usr/local/bin`. Dart ships inside the SDK.
- `flutter precache` at build bakes the Dart SDK + platform artifacts into the
  image (no per-boot download); `flutter --disable-analytics` suppresses the
  first-run consent prompt.
- `git config --system --add safe.directory /opt/flutter` + `chown -R coder`
  so the coder user can run the root-cloned SDK without git's "dubious
  ownership" refusal.
- Flutter build deps: `git curl file unzip xz-utils zip libglu1-mesa`.
- Node.js LTS via NodeSource (`node`/`npm`/`npx`).
- `FLUTTER_HOME` + `~/.pub-cache/bin` on PATH via `/etc/profile.d/10-flutter.sh`
  (login shells) and `FLUTTER_HOME`/`PUB_CACHE` in the `coder_agent.env`
  (agent/non-login shells).

**IDEs:** code-server (browser VS Code) with the `Dart-Code.dart-code` +
`Dart-Code.flutter` extensions pre-installed, VS Code Desktop (SSH), and
JetBrains Gateway → IntelliJ IDEA Ultimate (`IU`).

**Inherited unchanged from python-ai/java-fullstack:** per-owner shared Claude
config volume + symlink migration, `bypassPermissions`, webforJ MCP, MemPalace
MCP + `mempalace init`, GSD (gsd-core), persistent per-workspace home volume,
docker-outside-of-docker socket mount + `group_add`, git-over-SSH forge
known_hosts + `accept-new`, `gh` CLI, and the `127.0.0.1 → host.docker.internal`
init_script rewrite. JupyterLab (Python-specific) was dropped.

## Verification

Static (performed here):
- `terraform fmt -check` — clean.
- `terraform validate` — "The configuration is valid" (init resolved the
  registry modules, so the new `extensions` arg on code-server and
  `jetbrains_ides = ["IU"]` were schema-checked too).
- `docker build --check` — "Check complete, no warnings found."

Live gate (DEFERRED — per memory "Infra needs a live deploy gate"): a real
`docker build` of the stable variant (the `flutter precache` step is
network-heavy), a `flutter doctor` / `flutter build web` smoke test, and
`coder templates push flutter` must run on a host with Docker + the coder CLI.
Captured as the README live-verification checklist.

## Notes / follow-ups

- Committed `.terraform.lock.hcl` matches the java-fullstack/python-ai provider
  set (coder 2.18.0 + kreuzwerker/docker 4.5.0 + hashicorp/http 3.6.1) — same
  module composition.
- The image ships Flutter's **web** + **Linux desktop** targets; the Android
  SDK/NDK are NOT baked in (multi-GB). `flutter doctor` will flag the missing
  Android toolchain (expected); add it downstream if `flutter build apk` is
  needed. Documented in the README.
- `[LIVE-VERIFY]` markers in `main.tf`/README flag the pins to confirm at push
  time: `vscode-desktop @ 1.1.0`, the Open VSX extension ids, and the
  `/icon/flutter.svg` icon (fallback `/icon/dart.svg`).
</content>
