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

USER coder
