---
phase: 01-compose-hardening-configuration
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - compose.yaml
  - .gitignore
  - README.md
findings:
  critical: 2
  warning: 5
  info: 3
  total: 10
  false_positives: 1
  actionable_critical: 1
status: issues_found
resolution_notes: |
  CR-01 confirmed false positive: /usr/bin/curl IS present in ghcr.io/coder/coder:v2.33.8
  (verified via `docker compose exec coder command -v curl`). The coder healthcheck works as-is.
  CR-02 fixed: README migration section replaced with safe logical pg_dump/pg_restore path.
  WR-01 fixed: migration comment and command now consistent (coder_coder_pgdata with explanation).
  WR-04 fixed: reverse-proxy upstream now leads with container-network form (http://coder:7080).
  WR-05 fixed: start_period: 30s added to database healthcheck in compose.yaml.
  WR-02, WR-03, IN-02, IN-03: accepted as by-design / out of scope for this iteration.
---

# Phase 01: Code Review Report

**Reviewed:** 2026-06-17T00:00:00Z
**Depth:** standard
**Files Reviewed:** 3 (`.env.example` not reviewable in this environment — sandbox blocks reads of env files; it contains only placeholders by design)
**Status:** issues_found

## Summary

Reviewed the production-hardening of a Docker Compose deployment scaffold for self-hosting Coder: `compose.yaml`, `.gitignore`, and `README.md`. `.env.example` could not be read (sandbox rule denies access to env files) — its accuracy against `compose.yaml` was therefore only partially verifiable from the README's documented variable set and could not be fully cross-checked.

The `.gitignore` is correct and complete for the stated threat model. `compose.yaml` is largely sound (image pinning, `restart` policy, `depends_on: service_healthy`, no Postgres port exposure, env interpolation with safe fallbacks). However there are two correctness defects that will produce a misleading runtime state and a broken-as-documented migration path:

1. The Coder healthcheck invokes `curl`, which is not present in the `ghcr.io/coder/coder` image — the container will be reported permanently `unhealthy`, directly contradicting the README's "Look for: coder (healthy)" instruction.
2. The README's quickstart-data migration does a raw PGDATA file copy and claims it "just works," but raw cluster files are only portable between identical Postgres major versions. The upstream quickstart and this scaffold can differ in Postgres major (this scaffold pins `postgres:17`), in which case the copy yields a database that refuses to start.

Several internal-consistency and documentation issues round out the warnings.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Coder healthcheck uses `curl`, which is not in the Coder image — container reported permanently unhealthy

**File:** `compose.yaml:17-22`
**Status: CONFIRMED FALSE POSITIVE** — `/usr/bin/curl` IS present in `ghcr.io/coder/coder:v2.33.8`. Verified via `docker compose exec coder command -v curl` which returns `/usr/bin/curl`. The coder image includes curl despite being described as minimal; the healthcheck works correctly and the container reaches `(healthy)` as documented. No fix required.

**Issue (original):** The healthcheck is `test: ["CMD", "curl", "-f", "http://localhost:7080/healthz"]`. The `ghcr.io/coder/coder` image is a minimal image built around the `coder` Go binary and does **not** ship `curl` (nor `wget`). With `CMD` (exec form, no shell), Docker tries to exec `curl` directly; the binary is missing, every probe errors out, and the container settles into state `unhealthy` forever even though Coder is serving correctly on `:7080`.

This is not cosmetic in this scaffold:
- README Quick Start step 4 (`README.md:36-38`) tells the operator to run `docker compose ps` and "Look for: coder (healthy)". The operator will *never* see `(healthy)` and will reasonably conclude the deployment failed.
- Nothing currently `depends_on` the `coder` service's health, so startup is not blocked today — but the moment any future service (or an orchestrator/monitor) keys off `condition: service_healthy` for `coder`, it will hang indefinitely.

The Coder binary itself can perform the probe (it speaks HTTP and the binary is guaranteed present). Prefer a probe that does not assume `curl`.
**Fix:** No fix applied — CR-01 is a false positive. curl is present in the pinned image and the healthcheck is correct as-is.

### CR-02: Quickstart migration does a raw PGDATA file copy across (possibly mismatched) Postgres majors — produces a DB that won't start

**File:** `README.md:157-170`
**Issue:** The "Existing quickstart data migration" block copies the raw contents of the old Postgres data volume into the new one with `cp -a` and then states: "After migration, Postgres will initialize from the copied data. No admin re-creation is needed."

A raw PGDATA directory is **only** loadable by a Postgres server of the **same major version** that wrote it. The upstream Coder quickstart's `database` service is not guaranteed to be `postgres:17` — historically it has tracked an earlier major (e.g. 16). This scaffold pins `postgres:17` (`compose.yaml:41`). If the source cluster was written by Postgres 16 (or any major ≠ 17), the `postgres:17` container will fail at startup with:

```
FATAL: database files are incompatible with server
DETAIL: The data directory was initialized by PostgreSQL version 16, which is not compatible with this version 17.
```

The new `database` service then never becomes healthy, and per `depends_on` (`compose.yaml:35-37`) `coder` never starts — i.e. the documented "safe" migration path silently bricks the stack for any operator whose quickstart ran a different Postgres major. The phrase "Postgres will initialize from the copied data" is also misleading: Postgres does not re-initialize or upgrade an existing PGDATA; it either mounts it as-is (same major) or refuses (different major).
**Fix:** Either (a) gate the raw-copy path on a verified major-version match and document the check, or (b) replace it with a logical dump/restore that is version-portable:
```bash
# Version-safe migration (works across Postgres majors):
# 1. With the OLD stack running, dump logically:
docker compose -f <old-compose> exec -T database \
  pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" > coder-migrate.dump

# 2. Bring up THIS stack (fresh postgres:17), then restore:
docker compose up -d database
docker compose exec -T database \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists < coder-migrate.dump
```
If the raw `cp -a` path is kept, add an explicit caveat: "Only valid when the source quickstart ran the **same** Postgres major (17). Check with `docker run --rm -v coder_coder_data:/d alpine cat /d/PG_VERSION` first."

## Warnings

### WR-01: Migration comment names `coder_pgdata` but the command uses `coder_coder_pgdata` — operator cannot tell which is correct

**File:** `README.md:160` vs `README.md:163`
**Issue:** The comment says "into the new **coder_pgdata** volume" while the actual `docker run -v` target is **`coder_coder_pgdata`**. The command is the correct one: the top-level compose key is `coder_pgdata` (`compose.yaml:63`) and, with no `name:`/`COMPOSE_PROJECT_NAME` override, Compose prefixes it with the project name `coder`, yielding the real volume `coder_coder_pgdata`. The comment's `coder_pgdata` is wrong and contradicts the surrounding `docker volume rm coder_coder_pgdata` examples (`README.md:195`). An operator copy-pasting based on the comment will mount/create a non-existent `coder_pgdata` volume and copy data into a volume the stack never uses.
**Fix:** Make the comment match the command: `# Copy data from the old coder_coder_data volume into the new coder_coder_pgdata volume`. Consider noting the "project-name prefix" rule once near the volume section so the double-`coder_` naming is not mistaken for a typo.

### WR-02: `CODER_PG_DATA_DIR` bind-mount path is not declared in the top-level `volumes:` block — relies on implicit short-syntax behavior

**File:** `compose.yaml:51` and `compose.yaml:61-65`
**Issue:** The Postgres mount is `${CODER_PG_DATA_DIR:-coder_pgdata}:/var/lib/postgresql/data`. The default `coder_pgdata` resolves to the declared named volume — fine. But when an operator sets `CODER_PG_DATA_DIR=./data/postgres` (the documented opt-in, `README.md:71-75`), Compose must interpret the left side as a host bind path. Short-syntax mounts disambiguate named-volume vs bind by whether the source looks like a path (`.`/`/`), so `./data/postgres` is treated as a bind mount and *not* required to appear in the top-level `volumes:` map — this works, but it is fragile and undocumented in the file: a value like `data/postgres` (no leading `./`) would be ambiguous and may be treated as a named volume reference that is not declared, causing a confusing error. The behavior hinges entirely on the operator including a `.`/`/`.
**Fix:** Document the requirement inline ("`CODER_PG_DATA_DIR` must be an absolute path or start with `./` to be treated as a host bind mount") and, in the README opt-in step (`README.md:71-75`), show the value with the leading `./` (already done) plus an explicit warning that a bare `data/postgres` will not work. No code change strictly required, but the constraint should be stated where the variable is defined.

### WR-03: `CODER_ACCESS_URL` default of `http://127.0.0.1:7080` ships a non-production value with no startup guard

**File:** `compose.yaml:15`
**Issue:** The committed default is `http://127.0.0.1:7080`. Per the project's own CLAUDE.md, `127.0.0.1` "only works for the Docker-based quickstart" and is invalid for non-Docker templates — workspaces cannot reach the control plane. This is an accepted quickstart default, but there is no guard or loud warning, so an operator who deploys "production" without setting `CODER_ACCESS_URL` (the README Quick Start tells them to set it, but `docker compose up -d` will happily run without it) gets a silently-broken control plane and a live `*.try.coder.app` dev tunnel they may not expect in production.
**Fix:** Keep the default for quickstart, but add a prominent inline comment that this default is quickstart-only and add a README callout that leaving it unset on a public deployment exposes a dev tunnel and breaks non-Docker workspaces. Optionally provide a pre-up validation snippet that fails if `CODER_ACCESS_URL` still equals the localhost default in a production context.

### WR-04: Reverse-proxy upstream documented as `http://127.0.0.1:7080`, but Coder binds `0.0.0.0:7080` — off-host proxy guidance is buried

**File:** `README.md:130` cross-referenced with `compose.yaml:11`
**Issue:** The reverse-proxy contract lists the upstream as `http://127.0.0.1:7080` with a parenthetical "(use the host IP instead of `127.0.0.1` if the proxy runs off-host)". Coder binds `CODER_HTTP_ADDRESS: 0.0.0.0:7080` and the host port mapping is `7080:7080` (`compose.yaml:8`). For the common case of a proxy in a *separate container* on the same Docker host (e.g. an nginx/Caddy sidecar), `127.0.0.1` inside the proxy container refers to the proxy itself, not Coder — the upstream must be the Coder service/host. The caveat is easy to miss and the most common real deployment (containerized proxy) is exactly the one the literal value breaks.
**Fix:** Lead with the container-network-correct form. If the proxy is a Compose service, the upstream should be `http://coder:7080` (service name on the shared network); document `http://127.0.0.1:7080` only for a proxy running directly on the host process namespace. Make the off-host/own-container case the primary instruction rather than a parenthetical.

### WR-05: Postgres healthcheck has no `start_period`, so initdb time counts as failed retries

**File:** `compose.yaml:52-60`
**Issue:** The `database` healthcheck (`interval: 5s`, `timeout: 5s`, `retries: 5`) has no `start_period`. On first launch Postgres runs `initdb` (and, with a bind mount, the `chown`/permission dance), during which `pg_isready` fails. With only 5 retries at 5s, the service can be marked `unhealthy` during a slow first init (cold disk, large bind mount, constrained CI), which then blocks `coder` (`depends_on: condition: service_healthy`) from ever starting. The `coder` service got a `start_period: 30s` for exactly this class of problem (`compose.yaml:22`); the database — which has the longer cold-start — got none.
**Fix:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-username} -d ${POSTGRES_DB:-coder}"]
  interval: 5s
  timeout: 5s
  retries: 5
  start_period: 30s   # cover initdb on first boot
```

## Info

### IN-01: `.env.example` not verifiable in this environment

**File:** `.env.example`
**Issue:** Sandbox rules deny reads of env files, so this file was **not reviewable in this environment**. Per the task it is expected to contain only placeholders. The following could therefore NOT be confirmed and should be checked manually: (a) every `${VAR}` in `compose.yaml` is documented — `CODER_REPO`, `CODER_VERSION`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `CODER_ACCESS_URL`, `CODER_WILDCARD_ACCESS_URL`, `CODER_PG_DATA_DIR`; (b) no real secrets are present; (c) placeholder values are internally consistent with the README and compose defaults.
**Fix:** Manually diff the set of `${...}` tokens in `compose.yaml` against the keys in `.env.example` and confirm `CODER_PG_DATA_DIR` is present-but-commented (matching `README.md:71`).

### IN-02: `group_add` GID guidance is hardcoded to `998` with no discovery step

**File:** `compose.yaml:27-28`
**Issue:** The commented `group_add` block hardcodes `"998"` as "docker group on host". The host docker group GID is host-specific and frequently is not 998. An operator who uncomments it verbatim may grant the wrong GID and still fail to access the socket (or grant an unintended group).
**Fix:** Add a comment pointing to the discovery command, e.g. `# Find your host docker GID: getent group docker | cut -d: -f3` so the placeholder is clearly a value-to-replace, not a working default.

### IN-03: Docker socket is mounted read-write with no scoping note

**File:** `compose.yaml:30`
**Issue:** `/var/run/docker.sock:/var/run/docker.sock` grants the `coder` container full control of the host Docker daemon (root-equivalent on the host). This is required for the Docker-based workspace templates and is the documented design, so it is not a defect — but for a "production scaffold" the security implication deserves an explicit note so operators running non-Docker templates know they can drop it.
**Fix:** Add an inline comment noting the socket mount is root-equivalent host access required only for Docker-provisioned workspaces, and may be removed for deployments that exclusively use non-Docker (e.g. Kubernetes/cloud) templates.

---

_Reviewed: 2026-06-17T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
