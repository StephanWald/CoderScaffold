# templates/bbj-services/Dockerfile
#
# BBjServices workspace image. Forked from templates/java-fullstack/Dockerfile.
# Layers a build-time-selected Adoptium JDK, Maven, and Node.js on top of the
# base image, then bakes in the BasisHub BBj silent install from the operator-
# supplied build context (BBj*.jar + certificate.bls + this file + playback.properties).
#
# MULTI-STAGE (space cleanup): the ~1.25 GB BBj installer jar is ADDed and run in
# the throwaway `bbjinstall` stage. The `final` stage only COPYs the installed
# /opt/bbx tree, so the runtime image never carries the jar. (A plain `rm` after
# ADD would only whiteout the jar, not reclaim its space.) Multi-stage builds work
# on both the legacy and BuildKit builders — unlike RUN --mount — so this is safe
# for the kreuzwerker Terraform provider's in-template build as well as the CLI
# pre-warm script.
#
# Build args (set by main.tf from the selected BBj stack combo and template variables):
#   BASE_IMAGE      — base image (overridable via workspace_image variable)
#   JDK             — which JDK to install: adoptium-21 | adoptium-25 (derived from combo)
#   BBJ_JAR_NAME    — named BBj installer jar filename staged in the asset folder (derived from combo)
#   MAVEN_VERSION   — pinned Apache Maven version (3.9.x)
#   LICENSE_SERVER  — BLS license server host:port, sed'd into playback.properties
#
# IMPORTANT: This Dockerfile is version-controlled in the template but is built
# from the operator-supplied host context folder (BBJ_ASSETS_PATH / /mnt/bbj-assets).
# The operator MUST ship this file and playback.properties into that context folder
# alongside BBj*.jar and certificate.bls — see the README for setup instructions.
#
# BBjServices is NOT launched here. The Coder agent init_script is the container
# entrypoint; BBjServices is started by the agent startup_script in the background.
# Baking a service launch command into this image would conflict with the agent
# entrypoint pattern and prevent editors/SSH from attaching.
#
# Everything is installed SYSTEM-WIDE (/opt, /usr) — NOT under /home/coder, which
# is a persistent Docker volume that shadows anything baked into the user's home
# at runtime. /opt and /usr are outside that mount, so the toolchain survives.

ARG BASE_IMAGE=codercom/enterprise-base:ubuntu

# ════════════════════════════════════════════════════════════════════════════
# Stage: base — shared toolchain (JDK + Node.js + Maven + MemPalace + SSH).
# Both the BBj install stage and the final runtime image derive from this, so the
# toolchain layers are built once and shared (the final image reuses them).
# ════════════════════════════════════════════════════════════════════════════
FROM ${BASE_IMAGE} AS base

ARG JDK=adoptium-21
ARG MAVEN_VERSION=3.9.16

# Root for system installs; the final stage drops back to the coder user at the end.
USER root

# ── Node.js LTS via NodeSource ───────────────────────────────────────────────
# Provides node + npm/npx on the system PATH for JS/TS development (and the GSD
# install in the agent startup_script). Baked into the layer — no per-boot cost.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends nodejs ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── JDK (build-time selection, Adoptium only) ────────────────────────────────
# Installs the selected Adoptium JDK to /opt/java/default and registers it as
# the system java/javac via update-alternatives. Architecture is detected at
# build time so the same Dockerfile works on amd64 and arm64 hosts.
# Only adoptium-21 and adoptium-25 are supported — the BBj installer requires
# Adoptium; the playback.properties points INSTALL_JAVA_DIRECTORY_NON_WIN at
# /opt/java/default (this path).
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) jarch=x64 ;; \
      arm64) jarch=aarch64 ;; \
      *) echo "ERROR: unsupported architecture '$arch'" >&2; exit 1 ;; \
    esac; \
    case "$JDK" in \
      adoptium-21) url="https://api.adoptium.net/v3/binary/latest/21/ga/linux/${jarch}/jdk/hotspot/normal/eclipse" ;; \
      adoptium-25) url="https://api.adoptium.net/v3/binary/latest/25/ga/linux/${jarch}/jdk/hotspot/normal/eclipse" ;; \
      *) echo "ERROR: unknown JDK selection '$JDK' (only adoptium-21 and adoptium-25 are supported)" >&2; exit 1 ;; \
    esac; \
    echo "Installing JDK '$JDK' for '$arch' from: $url"; \
    mkdir -p /opt/java/default; \
    curl -fsSL "$url" -o /tmp/jdk.tar.gz; \
    tar -xzf /tmp/jdk.tar.gz -C /opt/java/default --strip-components=1; \
    rm -f /tmp/jdk.tar.gz; \
    test -x /opt/java/default/bin/java; \
    update-alternatives --install /usr/bin/java  java  /opt/java/default/bin/java  100; \
    update-alternatives --install /usr/bin/javac javac /opt/java/default/bin/javac 100; \
    /opt/java/default/bin/java -version

# ── Apache Maven (pinned) ────────────────────────────────────────────────────
# Pulled from archive.apache.org (retains every release, unlike the dlcdn mirror
# which only keeps the current one) so the pinned version is always resolvable.
RUN set -eux; \
    curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tar.gz; \
    mkdir -p /opt/maven; \
    tar -xzf /tmp/maven.tar.gz -C /opt/maven --strip-components=1; \
    rm -f /tmp/maven.tar.gz; \
    ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn; \
    test -x /opt/maven/bin/mvn

# ── System-wide JAVA_HOME / MAVEN_HOME for login shells ──────────────────────
# update-alternatives already puts java/javac on PATH and mvn is symlinked into
# /usr/local/bin; this profile script exports JAVA_HOME/MAVEN_HOME for tools that
# read them. main.tf also sets JAVA_HOME/MAVEN_HOME in the agent env for parity
# in non-login shells.
RUN printf '%s\n' \
      'export JAVA_HOME=/opt/java/default' \
      'export MAVEN_HOME=/opt/maven' \
      'export PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"' \
      > /etc/profile.d/10-java-maven.sh \
 && chmod 0644 /etc/profile.d/10-java-maven.sh

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

# ── ext4 casefold tooling (e2fsprogs + util-linux) ───────────────────────────
# These packages are only exercised when a workspace opts into the
# case_insensitive_project parameter (see main.tf): the agent startup_script
# creates a sparse ext4 loopback image with casefold support and loop-mounts it
# at the project folder before the git clone, giving case-insensitive filename
# lookups for Windows-origin codebases (CarIT et al.) on Linux.
#
#   e2fsprogs   — provides mkfs.ext4 (with -O casefold / -E encoding=utf8 support,
#                 requires >= 1.43) and chattr (sets the +F casefold flag on dirs).
#                 The codercom/enterprise-base:ubuntu base image likely ships a
#                 recent e2fsprogs already, but this block guarantees both presence
#                 and a version new enough to carry casefold support.
#   util-linux  — provides mount and losetup (required by sudo mount -o loop for the
#                 loopback device setup).
#
# Both tools are installed SYSTEM-WIDE via apt into /usr (outside the volume-
# shadowed /home/coder), so they are available on every workspace start at no
# per-boot cost.
RUN apt-get update \
 && apt-get install -y --no-install-recommends e2fsprogs util-linux \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ════════════════════════════════════════════════════════════════════════════
# Stage: bbjinstall — run the BBj silent install. The ~1.25 GB installer jar is
# ADDed HERE and never reaches the final image (this whole stage is discarded).
# ════════════════════════════════════════════════════════════════════════════
FROM base AS bbjinstall

# The build context is the operator-supplied host folder (BBJ_ASSETS_PATH /
# /mnt/bbj-assets). The operator must place BBj*.jar + certificate.bls + this
# Dockerfile + playback.properties into that folder before building.
COPY playback.properties /tmp/playback.properties
ARG BBJ_JAR_NAME=BBj.jar
COPY ${BBJ_JAR_NAME} /tmp/BBj.jar
COPY certificate.bls /tmp/certificate.bls

ARG LICENSE_SERVER
# Fail loud (in the build log) if the BLS server is empty — otherwise the sed
# replaces the placeholder with nothing, BLS_DESIGNATION_SERVERNAME= is left blank,
# and BBjServices reports "No license servers are configured" at runtime with no
# obvious cause. The value flows: .env BBJ_LICENSE_SERVER → coder templates push
# --variable bbj_license_server → var.bbj_license_server → this LICENSE_SERVER arg.
RUN if [ -z "${LICENSE_SERVER}" ]; then \
      echo "WARNING: LICENSE_SERVER build-arg is EMPTY — BBjServices will have NO BLS server configured (runtime: 'No license servers are configured'). Set BBJ_LICENSE_SERVER in .env and push with --variable bbj_license_server=host[:port]." >&2; \
    fi; \
    sed -i "s/LICENSE_SERVER_PLACEHOLDER/${LICENSE_SERVER}/g" /tmp/playback.properties

# BBj is installed silently (-p playback.properties) using the vfork launch
# mechanism required for Docker build environments.
RUN java -Djdk.lang.Process.launchMechanism=vfork -jar /tmp/BBj.jar -p /tmp/playback.properties

# Post-install configuration: set vfork launch mechanism in BBj.properties,
# disable the admin user warning, set web user to root, and clean up build
# artifacts so the /opt/bbx copied into the final stage is already trimmed.
RUN sed -i 's|^com.basis.startup.args=.*|com.basis.startup.args=-Djdk.lang.Process.launchMechanism=vfork|' /opt/bbx/cfg/BBj.properties \
 && sed -i 's|^defaultAdminUserWarning=.*|defaultAdminUserWarning=false|' /opt/bbx/cfg/BBj.properties \
 && sed -i 's|^webUser=.*|webUser=root|' /opt/bbx/cfg/BBj.properties \
 && umask 0 \
 && rm -rf /opt/bbx/log/* \
           /opt/bbx/cache/* \
           /opt/bbx/lib/libnative-foreign*.so \
           /opt/bbx/documentation \
           /opt/bbx/lib/aws-java-sdk-*.jar \
           /opt/bbx/lib/BBjTextSearch*.jar

# ════════════════════════════════════════════════════════════════════════════
# Stage: final — runtime image. Copies ONLY the installed /opt/bbx from the
# bbjinstall stage; the installer jar stays behind and is discarded.
# ════════════════════════════════════════════════════════════════════════════
FROM base AS final

# COPY --from preserves the full tree, including hidden dirs like /opt/bbx/.lib
# (BBjStartup.jar + native libraries). Files land root-owned, matching the
# install (BBjServices is launched as root via sudo from the agent startup_script).
COPY --from=bbjinstall /opt/bbx /opt/bbx

EXPOSE 8888

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

# ── Playwright chromium + OS deps ────────────────────────────────────────────
# Bakes the chromium browser AND its shared libs (libnss3, libatk, ...) so the
# Playwright MCP server (registered in the agent startup_script) can drive a
# headless browser for self-serve UI testing. Done at build time so workspace
# boot has zero per-start cost. --with-deps pulls the apt libraries.
# Runs in the final stage (inherits Node.js/npx from the base stage via FROM base AS final).
#
# PLAYWRIGHT_BROWSERS_PATH pins the browser to a world-readable SYSTEM path
# instead of the installing user's ~/.cache. This layer runs as root, but the
# workspace runs as `coder` with a volume-mounted $HOME — a browser left under
# /root/.cache would be invisible to the runtime user. ENV persists into the
# running container, so the `coder`-user `npx @playwright/mcp` inherits the same
# path and finds the baked browser; chmod o+rX keeps it readable/executable for
# the non-root runtime user.
# NOTE: the baked chromium revision is the one shipped with `playwright@latest`
# at BUILD time; if a much newer @playwright/mcp is fetched at runtime it may
# expect a different revision and try to re-download into this path. Rebuild the
# image to refresh, or pin both to matching versions if drift becomes an issue.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx -y playwright@latest install --with-deps chromium \
 && chmod -R o+rX /ms-playwright

USER coder
