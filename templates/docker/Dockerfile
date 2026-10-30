# templates/docker/Dockerfile
#
# Workspace base image + Node.js. Built in-template by docker_image.main in
# main.tf (build { context = path.module }). Node.js is required by the GSD
# (gsd-core) install in the agent startup_script — `npx @opengsd/gsd-core`
# needs npm/npx, which the stock codercom/enterprise-base image does not ship.
#
# The base image is overridable via the workspace_image variable (passed as the
# BASE_IMAGE build arg) so the pin-and-override property (D-02) is preserved.
# Pin to a digest for production reproducibility:
#   codercom/enterprise-base:ubuntu@sha256:<digest>

ARG BASE_IMAGE=codercom/enterprise-base:ubuntu
FROM ${BASE_IMAGE}

# Node.js LTS via NodeSource — provides node + npm/npx on the system PATH for
# every workspace, with no per-boot install cost (baked into the image layer).
# Run as root for apt, then drop back to the image's default coder user.
USER root
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
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

# ── tmux (terminal multiplexer for durable interactive sessions) ─────────────
# Installs tmux so that Coder browser web terminal sessions survive client disconnect
# or hibernate. The guarded auto-attach profile.d snippet below (10-tmux-autoattach.sh)
# wraps the browser web terminal's shell in a persistent tmux session named `main`;
# reopening the browser terminal re-attaches the same live session instead of starting
# a dead new one. SSH, herdr and IDE shells stay bare (see the snippet comment below).
# tmux runs as the unprivileged `coder` user — no new privilege boundary. Installed
# into /usr (outside /home/coder) so the binary survives the home-volume mount at
# runtime. Takes effect only after an image REBUILD — existing running workspaces need a rebuild to pick this up.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tmux \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Drop a guarded auto-attach snippet into /etc/profile.d/ (image layer, not home
# — /home/coder is a Docker volume that shadows the image at runtime, so anything
# written under home would be invisible in a running workspace). The snippet is
# POSIX-sh safe (it is sourced by the login shell, not executed as bash).
# It exec-replaces the shell with `tmux new -A -s main` ONLY in the Coder browser
# web terminal. Base guards: interactive shell, stdout is a TTY, not already inside
# tmux, tmux on PATH, and not a VS Code Remote-SSH / server shell (VSCODE_INJECTION
# or VSCODE_IPC_HOOK_CLI). Web-terminal detection: SSH_TTY unset (the Coder agent sets
# it only for SSH PTY sessions) AND the parent process is the agent binary `coder`
# (/proc/$PPID/comm). So `coder ssh`, plain ssh via config-ssh, herdr terminals,
# JetBrains Gateway and VS Code terminals get a bare shell — those tools manage their
# own panes/sessions. Per-session override: CODER_TMUX_AUTOATTACH=1 always attaches,
# =0 never (e.g. `ssh -o SetEnv=CODER_TMUX_AUTOATTACH=1 coder.<workspace>`). One-shot
# `coder ssh -- <cmd>` and scp/rsync stay excluded by the interactive + TTY guards.
# Fall-through never exits or returns — every non-matching shell continues normally.
RUN printf '%s\n' \
      '# /etc/profile.d/10-tmux-autoattach.sh' \
      '# Auto-attach the persistent tmux session `main` ONLY in the Coder browser web terminal.' \
      '# Every other interactive shell stays bare: `coder ssh`, plain ssh via config-ssh, herdr,' \
      '# JetBrains Gateway and VS Code terminals (those tools own their panes and sessions).' \
      '# Why: the web terminal is a reconnecting PTY started directly by the Coder agent, so' \
      '# SSH_TTY is unset (the agent sets it only for SSH PTY sessions) and the parent process' \
      '# is the agent binary `coder` (/proc/$PPID/comm). SSH_CLIENT/SSH_CONNECTION are set on' \
      '# both paths, so they cannot tell the two apart.' \
      '# Override: CODER_TMUX_AUTOATTACH=1 always attaches, =0 never attaches, e.g.' \
      '#   ssh -o SetEnv=CODER_TMUX_AUTOATTACH=1 coder.<workspace>' \
      '# Diagnose a shell: echo "$SSH_TTY"; cat /proc/$PPID/comm  (web terminal: empty, coder)' \
      '# Base guards (always apply): interactive ($- has i), TTY (fd 1), not already in tmux' \
      '# ($TMUX), tmux on PATH, not VS Code Remote-SSH (VSCODE_INJECTION/VSCODE_IPC_HOOK_CLI).' \
      '# Fall-through is always safe — the parent shell continues normally.' \
      'case "$-" in' \
      '  *i*)' \
      '    if [ -t 1 ] && [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1 \' \
      '         && [ -z "$VSCODE_INJECTION" ] && [ -z "$VSCODE_IPC_HOOK_CLI" ]; then' \
      '      case "${CODER_TMUX_AUTOATTACH:-}" in' \
      '        1) exec tmux new -A -s main ;;' \
      '        0) ;;' \
      '        *)' \
      '          if [ -z "$SSH_TTY" ]; then' \
      '            case "$(cat /proc/$PPID/comm 2>/dev/null)" in' \
      '              coder*) exec tmux new -A -s main ;;' \
      '            esac' \
      '          fi' \
      '          ;;' \
      '      esac' \
      '    fi' \
      '    ;;' \
      'esac' \
      > /etc/profile.d/10-tmux-autoattach.sh \
 && chmod 0644 /etc/profile.d/10-tmux-autoattach.sh

# Also cover interactive NON-login shells (e.g. the Coder browser web terminal),
# which read /etc/bash.bashrc — sourced by Ubuntu bash for interactive shells via
# SYS_BASHRC — NOT /etc/profile.d (that path is login-shell only). /etc/bash.bashrc
# lives on the image, unlike the volume-shadowed ~/.bashrc under /home/coder, so it
# survives at runtime. The sourced snippet is fully self-guarded (interactive + TTY
# + not-already-in-tmux + not-VS-Code), so sourcing it from both entry points is
# idempotent: no double-attach, no recursion (the shell tmux spawns has $TMUX set).
RUN printf '%s\n' \
      '' \
      '# Auto-attach tmux for interactive non-login shells (login shells use /etc/profile.d).' \
      'if [ -f /etc/profile.d/10-tmux-autoattach.sh ]; then . /etc/profile.d/10-tmux-autoattach.sh; fi' \
      >> /etc/bash.bashrc

# System-wide tmux config. /etc/tmux.conf is tmux's global config file, read at
# server start before any user config — and it lives on the image, so it survives
# the volume-shadowed /home/coder at runtime just like the auto-attach snippet
# above (a ~/.tmux.conf would be masked by the mounted home). Two quality-of-life
# defaults for the browser web terminal's durable `tmux new -A -s main` session:
#   mouse on      — wheel-scroll into scrollback, click-to-select pane/window, and
#                   drag-to-resize; without it the web terminal can't reach tmux's
#                   scrollback at all (tmux owns the alternate screen).
#   history-limit — raise per-pane scrollback from tmux's 2000-line default to
#                   50000 lines so long build/test output stays reviewable.
RUN printf '%s\n' \
      '# /etc/tmux.conf — system-wide defaults for the durable `tmux new -A -s main` session.' \
      'set -g mouse on' \
      'set -g history-limit 50000' \
      > /etc/tmux.conf \
 && chmod 0644 /etc/tmux.conf

# Make bash the explicit default shell. The base image already sets the coder
# user's login shell to /bin/bash, but pin it here so the intent survives a
# base-image change, and export SHELL (unset in the base image) so non-login
# contexts — the Coder agent web terminal, coder_script, tools that read $SHELL —
# all agree on bash.
RUN usermod -s /bin/bash coder
ENV SHELL=/bin/bash

# Shared-Claude self-test — operator-facing diagnostic for the per-owner shared
# Claude volume (~/.claude-shared) + MemPalace wiring. The script is staged into
# this build context by scripts/push-templates.sh (the docker build context only
# sees the template dir; the canonical, reviewed source lives at
# scripts/claude-share-selftest.sh in the repo). Installed at a system path so
# the volume-shadowed /home/coder can't hide it; run via the "Self-Test"
# workspace button or: /usr/local/bin/claude-share-selftest all
COPY claude-share-selftest.sh /usr/local/bin/claude-share-selftest
RUN chmod 0755 /usr/local/bin/claude-share-selftest

# ── OpenAI Codex CLI ─────────────────────────────────────────────────────────
# Codex CLI (@openai/codex) baked system-wide via npm -g — lands under
# /usr/local, OUTSIDE the /home/coder volume that shadows home at runtime, so
# the binary survives every workspace start. Version pinned via an overridable
# ARG per the repo's pin-don't-float convention; node/npm are guaranteed
# present from the NodeSource block above (no apt work needed). Config/auth
# persist per owner: ~/.codex is symlinked onto the shared volume in main.tf.
ARG CODEX_VERSION=0.155.1
RUN npm install -g @openai/codex@${CODEX_VERSION}

USER coder
