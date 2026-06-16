# Pitfalls Research

**Domain:** Self-hosted Coder production scaffold (Docker Compose, host-disk Postgres, backup/restore, Docker workspace template, Coder Tasks, MCP)
**Researched:** 2026-06-16
**Confidence:** HIGH — synthesized from STACK.md, ARCHITECTURE.md, FEATURES.md, upstream compose.yaml analysis, and domain knowledge across Coder internals, Postgres Docker conventions, and reverse-proxy contract details.

---

## Critical Pitfalls

### Pitfall 1: CODER_ACCESS_URL set to localhost or 127.0.0.1

**What goes wrong:**
Workspace containers boot, the coder-agent tries to dial `CODER_ACCESS_URL` to register, resolves `127.0.0.1` to itself (the workspace container, not the host), and can never reach the Coder server. The workspace is permanently stuck at "Connecting..." and the developer sees no terminal, no IDE, no apps.

**Why it happens:**
The upstream `compose.yaml` ships with `CODER_ACCESS_URL: "127.0.0.1"`. It works for demo purposes where the developer opens `localhost:7080` in a browser but does not create workspaces. Moving to production the compose file is edited minimally, the URL is left as-is, and the workspace breakage only surfaces once the first workspace is provisioned.

**How to avoid:**
Set `CODER_ACCESS_URL` to the real externally-reachable URL in `.env` (`https://coder.example.com`). Never hardcode `127.0.0.1` or `localhost` in compose.yaml. Validate with: `curl -sf https://coder.example.com/healthz` from inside a workspace container.

**Warning signs:**
- All workspaces stuck at "Connecting..." indefinitely
- `coder-agent` logs inside workspace container: `dial tcp 127.0.0.1:7080: connect: connection refused`
- Setting `CODER_ACCESS_URL` is the first fix that clears it every time

**Phase to address:** Phase 1 (compose.yaml hardening / environment configuration)

---

### Pitfall 2: CODER_WILDCARD_ACCESS_URL unset or unrouted at the reverse proxy

**What goes wrong:**
Without `CODER_WILDCARD_ACCESS_URL`, workspace apps (code-server, JetBrains Gateway, port-forwarded services) have no subdomain routing surface. Buttons appear in the Coder dashboard but clicking them either errors or falls back to path-based routing that breaks under typical reverse-proxy configurations. Even when the variable is set, if the external proxy does not route `*.apps.example.com` to `:7080`, apps return 404 or certificate errors.

**Why it happens:**
Two independent omissions: (1) the operator sets `CODER_ACCESS_URL` but does not realize `CODER_WILDCARD_ACCESS_URL` is a separate required variable, and (2) the operator sets the variable but forgets to add a second server block / virtual host for the wildcard in their reverse proxy.

**How to avoid:**
Always set both variables in `.env`. Add a wildcard TLS cert (`*.apps.example.com`) via DNS challenge to the reverse proxy. Add a second proxy rule that routes all of `*.apps.example.com` to `127.0.0.1:7080` with the original `Host` header preserved (do NOT rewrite `Host`). Validate: open code-server from the Coder dashboard and verify the browser URL is on the apps subdomain, not the main domain.

**Warning signs:**
- code-server button in dashboard opens a blank page or 404
- Browser URL for workspace apps is `coder.example.com/...` not `<slug>.apps.example.com/...`
- `CODER_WILDCARD_ACCESS_URL` missing from `docker compose config` output

**Phase to address:** Phase 1 (compose.yaml hardening) + Phase 3 (template with workspace apps)

---

### Pitfall 3: Postgres bind-mount directory wrong ownership (UID 999)

**What goes wrong:**
The `postgres:17` image runs as UID/GID `999` (the `postgres` user). If the host directory (`./data/postgres`) is owned by any other UID — including `root` (created by `docker compose up` when the directory doesn't exist) — Postgres startup fails with `Permission denied` or silently refuses to initialize. The coder container crash-loops because the DB is never healthy.

**Why it happens:**
Developers create the directory with `mkdir` (owner = current user, e.g. UID 1000), or they let Docker Compose auto-create it (owner = root). Neither is UID 999. The postgres image does not chown the bind-mount target on startup — it only chowns on named-volume initialization.

**How to avoid:**
Before the first `docker compose up`, explicitly run:
```bash
mkdir -p ./data/postgres
sudo chown -R 999:999 ./data/postgres
```
Add this step to the bootstrap documentation and to any setup script. Commit a `.gitkeep` inside `data/postgres/` so the directory exists in the repo — but `.gitkeep` does not set ownership, the chown must still happen.

**Warning signs:**
- `docker compose logs database` shows `initdb: error: could not change directory` or `Permission denied`
- `database` service never becomes healthy; `coder` container exits because of `depends_on` gate
- `ls -lan ./data/postgres` shows owner as `0` (root) or `1000` (current user) instead of `999`

**Phase to address:** Phase 1 (compose.yaml hardening / data directory setup)

---

### Pitfall 4: Initializing Postgres into a non-empty or wrong-owned directory

**What goes wrong:**
If the bind-mount target `./data/postgres` already contains data (from a prior Postgres major version, a failed init, or stale files), the `postgres:17` image exits immediately with `FATAL: could not open file "global/pg_filenode.map": No such file or directory` or `data directory has wrong ownership`. The container crashes before the healthcheck passes.

**Why it happens:**
Operators test with named volumes first, then switch to bind mounts but forget the directory isn't clean. Or they run `docker compose up` twice after a failed first run that left partial data. Or they accidentally mount the parent directory (e.g. `./data` instead of `./data/postgres`).

**How to avoid:**
Ensure `./data/postgres` is empty before first `docker compose up`. If re-initializing, `rm -rf ./data/postgres && mkdir -p ./data/postgres && sudo chown -R 999:999 ./data/postgres`. Verify the mount path in compose.yaml is the leaf directory, not the parent.

**Warning signs:**
- `FATAL: database files appear to belong to a different PostgreSQL version` on container start
- `data directory "/var/lib/postgresql/data" has wrong ownership` in container logs
- `ls ./data/postgres` shows unexpected files before first run

**Phase to address:** Phase 1 (compose.yaml hardening)

---

### Pitfall 5: Postgres major-version data incompatibility on upgrade

**What goes wrong:**
Postgres data directories are not forward-compatible across major versions. Changing the image from `postgres:15` to `postgres:17` (or any major jump) with existing data in the bind mount causes the container to refuse to start and prints `FATAL: database files are incompatible with server`. `pg_upgrade` is required but cannot be run directly from a Docker image swap.

**Why it happens:**
Operators update the image tag thinking it is equivalent to a patch upgrade. The `postgres:17` tag gets patch updates automatically (safe), but switching from `postgres:15` to `postgres:17` is a major version change. This is easy to do accidentally when updating compose.yaml.

**How to avoid:**
Pin the full major tag (e.g. `postgres:17`) and never change the major version without a migration plan. For major upgrades: (1) run a full `pg_dump` backup, (2) stop services, (3) wipe `./data/postgres`, (4) update image tag, (5) start DB, (6) restore from dump. Never do an in-place major version upgrade on a bind mount.

**Warning signs:**
- Container logs: `FATAL: database files are incompatible with server`
- Log line: `The data directory was initialized by PostgreSQL version X, which is not compatible with this version Y`
- Any recent change to `postgres:` image tag in compose.yaml

**Phase to address:** Phase 1 (baseline) — document upgrade path; re-addressed in Phase 5 (operations/maintenance)

---

### Pitfall 6: pg_dump TTY corruption — missing `-T` flag on `docker compose exec`

**What goes wrong:**
Running `docker compose exec database pg_dump ... > backup.dump` without the `-T` flag causes Docker to allocate a pseudo-TTY. The TTY injects ANSI escape sequences and carriage-return characters into the binary dump stream, corrupting the file. The dump appears to succeed (exit 0), but `pg_restore` fails with `pg_restore: error: input file does not appear to be a valid archive`.

**Why it happens:**
`docker compose exec` allocates a TTY by default when run interactively. Developers test the command interactively (it works), then copy it into a script. In the script context stdin is not a TTY, but stdout redirection still triggers TTY allocation without `-T` when using some shell configurations.

**How to avoid:**
Always include `-T` on every `docker compose exec` call in scripts:
```bash
docker compose exec -T database pg_dump --format=custom ...
```
Test restored dumps after every new backup script version by running `pg_restore --list backup.dump` which prints the table of contents without restoring — a corrupted file fails here immediately.

**Warning signs:**
- `pg_restore: error: input file does not appear to be a valid archive (too short?)`
- `file` command on the dump shows `ASCII text` instead of `PostgreSQL custom database dump`
- Dump file contains visible text like `[?2004h` or `^[[` at the start

**Phase to address:** Phase 2 (backup/restore scripts)

---

### Pitfall 7: pg_restore over a live database without --clean --if-exists

**What goes wrong:**
Running `pg_restore` into an existing database without `--clean --if-exists` causes conflicts: tables, sequences, and types already exist, and the restore errors out partway through with `ERROR: relation "X" already exists`. The database ends up in a partial, inconsistent state — neither fully old nor fully restored.

**Why it happens:**
The restore command is written for a fresh database (the "disaster recovery" mental model) but is run against a live database that already has the Coder schema. This happens when testing restores on a running instance without dropping the schema first.

**How to avoid:**
Always include `--clean --if-exists` in the restore script. These flags cause `pg_restore` to emit `DROP ... IF EXISTS` statements before recreating each object. Combine with `--no-owner --no-acl` to avoid role dependency errors. For full disaster recovery, also use `--create` and connect to `postgres` superuser database rather than the target database.

**Warning signs:**
- `pg_restore: error: could not execute query: ERROR: relation "X" already exists`
- Restore script exits nonzero but partial data is written
- `SELECT count(*) FROM workspaces` returns different values before and after restore

**Phase to address:** Phase 2 (backup/restore scripts)

---

### Pitfall 8: PGPASSWORD not reaching the container process (interactive password prompt breaks cron)

**What goes wrong:**
Backup/restore scripts run fine interactively but hang when called from cron. The cron job never completes. Database operations that require a password get an interactive `Password:` prompt, and cron has no TTY to receive input — the process hangs until the cron timeout kills it, producing no dump.

**Why it happens:**
`PGPASSWORD` is set in the script's environment but `docker compose exec` creates a new environment for the container process. The variable must be passed explicitly. Some operators use `.pgpass` on the host but forget it only applies to `psql`/`pg_dump` run directly on the host, not inside the container via `docker exec`.

**How to avoid:**
Prefix every `docker compose exec` database command with the `PGPASSWORD` export in the same command, or use `docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" database pg_dump ...`. The `-e` flag passes the variable into the container process environment. Test non-interactively: run the script redirecting stdin from `/dev/null` to confirm it never prompts.

**Warning signs:**
- Cron job produces no output and no dump files, but exits 0
- Running the script manually works; running it under `sudo -u cron_user` or without a terminal hangs
- `jobs` shows the backup script process alive but stalled for minutes

**Phase to address:** Phase 2 (backup/restore scripts)

---

### Pitfall 9: Bootstrap ordering violation — admin user creation with server running

**What goes wrong:**
`coder server create-admin-user --postgres-url ...` is documented as a command that writes directly to the database. If it is run while `coderd` is also running, the behavior is undefined — the server may reject the direct-DB write, or both processes may interfere. The actual failure mode is that `coderd` detects the new user, marks it as incomplete, and the credentials do not work for login.

**Why it happens:**
Operators run `docker compose up` to start everything, then try to create the admin user against the running stack. The `create-admin-user` subcommand is a one-shot database seeding command, not an API call — it is designed for pre-server use.

**How to avoid:**
Use Method B instead: let `coderd` run and create the first admin account via the web UI at `https://coder.example.com` on first visit — the first user to register automatically receives the Owner role. If headless seeding is required, stop the `coder` container first: `docker compose stop coder`, run `create-admin-user` with `--postgres-url`, then `docker compose start coder`.

**Warning signs:**
- Admin credentials created via `create-admin-user` are rejected at login with "invalid credentials"
- `coderd` logs show the user record in a pending/incomplete state
- Both `coder` and `database` containers are running when `create-admin-user` is executed

**Phase to address:** Phase 1 (compose.yaml hardening + bootstrap documentation)

---

### Pitfall 10: Workspace home not persisted — Coder Tasks agent state lost on stop

**What goes wrong:**
Without a persistent Docker volume for `/home/coder`, every workspace stop/start cycle destroys the agent state. Coder's AgentAPI writes session state to the workspace home. For Coder Tasks, this means in-progress task state, Claude Code configuration, and MCP server configuration are lost every time a workspace stops. The task appears to start fresh with no history.

**Why it happens:**
Developers add a `docker_container` resource to the Terraform template without adding the corresponding `docker_volume` resource. The container is ephemeral by default; workspace home lives only in the container layer.

**How to avoid:**
Add a `docker_volume` resource named with the workspace ID (immutable) and mount it at `/home/coder`:
```hcl
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.id}-home"
  lifecycle { ignore_changes = all }
}
```
The `lifecycle { ignore_changes = all }` prevents Terraform from destroying the volume if the workspace is renamed. This is non-optional for Coder Tasks.

**Warning signs:**
- Claude Code settings reset on every workspace restart
- MCP server configuration (`~/.config/claude/`) missing after workspace stop/start
- Coder Tasks show "starting from scratch" on every run despite prior context
- `docker volume ls` shows no volume for the workspace ID

**Phase to address:** Phase 3 (Docker workspace template)

---

### Pitfall 11: claude-code module v5 dropping coder_ai_task — Tasks UI never populated

**What goes wrong:**
The `claude-code` module v5 removed the built-in `coder_ai_task` wiring that existed in v4.x. Using module v5 with the expectation that it wires up Coder Tasks automatically produces a template where the Tasks UI shows nothing, and `coder tasks run` silently does nothing or errors.

**Why it happens:**
v4.x of the module had `experiment_report_tasks = true` and `task_app_id` output. v5 dropped both. Operators migrating from v4 examples or reading v4 docs expect the module to handle Tasks automatically.

**How to avoid:**
With `coder/claude-code 5.x`, wire `coder_ai_task` directly in the template:
```hcl
resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  open_in      = "slim-window"
  command      = "claude"
}

resource "coder_ai_task" "task" {
  count  = data.coder_task.me.enabled ? data.coder_workspace.me.start_count : 0
  app_id = coder_app.claude.id
}
```
Alternatively, use `coder/claude-code 4.x` if the auto-wiring is preferred, but note that 4.x is no longer the maintained version.

**Warning signs:**
- Coder Tasks UI shows the template but tasks never populate or run
- `coder tasks run --template <name> "..."` exits 0 but no workspace is created
- Template plan does not contain a `coder_ai_task` resource
- Module version is `5.x` and no separate `coder_ai_task` resource exists in `main.tf`

**Phase to address:** Phase 4 (Coder Tasks integration)

---

### Pitfall 12: Docker socket GID mismatch — workspace provisioning silently fails

**What goes wrong:**
The `coder` container mounts `/var/run/docker.sock` to provision workspace containers. If the Coder process inside the container does not have write permission on the socket, `docker run` calls from the Terraform provisioner fail with `permission denied while trying to connect to the Docker daemon socket`. The workspace creation fails at the Terraform apply step with an opaque Docker provider error.

**Why it happens:**
The Docker socket on the host is typically owned by group `docker` (GID varies by distro — commonly `998` on Arch/RHEL, `999` on Debian/Ubuntu, `0` on some systems). The `coder` container's process runs as a non-root user that is not in that group. The `group_add` directive in compose.yaml is commented out in the upstream baseline.

**How to avoid:**
Check the host Docker socket GID: `stat -c '%g' /var/run/docker.sock`. Uncomment and set `group_add` in compose.yaml:
```yaml
coder:
  group_add:
    - "998"  # replace with actual docker GID from stat command
```
Alternatively, run a test: `docker compose exec coder docker ps` — if it works, the socket is accessible.

**Warning signs:**
- Workspace creation fails with `Error: error creating Docker container: permission denied`
- `docker compose logs coder` shows `Got permission denied while trying to connect to the Docker daemon socket`
- `docker compose exec coder docker ps` returns `permission denied`

**Phase to address:** Phase 3 (Docker workspace template — first place Docker socket is exercised)

---

### Pitfall 13: Workspace container agent using localhost to reach Coder server

**What goes wrong:**
When the Terraform template provisions a workspace container, the `coder_agent.init_script` embeds the `CODER_ACCESS_URL`. If `CODER_ACCESS_URL` is `https://coder.example.com` (correct), the agent dials the external URL — which works if the host's reverse proxy is reachable from the workspace container. However, in local/dev scenarios where `CODER_ACCESS_URL` is inadvertently set to an IP that resolves differently inside Docker, the agent cannot reach coderd.

**Why it happens:**
The workspace container is on a Docker bridge network. `host.docker.internal` is the correct way to reach the Docker host from inside a container. The upstream template shows a `replace()` call that rewrites `localhost`/`127.0.0.1` in `init_script` to `host.docker.internal` — this is mandatory for local setups but is sometimes omitted.

**How to avoid:**
Include the replace pattern in the Docker template:
```hcl
entrypoint = ["sh", "-c",
  replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
]
host {
  host = "host.docker.internal"
  ip   = "host-gateway"
}
```
In production with a real `CODER_ACCESS_URL`, this replace is a no-op and causes no harm — always include it.

**Warning signs:**
- Workspace stuck at "Connecting..." in local/dev setup
- Agent logs: `dial tcp [::1]:7080: connect: connection refused`
- Works when `CODER_ACCESS_URL` is the real domain but fails when set to a local IP

**Phase to address:** Phase 3 (Docker workspace template)

---

### Pitfall 14: Reverse proxy rewrites Host header — workspace app routing breaks

**What goes wrong:**
Coder's wildcard subdomain routing uses the `Host` header to identify which workspace and app is being requested. If the reverse proxy rewrites `Host` to `127.0.0.1:7080` or `coder:7080` (common in naive proxy configs), all workspace app requests are misrouted. Code-server, JetBrains Gateway, and any port-forwarded app return 404 or a "workspace not found" error from coderd.

**Why it happens:**
Default nginx `proxy_pass` configurations set `proxy_set_header Host $host` (correct) but some proxy tutorials use `proxy_set_header Host $proxy_host` or omit the header entirely, causing the upstream host to default to the backend address.

**How to avoid:**
The reverse proxy must forward the original `Host` header:
```nginx
proxy_set_header Host $host;
```
It must also forward WebSocket upgrade headers:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```
And disable response buffering for streaming/terminal connections:
```nginx
proxy_buffering off;
```
Validate by opening code-server from the dashboard and inspecting the request `Host` header in browser devtools.

**Warning signs:**
- Workspace apps return 404 even though `CODER_WILDCARD_ACCESS_URL` is correctly set
- Browser network tab shows `Host: 127.0.0.1:7080` on requests to workspace apps
- Terminal in web UI freezes or disconnects frequently (buffering issue)
- JetBrains Gateway connection repeatedly drops

**Phase to address:** Phase 1 (proxy contract documentation) + Phase 3 (validation during template testing)

---

### Pitfall 15: ANTHROPIC_API_KEY committed to git or exposed via template variables

**What goes wrong:**
The API key ends up in git history (via `.env` committed, or hardcoded in `main.tf`), or it is visible to workspace users via Terraform output or non-sensitive template variables. In the worst case, the key is exposed in `docker inspect` output on the workspace container.

**Why it happens:**
Operators hardcode the key during development for convenience. Template variables are declared without `sensitive = true`. The compose.yaml passes the key as a plain environment variable without sourcing from `.env`.

**How to avoid:**
Source from `.env` (gitignored): `ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}` in compose environment block. In the Terraform template, declare the variable with `sensitive = true`:
```hcl
variable "anthropic_api_key" {
  type      = string
  sensitive = true
}
```
Never log or output it. In workspace containers, it is accessible in the environment but that is expected — it is scoped to the workspace owner.

**Warning signs:**
- `git log -p` shows `sk-ant-` in any committed file
- `terraform plan` output shows the key value in plaintext
- `docker inspect coder` reveals the key in `Env` array without masking

**Phase to address:** Phase 1 (secrets/env pattern) + Phase 3 (template variables)

---

### Pitfall 16: Postgres published on a host port in compose.yaml

**What goes wrong:**
Uncommenting the `ports: - "5432:5432"` block in the database service exposes Postgres to the network on the Docker host. Combined with weak passwords (the upstream defaults are `username`/`password`), this creates an externally accessible database — a common attack vector for credential stuffing and ransomware.

**Why it happens:**
Operators uncomment the port for convenience during development or debugging, then forget to remove it before deploying. The upstream compose.yaml helpfully comments this out by default.

**How to avoid:**
Never expose Postgres on a host port in production. Access the database from the host via `docker compose exec database psql` or by running `pg_dump` through the container. The Coder server reaches Postgres by the Docker Compose service name (`database:5432`) on the internal network — no host port needed.

**Warning signs:**
- `docker compose ps` shows `0.0.0.0:5432->5432/tcp` for the database service
- `nmap localhost` shows port 5432 open
- Firewall rules do not block port 5432 from external traffic

**Phase to address:** Phase 1 (compose.yaml hardening)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `CODER_VERSION: latest` in compose.yaml | Always runs newest Coder | Silent breaking upgrades on `docker compose pull`; impossible to roll back | Never in production — always pin a version |
| Named volume instead of bind mount for Postgres | Zero setup (no chown needed) | Backup scripts require `docker cp` or helper containers; data invisible on host | Only for throwaway dev instances |
| Hardcoded DB credentials (`username`/`password`) | Faster setup | Credential exposure if repo or logs are ever shared | Never — always override via `.env` |
| Skipping `--clean --if-exists` in pg_restore | Simpler restore command | Partial restores on live databases leave schema in inconsistent state | Only when restoring to a verified empty database |
| Skipping `lifecycle { ignore_changes = all }` on home volume | Simpler Terraform | Volume deleted and recreated on workspace rename, destroying developer's data | Never — always include for workspace home volumes |
| Not testing restore after writing backup script | Saves time | Backups exist but are unrestorable (corrupted format, wrong flags) | Never — test restore before any production data accumulates |
| Plain SQL dump (`-Fp`) instead of custom format (`-Fc`) | Human-readable output | No built-in compression; no selective restore; larger files | Only for ad-hoc inspection of schema structure |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| External reverse proxy | Rewrites `Host` header to backend address | `proxy_set_header Host $host` — forward original |
| External reverse proxy | Buffers WebSocket/streaming responses | `proxy_buffering off` + forward `Upgrade`/`Connection` headers |
| External reverse proxy | Single server block for `coder.example.com` only | Separate (or wildcard) block for `*.apps.example.com` routing to same upstream |
| External reverse proxy | Self-signed cert on `*.apps.example.com` | Must be trusted by browsers — use Let's Encrypt DNS challenge or on-demand TLS |
| Docker socket mount | GID not added to coder container | `group_add: [<docker-gid>]` in compose.yaml |
| Coder MCP server (stdio) | Running `coder exp mcp server` as a persistent daemon | It is a stdio process — run it via the MCP client config, not as a background service |
| Coder MCP HTTP endpoint | Expecting it to work without experiment flags | Requires `CODER_EXPERIMENTS=oauth2,mcp-server-http` on the server |
| Terraform template push | Pushing before `coder login` succeeds | Gate template push on `curl -sf .../healthz` success; require login session first |
| `coder_ai_task` resource | Using it with `coder/coder` provider `< 2.13` | Pin `required_providers { coder = { version = ">= 2.13" } }` |
| PGPASSWORD with docker exec | Setting `PGPASSWORD` in shell but not passing to container | Use `docker compose exec -T -e PGPASSWORD="$PW" database ...` |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| All workspaces starting simultaneously | Docker daemon queues all container creates; workspaces appear to start but take 5-10 min | Document that concurrent starts compete for Docker socket; advise staggered starts | 5+ workspaces started at once |
| Postgres on spinning disk or NFS | Coder state polling (workspace status, audit log writes) causes I/O wait; dashboard appears sluggish | Use SSD-backed host storage for `./data/postgres` | Any production use on slow storage |
| Workspace images not pre-pulled | First workspace start triggers Docker pull; appears hung with no logs | Pre-pull base image on the host before first workspace: `docker pull <image>` | First workspace creation on a fresh host |
| Backup script without exit-code check | Silently-failed dumps fill cron logs with success | `set -e` at top of backup script; verify dump file is non-zero size | At first backup failure |
| Coder server restart while workspace is running | Workspace agents reconnect automatically via WireGuard retry logic; this is normally fine | None needed — by design | Not a trap; expected behavior |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| `.env` committed to git | All secrets (DB password, API key, admin credentials) in git history | `.gitignore` includes `.env`; CI blocks commits containing `PGPASSWORD=` or `sk-ant-` patterns |
| Postgres exposed on host port | Database directly reachable from network; credential stuffing, data exfiltration | Keep `ports:` commented out; access via `docker compose exec` only |
| `ANTHROPIC_API_KEY` in non-sensitive Terraform variable | Key appears in `terraform plan` output, CI logs, Coder UI | Declare with `sensitive = true`; verify it is masked in plan output |
| Docker socket mount without group restriction | Any process in the coder container has full Docker daemon access | Acceptable for single-host setup; document that the Coder container should be treated as a privileged service |
| Weak default DB credentials never changed | `username`/`password` credentials are known defaults; any leaked `CODER_PG_CONNECTION_URL` is immediately usable | Override `POSTGRES_USER`, `POSTGRES_PASSWORD` in `.env` before first `docker compose up` |
| `CODER_WILDCARD_ACCESS_URL` on a top-level domain | Cookie scope issues: cookies for `coder.example.com` bleed into `*.example.com` | Always use a dedicated subdomain: `*.apps.coder.example.com` not `*.example.com` |

---

## "Looks Done But Isn't" Checklist

- [ ] **Postgres bind mount:** Directory exists in repo but ownership not set — verify `stat ./data/postgres` shows UID 999 before first `docker compose up`
- [ ] **Backup script:** Script exists and is executable — verify by running it with `DUMP_FILE=$(mktemp)` then checking `pg_restore --list $DUMP_FILE` succeeds (proves non-corruption)
- [ ] **CODER_ACCESS_URL:** Set in `.env` to a real URL — verify `docker compose config` shows it is NOT `127.0.0.1`
- [ ] **CODER_WILDCARD_ACCESS_URL:** Set in compose.yaml/`.env` — verify by opening code-server from dashboard and confirming the URL is on the apps subdomain
- [ ] **Workspace home volume:** `docker_volume` resource present in template — verify `docker volume ls` shows the volume after first workspace start
- [ ] **coder_ai_task:** Resource present in template AND `data.coder_task.me` data source declared — verify Coder Tasks UI lists the template as task-capable
- [ ] **claude-code module wiring:** Using v5 — verify a standalone `coder_ai_task` resource exists (module v5 does NOT include it)
- [ ] **Docker socket GID:** `group_add` set in compose.yaml — verify `docker compose exec coder docker ps` succeeds
- [ ] **Proxy websocket headers:** Reverse proxy config includes `Upgrade` and `Connection` passthrough — verify web terminal does not disconnect after 60 seconds of idle
- [ ] **Secrets pattern:** `.env` in `.gitignore` AND not already tracked — verify `git ls-files .env` returns empty
- [ ] **Postgres port not exposed:** `ports:` block under `database` is commented out — verify `docker compose ps` does not show `5432->5432`

---

## Recovery Strategies

| Pitfall Occurred | Recovery Cost | Recovery Steps |
|-----------------|---------------|----------------|
| CODER_ACCESS_URL was localhost, workspaces broken | LOW | Update `.env`, `docker compose restart coder`; workspaces must be stopped/started to pick up new agent URL |
| Postgres bind mount bad ownership | LOW | `docker compose stop`, `sudo chown -R 999:999 ./data/postgres`, `docker compose start database` |
| Postgres data initialized by wrong version | HIGH | Stop all services, `pg_dump` from the old version container, wipe `./data/postgres`, start with new version, restore from dump |
| Corrupt backup dump (TTY corruption) | MEDIUM | Identify last known-good dump with `pg_restore --list`; fix script to add `-T`; re-dump immediately |
| Partial restore (missing --clean) | MEDIUM | Stop `coder` service, drop and recreate the database in psql, restore again with `--clean --if-exists` |
| API key committed to git | HIGH | Rotate key immediately at Anthropic console; use `git filter-repo` or BFG to scrub history; force-push; notify all collaborators to re-clone |
| Workspace home volume deleted on rename | HIGH | Workspace data is gone; recreate from git clone; preventable with `lifecycle { ignore_changes = all }` |
| Docker socket GID wrong, workspaces won't provision | LOW | `stat -c '%g' /var/run/docker.sock` to get correct GID; update `group_add` in compose.yaml; `docker compose restart coder` |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CODER_ACCESS_URL = localhost | Phase 1: compose.yaml hardening | `docker compose config` shows real URL; workspace agent connects |
| CODER_WILDCARD_ACCESS_URL missing/unrouted | Phase 1 (config) + Phase 3 (validate) | code-server opens on apps subdomain |
| Postgres UID 999 ownership | Phase 1: data directory setup | `stat ./data/postgres` UID = 999 before `docker compose up` |
| Non-empty/wrong-version data dir | Phase 1: bootstrap docs | Postgres starts healthy on first run |
| Postgres major version upgrade path | Phase 1 (document); Phase 5+ (ops) | Upgrade runbook exists; tested with a backup/restore cycle |
| pg_dump TTY corruption | Phase 2: backup script | `pg_restore --list <dump>` succeeds on every backup |
| pg_restore over live DB | Phase 2: restore script | Restore script passes `--clean --if-exists`; tested on staging |
| PGPASSWORD not reaching container | Phase 2: backup/restore scripts | Scripts tested with `stdin < /dev/null` (no TTY) |
| Bootstrap ordering violation | Phase 1: bootstrap documentation | First-run instructions tested on a clean host |
| Workspace home not persisted | Phase 3: Docker template | `docker volume ls` shows home volume after workspace start |
| claude-code v5 missing coder_ai_task | Phase 4: Coder Tasks integration | `terraform plan` shows `coder_ai_task` resource; Tasks UI lists template |
| Docker socket GID mismatch | Phase 3: Docker template | `docker compose exec coder docker ps` succeeds before creating first workspace |
| Agent using localhost to reach Coder | Phase 3: Docker template | Agent connects in under 30s; no "Connecting..." timeout |
| Reverse proxy Host header rewrite | Phase 1 (document) + Phase 3 (test) | Workspace app URL uses apps subdomain; terminal doesn't freeze |
| ANTHROPIC_API_KEY in git | Phase 1: secrets pattern | `git log -p | grep sk-ant` returns empty |
| Postgres port exposed | Phase 1: compose.yaml hardening | `docker compose ps` shows no 5432 host port mapping |

---

## Sources

- Upstream `compose.yaml` in this repository — baseline anti-patterns (localhost access URL, named volumes, commented group_add, default credentials)
- STACK.md (this project) — UID 999 pattern, `-T` flag, `--clean --if-exists`, `PGPASSWORD` env var strategy, claude-code v5 dropping `coder_ai_task`
- ARCHITECTURE.md (this project) — proxy contract (Host header, WebSocket, wildcard cert), bootstrap ordering, Docker socket GID, `host.docker.internal` replace pattern
- FEATURES.md (this project) — persistent home requirement for Coder Tasks, `lifecycle { ignore_changes = all }` for home volume, dependency map
- [Coder Docker Install docs](https://coder.com/docs/install/docker) — `CODER_ACCESS_URL` localhost warning (reproduced verbatim in upstream compose comment)
- [Coder Tasks Core Principles](https://coder.com/docs/ai-coder/tasks-core-principles) — persistent storage requirement for AgentAPI state
- [docker-library/postgres GitHub](https://github.com/docker-library/postgres) — UID 999 bind mount ownership convention
- [Coder modules — claude-code](https://github.com/coder/modules/tree/main/claude-code) — v5 changelog confirming `task_app_id` output removed

---

*Pitfalls research for: Self-hosted Coder production scaffold (Docker Compose, host-disk Postgres, Docker workspace template, Coder Tasks, MCP)*
*Researched: 2026-06-16*
