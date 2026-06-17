# Phase 1: Compose Hardening & Configuration - Context

**Gathered:** 2026-06-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Convert the upstream proof-of-concept `compose.yaml` into a production-grade, `.env`-driven deployment: Postgres data on a host-disk bind mount that survives container recreation, a pinned/overridable Coder image, restart policies, a Coder healthcheck, `.env`-sourced secrets and URLs (`CODER_ACCESS_URL` / `CODER_WILDCARD_ACCESS_URL`), and the operator documentation (README) that makes the stack trustworthy to stand up and reach at a real public URL.

**In scope:** SRV-01..05, CFG-01..05, OPS-01..03.
**Out of scope (own phases / v2):** backup & restore scripts (Phase 2), Docker workspace Terraform template (Phase 3), AI/MCP integration (v2), bundled TLS/reverse proxy (external operator responsibility).

</domain>

<decisions>
## Implementation Decisions

### First-admin bootstrap (OPS-02)
- **D-01:** Use Coder's built-in **manual UI first-run** to create the initial admin — operator opens `CODER_ACCESS_URL` in a browser and completes the first-run screen. No env-var autocreate (`CODER_FIRST_USER_*`), so no admin password lives in `.env`.
- **D-02:** No separate manual start-order dance to document. The compose `depends_on: database: condition: service_healthy` already enforces DB-first ordering; the README bootstrap section just covers "bring up → wait for healthy → open URL → create admin."

### Bind-mount permissions (SRV-05, OPS-03)
- **D-03:** Handle the UID 999 ownership requirement as a **documented manual prerequisite** — `sudo chown -R 999:999 ./data/postgres` (or the configured `CODER_PG_DATA_DIR`) run before the first `docker compose up`. No init-container/entrypoint automation.
- **D-04:** Because skipping this is the #1 first-boot failure (Postgres crashes), it MUST be prominent in the README bring-up sequence (OPS-03) — not buried. State the symptom (DB won't initialize) so operators can self-diagnose.

### Reverse-proxy documentation (OPS-01)
- **D-05:** Document the proxy contract in **prose only** — keep the scaffold proxy-agnostic. No bundled or example proxy config files (Caddy/nginx), consistent with the out-of-scope decision to not ship a proxy.
- **D-06:** The prose must be precise enough to implement against any proxy: upstream is HTTP `:7080`; wildcard TLS certificate for `*.<apps-domain>`; preserve the original `Host` header; forward WebSocket upgrade headers; disable response buffering (terminals/logs stream).

### Committed defaults & dev tunnel (CFG-03, CFG-04)
- **D-07:** Keep the committed `CODER_ACCESS_URL=${CODER_ACCESS_URL:-127.0.0.1}` fallback. Preserves the zero-setup Docker quickstart and the stable reference upstream docs/automations depend on. `.env.example` shows the real public-URL placeholder operators should set for production (which auto-disables the `*.try.coder.app` dev tunnel).
- **D-08:** `.env.example` documents `CODER_WILDCARD_ACCESS_URL` (e.g. `*.coder.example.com`) as a placeholder so workspace apps resolve under a wildcard subdomain (CFG-04). Note: do not use a top-level domain (cookie-scope issues).
- **D-09:** Keep the `coder_home` named volume in compose. Harmless in production (Coder recreates what it needs); preserves quickstart convenience. Document it as safe-to-remove in production.
- **D-10:** Leave telemetry at Coder's default (`CODER_TELEMETRY_ENABLE` unset → enabled). Do not force-disable. Operators who care can set it in `.env`.

### Claude's Discretion
- Coder healthcheck mechanism (test command, interval/timeout/retries) — researcher/planner to determine the right readiness probe for the `ghcr.io/coder/coder` image (e.g. against the health endpoint), mirroring the existing Postgres `pg_isready` healthcheck pattern.
- Exact `.env.example` layout, grouping, and comment wording — follow CFG-01 (every variable documented with safe placeholders).
- `restart: unless-stopped` applied to both services (SRV-03); precise placement and any per-service nuance left to planning.
- The configurable bind-mount path variable name/default (`CODER_PG_DATA_DIR`, default `./data/postgres`) per SRV-01.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning docs (this repo)
- `.planning/PROJECT.md` — project scope, core value, key decisions table
- `.planning/REQUIREMENTS.md` §"Server & Persistence", §"Configuration", §"Operations & Documentation" — SRV-01..05, CFG-01..05, OPS-01..03 (the locked requirement set for this phase)
- `.planning/ROADMAP.md` §"Phase 1: Compose Hardening & Configuration" — goal + 5 success criteria
- `.planning/STATE.md` — accumulated decisions and the Phase 1 / Phase 3 blockers/concerns

### Existing artifact to harden
- `compose.yaml` (repo root) — the upstream POC compose file this phase transforms. **Keep the `coder.image` reference (`${CODER_REPO:-...}:${CODER_VERSION:-...}`) overridable and stable** — a comment in the file notes upstream docs/automations depend on it.
- `CLAUDE.md` §"Technology Stack", §"Key Environment Variables", §"Data Persistence", §"What NOT to Use" — pinned versions (Coder `v2.33.8`, Postgres `17`), env-var behavior, bind-mount UID 999 pattern, and anti-patterns (no `:latest`, no named volume for PG data, no PG host port).

### External docs (authoritative, verify at plan/research time)
- `coder.com/docs/install/docker` — baseline compose file and environment-variable documentation
- docker-library/postgres GitHub issues #1010, #26 — UID 999 bind-mount permissions pattern (background for D-03/D-04)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`compose.yaml` Postgres healthcheck** — existing `pg_isready` healthcheck (`interval: 5s`, `timeout: 5s`, `retries: 5`) is a direct pattern to mirror for the new Coder healthcheck (SRV-04).
- **`${VAR:-default}` env interpolation** — already used throughout compose; extend the same pattern to `CODER_PG_DATA_DIR`, `CODER_ACCESS_URL`, `CODER_WILDCARD_ACCESS_URL`, image pin, and PG credentials.
- **`depends_on: condition: service_healthy`** — already wires coder→database; reused for the start-order guarantee that removes the need for a manual bootstrap ordering step (D-02).

### Established Patterns
- Two-service stack (`coder` + `database`) on the default compose network; Coder reaches Postgres by service name `database` (no host port). Preserve this — do NOT expose Postgres on a host port (anti-pattern in CLAUDE.md).
- Image references are pinned-but-overridable; `database` already uses `postgres:17`. `coder` currently defaults to `:latest` — this phase pins it to `v2.33.8` (SRV-02) while keeping `CODER_REPO`/`CODER_VERSION` overrides.

### Integration Points
- Postgres data volume currently a named volume (`coder_data`) → this phase replaces it with a host bind mount at `CODER_PG_DATA_DIR` (default `./data/postgres`) (SRV-01).
- New `.env` / `.env.example` files are introduced here and become the configuration contract that Phase 2 (backup scripts) and Phase 3 (template) read from.

</code_context>

<specifics>
## Specific Ideas

- README should let a new contributor go clone → `cp .env.example .env` → fill values → `chown` → `docker compose up` → open URL → create admin, with every required variable documented and the `chown` step impossible to miss.
- Reverse-proxy section is a *contract*, not a tutorial: list the exact requirements (`:7080`, wildcard TLS, `Host` header, WebSocket upgrade, no buffering) so an operator can configure any proxy correctly.

</specifics>

<deferred>
## Deferred Ideas

- **Init-container / entrypoint automation for bind-mount chown** — considered for SRV-05, rejected in favor of documented manual step (D-03). Could revisit if first-boot failures prove common in practice.
- **Reference proxy config snippets (Caddy/nginx)** — considered for OPS-01, rejected to keep the scaffold proxy-agnostic (D-05). Could be added later as an optional `docs/examples/` aid without bundling a proxy.
- **Env-var admin autocreate (`CODER_FIRST_USER_*`)** — considered for OPS-02, rejected to avoid storing an admin password in `.env` (D-01). Relevant if fully headless/automated provisioning is needed later.
- **Telemetry default-off posture** — considered, left at Coder default (D-10).
- Backup/restore scripts (Phase 2), Docker workspace template (Phase 3), AI/MCP + QoL (v2) — already scoped to their own phases/milestone.

</deferred>

---

*Phase: 1-Compose Hardening & Configuration*
*Context gathered: 2026-06-16*
