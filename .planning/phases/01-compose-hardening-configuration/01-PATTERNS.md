# Phase 1: Compose Hardening & Configuration - Pattern Map

**Mapped:** 2026-06-16
**Files analyzed:** 4 (compose.yaml modify, .env.example create, .gitignore create, README.md create)
**Analogs found:** 1 / 4 (compose.yaml is the only source of extractable code patterns; the other three files have no pre-existing analog in this repo)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `compose.yaml` | config (compose service definition) | request-response (service orchestration) | `compose.yaml` (current state, lines 1-54) | exact — modifying in place |
| `.env.example` | config (environment variable reference) | n/a | none in repo | no analog |
| `.gitignore` | config (git exclusion) | n/a | none in repo | no analog |
| `README.md` | documentation (operator runbook) | n/a | none in repo | no analog |

---

## Pattern Assignments

### `compose.yaml` (modify in place)

**Analog:** `compose.yaml` current state (repo root, all 54 lines — read above)

This file is its own analog. The patterns already established in it must be preserved and extended consistently.

---

#### Pattern 1: `${VAR:-default}` env interpolation

**Source:** `compose.yaml` lines 5, 9, 38-40, 42, 47

```yaml
# Existing pattern — copy this form for every new variable
image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-latest}
CODER_PG_CONNECTION_URL: "postgresql://${POSTGRES_USER:-username}:${POSTGRES_PASSWORD:-password}@database/${POSTGRES_DB:-coder}?sslmode=disable"
POSTGRES_USER: ${POSTGRES_USER:-username}
POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
POSTGRES_DB: ${POSTGRES_DB:-coder}
```

**Apply to (changes in this phase):**
- Image default: change `${CODER_VERSION:-latest}` → `${CODER_VERSION:-v2.33.8}` (SRV-02)
- Access URL: change literal `"127.0.0.1"` → `"${CODER_ACCESS_URL:-http://127.0.0.1:7080}"` (CFG-03)
- Add new env var: `CODER_WILDCARD_ACCESS_URL: "${CODER_WILDCARD_ACCESS_URL:-}"` (CFG-04)
- Add new volume source: `${CODER_PG_DATA_DIR:-./data/postgres}:/var/lib/postgresql/data` (SRV-01)

---

#### Pattern 2: `depends_on: condition: service_healthy`

**Source:** `compose.yaml` lines 27-29

```yaml
depends_on:
  database:
    condition: service_healthy
```

**Apply to:** Preserved unchanged. The new Coder healthcheck (SRV-04) makes the `coder` service itself health-checkable, extending this existing pattern — it does not change the `depends_on` block.

---

#### Pattern 3: Postgres `pg_isready` healthcheck block

**Source:** `compose.yaml` lines 43-51

```yaml
healthcheck:
  test:
    [
      "CMD-SHELL",
      "pg_isready -U ${POSTGRES_USER:-username} -d ${POSTGRES_DB:-coder}",
    ]
  interval: 5s
  timeout: 5s
  retries: 5
```

**Mirror this pattern for the new Coder healthcheck (SRV-04).** Use `CMD` (not `CMD-SHELL`) because the command needs no shell expansion, and add `start_period` (not needed for Postgres because `pg_isready` is a lightweight socket check, but Coder needs 30s for migrations):

```yaml
# New block — add to coder service, directly after `environment:` block
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:7080/healthz"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s
```

---

#### Pattern 4: Named volume declaration

**Source:** `compose.yaml` lines 52-54

```yaml
volumes:
  coder_data:
  coder_home:
```

**Change required:** Remove `coder_data:` (replaced by bind mount). Keep `coder_home:` (D-09). Final `volumes:` block becomes:

```yaml
volumes:
  coder_home:
  # NOTE: coder_data removed — Postgres data now on host bind mount (SRV-01)
```

---

#### Pattern 5: Commented-out Postgres host port (anti-pattern guard)

**Source:** `compose.yaml` lines 34-36

```yaml
# Uncomment the next two lines to allow connections to the database from outside the server.
#ports:
#  - "5432:5432"
```

**Preserve verbatim.** This comment and the commented-out block must remain. Do not expose Postgres on a host port (CLAUDE.md "What NOT to Use").

---

#### Pattern 6: Canonical image comment

**Source:** `compose.yaml` lines 2-4

```yaml
# This MUST be stable for our documentation and
# other automations.
image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-latest}
```

**Preserve verbatim** (except change `latest` default to `v2.33.8`). The comment wording is a contract with upstream automations and must not be rephrased.

---

#### Pattern 7: `restart: unless-stopped` (new — SRV-03)

No existing analog in `compose.yaml`. Add to both services at the same indent level as `image:` (or `ports:`):

```yaml
services:
  coder:
    # This MUST be stable for our documentation and
    # other automations.
    image: ${CODER_REPO:-ghcr.io/coder/coder}:${CODER_VERSION:-v2.33.8}
    restart: unless-stopped        # add here, after image line
    ports:
      ...
  database:
    image: "postgres:17"
    restart: unless-stopped        # add here, after image line
    ...
```

---

### `.env.example` (create)

**Analog:** None in this repo. Pattern comes from RESEARCH.md §Pattern 5 (lines 297-324 of RESEARCH.md).

**Key constraints extracted from CONTEXT.md / RESEARCH.md:**
- Every variable must have a safe placeholder — no real secrets
- Group by subsystem with `# ── Section ──` comment headers
- `POSTGRES_PASSWORD` placeholder must be obviously fake (`change-me-in-production`)
- `CODER_ACCESS_URL` placeholder must be a full URL with protocol (`https://coder.example.com`)
- `CODER_WILDCARD_ACCESS_URL` placeholder must be a qualified subdomain (`*.coder.example.com`), not a top-level domain
- `CODER_PG_DATA_DIR` default matches compose fallback (`./data/postgres`)
- `CODER_VERSION` placeholder is the pinned stable version (`v2.33.8`)
- `CODER_TELEMETRY_ENABLE` is NOT included (D-10: left at Coder default)
- `CODER_FIRST_USER_*` are NOT included (D-01: no admin password in env)

No code excerpt to copy — write fresh from the layout in RESEARCH.md §Pattern 5.

---

### `.gitignore` (create)

**Analog:** None in this repo. Pattern comes from RESEARCH.md §Pattern 6 (lines 336-346).

**Minimum required entries:**

```gitignore
# Local environment — real secrets, never commit
.env

# Postgres data directory — large binary files
data/

# Backup files (Phase 2 scripts will write here)
backups/
```

No additional entries needed for this phase. The file is short and complete as listed.

---

### `README.md` (create)

**Analog:** None in this repo. This is prose documentation — there is no code pattern to copy from.

**Content requirements (from CONTEXT.md decisions and RESEARCH.md):**

The README must cover these sections in order, without burying critical steps:

1. **Prerequisites** — Docker Engine with Compose v2, a public domain (for production)
2. **Quick start (bring-up sequence)** — exact command sequence:
   ```bash
   git clone <repo> && cd <repo>
   cp .env.example .env
   # Edit .env with real CODER_ACCESS_URL, POSTGRES_PASSWORD, etc.
   mkdir -p ./data/postgres
   sudo chown -R 999:999 ./data/postgres    # CRITICAL — must precede docker compose up
   docker compose up -d
   docker compose ps                         # wait until both services show (healthy)
   # Open CODER_ACCESS_URL in browser → complete first-run admin creation
   ```
3. **Postgres bind-mount ownership (D-04)** — must be prominent, not a footnote. Include the failure symptom: "If you skip this step, the `database` service exits immediately. `docker compose logs database` will show: `chown: changing ownership of '/var/lib/postgresql/data': Permission denied`"
4. **First-admin bootstrap (D-01, D-02)** — open `CODER_ACCESS_URL` in browser; `depends_on: service_healthy` already enforces DB-first ordering; no manual start-order dance needed
5. **Reverse-proxy contract (D-05, D-06)** — prose section listing exact requirements:
   - Upstream: `http://127.0.0.1:7080` (or host IP if proxy is off-host)
   - TLS termination at proxy; Coder only speaks HTTP
   - Wildcard TLS certificate for `*.<apps-domain>` matching `CODER_WILDCARD_ACCESS_URL`
   - Forward `Host` header verbatim
   - Forward `Upgrade: websocket` + `Connection: upgrade` (terminal I/O, DERP relay)
   - Disable response buffering (terminal/log streaming)
   - Set `X-Forwarded-For` and `X-Forwarded-Proto: https`
6. **Upgrading from quickstart** — note on named volume migration (`coder_data` → bind mount)
7. **Common operations** — `docker compose logs -f coder`, `docker compose pull && docker compose up -d`, volume reset commands
8. **`coder_home` volume** — note it is safe to remove in production (D-09)

---

## Shared Patterns

### `${VAR:-default}` interpolation convention

**Source:** `compose.yaml` lines 5, 9, 38-40, 47
**Apply to:** All new environment variable references in `compose.yaml`
**Rule:** Always use the `${VAR:-default}` form. Never use bare `$VAR` (fails if unset). Never hardcode values that operators need to override.

### Compose service structure order

**Source:** `compose.yaml` (implicit ordering in current file)
**Convention observed:** Within each service block, the order is: `image` → (restart) → `ports` → `environment` → `healthcheck` → `volumes` → `depends_on`. Follow this order when inserting new stanzas (`restart`, `healthcheck`) into the `coder` service.

### Comments as documentation

**Source:** `compose.yaml` lines 2-4, 11-14, 19-25, 31-36
**Convention:** Inline comments in `compose.yaml` explain non-obvious decisions. Preserve all existing comments verbatim. New stanzas added in this phase should carry a short comment referencing the requirement ID (e.g., `# SRV-03`, `# SRV-04`) so the mapping to requirements is traceable.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.env.example` | config | n/a | No `.env.example` or similar file exists in this repo yet; pattern sourced from RESEARCH.md §Pattern 5 |
| `.gitignore` | config | n/a | No `.gitignore` exists in this repo yet; entries defined in RESEARCH.md §Pattern 6 |
| `README.md` | documentation | n/a | No README exists in this repo yet; content structure derived from CONTEXT.md decisions D-01 through D-09 and RESEARCH.md §Pattern 7 |

---

## Metadata

**Analog search scope:** repo root (only `compose.yaml` contains extractable patterns)
**Files scanned:** 1 (`compose.yaml`, 54 lines)
**External pattern sources used:** RESEARCH.md §Pattern 5 (`.env.example` layout), §Pattern 6 (`.gitignore`), §Pattern 7 (reverse-proxy contract)
**Pattern extraction date:** 2026-06-16
