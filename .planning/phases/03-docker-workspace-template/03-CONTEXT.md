# Phase 3: Docker Workspace Template - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a Docker-based Terraform workspace template at `templates/docker/` that provisions Coder workspaces as containers on the host (via the mounted Docker socket), wiring in **code-server** (browser VSCode) and **JetBrains Gateway** (IntelliJ IDEA) as workspace apps, with a **persistent `/home`** that survives stop/start and **reliable workspace-agent → access-URL connectivity**.

**In scope:** TPL-01 (Docker Terraform template), TPL-02 (code-server module), TPL-03 (jetbrains-gateway module), TPL-04 (persistent `/home`), TPL-05 (Docker socket GID handling), TPL-06 (agent reaches access URL).
**Out of scope (own phases / v2):** AI/MCP integration — `coder_ai_task`, `claude-code` module, `coder exp mcp`, in-workspace MCP servers (AI-01..04, v2); dotfiles module (QOL-01, v2); backup retention (QOL-02, v2); workspace CPU/memory resource limits (QOL-03, v2). Bundled TLS/reverse proxy stays an external-operator responsibility (Phase 1 contract).

</domain>

<decisions>
## Implementation Decisions

### Workspace base image (TPL-01)
- **D-01:** Workspaces run **`codercom/enterprise-base:ubuntu`** — Coder's prebuilt, batteries-included image (git, build-essential, common runtimes, and the JetBrains/code-server backend dependencies already present). It is what Coder's own Docker template ships, so the code-server and JetBrains Gateway modules connect without extra setup. No custom Dockerfile to maintain in this phase.
- **D-02:** Pin the image to a **specific tag and keep it overridable** via a Terraform variable (mirrors Phase 1's pinned-but-overridable image ethos — `CODER_REPO`/`CODER_VERSION`). Default is fixed for reproducibility; operators can override.

### Create-workspace form (TPL-01)
- **D-03:** The create-workspace form is **bare — no `coder_parameter` blocks.** The developer clicks "Create" and gets a working workspace. Simplest MVP slice, least to verify, and consistent with the deferred-QoL posture (no CPU/memory knobs — QOL-03 is v2).
- **D-04:** Consequence of D-03: the **workspace image and the IDE are fixed in the template**, not developer-selectable at create time. (Image choice / IDE choice / git-repo-clone / dotfiles-URL parameters were all considered and declined for the MVP — see Deferred Ideas.)

### Editors / IDEs (TPL-02, TPL-03)
- **D-05:** Wire **code-server** (browser VSCode) via the `coder/code-server` module (`1.5.0`) as a workspace app — TPL-02 is locked.
- **D-06:** Wire **JetBrains Gateway for IntelliJ IDEA only** via the `coder/jetbrains-gateway` module (`1.2.6`) — IntelliJ is the sole offering and the default. Matches the roadmap wording and SC-3 exactly; keeps the verification surface tight. (Full suite / multi-IDE picker declined — see Deferred Ideas.)

### Persistent home (TPL-04)
- **D-07:** Persist `/home/coder` via a **per-workspace Docker volume** keyed to the workspace (the canonical Coder Docker-template pattern): the container is ephemeral and recreated on start, the home volume survives stop/start. Files created before a stop are present after restart (SC-4).

### Docker socket GID (TPL-05)
- **D-08:** Handle the host Docker-socket GID as an **operator-resolved concern via a commented block + README docs**, mirroring Phase 1's existing `#group_add: - "998"` pattern in `compose.yaml`. The template/docs make the `group_add` / GID handling discoverable so operators can fix socket-permission failures; the GID is not hardcoded (it varies by host distro — STATE.md blocker).

### Agent connectivity (TPL-06)
- **D-09:** **Bake `extra_hosts = ["host.docker.internal:host-gateway"]` into the workspace container by default** so `host.docker.internal` resolves on Linux Docker hosts out-of-the-box (zero-config for the local/single-host case — directly closes the flagged TPL-06 blocker).
- **D-10:** **Also document the production path:** operators who set a real reachable `CODER_ACCESS_URL` (IP/domain) don't depend on `host-gateway`. README/template prose explains which mechanism applies when, so both the local quickstart and a real public-URL deployment connect reliably.

### Claude's Discretion
- Exact `templates/docker/` file layout and `main.tf` structure (required-providers block, `coder_agent`, `coder_app`, `docker_container`, `docker_volume`, `docker_image` resources).
- Precise Terraform variable name/default for the overridable image (D-02), and the per-workspace home-volume naming scheme (D-07).
- code-server module configuration details (default folder opened, version, any settings) within TPL-02.
- How the workspace agent startup script and metadata are wired, and the exact `coder_agent` env/connectivity plumbing, per the pinned `coder/coder ~> 2.18` provider.
- Whether the Docker socket GID is surfaced as a commented Terraform locals/variable vs README-only note — implementation detail of D-08, as long as it stays operator-resolved and non-hardcoded.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning docs (this repo)
- `.planning/PROJECT.md` — project scope, core value, Key Decisions table (incl. "Include Docker workspace template with VSCode + IntelliJ")
- `.planning/REQUIREMENTS.md` §"Workspace Template" — TPL-01..06, the locked requirement set for this phase (and §"v2 Requirements" for the deferred AI/MCP + QoL items that bound scope)
- `.planning/ROADMAP.md` §"Phase 3: Docker Workspace Template" — goal + 5 success criteria
- `.planning/STATE.md` — accumulated decisions and the two Phase 3 blockers/concerns (Docker socket GID varies by host → D-08; `host.docker.internal` handling → D-09/D-10)
- `.planning/phases/01-compose-hardening-configuration/01-CONTEXT.md` — Phase 1 decisions that establish the `.env` config contract and the "documented manual step + commented compose block" pattern reused here for D-08

### Pinned stack & anti-patterns (authoritative)
- `CLAUDE.md` §"Recommended Stack" / §"Coder Registry Modules" / §"Version Compatibility Matrix" — pinned versions: `kreuzwerker/docker ~> 4.4`, `coder/coder ~> 2.18`, `coder/code-server 1.5.0`, `coder/jetbrains-gateway 1.2.6`, Terraform `>= 1.9`. **Use these exact pins.**
- `CLAUDE.md` §"What NOT to Use" / §"Alternatives Considered" — e.g. use `kreuzwerker/docker` not `hashicorp/docker`; jetbrains-**gateway** not jetbrains (Toolbox); do NOT pull AI/MCP wiring (`coder/claude-code`, `coder_ai_task`) into this phase (v2).
- `CLAUDE.md` §"Terraform Workspace Template Structure" — required-providers block, core resources, module wiring guidance.

### Existing artifacts to integrate with
- `compose.yaml` (repo root) — the running Coder server this template provisions against. Note the existing **commented `#group_add: - "998"` block** (the GID pattern D-08 mirrors), the mounted `/var/run/docker.sock`, and `CODER_ACCESS_URL` / `CODER_WILDCARD_ACCESS_URL` env wiring the workspace agent depends on (TPL-06).
- `.env.example` / `.env` — the configuration contract from Phase 1; any new operator-facing template knobs should follow the same `${VAR:-default}` documented-placeholder convention.

### External docs (authoritative — verify at research/plan time)
- `registry.coder.com` modules `coder/code-server`, `coder/jetbrains-gateway` — module inputs, source, and version constraints
- `coder.com/docs/install/docker` — the upstream Docker workspace template this phase is modeled on (base image, `docker_volume` home-persistence pattern, `host.docker.internal` handling)
- `kreuzwerker/terraform-provider-docker` (`~> 4.4`) docs — `docker_container` `host` / `extra_hosts` (for D-09 `host-gateway`), `docker_volume`, `docker_image`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`compose.yaml` `#group_add: - "998"` commented block** — the exact operator-resolved Docker-socket-GID pattern to mirror for TPL-05 (D-08). Reuse the "commented default + README docs" approach rather than inventing a new mechanism.
- **`${VAR:-default}` env-interpolation + `.env`/`.env.example` contract** (Phase 1) — extend the same documented-placeholder convention to any new template-facing config (e.g. the overridable image variable D-02).
- **Phase 1 "documented manual prerequisite" pattern** (`01-CONTEXT.md` D-03/D-04) — the template for how to surface an operator-resolved step (GID, connectivity) prominently in docs.

### Established Patterns
- Two-service compose stack with the Coder server mounting `/var/run/docker.sock` to provision workspaces as host containers — this template is the consumer of that socket mount. Single Docker host only (PROJECT.md constraint).
- Pinned-but-overridable image references (Phase 1 pinned `coder` to `v2.33.8`) — D-02 applies the same discipline to the workspace base image.

### Integration Points
- New directory `templates/docker/` (does not exist yet — confirmed: repo has `backups/`, `scripts/`, `data/`, `compose.yaml`, `README.md`, `CLAUDE.md`; no `templates/`).
- Workspace agent → `CODER_ACCESS_URL` (set in `compose.yaml` / `.env`) is the connectivity contract TPL-06 (D-09/D-10) must satisfy; `CODER_WILDCARD_ACCESS_URL` is what makes the code-server/JetBrains app URLs resolve under the wildcard subdomain (SC-1).
- README (from Phase 1) is the home for the new operator docs (socket GID, connectivity, "create a workspace from the template") — extend it rather than starting a separate doc.

</code_context>

<specifics>
## Specific Ideas

- Optimize for a **zero-config local "create → Connected → open VSCode / open IntelliJ → files persist"** happy path, while keeping a documented production path for real `CODER_ACCESS_URL` deployments (D-09 + D-10).
- Keep the MVP slice deliberately thin: one base image, one IDE (IntelliJ), no create-form parameters — so all 5 Phase 3 success criteria are cleanly verifiable.

</specifics>

<deferred>
## Deferred Ideas

- **Git-repo-to-clone `coder_parameter`** — considered for the create-form, declined for the bare-form MVP (D-03). Easy future add.
- **Dotfiles URL `coder_parameter`** — declined; overlaps QOL-01 (dotfiles module, v2).
- **Developer-selectable image / IDE at create time** — declined (D-04); image and IDE are fixed in the template for the MVP.
- **Additional JetBrains IDEs (PyCharm, GoLand, full suite)** — declined (D-06); IntelliJ only matches the roadmap. Adding more is a config change to the jetbrains-gateway module later.
- **Workspace CPU/memory resource limits (QOL-03)**, **backup retention (QOL-02)**, **AI/MCP wiring (AI-01..04)** — already scoped to v2; do not pull into this phase.

</deferred>

---

*Phase: 3-Docker Workspace Template*
*Context gathered: 2026-06-17*
