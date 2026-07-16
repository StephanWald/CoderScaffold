# templates/coderscaffold/Dockerfile
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
#
# Note: git is required by the startup_script clone step (git clone
# StephanWald/CoderScaffold). git ships pre-installed in codercom/enterprise-base:ubuntu,
# so no additional apt install is needed here.

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

USER coder
