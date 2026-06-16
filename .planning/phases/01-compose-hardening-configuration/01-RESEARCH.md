# Phase 1: Compose Hardening & Configuration - Research

**Researched:** 2026-06-16
**Domain:** Docker Compose, Coder server, PostgreSQL bind-mount persistence, environment-variable configuration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Use Coder's built-in manual UI first-run to create the initial admin — operator opens `CODER_ACCESS_URL` in a browser and completes the first-run screen. No env-var autocreate (`CODER_FIRST_USER_*`), so no admin password lives in `.env`.

**D-02:** No separate manual start-order dance to document. The compose `depends_on: database: condition: service_healthy` already enforces DB-first ordering; the README bootstrap section just covers "bring up → wait for healthy → open URL → create admin."

**D-03:** Handle the UID 999 ownership requirement as a documented manual prerequisite — `sudo chown -R 999:999 ./data/postgres` (or the configured `CODER_PG_DATA_DIR`) run before the first `docker compose up`. No init-container/entrypoint automation.

**D-04:** Because skipping this is the #1 first-boot failure (Postgres crashes), it MUST be prominent in the README bring-up sequence (OPS-03) — not buried. State the symptom (DB won't initialize) so operators can self-diagnose.

**D-05:** Document the proxy contract in prose only — keep the scaffold proxy-agnostic. No bundled or example proxy config files (Caddy/nginx), consistent with the out-of-scope decision to not ship a proxy.

**D-06:** The prose must be precise enough to implement against any proxy: upstream is HTTP `:7080`; wildcard TLS certificate for `*.<apps-domain>`; preserve the original `Host` header; forward WebSocket upgrade headers; disable response buffering (terminals/logs stream).

**D-07:** Keep the committed `CODER_ACCESS_URL=${CODER_ACCESS_URL:-127.0.0.1}` fallback. Preserves the zero-setup Docker quickstart and the stable reference upstream docs/automations depend on. `.env.example` shows the real public-URL placeholder operators should set for production (which auto-disables the `*.try.coder.app` dev tunnel).

**D-08:** `.env.example` documents `CODER_WILDCARD_ACCESS_URL` (e.g. `*.coder.example.com`) as a placeholder so workspace apps resolve under a wildcard subdomain (CFG-04). Note: do not use a top-level domain (cookie-scope issues).

**D-09:** Keep the `coder_home` named volume in compose. Harmless in production (Coder recreates what it needs); preserves quickstart convenience. Document it as safe-to-remove in production.

**D-10:** Leave telemetry at Coder's default (`CODER_TELEMETRY_ENABLE` unset → enabled). Do not force-disable. Operators who care can set it in `.env`.

### Claude's Discretion

- Coder healthcheck mechanism (test command, interval/timeout/retries) — researcher/planner to determine the right readiness probe for the `ghcr.io/coder/coder` image (e.g. against the health endpoint), mirroring the existing Postgres `pg_isready` healthcheck pattern.
- Exact `.env.example` layout, grouping, and comment wording — follow CFG-01 (every variable documented with safe placeholders).
- `restart: unless-stopped` applied to both services (SRV-03); precise placement and any per-service nuance left to planning.
- The configurable bind-mount path variable name/default (`CODER_PG_DATA_DIR`, default `./data/postgres`) per SRV-01.

### Deferred Ideas (OUT OF SCOPE)

- Init-container / entrypoint automation for bind-mount chown
- Reference proxy config snippets (Caddy/nginx)
- Env-var admin autocreate (`CODER_FIRST_USER_*`)
- Telemetry default-off posture
- Backup/restore scripts (Phase 2), Docker workspace template (Phase 3), AI/MCP + QoL (v2)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRV-01 | Postgres data persists on host-disk bind mount at configurable path (`CODER_PG_DATA_DIR`, default `./data/postgres`) | Bind-mount pattern, UID 999 requirements, compose volume syntax confirmed |
| SRV-02 | Coder image pinned to `ghcr.io/coder/coder:v2.33.8`, overridable via `CODER_REPO`/`CODER_VERSION` | Existing compose pattern already uses `${CODER_REPO:-...}:${CODER_VERSION:-...}` — just change default value |
| SRV-03 | Both services declare `restart: unless-stopped` | Docker Compose restart policy behavior confirmed; reboot behavior documented with caveat |
| SRV-04 | Coder server has a healthcheck for `depends_on` and operator readiness detection | `/healthz` endpoint confirmed; curl available in Alpine image; parameters researched |
| SRV-05 | Operator can set Postgres bind-mount ownership to UID 999 (documented pre-`up` chown step) | UID 999 confirmed for `postgres:17`; failure symptom documented |
| CFG-01 | Committed `.env.example` documents every variable with safe placeholder values | Layout and grouping designed; all variables identified |
| CFG-02 | Local `.env` (gitignored) supplies real config and secrets to compose | `.gitignore` creation needed; Docker Compose auto-loads `.env` from project directory |
| CFG-03 | `CODER_ACCESS_URL` set from `.env` to public-facing URL, disabling dev tunnel | Confirmed: setting a real access URL disables `*.try.coder.app` tunnel |
| CFG-04 | `CODER_WILDCARD_ACCESS_URL` set from `.env` so workspace apps resolve under wildcard subdomain | Confirmed; cookie-scope warning (no top-level domains) documented |
| CFG-05 | DB credentials sourced from `.env` and reflected in `CODER_PG_CONNECTION_URL` | Already implemented in upstream compose; pattern extends cleanly |
| OPS-01 | README documents external reverse-proxy contract | Exact proxy requirements researched and confirmed |
| OPS-02 | README documents first-admin bootstrap and start-order | D-01/D-02 lock the approach; research confirms no additional complexity |
| OPS-03 | README documents `chown 999:999` prerequisite and bring-up sequence | D-03/D-04 lock the approach; failure symptom confirmed |
</phase_requirements>

---

## Summary

This phase transforms the upstream proof-of-concept `compose.yaml` into a production-grade deployment. The existing file already uses the right structural patterns (`${VAR:-default}` interpolation, `depends_on: condition: service_healthy`) — this phase fills the gaps: host bind mount for Postgres, pinned Coder image, restart policies, a Coder healthcheck, `.env`/`.env.example` for secrets, and operator documentation.

All major decisions are locked in CONTEXT.md (D-01 through D-10). Research focused on the four open questions identified in the brief: (1) correct healthcheck probe for the Coder image, (2) exact reverse-proxy contract headers, (3) Postgres UID 999 bind-mount behavior, and (4) restart-policy behavior across host reboots. All four questions were answered with HIGH confidence from authoritative sources.

**The `ghcr.io/coder/coder` image is Alpine-based (not distroless)** — `curl` and `wget` are both available, making a straightforward `curl -f http://localhost:7080/healthz` healthcheck the correct pattern. The `/healthz` endpoint returns `200 OK` with body `OK` and requires no authentication. This is the endpoint Coder itself uses for its own internal self-check.

**Primary recommendation:** Mirror the Postgres `pg_isready` healthcheck pattern for Coder using `curl -f http://localhost:7080/healthz`, with `interval: 10s`, `timeout: 5s`, `retries: 5`, `start_period: 30s`.

---

## Project Constraints (from CLAUDE.md)

All directives below are enforced for this phase:

| Directive | Requirement |
|-----------|-------------|
| Never use `:latest` image tag | Coder image must be `ghcr.io/coder/coder:v2.33.8` (or `${CODER_VERSION:-v2.33.8}`) |
| Keep image reference overridable | `${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}` pattern required; upstream docs depend on this |
| No named volume for Postgres | Bind mount `./data/postgres` with `chown 999:999`; named volume is opaque on host |
| No Postgres host port exposure | `ports:` block must remain commented out on `database` service |
| `postgres:17` minimum | No downgrade; this is the current Coder default and minimum-supported is 13 |
| Use `docker compose` (v2), not `docker-compose` | All docs reference `docker compose` CLI |
| All secrets in gitignored `.env` | Only `.env.example` with placeholders is committed |
| `CODER_ACCESS_URL=127.0.0.1` committed default only for quickstart | Production operators override via `.env` |
| `CODER_WILDCARD_ACCESS_URL` not top-level domain | Cookie scope breaks with `*.workspaces` style — must use qualified subdomain |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Data persistence | Host filesystem | Docker bind mount | Postgres data must be directly accessible on host for backup scripts (Phase 2) |
| Service orchestration | Docker Compose | — | Single-host deployment; no Swarm/K8s needed |
| TLS termination | External reverse proxy | — | Explicitly out of scope; scaffold is HTTP-only on `:7080` |
| Environment configuration | `.env` file (host) | Compose `${VAR:-default}` | Secrets never in git; defaults in compose for quickstart compatibility |
| Health signaling | Coder server (`/healthz`) | Docker healthcheck | Docker reads the endpoint; `depends_on: service_healthy` gates Coder start |
| Start ordering | Docker Compose `depends_on` | Application retry | Compose enforces DB-first on `up`; Coder retries DB connection on reboot |
| Operator documentation | README.md | `.env.example` | README covers flow; `.env.example` is the variable reference |

---

## Standard Stack

### Core (no new packages to install — this is a compose/config phase)

| Component | Version | Purpose | Source |
|-----------|---------|---------|--------|
| `ghcr.io/coder/coder` | `v2.33.8` | Coder control plane | Pinned stable track per CLAUDE.md |
| `postgres` | `17` | Workspace metadata store | Current Coder default; minimum supported is 13 |
| Docker Compose v2 | Bundled with Docker Engine 20.10+ | Stack orchestration | `docker compose` plugin (not `docker-compose` v1) |

### No External Packages

This phase introduces no new software packages. It modifies `compose.yaml`, creates `.env.example`, `.gitignore`, and `README.md`. No `npm install`, `pip install`, or `apt install` is needed.

---

## Package Legitimacy Audit

> **Not applicable.** This phase installs no external packages. All components are the Coder server image and the official Postgres image, both already established in the project.

---

## Architecture Patterns

### System Architecture Diagram

```
[Operator's shell]
       |
       | docker compose up -d
       v
[Docker Engine]
       |
       |-- starts --> [database (postgres:17)]
       |                    |
       |                    | healthcheck: pg_isready
       |                    | passes after ~5s
       |                    v
       |              [service_healthy]
       |                    |
       |-- waits for -------+
       |
       |-- starts --> [coder (ghcr.io/coder/coder:v2.33.8)]
                            |
                            | CODER_PG_CONNECTION_URL
                            | connects to database:5432
                            |
                            | CODER_HTTP_ADDRESS=0.0.0.0:7080
                            | listens on :7080
                            |
                            | healthcheck: curl -f http://localhost:7080/healthz
                            | passes after ~30s start_period
                            v
                      [service_healthy]
                            |
[Host port 7080] <----------+
       |
[External reverse proxy]
       | - TLS termination
       | - Wildcard cert *.<apps-domain>
       | - Preserves Host header
       | - Forwards Upgrade/Connection headers
       | - proxy_buffering off
       v
[Operator browser] --> CODER_ACCESS_URL (e.g. https://coder.example.com)
```

Data flow for persistence:
```
[postgres:17 container]
       |
       | /var/lib/postgresql/data
       | (bind mount)
       v
[Host: ./data/postgres]   <-- visible to backup scripts (Phase 2)
  owned by UID 999:999
  pre-created by operator
```

### Recommended Project Structure

```
./                          # repo root
├── compose.yaml            # hardened stack (this phase)
├── .env.example            # committed, all vars with placeholders (CFG-01)
├── .env                    # gitignored, real values (CFG-02)
├── .gitignore              # at minimum: .env, data/
├── README.md               # operator runbook (OPS-01..03)
└── data/
    └── postgres/           # host bind mount (SRV-01) — gitignored
                            # pre-created: sudo chown -R 999:999 ./data/postgres
```

### Pattern 1: Host Bind Mount for Postgres (SRV-01, SRV-05)

**What:** Replace the named volume `coder_data` with a host bind mount so Postgres data is directly visible on the host filesystem and can be backed up without a helper container.

**When to use:** Any production deployment where data durability and backup access matter.

**Example (compose.yaml database service volumes section):**
```yaml
# Source: upstream pattern from docker-library/postgres + CLAUDE.md
volumes:
  - ${CODER_PG_DATA_DIR:-./data/postgres}:/var/lib/postgresql/data
```

**Pre-requisite (must run before first `docker compose up`):**
```bash
mkdir -p ./data/postgres
sudo chown -R 999:999 ./data/postgres
```

**Failure symptom if skipped:** Postgres container fails to initialize with:
```
chown: changing ownership of '/var/lib/postgresql/data': Permission denied
```
The `database` service exits with a non-zero code; the `coder` service never starts because `condition: service_healthy` is never satisfied. [VERIFIED: docker-library/postgres GitHub issues #1010, #26]

### Pattern 2: Coder Server Healthcheck (SRV-04)

**What:** Add a Docker healthcheck to the `coder` service using the `/healthz` endpoint, mirroring the Postgres `pg_isready` pattern already in compose.yaml.

**Endpoint:** `GET http://localhost:7080/healthz` → `200 OK`, body `OK`, no authentication required. [VERIFIED: coder.com/docs/admin/monitoring/health-check]

**Tool availability:** The `ghcr.io/coder/coder` image is built on `alpine:3.23.3` with `curl` and `wget` both installed via `apk`. The image is NOT distroless. [VERIFIED: github.com/coder/coder Dockerfile.base at v2.33.8]

**Recommended healthcheck block:**
```yaml
# Source: /healthz endpoint from coder.com/docs/admin/monitoring/health-check
#         curl availability from Dockerfile.base (alpine:3.23.3)
#         timing modeled on existing pg_isready healthcheck (interval:5s, timeout:5s, retries:5)
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:7080/healthz"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s
```

**Rationale for `start_period: 30s`:** Coder must connect to Postgres and run migrations before `/healthz` returns healthy. On a fresh install this can take 10–30 seconds. The `start_period` excludes this window from the retry count, preventing premature unhealthy status. The Postgres check uses no `start_period` because `pg_isready` is purely a socket/protocol check (no migrations).

**Rationale for `interval: 10s` vs Postgres `5s`:** Coder's HTTP healthcheck is heavier than a TCP/protocol check; 10s is a reasonable polling interval that won't spam the server.

### Pattern 3: Image Pinning (SRV-02)

**What:** Change the `coder` image default from `:latest` to `v2.33.8` while keeping `CODER_REPO`/`CODER_VERSION` overridable.

**Example:**
```yaml
# Source: CLAUDE.md §Technology Stack; upstream compose.yaml comment preserved
image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}
```

The comment `# This MUST be stable for our documentation and other automations.` must be preserved verbatim. [VERIFIED: upstream compose.yaml canonical comment]

### Pattern 4: Restart Policies (SRV-03)

**What:** Add `restart: unless-stopped` to both `coder` and `database` services.

**Example:**
```yaml
services:
  coder:
    restart: unless-stopped
    # ... rest of coder service
  database:
    restart: unless-stopped
    # ... rest of database service
```

**Behavior:** `unless-stopped` restarts the container after any exit (including crash, OOM kill, and host reboot) unless it was explicitly stopped with `docker compose stop` or `docker stop`. [CITED: docs.docker.com/compose/how-tos/startup-order/]

**Reboot caveat:** Docker Compose `depends_on: condition: service_healthy` ordering is only guaranteed during `docker compose up`. On host reboot, Docker Engine restarts all containers with restart policies independently — Postgres and Coder may start simultaneously. This is mitigated by Coder's built-in DB connection retry logic: if Coder starts before Postgres is ready, it will retry the connection until the database becomes available. The healthcheck still gates `depends_on` for `docker compose up` flows; the reboot behavior is acceptable for this use case. [CITED: github.com/docker/compose/issues/12589]

### Pattern 5: Environment Variable Configuration (CFG-01..05)

**What:** All configuration comes from environment variables, either set in `.env` (operator) or falling back to safe defaults in `compose.yaml`. Docker Compose automatically loads `.env` from the project directory (same directory as `compose.yaml`).

**`.env.example` recommended layout:**
```bash
# ── Coder Server ──────────────────────────────────────────────────────────────

# The public URL operators and workspaces use to reach the Coder server.
# Setting this to a real URL disables the *.try.coder.app dev tunnel.
# Must be reachable from workspace containers — 127.0.0.1 only works for
# Docker-local templates.
CODER_ACCESS_URL=https://coder.example.com

# Wildcard subdomain for workspace app URLs (e.g. *.coder.example.com).
# Do NOT use a top-level domain (e.g. *.workspaces) — browsers reject cookies
# from top-level domains, breaking workspace apps.
CODER_WILDCARD_ACCESS_URL=*.coder.example.com

# Coder image version. Default is v2.33.8 (stable track).
# Change only when intentionally upgrading.
CODER_VERSION=v2.33.8

# ── PostgreSQL ────────────────────────────────────────────────────────────────

POSTGRES_USER=coder
POSTGRES_PASSWORD=change-me-in-production
POSTGRES_DB=coder

# Host path for PostgreSQL data directory (bind mount).
# Pre-create this directory and run: sudo chown -R 999:999 $CODER_PG_DATA_DIR
CODER_PG_DATA_DIR=./data/postgres
```

**Key variable behaviors:**
- `CODER_ACCESS_URL` set to real URL → `*.try.coder.app` tunnel is disabled [VERIFIED: coder.com/docs/admin/setup via WebFetch]
- `CODER_WILDCARD_ACCESS_URL=*.coder.example.com` → workspace apps route under subdomain; top-level domain breaks cookie scope [VERIFIED: coder.com/docs/admin/setup]
- `CODER_HTTP_ADDRESS` CLI default is `127.0.0.1:3000`; compose already overrides to `0.0.0.0:7080` — keep this override [VERIFIED: coder.com/docs/reference/cli/server]
- `CODER_TELEMETRY_ENABLE` defaults to `true`; leave unset per D-10 [VERIFIED: coder.com/docs/reference/cli/server]

### Pattern 6: `.gitignore` Required Entries (CFG-02)

**What:** The repo currently has no `.gitignore`. This phase must create one to prevent secrets and data from being committed.

**Minimum required entries:**
```gitignore
# Local environment — real secrets, never commit
.env

# Postgres data directory — can be large, contains binary data
data/

# Backup files produced by Phase 2 scripts (future-proofing)
backups/
```

### Pattern 7: Reverse-Proxy Contract Documentation (OPS-01)

**What:** A prose section in README.md describing exactly what the external reverse proxy must provide.

**Confirmed requirements** (from coder.com nginx docs + general networking research):

| Requirement | Detail | Source |
|-------------|--------|--------|
| Upstream | `http://127.0.0.1:7080` (or host IP if proxy runs off-host) | [CITED: coder.com/docs/tutorials/reverse-proxy-nginx] |
| TLS termination | Proxy handles HTTPS; Coder only listens HTTP | [ASSUMED — standard pattern] |
| Wildcard certificate | `*.<apps-domain>` must match `CODER_WILDCARD_ACCESS_URL` | [CITED: coder.com/docs/admin/setup] |
| `Host` header | Must be forwarded verbatim (not replaced by proxy hostname) | [CITED: coder.com/docs/tutorials/reverse-proxy-nginx] |
| WebSocket upgrade | `Upgrade: websocket` + `Connection: upgrade` headers must be forwarded | [VERIFIED: coder.com/docs/admin/networking — "must support WebSockets"] |
| DERP relay | Uses `Upgrade: derp` — proxy must not strip unrecognized Upgrade values | [CITED: coder.com/docs/admin/networking] |
| Response buffering | Must be disabled for terminal/log streaming | [CITED: coder.com/docs/tutorials/reverse-proxy-nginx via nginx `proxy_buffering off` pattern] |
| `X-Forwarded-For` | Should be set to `$remote_addr` / `$proxy_add_x_forwarded_for` | [CITED: coder.com/docs/tutorials/reverse-proxy-nginx] |
| `X-Forwarded-Proto` | Should be set to `https` so Coder knows the external scheme | [CITED: coder.com/docs/tutorials/reverse-proxy-nginx] |

**The key restriction any reverse proxy must satisfy:** Any proxy in front of Coder must support WebSocket connections. Standard HTTP-only proxies (without WebSocket passthrough) will break terminal access and the DERP relay. [VERIFIED: coder.com/docs/admin/networking]

### Anti-Patterns to Avoid

- **Named volume for Postgres:** `coder_data:` (named volume) makes data opaque on the host and requires a helper container to access for backups. Use bind mount instead. [CLAUDE.md "What NOT to Use"]
- **`:latest` image tag:** Non-reproducible; can't rollback; upstream automation docs explicitly warn against this. [CLAUDE.md]
- **Exposing Postgres on host port:** `ports: - "5432:5432"` on the database service creates unnecessary attack surface; Coder reaches it by service name `database`. [CLAUDE.md]
- **`CODER_ACCESS_URL=127.0.0.1` in production:** Workspace agents in non-Docker templates cannot reach the Coder server at localhost. [CLAUDE.md]
- **`CODER_WILDCARD_ACCESS_URL=*.workspaces` (top-level):** Browsers treat these as public domains and reject Coder's cookies. [VERIFIED: coder.com/docs/admin/setup]
- **`docker-compose` (v1 hyphenated CLI):** Deprecated since 2023; use `docker compose` (v2 plugin). [CLAUDE.md]
- **Storing `CODER_FIRST_USER_*` in `.env`:** Puts admin password in a file on disk; manual UI first-run is the locked approach (D-01).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Health probe HTTP check | Custom shell polling loop | `curl -f http://localhost:7080/healthz` in Docker `healthcheck:` | Docker healthcheck is lifecycle-integrated; `depends_on: condition: service_healthy` only reads Docker's health state |
| DB readiness check | Custom TCP probe script | `pg_isready` (already in compose) | `pg_isready` is the PostgreSQL-official readiness probe; handles auth correctly |
| Secret management | Inline values in compose.yaml | `.env` + Docker Compose env interpolation | Compose auto-loads `.env`; no extra tooling needed for single-host deployment |
| Image version pinning | External CI/CD pin | `${CODER_VERSION:-v2.33.8}` in compose | Simple, visible, overridable by operator without modifying compose.yaml |

---

## Runtime State Inventory

> Step 2.5 triggered: this is a migration phase (named volume → bind mount).

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | Named Docker volume `coder_data` (contains Postgres data from quickstart use) | Data migration if operator has existing data; fresh install: just delete old volume. See pitfall below. |
| Live service config | None — no running Coder instance in this devcontainer environment | None |
| OS-registered state | None — no systemd/launchd/cron entries for Coder in this repo | None |
| Secrets/env vars | None committed — current compose uses inline `${VAR:-default}` patterns only | Create `.env` (operator) and `.env.example` (committed) |
| Build artifacts | None — no compiled artifacts; image is pulled from GHCR | None |

**Named volume migration note:** If an operator upgrades an existing quickstart deployment (which uses `coder_data` named volume), they must either:
1. Export data from `coder_data` volume into the new bind mount path before switching, OR
2. Accept a fresh start (delete `coder_data` volume, let Coder reinitialize)

The plan must include a note on this for operators upgrading from the quickstart compose. Fresh installs have no migration burden.

---

## Common Pitfalls

### Pitfall 1: Missing `chown` Before First `docker compose up`

**What goes wrong:** Postgres container exits immediately on first start; `docker compose up` shows `database` service unhealthy; `coder` service never starts.

**Why it happens:** The `postgres:17` image runs as UID 999 (`postgres` user) and attempts to initialize the data directory at `/var/lib/postgresql/data`. If the bind-mounted host directory is owned by root or another UID, the `chown` inside the container fails with `Permission denied`.

**How to avoid:** Run `sudo chown -R 999:999 ./data/postgres` (or `$CODER_PG_DATA_DIR`) before the first `docker compose up`. Pre-create the directory too: `mkdir -p ./data/postgres`. [VERIFIED: docker-library/postgres GitHub issues #1010, #26]

**Warning signs:** `database` container exits with code 1; `docker compose logs database` shows `chown: changing ownership of '/var/lib/postgresql/data': Permission denied`.

### Pitfall 2: Migrating from Named Volume Without Data Export

**What goes wrong:** Operator switches from `coder_data` named volume to bind mount and loses all existing workspaces, users, and templates.

**Why it happens:** The old `coder_data` named volume is not automatically migrated to the new bind mount path. Postgres starts fresh with an empty data directory.

**How to avoid:** For fresh installs: no action needed. For existing quickstart deployments: export data from `coder_data` into `./data/postgres` before switching, OR intentionally start fresh and accept data loss.

**Warning signs:** After switching, Coder shows the first-run screen even though you had existing data.

### Pitfall 3: `/healthz` Endpoint Returns Unhealthy During Migration Phase

**What goes wrong:** Healthcheck fails repeatedly during Coder's startup, causing `docker compose up` to report the service as unhealthy even though Coder is still initializing.

**Why it happens:** Coder must connect to Postgres and run database migrations before `/healthz` responds with `200 OK`. On a cold start with schema migrations (e.g., first run, or upgrade), this can take 15–45 seconds.

**How to avoid:** Use `start_period: 30s` in the healthcheck block. Failures during the start period do not count against `retries`. If migrations take longer than 30s (e.g., large datasets, slow I/O), increase `start_period` to `60s`.

**Warning signs:** `docker compose ps` shows `coder` as `(health: starting)` for more than a minute; `docker compose logs coder` shows migration progress messages.

### Pitfall 4: `CODER_ACCESS_URL` Not Set to Real URL in Production

**What goes wrong:** Coder starts a `*.try.coder.app` dev tunnel to make the server reachable, even when operator intends to use their own domain.

**Why it happens:** If `CODER_ACCESS_URL` is left at the `127.0.0.1` default (or is empty), Coder activates the dev tunnel so the server is reachable from workspaces.

**How to avoid:** Set `CODER_ACCESS_URL=https://coder.example.com` (a real reachable URL) in `.env`. The tunnel is disabled as soon as a real access URL is configured. [VERIFIED: coder.com/docs/admin/setup]

**Warning signs:** Coder logs show `Started tunnel`; the admin UI shows a `*.try.coder.app` access URL in Settings > General.

### Pitfall 5: `CODER_WILDCARD_ACCESS_URL` Using Top-Level Domain

**What goes wrong:** Workspace app URLs appear to resolve but the browser refuses to set or send cookies, breaking workspace authentication and app access.

**Why it happens:** Browsers (following RFC 6265 and the Public Suffix List) treat top-level domains like `*.workspaces` as public domains and refuse to set cookies with that scope.

**How to avoid:** Always use a qualified subdomain: `CODER_WILDCARD_ACCESS_URL=*.coder.example.com`. The apps domain should be a subdomain of your main domain or a separate domain entirely. [VERIFIED: coder.com/docs/admin/setup]

**Warning signs:** Workspace apps load but immediately show authentication errors or redirect loops.

### Pitfall 6: Reverse Proxy Without WebSocket Support

**What goes wrong:** Workspace terminals and log streams silently fail or disconnect; the DERP relay connection cannot be established.

**Why it happens:** Coder uses WebSocket for terminal I/O and server-sent events for log streaming. A proxy that doesn't forward `Upgrade: websocket` and `Connection: upgrade` will respond with `400 Bad Request` or silently downgrade to HTTP.

**How to avoid:** Ensure the reverse proxy is configured with WebSocket passthrough. For nginx: `proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection upgrade;`. For Caddy: reverse_proxy handles WebSocket by default. [CITED: coder.com/docs/tutorials/reverse-proxy-nginx]

**Warning signs:** Terminal opens but immediately closes; log streaming shows no output; `docker compose logs coder` shows WebSocket upgrade errors.

---

## Code Examples

### Hardened `compose.yaml` (annotated key changes)

```yaml
# Source: github.com/coder/coder blob/v2.33.8/compose.yaml (upstream) + phase 1 hardening
services:
  coder:
    # This MUST be stable for our documentation and
    # other automations.
    image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}
    restart: unless-stopped                          # SRV-03
    ports:
      - "7080:7080"
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://${POSTGRES_USER:-username}:${POSTGRES_PASSWORD:-password}@database/${POSTGRES_DB:-coder}?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_ACCESS_URL: "${CODER_ACCESS_URL:-http://127.0.0.1:7080}"  # CFG-03; real URL disables tunnel
      CODER_WILDCARD_ACCESS_URL: "${CODER_WILDCARD_ACCESS_URL:-}"      # CFG-04; empty = disabled
    healthcheck:                                     # SRV-04
      test: ["CMD", "curl", "-f", "http://localhost:7080/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coder_home:/home/coder                       # D-09: keep for quickstart convenience
    depends_on:
      database:
        condition: service_healthy

  database:
    image: "postgres:17"
    restart: unless-stopped                          # SRV-03
    # ports:                                         # Do NOT expose; Coder reaches by service name
    #   - "5432:5432"
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-username}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
      POSTGRES_DB: ${POSTGRES_DB:-coder}
    volumes:
      - ${CODER_PG_DATA_DIR:-./data/postgres}:/var/lib/postgresql/data  # SRV-01 (bind mount)
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "pg_isready -U ${POSTGRES_USER:-username} -d ${POSTGRES_DB:-coder}",
        ]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  coder_home:
  # NOTE: coder_data named volume removed — replaced by bind mount above (SRV-01)
```

### Healthcheck Verification Commands

```bash
# Check healthcheck status after docker compose up
docker compose ps

# Watch health status in real-time
watch -n 2 docker compose ps

# See healthcheck log for coder container
docker inspect $(docker compose ps -q coder) --format='{{json .State.Health}}' | python3 -m json.tool

# Manually test the /healthz endpoint from inside the container
docker compose exec coder curl -s http://localhost:7080/healthz
# Expected output: OK
```

### Pre-startup Prerequisite Commands (Document in README)

```bash
# 1. Clone and copy env file
git clone <repo>
cd <repo>
cp .env.example .env
# Edit .env with real values

# 2. Create and own the Postgres data directory (REQUIRED before first up)
mkdir -p ./data/postgres
sudo chown -R 999:999 ./data/postgres

# 3. Bring up the stack
docker compose up -d

# 4. Check health (wait ~30-60s for Coder to initialize)
docker compose ps

# 5. Open CODER_ACCESS_URL in browser → complete first-run admin creation
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Named Docker volume for Postgres | Host bind mount with UID 999 chown | This phase | Data visible on host for backup scripts |
| `:latest` image tag | Pinned `v2.33.8` | This phase | Reproducible deployments, rollback possible |
| No healthcheck on Coder service | `curl -f /healthz` healthcheck | This phase | `depends_on: service_healthy` can gate on Coder readiness |
| Inline default `127.0.0.1` | `.env`-sourced with documented fallback | This phase | Operators configure production URL without editing compose.yaml |
| No `.gitignore` | `.env`, `data/`, `backups/` gitignored | This phase | Secrets and binary data never accidentally committed |

**Deprecated/outdated in this context:**
- `coder_data` named volume: replaced by bind mount — remove from `volumes:` section
- `CODER_VERSION:-latest`: change default to `v2.33.8`

---

## Open Questions

1. **`CODER_ACCESS_URL` fallback value format**
   - What we know: D-07 says keep `${CODER_ACCESS_URL:-127.0.0.1}` fallback. Upstream v2.33.8 compose.yaml uses `${CODER_ACCESS_URL}` (no default — value must be set). The current local compose uses literal `"127.0.0.1"` (no env interpolation at all).
   - What's unclear: Should the default be `http://127.0.0.1:7080` (a full URL with protocol and port) or `http://127.0.0.1` or just `127.0.0.1`? Coder may auto-add protocol.
   - Recommendation: Use `${CODER_ACCESS_URL:-http://127.0.0.1:7080}` — the full URL form is clearest and matches what Coder expects. Verify during task execution by checking if Coder logs an error with the partial form.

2. **`CODER_WILDCARD_ACCESS_URL` when not set**
   - What we know: An empty value disables wildcard subdomain routing. The D-08 placeholder is `*.coder.example.com`.
   - What's unclear: Does `${CODER_WILDCARD_ACCESS_URL:-}` (empty default) cause Coder to log a warning on every startup?
   - Recommendation: Use `${CODER_WILDCARD_ACCESS_URL:-}` — the empty value is equivalent to not setting the variable, which is correct for quickstart mode.

3. **Named volume migration for existing quickstart users**
   - What we know: The phase switches `coder_data` (named volume) to a bind mount. Operators with existing quickstart deployments will lose data if they just switch without migrating.
   - What's unclear: Should the plan include a migration helper command or a prominent README callout?
   - Recommendation: Add a clear README callout (not a script) in the "Upgrading from quickstart" section documenting: stop stack → `docker run --rm -v coder_coder_data:/data -v $(pwd)/data/postgres:/target alpine sh -c 'cp -a /data/. /target/'` → fix ownership → bring up with new compose. The planner should include this as a task (README section, not a script).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Engine | Entire stack | ✓ | (devcontainer environment) | — |
| Docker Compose v2 | Stack orchestration | ✓ | Bundled with Docker Engine | — |
| `curl` (inside coder container) | Healthcheck | ✓ | Alpine `curl` (confirmed in Dockerfile.base) | `wget --spider` as alternative |
| `pg_isready` (inside database container) | Postgres healthcheck | ✓ | Bundled in `postgres:17` image | — |

---

## Validation Architecture

> `nyquist_validation: true` — this section is required.

### Test Framework

This is a Docker Compose + documentation phase — there is no application code and no unit test framework. Validation is operational (smoke tests via `docker compose` commands) rather than automated unit tests.

| Property | Value |
|----------|-------|
| Framework | None (operational smoke tests) |
| Config file | none |
| Quick run command | `docker compose ps` + `docker compose exec coder curl -s http://localhost:7080/healthz` |
| Full suite command | See Phase Gate below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| SRV-01 | Postgres data survives container recreation | smoke | `docker compose down && docker compose up -d && docker compose exec database pg_isready` | Manual: verify `./data/postgres` exists on host with content |
| SRV-02 | Coder runs at pinned version | smoke | `docker compose exec coder /opt/coder version` | Should show `v2.33.8` |
| SRV-03 | Services restart after `docker compose restart` | smoke | `docker compose restart && docker compose ps` | Manual: verify both show `Up` |
| SRV-04 | Coder healthcheck passes | smoke | `docker compose exec coder curl -f http://localhost:7080/healthz` | Returns `OK` |
| SRV-05 | Postgres initializes cleanly | smoke | `docker compose logs database \| grep "database system is ready"` | Requires chown pre-step |
| CFG-01 | `.env.example` documents all variables | manual | `diff <(grep '^[A-Z]' .env.example) <(grep '^[A-Z]' .env)` | Visual review |
| CFG-02 | `.env` is gitignored | smoke | `git check-ignore -v .env` | Must return `.gitignore:.env` |
| CFG-03 | No `*.try.coder.app` tunnel when access URL set | manual | `docker compose logs coder \| grep -i tunnel` | Should show no tunnel started |
| CFG-04 | Wildcard apps URL resolves | manual | Browser: verify workspace app URL has `*.coder.example.com` pattern | Requires real domain |
| CFG-05 | DB credentials from `.env` | smoke | `docker compose config` (shows resolved values) | Review DSN includes correct user/pass |
| OPS-01 | README proxy contract section exists and is complete | manual | Human review against D-06 checklist | 9 proxy requirements listed |
| OPS-02 | README first-admin section documents flow | manual | Human review | Covers: up → wait → open URL → create admin |
| OPS-03 | README chown prerequisite is prominent | manual | Human review | Must appear before `docker compose up` step |

### Sampling Rate

- **Per task commit:** `docker compose ps` (if stack is running)
- **Per wave merge:** Full smoke sequence — `down → up -d → ps → healthcheck curl`
- **Phase gate:** All manual checks reviewed + smoke tests green before `/gsd-verify-work`

### Wave 0 Gaps

None — this phase creates only `compose.yaml` edits, `.gitignore`, `.env.example`, and `README.md`. No test files to create. The "test suite" is the operational smoke sequence above.

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` — section required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Partial | Coder's built-in UI first-run (no env-var password — D-01) |
| V3 Session Management | No | Coder handles sessions internally; not configured here |
| V4 Access Control | No | Access control is Coder's responsibility, not compose config |
| V5 Input Validation | No | No application code written in this phase |
| V6 Cryptography | Partial | Secrets in `.env` (gitignored); DB password never in compose.yaml |
| V7 Error Handling | No | No application code |
| V9 Communications | Partial | TLS is external proxy's responsibility; `sslmode=disable` is correct for intra-Docker traffic |
| V14 Configuration | Yes | No secrets in compose; `.env.example` uses placeholders; `.gitignore` prevents accidental commit |

### Threat Patterns for Docker Compose / Coder Deployment

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| DB credentials committed to git | Information Disclosure | `.gitignore` blocks `.env`; `.env.example` uses placeholders |
| Postgres accessible from host network | Elevation of Privilege | `ports:` block on database service stays commented out |
| Admin password in `.env` | Information Disclosure | D-01: no `CODER_FIRST_USER_*` vars; manual UI first-run |
| Coder image drift (`:latest`) | Tampering | Pin to `v2.33.8`; `CODER_VERSION` var makes upgrades intentional |
| Dev tunnel active in production | Information Disclosure | Setting real `CODER_ACCESS_URL` disables tunnel |
| Postgres data accessible by all users | Information Disclosure | `data/postgres` owned by `999:999`; not world-readable by default |

**Key security note for V6/V14:** The `.env` file containing `POSTGRES_PASSWORD` and any other secrets must be in `.gitignore` from the start of this phase. If it is ever accidentally committed, git history must be purged — a gitignore created late does not retroactively prevent exposure.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `CODER_WILDCARD_ACCESS_URL` set to empty string (`${CODER_WILDCARD_ACCESS_URL:-}`) behaves identically to not setting the variable | Code Examples (compose.yaml) | Coder may log a configuration error on every startup; low impact |
| A2 | `CODER_ACCESS_URL=http://127.0.0.1:7080` (with protocol + port) is the correct full-URL form for the quickstart fallback | Code Examples, Open Questions | If Coder requires only `127.0.0.1` (no protocol), the URL form may cause a parse error; easy to verify at execution time |
| A3 | `/healthz` endpoint is present in `v2.33.8` (confirmed in monitoring docs which don't specify when it was added) | Standard Stack, Code Examples | If endpoint was added after v2.33.8, healthcheck will always fail; fallback: use `curl -f http://localhost:7080/api/v2/buildinfo` |
| A4 | Coder will retry the DB connection internally on reboot before the depends_on health gate is re-evaluated | Common Pitfalls (restart caveat) | If Coder crashes without retry on DB unavailability, it may need `restart: on-failure:3` instead of `unless-stopped`; low risk given Coder's production-grade DB handling |

---

## Sources

### Primary (HIGH confidence)

- `github.com/coder/coder blob/v2.33.8/compose.yaml` — canonical upstream compose.yaml; confirmed CODER_HTTP_ADDRESS, volume structure, healthcheck pattern
- `github.com/coder/coder blob/v2.33.8/scripts/Dockerfile.base` — confirmed Alpine 3.23.3 base, `curl` and `wget` availability, UID 1000 for coder user
- `github.com/coder/coder blob/v2.33.8/scripts/Dockerfile` — confirmed final image structure (binary + base; no RUN commands)
- `coder.com/docs/admin/monitoring/health-check` — confirmed `/healthz` endpoint, `200 OK` + body `OK`, no auth required
- `coder.com/docs/admin/setup` — confirmed CODER_ACCESS_URL disables tunnel when set; CODER_WILDCARD_ACCESS_URL top-level domain cookie warning
- `coder.com/docs/reference/cli/server` — confirmed CODER_HTTP_ADDRESS default (`127.0.0.1:3000`), CODER_TELEMETRY_ENABLE default (`true`)
- `coder.com/docs/admin/networking` — confirmed "Any reverse proxy must support WebSockets"
- `coder.com/docs/tutorials/reverse-proxy-nginx` — confirmed required proxy headers (Host, Upgrade, Connection, X-Forwarded-For, X-Forwarded-Proto)

### Secondary (MEDIUM confidence)

- `github.com/docker/compose/issues/12589` — `depends_on: condition: service_healthy` not re-evaluated on reboot; confirmed as known limitation
- `docs.docker.com/compose/how-tos/startup-order/` — official Docker documentation on startup ordering; confirms `service_healthy` condition behavior
- `docker-library/postgres GitHub issues #1010, #26` — UID 999 bind-mount permissions pattern (cited in CLAUDE.md as authoritative)

### Tertiary (LOW confidence / ASSUMED)

- A1–A4 in Assumptions Log above

---

## Metadata

**Confidence breakdown:**
- Standard stack (compose.yaml changes): HIGH — confirmed from upstream source at the exact target version
- Healthcheck (endpoint + tool availability): HIGH — endpoint from official docs, curl from Dockerfile.base source
- Bind-mount permissions (UID 999): HIGH — confirmed pattern from CLAUDE.md citing docker-library/postgres issues
- Reverse-proxy contract: HIGH for WebSocket requirement; MEDIUM for specific nginx headers (confirmed from nginx tutorial, not from a Coder-specific contract document)
- Restart policy reboot behavior: MEDIUM — known Docker Compose limitation; mitigated by Coder's internal retry

**Research date:** 2026-06-16
**Valid until:** 2026-07-16 (stable ecosystem — Coder v2.33.x is the stable track)
