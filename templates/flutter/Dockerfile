# templates/flutter/Dockerfile
#
# Flutter / Dart workspace image. Built in-template by docker_image.main in main.tf
# (build { context = path.module }). Layers a build-time-selected Flutter SDK
# channel (which bundles the matching Dart SDK) and Node.js LTS on top of the base
# image.
#
# Build args (set by main.tf from the workspace's coder_parameter values):
#   BASE_IMAGE      — base image (overridable via the workspace_image variable, D-02)
#   FLUTTER_CHANNEL — which Flutter channel to install: stable | beta (default stable)
#
# Everything is installed SYSTEM-WIDE (/opt, /usr) — NOT under /home/coder, which
# is a persistent Docker volume that shadows anything baked into the user's home
# at runtime. /opt and /usr are outside that mount, so the toolchain survives.

ARG BASE_IMAGE=codercom/enterprise-base:ubuntu
FROM ${BASE_IMAGE}

ARG FLUTTER_CHANNEL=stable

# Root for system installs; the base image drops back to the coder user at the end.
USER root

# ── Node.js LTS via NodeSource ───────────────────────────────────────────────
# Provides node + npm/npx on the system PATH (needed for Claude Code CLI, GSD,
# and the node JSON merges in startup_script). Baked into the layer — no per-boot cost.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends nodejs ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── Flutter build/runtime dependencies ───────────────────────────────────────
# The Flutter tool shells out to these: git (the SDK IS a git checkout and flutter
# runs git internally), curl, unzip/xz-utils/zip (artifact archives), and
# libglu1-mesa (required by the Flutter tooling / desktop + some build steps).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl file unzip xz-utils zip libglu1-mesa \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── Flutter SDK (build-arg channel) — system-wide under /opt ──────────────────
# The Flutter SDK is a git repository; `flutter` on a channel == that repo checked
# out to the channel branch. Cloned to /opt/flutter (outside the /home/coder volume
# that shadows home at runtime), with `flutter` and the bundled `dart` symlinked
# onto the system PATH. Dart ships INSIDE the SDK — no separate install.
#
# `git config --system --add safe.directory /opt/flutter` + a chown to the coder
# user prevent git's "detected dubious ownership" refusal: the SDK is cloned by
# root here, but the coder user (the image's final USER) is who runs `flutter`,
# and flutter invokes git under the hood. Without this, every flutter command
# aborts with a fatal ownership error.
#
# `flutter precache` downloads the Dart SDK + the platform artifacts into
# /opt/flutter/bin/cache at BUILD time so the first workspace shell is ready with
# no multi-hundred-MB per-boot download. `--disable-analytics` suppresses the
# first-run telemetry consent so scripted/non-interactive invocations don't stall.
RUN set -eux; \
    git clone --depth 1 -b "${FLUTTER_CHANNEL}" https://github.com/flutter/flutter.git /opt/flutter; \
    git config --system --add safe.directory /opt/flutter; \
    ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter; \
    ln -sf /opt/flutter/bin/dart /usr/local/bin/dart; \
    flutter --version; \
    flutter --disable-analytics; \
    dart --disable-analytics || true; \
    flutter precache; \
    chown -R coder:coder /opt/flutter; \
    flutter --version; \
    dart --version

# ── System-wide Flutter env for login shells ─────────────────────────────────
# flutter/dart are already symlinked into /usr/local/bin; this profile script
# exports FLUTTER_HOME for tools that read it and puts the per-user pub global
# bin (~/.pub-cache/bin, where `dart pub global activate` drops executables) on
# PATH. main.tf mirrors FLUTTER_HOME/PUB_CACHE in the agent env for non-login
# shell parity.
RUN printf '%s\n' \
      'export FLUTTER_HOME=/opt/flutter' \
      'export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"' \
      > /etc/profile.d/10-flutter.sh \
 && chmod 0644 /etc/profile.d/10-flutter.sh

# ── Git over SSH: host keys for common forges + accept-new fallback ──────────
# Without this, an SSH clone (e.g. git@github.com:owner/repo.git, including the
# optional git_repo parameter) fails with "Host key verification failed": a fresh
# container has no known_hosts entry, and the non-interactive ssh invoked by
# `coder gitssh` refuses unverified hosts. Pre-seed the well-known forge keys into
# the SYSTEM known_hosts (outside the volume-shadowed /home/coder, so it always
# applies), and set StrictHostKeyChecking=accept-new globally so any other host
# (self-hosted GitLab, etc.) is trusted-on-first-use instead of rejected.
#
# NOTE: this only fixes HOST verification. Authenticating to a PRIVATE repo still
# requires the Coder-managed SSH public key to be registered with your Git host
# (Coder prints it; add it at https://github.com/settings/ssh/new). See README.
RUN set -eux; \
    mkdir -p /etc/ssh /etc/ssh/ssh_config.d; \
    for h in github.com gitlab.com bitbucket.org ssh.dev.azure.com; do \
      ssh-keyscan -t rsa,ecdsa,ed25519 "$h" >> /etc/ssh/ssh_known_hosts 2>/dev/null \
        || echo "WARN: ssh-keyscan $h failed; continuing" >&2; \
    done; \
    chmod 0644 /etc/ssh/ssh_known_hosts; \
    printf '%s\n' 'Host *' '    StrictHostKeyChecking accept-new' \
      > /etc/ssh/ssh_config.d/10-accept-new.conf; \
    chmod 0644 /etc/ssh/ssh_config.d/10-accept-new.conf

# ── MemPalace CLI (Python) ───────────────────────────────────────────────────
# Local-first AI memory CLI (https://github.com/MemPalace/mempalace). Installed
# SYSTEM-WIDE into a venv under /opt — OUTSIDE the /home/coder volume that
# shadows home at runtime — and symlinked onto the system PATH, so it survives
# every workspace start with no per-boot cost. Its MCP server is registered in
# the agent startup_script; data persists under ~/.mempalace on the home volume.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && python3 -m venv /opt/mempalace \
 && /opt/mempalace/bin/pip install --no-cache-dir mempalace \
 && ln -sf /opt/mempalace/bin/mempalace /usr/local/bin/mempalace \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI (gh) ──────────────────────────────────────────────────────────
# Official apt repo (cli.github.com), arch-aware. Auth is per-user at runtime:
# run `gh auth login` once per workspace — the token persists in ~/.config/gh
# on the home volume.
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── Docker CLI + Compose plugin (docker-outside-of-docker) ───────────────────
# NOTHING TO INSTALL HERE. The base image (codercom/enterprise-base:ubuntu)
# ALREADY ships the Docker CLI + Compose plugin (+ buildx) pre-installed.
#
# DO NOT re-add an `apt-get install docker-ce-cli docker-compose-plugin` block:
# the base image already configures Docker's apt repo at
# /etc/apt/sources.list.d/docker.list with a dearmored keyring under
# /usr/share/keyrings. A hand-rolled block that writes an ASCII-armored key to
# /etc/apt/keyrings/docker.gpg and overwrites that docker.list breaks apt with
# `NO_PUBKEY 7EA0A9C3F273FCD8`, so the install fails (exit 100).
#
# This template uses docker-OUTSIDE-of-docker (DooD): the pre-installed CLI +
# Compose plugin drive the HOST Docker daemon via the socket bind-mounted by
# main.tf (docker_container.workspace mounts /var/run/docker.sock and adds
# group_add = [var.docker_group_id] so the coder user can reach it). A nested
# engine is NOT used and would NOT work here — this workspace container has no
# NET_ADMIN and cannot create namespaces, so a nested Docker daemon cannot run.
# Because the CLI talks to the host daemon:
#   - `docker ps` lists HOST containers, not workspace-local ones.
#   - `docker compose up` starts stacks as SIBLING containers alongside the
#     workspace, not children of it.
#
# Operator gotchas:
#   (a) Bind-mount paths in compose files (volumes: section) resolve against the
#       HOST filesystem, not the workspace filesystem. A path that looks correct
#       inside the workspace may silently reference an unexpected host path.
#   (b) Socket access grants EFFECTIVE ROOT ON THE HOST (any process in the
#       workspace can start privileged containers, read host files via volume
#       mounts, etc.). This is acceptable for a single-operator self-hosted setup
#       but is NOT appropriate for a shared or multi-tenant team deployment.

USER coder
