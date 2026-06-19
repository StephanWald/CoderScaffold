---
quick_id: 260619-9ii
title: java-fullstack universal workspace template
date: 2026-06-19
status: complete
commit: f78975d
---

# Quick Task 260619-9ii — Summary

Added a new universal Coder workspace template, `templates/java-fullstack/`, for a
stack of Java/Spring Boot backends + JavaScript/TypeScript UIs (e.g. webforJ).

## What shipped

`templates/java-fullstack/main.tf` + `Dockerfile` (auto-discovered by
`scripts/push-templates.sh`), plus a README section.

**Workspace parameters (prompted at create time):**
- `git_repo` — optional Git URL; when set, cloned on first start into a folder
  derived from the repo name, and both editors open that checkout (else
  `/home/coder`). `mutable = false` (clone-once, create-time decision).
- `jdk` — build-time JDK selector with four options:
  - `adoptium-21`, `adoptium-25` — Adoptium (Temurin) "latest GA" via the
    Adoptium API.
  - `oracle-21`, `oracle-25` — Oracle JDK "latest" via download.oracle.com under
    the No-Fee Terms (NFTC) — no login required.
  Default `adoptium-21`. `mutable = true`: the value is part of the image name +
  triggers + build args, so changing it rebuilds (and separately caches) the image.

**Toolchain (installed system-wide, NOT in the volume-shadowed `/home/coder`):**
- Selected JDK → `/opt/java/default`, registered via `update-alternatives`
  (`/usr/bin/java`, `/usr/bin/javac`); arch auto-detected (amd64→x64, arm64→aarch64).
- Apache Maven, pinned `3.9.16` (var `maven_version`), from archive.apache.org →
  `/opt/maven`, symlinked to `/usr/local/bin/mvn`.
- Node.js LTS via NodeSource (`node`/`npm`/`npx`).
- `JAVA_HOME`/`MAVEN_HOME` exported via `/etc/profile.d/10-java-maven.sh` (login
  shells) and the `coder_agent.env` (agent/non-login shells).

**Inherited from the `docker` template:** persistent per-workspace home volume,
per-owner shared Claude config volume, code-server (VS Code), JetBrains Gateway
(IntelliJ IDEA), Claude Code module, the webforJ MCP preconfig (260619-93j), GSD,
and the `127.0.0.1 → host.docker.internal` agent-connectivity rewrite.

## Verification

Static:
- `terraform fmt -check` clean; `terraform validate` (with real providers) →
  "configuration is valid".
- JDK/arch URL selection resolves correctly for all 4 JDKs × {amd64, arm64};
  unknown JDK/arch hit the fail-loud error paths. All 8 download URLs confirmed
  HTTP 206 (live, no login).
- `docker build --check` — no warnings.

Live gate (per "infra needs a live deploy gate"):
- **Built `adoptium-21`** end-to-end → smoke test: `java -version` =
  Temurin 21.0.11 LTS, `javac` 21.0.11, `mvn -v` = Maven 3.9.16 resolving
  `/opt/java/default`, `node` v24.17.0 + npm/npx, `JAVA_HOME`/`MAVEN_HOME` set,
  `java` → `/opt/java/default/bin/java`.
- **Built `oracle-25`** end-to-end → `java -version` = Oracle JDK 25.0.3 LTS
  (vendor: Oracle Corporation), Maven resolves it. Confirms the Oracle/NFTC path
  works without login.
- Both built on an aarch64 host, exercising the arm64 arch-detection branch.
- Test images removed after verification.

## Notes / follow-ups

- Not built for all four JDK variants (only adoptium-21 + oracle-25); the other
  two (`adoptium-25`, `oracle-21`) use identical logic with pre-confirmed URLs.
- "Latest" JDK endpoints mean a fixed download checksum can't be pinned without
  defeating the user's "Adoptium Latest" requirement — accepted trade-off.
- LIVE Coder-server push/provision (`coder templates push java-fullstack`) is
  still deferred to an environment with the coder CLI + a running server, same as
  the existing templates. The image itself is fully verified here.
</content>
