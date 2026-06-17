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
USER coder
