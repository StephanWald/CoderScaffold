# templates/java-fullstack/Dockerfile
#
# Universal Java + JavaScript/TypeScript workspace image. Built in-template by
# docker_image.main in main.tf (build { context = path.module }). Layers a
# build-time-selected JDK, Maven, and Node.js LTS on top of the base image.
#
# Build args (set by main.tf from the workspace's coder_parameter values):
#   BASE_IMAGE    — base image (overridable via the workspace_image variable, D-02)
#   JDK           — which JDK to install: adoptium-21 | adoptium-25 | oracle-21 | oracle-25
#   MAVEN_VERSION — pinned Apache Maven version (3.9.x)
#
# Everything is installed SYSTEM-WIDE (/opt, /usr) — NOT under /home/coder, which
# is a persistent Docker volume that shadows anything baked into the user's home
# at runtime. /opt and /usr are outside that mount, so the toolchain survives.
#
# JDK source URLs (both verified to need NO login):
#   Adoptium (Temurin) "latest GA" — api.adoptium.net redirect, per the user's
#     "Adoptium Latest 21/25" requirement (intentionally not pinned to a build).
#   Oracle JDK — download.oracle.com "latest" under the No-Fee Terms (NFTC).
# Because both are "latest" endpoints, a fixed download checksum cannot be pinned
# without defeating the "latest" requirement; the URLs are HTTPS + redirect-followed.

ARG BASE_IMAGE=codercom/enterprise-base:ubuntu
FROM ${BASE_IMAGE}

ARG JDK=adoptium-21
ARG MAVEN_VERSION=3.9.16

# Root for system installs; the base image drops back to the coder user at the end.
USER root

# ── Node.js LTS via NodeSource ───────────────────────────────────────────────
# Provides node + npm/npx on the system PATH for JS/TS development (and the GSD
# install in the agent startup_script). Baked into the layer — no per-boot cost.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends nodejs ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── JDK (build-time selection) ───────────────────────────────────────────────
# Installs the selected JDK to /opt/java/default and registers it as the system
# java/javac via update-alternatives. Architecture is detected at build time so
# the same Dockerfile works on amd64 and arm64 hosts.
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
      oracle-21)   url="https://download.oracle.com/java/21/latest/jdk-21_linux-${jarch}_bin.tar.gz" ;; \
      oracle-25)   url="https://download.oracle.com/java/25/latest/jdk-25_linux-${jarch}_bin.tar.gz" ;; \
      *) echo "ERROR: unknown JDK selection '$JDK'" >&2; exit 1 ;; \
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
