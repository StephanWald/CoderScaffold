# Coder Production Scaffold

A Docker Compose–based, production-ready scaffold for self-hosting [Coder](https://coder.com)
(the self-hosted cloud development environment platform). It refines the upstream Docker install
into a deployable environment with durable Postgres persistence, environment-driven configuration,
and clear operator documentation.

Coder runs on HTTP at `:7080`. TLS termination is the responsibility of your external reverse
proxy — see [Reverse-proxy contract](#reverse-proxy-contract) below.

---

## Prerequisites

- **Docker Engine** with Compose v2 (`docker compose`, not `docker-compose`)
- **For production:** a public domain and an external reverse proxy that terminates TLS and
  supports WebSocket connections

---

## Quick start

```bash
# 1. Clone and enter the repo
git clone <repo-url> && cd <repo-name>

# 2. Copy the example env file and edit it with your real values
cp .env.example .env
#    Set CODER_ACCESS_URL to your public URL (e.g. https://coder.example.com)
#    Set POSTGRES_PASSWORD to a strong password
#    Set CODER_WILDCARD_ACCESS_URL for workspace app routing (e.g. *.coder.example.com)

# 3. Start the stack
docker compose up -d

# 4. Wait for both services to become healthy
docker compose ps
#    Look for: coder (healthy) and database (healthy)

# 5. Open CODER_ACCESS_URL in your browser and complete the first-run admin setup
```

No `chown` or `mkdir` is required for the default configuration — Postgres data is stored in the
cross-platform named volume `coder_pgdata`. See
[Postgres storage](#postgres-storage-named-volume-vs-host-bind-mount) for details and for the
optional host bind mount path (Linux).

---

## Postgres storage: named volume vs host bind mount

### Default: named volume `coder_pgdata` (recommended)

By default, Postgres data lives in the Docker named volume `coder_pgdata`. This:

- Works on macOS, Windows, and Linux Docker Desktop with no extra setup
- Survives `docker compose down && docker compose up -d` (data is not lost on container recreation)
- Is the correct storage backend for the `pg_dump`-based backup strategy in Phase 2 —
  `pg_dump` is transparent to the storage backend

No `mkdir` or `chown` is needed. The named volume is created automatically on `docker compose up`.

### Optional: host bind mount for Postgres data (Linux)

> **Linux only.** Docker Desktop on macOS and Windows uses VirtioFS for bind mounts, which
> denies the `chown` Postgres requires during initialization. Setting `CODER_PG_DATA_DIR` on
> macOS/Windows will crash-loop the `database` service.

To store Postgres data on the host filesystem (e.g., for direct file-level inspection):

1. Uncomment and set `CODER_PG_DATA_DIR` in your `.env`:

   ```bash
   CODER_PG_DATA_DIR=./data/postgres
   ```

2. Pre-create the directory and set ownership **before** the first `docker compose up`:

   ```bash
   mkdir -p ./data/postgres
   sudo chown -R 999:999 ./data/postgres
   ```

3. Then bring up the stack:

   ```bash
   docker compose up -d
   ```

**Failure symptom if you skip the `chown` step:** The `database` service exits immediately. Run
`docker compose logs database` and you will see:

```
chown: changing ownership of '/var/lib/postgresql/data': Permission denied
```

The database never becomes healthy, so the `coder` service — which waits for
`condition: service_healthy` on `database` — never starts.

---

## First-admin bootstrap

Once both services show `(healthy)` in `docker compose ps`:

1. Open `CODER_ACCESS_URL` in your browser.
2. Complete the built-in first-run screen to create the initial admin account.

No environment variable is needed for the admin account — `CODER_FIRST_USER_*` vars are
intentionally absent from `.env.example`. The admin password lives only in your browser session.

**Start ordering is automatic.** The `depends_on: condition: service_healthy` directive in
`compose.yaml` ensures Coder only starts after Postgres passes its `pg_isready` healthcheck. No
manual DB-first start dance is required on `docker compose up`.

> **On host reboot:** Docker Engine restarts all services with `restart: unless-stopped`
> independently. Coder retries its database connection until Postgres is ready, so the stack
> self-heals after a reboot even if Postgres and Coder start simultaneously.

---

## Reverse-proxy contract

Coder speaks plain HTTP on `:7080`. Your reverse proxy must satisfy all of the following
requirements for Coder to function correctly. This list is proxy-agnostic — configure any
proxy (nginx, Caddy, Traefik, HAProxy, etc.) to meet these requirements.

| Requirement | Detail |
|-------------|--------|
| **Upstream** | If the proxy is a **Compose service on the same Docker network**: use `http://coder:7080` (the service name). If the proxy runs **directly on the host** (process, not container): use `http://127.0.0.1:7080`. If the proxy runs **off-host** on a different machine: use the host IP (e.g. `http://192.168.1.10:7080`). `127.0.0.1` inside a proxy container refers to that container itself, not Coder. |
| **TLS termination** | The proxy handles HTTPS; Coder only listens on HTTP |
| **Wildcard TLS certificate** | Must cover `*.<apps-domain>` matching `CODER_WILDCARD_ACCESS_URL` (e.g. `*.coder.example.com`) |
| **`Host` header** | Forward the original `Host` header verbatim — do not replace it with the proxy hostname |
| **WebSocket `Upgrade`/`Connection`** | Forward `Upgrade: websocket` and `Connection: upgrade` headers (required for terminal I/O and workspace agent streams) |
| **DERP `Upgrade` passthrough** | Do not strip unrecognized `Upgrade` values — Coder uses `Upgrade: derp` for its relay protocol |
| **Response buffering** | Disable response buffering (nginx: `proxy_buffering off`) — required for terminal and log streaming |
| **`X-Forwarded-For`** | Set to `$remote_addr` / `$proxy_add_x_forwarded_for` |
| **`X-Forwarded-Proto`** | Set to `https` so Coder knows the external scheme |

> **Hard requirement:** Any proxy in front of Coder **must** support WebSocket connections.
> Standard HTTP-only proxies (without WebSocket passthrough) will break workspace terminal
> access and the DERP relay. Signs of a misconfigured proxy: terminals open and immediately
> close; log streaming shows no output.

No bundled proxy configuration is included — add your own Caddy, nginx, or Traefik config using
the requirements above.

---

## Upgrading from the quickstart

The upstream Docker quickstart uses the named volume `coder_coder_data`. This scaffold uses
`coder_pgdata` (and optionally a host bind mount via `CODER_PG_DATA_DIR`).

**Fresh install:** No migration needed — bring up the stack and complete first-run.

**Existing quickstart data migration (named volume → named volume):**

Use a logical dump/restore — this is safe across **any** Postgres major version (including when
the old quickstart ran Postgres 16 and this scaffold uses postgres:17). Raw PGDATA file copies
only work when both source and destination run the **same Postgres major version**, and postgres:17
will refuse to start on data from an older cluster.

**Safe path (works across Postgres majors):**

```bash
# 1. While the OLD quickstart stack is still running, dump logically:
docker compose exec -T database \
  pg_dump -U "${POSTGRES_USER:-coder}" -Fc "${POSTGRES_DB:-coder}" > coder-migrate.dump

# 2. Bring up the NEW scaffold stack (fresh postgres:17 — data is empty):
docker compose up -d

# 3. Wait for the database service to become healthy, then restore:
docker compose exec -T database \
  pg_restore -U "${POSTGRES_USER:-coder}" -d "${POSTGRES_DB:-coder}" \
  --clean --if-exists < coder-migrate.dump
```

No admin account re-creation is needed — the dump includes all users, templates, and workspace
metadata. Adjust `-U` and `-d` flags to match your old `POSTGRES_USER` / `POSTGRES_DB` values.

**Same-major shortcut (Postgres 17 → 17 only):**

If you can verify the old quickstart also ran postgres:17 (check with
`docker run --rm -v coder_coder_data:/d alpine cat /d/PG_VERSION`), you may use the faster raw
file copy instead:

```bash
# Only valid when source PGDATA was written by the SAME Postgres major (17).
# postgres:17 will refuse to start on data from Postgres 16 or earlier.
# Compose prefixes the top-level volume key coder_pgdata with the project name
# (coder), so the real Docker volume name is coder_coder_pgdata (double coder_).
docker run --rm \
  -v coder_coder_data:/from \
  -v coder_coder_pgdata:/to \
  alpine sh -c 'cp -a /from/. /to/'

docker compose up -d
```

---

## Common operations

```bash
# Tail Coder server logs
docker compose logs -f coder

# Tail Postgres logs
docker compose logs -f database

# Check service health
docker compose ps

# Pull a newer image and restart
docker compose pull
docker compose up -d

# Stop the stack (data volumes are preserved)
docker compose down

# Reset the Postgres database (destructive — wipes all workspaces, users, templates)
docker compose down
docker volume rm coder_coder_pgdata

# Reset the dev tunnel URL (safe — Coder recreates it on restart)
docker volume rm coder_coder_home
```

### `coder_home` volume

The `coder_home` named volume stores the dev tunnel URL (`*.try.coder.app`). It is a quickstart
convenience — Coder recreates everything it needs on restart. You may safely remove it in
production (`docker volume rm coder_coder_home`). Setting a real `CODER_ACCESS_URL` disables
the dev tunnel entirely, making this volume unnecessary.
