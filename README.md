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

---

## Backup & restore

`scripts/backup.sh` and `scripts/restore.sh` provide non-interactive database backup and restore.
Both scripts read connection credentials from `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`) and fall back to the compose.yaml defaults if `.env` is absent.

### Taking a backup

```bash
./scripts/backup.sh
```

- Reads credentials from `.env`; no password prompt.
- Writes a timestamped dump to `./backups/coder-YYYYMMDD-HHMMSS.dump` (directory is
  created automatically; already gitignored).
- Applies `chmod 600` to the dump immediately — the file contains all user data, workspace
  metadata, and tokens.
- Performs a two-step integrity check: non-zero size guard + `pg_restore --list` structural
  verification. Exits non-zero if either check fails (cron-safe).
- Prints a parseable `BACKUP_FILE=<path>` line on success for use in calling scripts.

### Restoring a backup

> **DESTRUCTIVE.** `restore.sh` runs `pg_restore --clean`, which drops all existing objects in
> the target database before recreating them from the dump. Double-check you are pointing at the
> intended stack and database before running — data not in the dump will be permanently lost.

```bash
./scripts/restore.sh ./backups/coder-YYYYMMDD-HHMMSS.dump
```

- Validates the dump-file argument before doing anything (regular file, non-zero size).
- Stops the `coder` service before restoring, to release its database connection pool
  (avoids `pg_restore --clean` deadlocking on active connections).
- Runs `pg_restore --clean --if-exists --no-owner --no-acl` — handles both fresh-instance
  restores (no existing objects to drop) and overwrites of an existing database.
- Restarts `coder` automatically via an EXIT trap — even if the restore command fails.
  After a failed restore, inspect logs with `docker compose logs -f coder`.

### Cron and automation

Both scripts are non-interactive and return meaningful exit codes, so they are safe to wrap
in cron jobs or monitoring scripts. When calling from cron, use absolute paths:

```bash
# Example crontab entry — daily backup at 02:00 UTC
0 2 * * * /opt/coder/scripts/backup.sh >> /var/log/coder-backup.log 2>&1
```

**Backup retention/pruning** is out of scope for v1 — operators prune `./backups/` manually
or via a separate cleanup job (deferred to QOL-02 in v2).

---

## Workspace Template

The `templates/docker/` directory contains a Terraform template that provisions Coder workspaces
as Docker containers on the host machine, with browser VS Code (via code-server), JetBrains
Gateway (IntelliJ IDEA), and a persistent home directory.

### Push the template

Run the following from the repo root (requires the `coder` CLI logged in to your Coder server):

```bash
# Push the template — -y suppresses interactive prompts (safe for CI)
coder templates push docker --directory templates/docker/ -y
```

Then set the display name, description, and icon. These are server-side settings — they are
not Terraform-managed fields and must be set via `coder templates edit` (or the dashboard) after
the initial push:

```bash
coder templates edit docker \
  --display-name "Docker Workspace" \
  --description "Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start." \
  --icon "/icon/docker.png"
```

> **Note:** If you push a template update later, re-run `coder templates edit` to keep the
> display name, description, and icon — they are not preserved automatically on re-push.

### Create a workspace

In the Coder dashboard, click **Templates → Docker Workspace → Create Workspace**, then click
**Create**. No parameters to fill.

Once the workspace agent connects (status shows **Connected**), two app buttons appear:

- **VS Code** — opens a browser-based VS Code session (code-server) at `/home/coder`
- **IntelliJ IDEA** — opens a JetBrains Gateway URL that connects your local Gateway client to
  an IntelliJ IDEA server running inside the workspace container

### Docker Socket Permissions

If workspace provisioning fails with a permission error on `/var/run/docker.sock`, the `coder`
user inside the server container can't access the mounted Docker socket. The required `group_add`
GID depends on where Docker runs.

The reliable way to find the value — on every platform — is to read the socket's group GID **as
seen inside the running `coder` container** (this is the number `group_add` must match):

```bash
docker compose exec coder stat -c '%g' /var/run/docker.sock
```

Then, in `compose.yaml`, set the `group_add` value to that number and restart:

```yaml
group_add:
  - "0"  # replace with the GID printed by the command above
```
```bash
docker compose up -d coder
```

**Docker Desktop (macOS / Windows):** The socket is proxied through the Docker Desktop VM and
appears **root-owned (GID `0`) inside the container**, regardless of what the macOS/Windows host
reports — so the value is `0`. `compose.yaml` ships with `group_add: ["0"]` as the default for
this reason. Note: the macOS host `stat` command is `stat -f '%g'` (BSD), not `stat -c '%g'`
(GNU) — but the host value does not apply here; use the in-container command above.

**Linux:** The socket is owned by the host's `docker` group. Use that GID (commonly `999`, or
`998` on Ubuntu, `101` on Alpine). Discover it on the host with `stat -c '%g' /var/run/docker.sock`,
or use the in-container command above — both report the same number on Linux.

**Failure symptom:** Provisioning fails immediately (the agent/app resources may create, but the
first `docker_*` resource errors) with `permission denied while trying to connect to the Docker
daemon socket at unix:///var/run/docker.sock`. Run `docker compose logs coder` and look for
`permission denied` on Docker socket operations.

### Workspace Agent Connectivity

**Local deployment (`CODER_ACCESS_URL=http://127.0.0.1:7080`):** The template adds
`host.docker.internal` via an `extra_hosts` / `host-gateway` entry so the workspace agent
can reach the Coder server from inside the container. No additional configuration required —
the `host.docker.internal` replacement is baked into the container entrypoint automatically.

**Production deployment (real `CODER_ACCESS_URL`):** With a real `CODER_ACCESS_URL` (an IP or
domain reachable from workspace containers), `host.docker.internal` is not used. Set
`CODER_ACCESS_URL` to a URL that workspace containers on the host network can reach — `127.0.0.1`
will not work for non-Docker templates because it refers to the container's own loopback
interface, not the host.

**Failure symptom:** The workspace agent shows "Connecting" indefinitely and never transitions
to "Connected". Check:

- For local deployments: confirm `CODER_ACCESS_URL` is `http://127.0.0.1:7080` (the default).
  The template automatically rewrites `127.0.0.1` → `host.docker.internal` in the agent
  init script, and adds the `host-gateway` host entry so the workspace container can resolve it.
- For production deployments: verify `CODER_ACCESS_URL` is reachable from a container running
  on the Docker host network. `127.0.0.1` will not work — use a real IP or domain.

### Home directory persistence

Workspace home directories (`/home/coder`) are stored in per-workspace Docker volumes and
survive workspace stop/start cycles. Deleting a workspace deletes its home volume — all files
under `/home/coder` are permanently removed when the workspace is deleted.
