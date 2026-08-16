# templates/python-ai/Dockerfile
#
# Python / AI workspace image. Built in-template by docker_image.main in main.tf
# (build { context = path.module }). Layers a build-time-selected CPython (via uv),
# Python dev tools, AI SDKs, JupyterLab, and Node.js LTS on top of the base image.
#
# Build args (set by main.tf from the workspace's coder_parameter values):
#   BASE_IMAGE     — base image (overridable via the workspace_image variable, D-02)
#   PYTHON_VERSION — which CPython to install: 3.13 | 3.12 | 3.11 (default 3.13)
#
# Everything is installed SYSTEM-WIDE (/opt, /usr) — NOT under /home/coder, which
# is a persistent Docker volume that shadows anything baked into the user's home
# at runtime. /opt and /usr are outside that mount, so the toolchain survives.

ARG BASE_IMAGE=codercom/enterprise-base:ubuntu
FROM ${BASE_IMAGE}

ARG PYTHON_VERSION=3.13

# Root for system installs; the base image drops back to the coder user at the end.
USER root

# ── Node.js LTS via NodeSource ───────────────────────────────────────────────
# Provides node + npm/npx on the system PATH (needed for Claude Code CLI, GSD,
# and the node JSON merges in startup_script). Baked into the layer — no per-boot cost.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends nodejs ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── uv (Astral) — system-wide Python toolchain manager ───────────────────────
# Installs the standalone uv + uvx binaries to /usr/local/bin so all users get
# them on PATH. UV_PYTHON_INSTALL_DIR, UV_TOOL_DIR, UV_TOOL_BIN_DIR are set to
# /opt/* so neither managed Pythons nor tool shims touch /home/coder.
# main.tf also exports these same vars in the agent env for non-login-shell parity.
RUN set -eux; \
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/uv-install.sh; \
    UV_INSTALL_DIR=/usr/local/bin sh /tmp/uv-install.sh --no-modify-path; \
    rm -f /tmp/uv-install.sh; \
    uv --version; \
    command -v uvx

# ── System-wide uv env for login shells ──────────────────────────────────────
# Exports the uv install dirs so login shells pick up the same paths.
# main.tf mirrors these in the coder_agent env for non-login-shell parity.
RUN printf '%s\n' \
      'export UV_PYTHON_INSTALL_DIR=/opt/uv-python' \
      'export UV_TOOL_DIR=/opt/uv-tools' \
      'export UV_TOOL_BIN_DIR=/usr/local/bin' \
      'export PATH="/usr/local/bin:$PATH"' \
      > /etc/profile.d/10-uv.sh \
 && chmod 0644 /etc/profile.d/10-uv.sh

# ── CPython (build-arg version) via uv — system-wide ─────────────────────────
# Installs the selected CPython into /opt/uv-python (outside the home volume),
# then symlinks python3 and python in /usr/local/bin so the selected version is
# the default interpreter for all users regardless of shell type.
RUN set -eux; \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python uv python install "${PYTHON_VERSION}"; \
    PY_BIN=$(UV_PYTHON_INSTALL_DIR=/opt/uv-python uv python find "${PYTHON_VERSION}"); \
    ln -sf "${PY_BIN}" /usr/local/bin/python3; \
    ln -sf "${PY_BIN}" /usr/local/bin/python; \
    python --version

# ── Python dev tooling via uv tool — system-wide shims ───────────────────────
# ruff (linter/formatter), mypy (type checker), pytest (test runner), ipython
# (interactive REPL) are installed into /opt/uv-tools with shims in /usr/local/bin.
# All land OUTSIDE /home/coder so the persistent home volume never shadows them.
RUN set -eux; \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install ruff; \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install mypy; \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install pytest; \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install ipython; \
    command -v ruff mypy pytest ipython

# ── AI SDKs — importable from the default python ─────────────────────────────
# Installs anthropic + claude-agent-sdk into the uv-managed CPython created above
# (the same interpreter /usr/local/bin/python points to) so `python -c "import
# anthropic, claude_agent_sdk"` succeeds in a fresh login shell with no venv
# activation. Uses uv pip --python to target the exact interpreter; does NOT
# --system into the base image's own Python. --break-system-packages is required:
# uv-managed CPythons ship an EXTERNALLY-MANAGED marker and uv refuses to install
# into them otherwise (live-verified failure without it, exit code 2).
RUN set -eux; \
    uv pip install --break-system-packages --python /usr/local/bin/python anthropic claude-agent-sdk; \
    python -c "import anthropic; import claude_agent_sdk; print('AI SDK import OK')"

# ── JupyterLab ───────────────────────────────────────────────────────────────
# Installed as a uv tool (shim in /usr/local/bin) so `jupyter lab` is available
# system-wide. Launched via the JupyterLab module (or coder_app fallback) in main.tf.
# uv tool install only exposes jupyterlab's own executables (jupyter-lab,
# jupyter-labextension, jupyter-labhub) — the bare `jupyter` launcher belongs to
# the jupyter-core dependency and gets no shim, so link it from the tool venv.
RUN set -eux; \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install jupyterlab; \
    ln -sf /opt/uv-tools/jupyterlab/bin/jupyter /usr/local/bin/jupyter; \
    jupyter --version; \
    command -v jupyter-lab

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

# ── PostgreSQL + pgvector ─────────────────────────────────────────────────────
# Docker-in-Docker is structurally unusable inside this workspace container
# (live-probed: `iptables -t nat -N DOCKER` -> Permission denied, `unshare:
# operation not permitted` — no NET_ADMIN, no namespace creation), so Postgres
# cannot run as a nested container. It is baked here and started by the agent
# (see main.tf startup_script) with PGDATA on the persistent /home/coder volume
# — NOT the Debian-managed cluster below, which lives in the container layer
# and would be wiped on every workspace restart. The default cluster is dropped
# immediately after install so nobody mistakes it for the live database.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql postgresql-contrib; \
    PG_MAJOR="$(ls /usr/lib/postgresql | sort -V | tail -1)"; \
    apt-get install -y --no-install-recommends "postgresql-$PG_MAJOR-pgvector"; \
    pg_dropcluster --stop "$PG_MAJOR" main 2>/dev/null || true; \
    install -d -o coder -g coder -m 0775 /var/run/postgresql; \
    printf '%s\n' \
      'export PGDATA=/home/coder/.pgdata' \
      'export DATABASE_URL=postgresql://coder@localhost:5432/coder' \
      > /etc/profile.d/20-postgres.sh; \
    printf 'export PATH="/usr/lib/postgresql/%s/bin:$PATH"\n' "$PG_MAJOR" \
      >> /etc/profile.d/20-postgres.sh; \
    chmod 0644 /etc/profile.d/20-postgres.sh; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    "/usr/lib/postgresql/$PG_MAJOR/bin/initdb" --version

# ── Docker CLI + Compose plugin (docker-outside-of-docker) ───────────────────
# This is docker-OUTSIDE-of-docker (DooD): the Docker CLI and Compose plugin
# installed here talk to the HOST Docker daemon via the socket mounted by main.tf
# (/var/run/docker.sock bind-mount). A nested engine is NOT installed and would
# NOT work — see the PostgreSQL block above for why (no NET_ADMIN, no namespace
# creation inside this workspace container). The socket mount means:
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
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.gpg \
 && chmod go+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

USER coder
