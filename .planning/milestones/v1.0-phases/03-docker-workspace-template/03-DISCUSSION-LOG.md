# Phase 3: Docker Workspace Template - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 3-Docker Workspace Template
**Areas discussed:** Workspace base image, Create-form parameters, JetBrains IDE offering, Agent connectivity (TPL-06)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Workspace base image | Prebuilt vs custom Dockerfile vs minimal | ✓ |
| Create-form parameters | What `coder_parameter` knobs the developer sees | ✓ |
| JetBrains IDE offering | IntelliJ only vs multi-IDE vs full suite | ✓ |
| Agent connectivity (TPL-06) | host-gateway vs documented CODER_ACCESS_URL | ✓ |

**User's choice:** All four areas selected for discussion.

---

## Workspace base image

| Option | Description | Selected |
|--------|-------------|----------|
| codercom/enterprise-base:ubuntu | Coder's prebuilt batteries-included image; git/build tools + JetBrains/code-server backend deps present; what Coder's own Docker template ships | ✓ |
| Custom Dockerfile in template | Commit a Dockerfile under templates/docker/ for full control; more to maintain | |
| Minimal image | Smallest footprint; developers add tools; JetBrains Gateway may need extra deps | |

**User's choice:** codercom/enterprise-base:ubuntu
**Notes:** Fastest path to a working IntelliJ + VSCode session with no Dockerfile to maintain. Claude to pin the tag and keep it overridable via a Terraform variable (mirrors Phase 1's pinned-but-overridable image ethos).

---

## Create-form parameters

| Option | Description | Selected |
|--------|-------------|----------|
| Bare form (no parameters) | No coder_parameter blocks; developer clicks Create and gets a working workspace | ✓ |
| Git repo to clone | coder_parameter for an optional repo URL cloned into /home/coder | |
| Dotfiles URL | coder_parameter for a personal dotfiles repo (overlaps QOL-01, v2) | |
| Image / IDE choice | Let the developer pick image or JetBrains IDE at create time | |

**User's choice:** Bare form (no parameters)
**Notes:** Minimal MVP slice — least to verify, consistent with deferred-QoL posture (CPU/memory limits are QOL-03, v2). Consequence: workspace image and IDE are fixed in the template, not developer-selectable.

---

## JetBrains IDE offering

| Option | Description | Selected |
|--------|-------------|----------|
| IntelliJ IDEA only | Matches roadmap wording and SC-3; one IDE, least to verify | ✓ |
| IntelliJ + a couple common IDEs | IntelliJ + e.g. PyCharm/GoLand, IntelliJ default | |
| Full JetBrains suite | All module-supported IDEs, IntelliJ default; heaviest to validate | |

**User's choice:** IntelliJ IDEA only
**Notes:** Sole offering and default. Keeps verification tight and matches the roadmap. code-server/VSCode remains wired separately per TPL-02.

---

## Agent connectivity (TPL-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Bake in host-gateway by default | extra_hosts = host.docker.internal:host-gateway on the workspace container; zero-config on Linux | |
| Document CODER_ACCESS_URL only | No extra_hosts; rely on operator setting a reachable CODER_ACCESS_URL | |
| Both: host-gateway default + docs | Bake in host-gateway AND document the production CODER_ACCESS_URL path | ✓ |

**User's choice:** Both — host-gateway default + docs
**Notes:** Most robust. Closes the flagged TPL-06 blocker for the local/single-host case out-of-the-box, while documenting the production path for operators with a real reachable CODER_ACCESS_URL.

---

## Claude's Discretion

- `templates/docker/` file layout and `main.tf` structure (required-providers, coder_agent, coder_app, docker_container/volume/image resources).
- Terraform variable name/default for the overridable base image; per-workspace home-volume naming scheme.
- code-server module config details (default folder, version, settings).
- Workspace agent startup script and `coder_agent` env/connectivity plumbing.
- Whether the Docker-socket GID is surfaced as a commented Terraform local/variable vs README-only note (stays operator-resolved, non-hardcoded).
- Canonical per-workspace `/home/coder` Docker volume for persistence (TPL-04); commented-block + docs pattern for Docker-socket GID (TPL-05), mirroring Phase 1.

## Deferred Ideas

- Git-repo-to-clone coder_parameter — declined for bare-form MVP.
- Dotfiles URL coder_parameter — declined (overlaps QOL-01, v2).
- Developer-selectable image / IDE at create time — declined; fixed in template.
- Additional JetBrains IDEs (PyCharm, GoLand, full suite) — declined; IntelliJ only.
- Workspace CPU/memory resource limits (QOL-03), backup retention (QOL-02), AI/MCP wiring (AI-01..04) — already scoped to v2.
