# Pitfalls Research

**Domain:** Portable Claude Code config via shared Docker volume in a Coder workspace Terraform template
**Researched:** 2026-06-17
**Confidence:** HIGH

This file covers failure modes specific to adding a per-owner shared Docker volume for `~/.claude/` and `~/.claude.json` to the existing `templates/docker/main.tf` template. Generic Docker advice is excluded; every pitfall is anchored to this codebase's concrete patterns.

---

## Critical Pitfalls

### Pitfall 1: Concurrent-Write Clobbering of Claude Session State

**What goes wrong:**
Claude Code writes frequently to files inside `~/.claude/` — active session state, history, todo lists, and project metadata. When two of the same owner's workspaces run simultaneously (both mounting the same shared volume read-write), they see an eventually-consistent but unsynchronized view of the directory. Each process reads a stale snapshot, makes edits, and writes back — the last writer wins and silently discards the other's changes. Session history entries disappear. Todo items written in workspace A are gone when Claude resumes in workspace B. Projects directory can accumulate partial or duplicate entries.

**Why it happens:**
Docker named volumes provide POSIX file semantics — no advisory locking, no atomic cross-process coordination. Claude Code is designed for single-user, single-active-session use and does not implement its own file locking. Two processes writing `~/.claude/todos.json` (or equivalent) through the same bind point will produce torn writes under concurrent access. The Coder template has no guard preventing two of the same owner's workspaces from running simultaneously.

**How to avoid:**
- In the README operator runbook, document the limitation explicitly: one active workspace per owner at a time avoids lost writes. This is the primary mitigation for v1.1.
- For future hardening: a startup-script flock guard can prevent Claude from launching in a second workspace if a lock file is held in `~/.claude/.workspace.lock` (using `flock -n`). This is a v2+ enhancement.
- Mount the volume `read_only = true` in workspace containers if Claude is only needed for reading config/auth (not an option if the user actively uses Claude in the workspace).
- The Coder template can include a `coder_agent` `startup_script` warning that logs when the shared volume lock is already held.

**Warning signs:**
- User reports Claude "forgot" a task it just completed, or history shows gaps.
- `~/.claude/` contains files with modification times from two different running containers at the same second.
- `docker inspect` shows the same volume attached to two running containers under the same owner.

**Phase to address:**
v1.1, Phase 1 (volume wiring) — document the caveat in the README at the same time the volume is introduced. The flock guard is a v2 enhancement and should be called out as a deferred item.

---

### Pitfall 2: File-vs-Directory Mount Trap for `~/.claude.json`

**What goes wrong:**
`~/.claude.json` is a file, not a directory. If you declare a `docker_volume` and mount it at `/home/coder/.claude.json`, Docker creates a directory named `.claude.json` at that path (volumes are always directory mounts). Claude Code then cannot read or write its global settings file because it finds a directory where it expects a plain file. The failure mode is silent on first start — Claude launches but uses defaults; on write it may silently fail or error depending on Claude version. The directory cannot be easily removed because it is a mount point.

**Why it happens:**
Docker volume mounts are always directories. The distinction between "mount a volume that contains a file" and "mount a volume at a file path" is not enforced by the Docker or Terraform provider — the provider will accept the mount declaration without error and Docker will create the directory.

**How to avoid:**
Two correct approaches (pick one, be consistent):

1. **`CLAUDE_CONFIG_DIR` relocation**: Set the environment variable `CLAUDE_CONFIG_DIR=/home/coder/.claude` in the `coder_agent` env block. When this variable is set, Claude Code stores its global config file inside that directory (as `config.json` or similar) instead of at `~/.claude.json`. This makes both `~/.claude/` and the global config file live inside the same shared volume, eliminating the need to mount `~/.claude.json` as a separate volume at all. This is the recommended approach.

2. **Symlink approach**: Mount the shared volume at a neutral path (e.g. `/home/coder/.claude-shared`) and add a `startup_script` step that creates a symlink: `ln -sf /home/coder/.claude-shared/.claude.json /home/coder/.claude.json`. This works but introduces startup-script complexity and a race condition if Claude launches before the symlink is established.

**Warning signs:**
- `ls -la /home/coder/.claude.json` inside a running container shows `drwxr-xr-x` (directory, not file).
- Claude settings changes don't persist across workspace restarts.
- Error log: `ENOTDIR` or `Is a directory` when Claude tries to open `~/.claude.json`.

**Phase to address:**
v1.1, Phase 1 (volume wiring) — the `CLAUDE_CONFIG_DIR` approach must be in place before any testing; catching this during UAT would require a teardown and rebuild of already-provisioned volumes.

---

### Pitfall 3: Owner-Name Keying Creates Orphaned Volumes on Username Change

**What goes wrong:**
If the shared Claude volume name is keyed on `data.coder_workspace_owner.me.name` (the display username) instead of `data.coder_workspace_owner.me.id` (the immutable UUID), a Coder admin renaming the user causes Terraform to compute a new volume name on the next `terraform apply`. The provider destroys the old volume (and all Claude config, auth, and history in it) and creates a fresh empty volume under the new name. The prior volume becomes an orphan — visible in `docker volume ls` but no longer referenced by any template resource.

The existing `docker_volume.home_volume` in this template already demonstrates the correct pattern: it keys on `data.coder_workspace.me.id` (workspace UUID) with a comment explicitly noting that workspace name can change and would orphan the volume.

**Why it happens:**
Developers copy the naming pattern but reach for `.name` because it produces human-readable volume names for debugging. The `data.coder_workspace_owner.me.name` field looks stable but is actually mutable.

**How to avoid:**
Key the shared Claude volume on the immutable owner UUID:

```hcl
resource "docker_volume" "claude_volume" {
  name = "coder-claude-${data.coder_workspace_owner.me.id}"

  lifecycle {
    ignore_changes = [name]
  }
  ...
}
```

Mirror `ignore_changes = [name]` exactly as the home volume does — this is already established convention in this template (see `docker_volume.home_volume`, line 125). The `ignore_changes` guard protects against any future name-format refactoring forcing an unintended destroy.

Add a human-readable label for debugging (safe because labels are not the primary key):

```hcl
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
```

**Warning signs:**
- After a username change, `docker volume ls | grep coder-claude` shows two volumes for the same logical owner.
- Claude prompts for login on next workspace start (empty new volume).
- `terraform plan` on a running workspace shows a `docker_volume` destroy + create instead of no-op.

**Phase to address:**
v1.1, Phase 1 (volume resource declaration) — must be correct from the first commit. Retrofitting after volumes are in production requires a manual data migration.

---

### Pitfall 4: Empty Volume Owned by Root — Claude Can't Write Config

**What goes wrong:**
A freshly created Docker named volume has its root directory owned by `root:root` with permissions `755`. The workspace container runs as the `coder` user (UID 1000). On first start, Claude Code attempts to write `~/.claude/credentials.json` (or equivalent) and gets `EACCES` — permission denied. The login flow fails silently: the browser OAuth completes, the callback writes the credential, the write fails, and on the next command Claude prompts for login again.

**Why it happens:**
Docker named volumes do not inherit the UID/GID of the process that first writes to them unless that first write happens as the right user. The `codercom/enterprise-base:ubuntu` image runs as UID 1000 (`coder`), but an empty volume presented at `/home/coder/.claude` starts owned by `root`. Unlike the home volume (which is seeded via the `cp -rT /etc/skel ~` step running as `coder`), the Claude volume has no seeding step that establishes the right ownership before Claude tries to use it.

**How to avoid:**
Add a `startup_script` step that runs before Claude initialization, establishing ownership on the shared volume mount point:

```bash
# Ensure the shared Claude config directory is owned by the workspace user.
# Required on first start (empty volume is root-owned by Docker).
if [ ! -f ~/.claude/.owner_init ]; then
  sudo chown -R coder:coder ~/.claude 2>/dev/null || true
  mkdir -p ~/.claude
  touch ~/.claude/.owner_init
fi
```

Alternatively, use a Terraform `null_resource` or the Docker provider's `volumes_from` / `mounts` with a `tmpfs` seeding container, but the startup script approach is simpler and consistent with this template's existing skel-seeding pattern.

If the workspace image supports it, pre-create the directory in the Dockerfile with the correct UID. This is the cleanest fix but requires a custom image.

**Warning signs:**
- `ls -la /home/coder/ | grep .claude` shows `.claude` owned by `root` inside a running container.
- Claude login loop: auth completes in browser, but `claude auth status` still reports unauthenticated.
- `~/.claude/.credentials.json` does not exist after a completed OAuth flow.

**Phase to address:**
v1.1, Phase 1 (volume wiring + startup script) — the permission fix must be part of the startup script added in the same commit as the volume mount.

---

### Pitfall 5: `claude-code` Module Version Trap — v5 vs v4 and Conflict with Pre-Populated Volume

**What goes wrong:**
Two sub-problems:

**5a. Unnecessary v4 pin:** CLAUDE.md notes that `coder/claude-code v5.x` dropped `coder_ai_task` wiring. This project does NOT use Coder Tasks in v1.1 (deferred to v2). Using v4 just to get Tasks wiring that isn't being used introduces an unnecessary version lag and a misleading signal to future readers. v5.2.0 is the current maintained version and is the correct choice for pure Claude Code installation without Tasks.

**5b. Module's first-run config step conflicts with a pre-populated shared volume:** The `coder/claude-code` module runs an install + configuration script during agent startup. If the shared volume already contains credentials and settings from a previous workspace start, the module's config step may overwrite or reset portions of the config (API key injection, model selection) in ways that conflict with the persisted state. Specifically, if the module writes `~/.claude.json` (or the `CLAUDE_CONFIG_DIR` target) unconditionally, it can clobber user-customized settings.

**How to avoid:**
- Use `coder/claude-code 5.2.0` (current stable, per CLAUDE.md). Do not use v4 unless `coder_ai_task` integration via the module is specifically needed.
- Audit the module's startup behavior: check whether it writes config unconditionally or only when config is absent. Most Coder registry modules guard with `[ -f ~/.claude.json ] || ...` patterns. If the module does write unconditionally, pass the `ANTHROPIC_API_KEY` as a module variable (the module will inject it idempotently) rather than also writing it to the persisted config file.
- The `CLAUDE_CONFIG_DIR` approach (Pitfall 2) gives the module a predictable, volume-backed location; the module should be told to use it via its `env` pass-through if it supports that variable.

**Warning signs:**
- User reports their Claude model preference or MCP server config resets on every workspace start.
- `~/.claude/` shows modification times matching workspace start times, not user-edit times.
- `terraform plan` shows `module.claude-code` triggering changes on every apply.

**Phase to address:**
v1.1, Phase 1 (module wiring) — select the correct version and audit the module's idempotency before wiring the shared volume. If the module is not idempotent, add a guard in the startup script.

---

### Pitfall 6: Credential Location Assumptions — `~/.claude/.credentials.json` Not Inside Shared Path

**What goes wrong:**
Claude Code on Linux stores OAuth credentials at `~/.claude/.credentials.json`. If the shared volume is mounted only at `~/.claude/` (the directory), the credentials file is inside the shared volume and roams correctly. However, if the shared volume is mounted at `~/.claude/` but `~/.claude.json` (the global settings file, handled separately — see Pitfall 2) is stored outside the volume (e.g. at a hardcoded `~/.claude.json` path that is part of the home volume, not the shared volume), then settings persist per-workspace while credentials roam per-owner. The user is authenticated in one workspace and not in another.

The `devcontainer.json` in this repository demonstrates this gap in a different context: it mounts the volume at `/home/node/.claude` (directory only) and makes no provision for `/home/node/.claude.json`. Any global settings in `.claude.json` are lost on devcontainer rebuild. This is a real, confirmed gap in the current devcontainer setup.

**Why it happens:**
The Claude config surface has two roots: the `~/.claude/` directory (credentials, projects, history) and `~/.claude.json` (global settings, model preferences, MCP server list). Developers mount the directory and assume that covers everything. It does not. `~/.claude.json` is a sibling of `~/.claude/`, not inside it.

**How to avoid:**
Use the `CLAUDE_CONFIG_DIR` approach (see Pitfall 2): setting `CLAUDE_CONFIG_DIR=/home/coder/.claude` causes Claude Code to colocate the settings file inside the `.claude/` directory, eliminating the split. Verify after first login that `~/.claude/` contains all expected files and `~/.claude.json` does not appear as a separate file in the home directory.

For the devcontainer specifically: add `~/.claude.json` awareness — either mount a second volume for it or adopt `CLAUDE_CONFIG_DIR` in the devcontainer feature config.

**Warning signs:**
- `ls -la /home/coder/` shows `.claude.json` as a regular file NOT on the shared volume (i.e., it is on the home volume, not the Claude volume).
- After workspace recreation, model preferences or MCP server config reverts to defaults even though auth still works.
- `docker inspect <claude-volume>` shows no `.claude.json` file inside when listing via `docker run --rm -v claude-vol:/data alpine ls /data`.

**Phase to address:**
v1.1, Phase 1 (volume design) — the `CLAUDE_CONFIG_DIR` decision eliminates this pitfall at design time. Also add a note to the devcontainer gap in the operator runbook.

---

### Pitfall 7: Nested Mount Shadowing — `/etc/skel` Seeding Writes Into the Wrong Layer

**What goes wrong:**
The existing `startup_script` in `coder_agent.main` seeds the home directory from `/etc/skel` on first start:

```bash
if [ ! -f ~/.init_done ]; then
  cp -rT /etc/skel ~
  touch ~/.init_done
fi
```

When `~/.claude` is separately mounted as a Docker volume (a subpath mount over the home volume), Docker's nested mount semantics cause the `.claude` directory inside the home volume to be hidden by the Claude volume at that path. The `cp -rT /etc/skel ~` command sees `~/.claude` as the live Claude volume — NOT the home volume's `.claude` directory. If `/etc/skel/.claude/` contains any files (e.g. a default config seeded by the template author), those files are written into the shared Claude volume on the first workspace start of whoever starts first. This pollutes the shared volume with skel defaults, overwriting any pre-existing user config.

Conversely, if the workspace image includes `/etc/skel/.claude.json`, the skel copy writes `.claude.json` into the home volume (the home volume path, not the Claude volume) because `.claude.json` is not shadowed by the Claude volume mount. This means `.claude.json` gets re-seeded from skel on every fresh home volume, ignoring any user customization stored in the Claude volume.

**Why it happens:**
The `cp -rT /etc/skel ~` pattern predates the nested mount design. It is correct for single-volume home setups but becomes unpredictable when subpath mounts are introduced.

**How to avoid:**
- Do not put anything in `/etc/skel/.claude/` or `/etc/skel/.claude.json` in the workspace image. Keep skel free of Claude paths — the shared volume is the canonical source of truth for all Claude config.
- If the `startup_script` skel-seeding step needs to remain, add an explicit exclusion or change it to only seed specific known-safe files (`.bashrc`, `.profile`) rather than the entire skel tree.
- The `~/.init_done` guard already prevents repeat seeding, so the shadowing risk only occurs on the very first workspace start per workspace — but that is when initial user config is most vulnerable.
- After the mount is in place, verify with `docker inspect` that the Claude volume is mounted at `/home/coder/.claude` and that `ls /home/coder/.claude` shows volume contents, not skel contents.

**Warning signs:**
- `~/.claude/` on the shared volume contains files with names matching `/etc/skel/.claude/` contents after first workspace start.
- User's pre-existing Claude history is replaced with template defaults on first start.
- The `~/.init_done` file exists but `~/.claude/` contents look like defaults, not the user's history.

**Phase to address:**
v1.1, Phase 1 (volume wiring + startup script audit) — review `/etc/skel` contents in the workspace image before wiring the nested mount. Add a comment to the startup script noting the Claude volume excludes skel coverage.

---

### Pitfall 8: Stale Auth / Token Refresh Racing Across Concurrent Workspaces

**What goes wrong:**
Claude Code's OAuth credentials include a refresh token and a short-lived access token. When multiple workspaces are running simultaneously (or restart in quick succession), each workspace's Claude process may independently detect an expired access token and attempt to refresh it. Both processes write a new access token (and potentially a new refresh token) to `~/.claude/.credentials.json`. The second write clobbers the first refresh. If the OAuth server invalidates the old refresh token after first use, the credential file now contains a stale refresh token from the losing process — all subsequent token refreshes fail, requiring the user to re-authenticate.

**Why it happens:**
OAuth PKCE / refresh flows are designed for single-client use. The credential file is not transactionally updated. Two writers racing to update the same JSON file with non-overlapping tokens results in one process holding valid tokens and one holding invalidated ones, with no way to know which view is authoritative.

**How to avoid:**
- The primary mitigation is the same as Pitfall 1: one active workspace per owner at a time. Document in the README.
- If users routinely run two workspaces simultaneously, consider credential isolation: each workspace gets its own credential store and shares only the non-sensitive config (settings, skills, MCP config). Auth is per-workspace. This trades convenience for correctness.
- Monitor for `~/.claude/.credentials.json` modification times from multiple containers within the same minute — this is a signal of the race.
- The flock guard (Pitfall 1 future work) would also prevent this, since only one Claude process would be active at a time.

**Warning signs:**
- Authentication errors appearing randomly after a period of working correctly.
- `claude auth status` alternates between authenticated and unauthenticated across workspace restarts.
- `~/.claude/.credentials.json` shows a modification time from a container that is no longer running.

**Phase to address:**
v1.1, Phase 1 — document in the README operator runbook alongside the concurrent-write caveat. Same root cause, same mitigation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Key shared volume on `owner.name` instead of `owner.id` | Human-readable volume names in `docker volume ls` | Volume destroyed on username rename; auth lost | Never — use `owner.id` with a name label for readability |
| Mount shared volume without `ignore_changes = [name]` | Simpler HCL | Future name-format refactor destroys the volume | Never — mirror the existing home volume pattern |
| Skip `CLAUDE_CONFIG_DIR` and mount `.claude.json` as a volume | Seems direct | Docker creates a directory at the file path; Claude silently fails | Never — the mount-at-file-path pattern does not work |
| Omit the `chown` startup step and assume Docker sets correct ownership | Fewer startup-script lines | Login silently fails on first workspace start (write permission denied) | Never when running as non-root |
| Use `coder/claude-code v4` "just in case" Tasks are needed later | Forward-compatible | v4 is older, less maintained; sends wrong signal to future readers | Only if `coder_ai_task` module wiring is actively needed this milestone |
| Share volume read-write with no concurrent-use documentation | Simplest mount config | Lost writes, auth corruption if two workspaces run simultaneously | Acceptable for v1.1 if concurrent-use caveat is documented |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `coder/claude-code` module + shared volume | Assume module is idempotent; skip reviewing startup behavior | Audit whether the module writes config unconditionally; add guards if needed |
| Docker named volume at `~/.claude.json` (file path) | Declare a volume mount targeting the file directly | Use `CLAUDE_CONFIG_DIR=/home/coder/.claude` to move the settings file inside the directory volume |
| `devcontainer.json` claude-code volume | Mount only `/home/node/.claude` (directory); assume `.claude.json` is covered | Either add `CLAUDE_CONFIG_DIR` to the devcontainer feature or acknowledge `.claude.json` is not persisted (documented gap) |
| `docker_volume` resource naming | Use `owner.name` for readability | Use `owner.id` (UUID) as the volume name key; put `owner.name` in a label |
| `cp -rT /etc/skel ~` with nested Claude volume mounted | Skel copies into the shared Claude volume on first start | Do not put Claude paths in `/etc/skel`; keep skel free of `~/.claude/` and `~/.claude.json` |
| Terraform `lifecycle.ignore_changes` | Omit it, assuming the volume name never needs changing | Always include `ignore_changes = [name]` on any volume resource, mirroring the home volume convention |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Shared credential file accessible to all processes in the container | Any process in the workspace container can read `~/.claude/.credentials.json` (OAuth tokens) | This is inherent to the shared-volume model; acceptable if workspace containers are single-user. Do not multi-tenant workspace containers (one owner per container). |
| Credential volume in a backup | `pg_dump` does not back up Docker volumes — credentials are not in the Postgres backup. But if a Docker volume is explicitly backed up (e.g. `docker run --volumes-from`), the credential file is in plaintext in the backup | Exclude Claude credential volumes from backup tooling; credentials should be re-obtained via OAuth, not restored from backup |
| `ANTHROPIC_API_KEY` stored in the shared volume config | If written to `~/.claude/` config by the module or user, it is visible to all workspaces sharing the volume | Pass `ANTHROPIC_API_KEY` via `coder_agent.env` (injected at container start) rather than persisting it in the shared volume |
| Wide volume permissions after `chown -R coder:coder ~/.claude` | Correct — `coder` owns the files. Not a problem for single-user workspaces. | If workspace containers ever run as multiple users, scope volume permissions appropriately; not a concern for this template's single-user model |

---

## "Looks Done But Isn't" Checklist

- [ ] **Volume ownership:** `ls -la /home/coder/.claude` inside a running container shows `coder:coder` ownership, not `root:root`
- [ ] **Config colocation:** `ls /home/coder/.claude.json` should return "No such file" (the file is inside `~/.claude/` via `CLAUDE_CONFIG_DIR`); if it exists as a separate file, the volume design is incomplete
- [ ] **Auth persistence:** Authenticate in workspace A, stop it, start workspace B for the same owner — `claude auth status` in workspace B shows authenticated without a new login
- [ ] **Volume key:** `docker volume ls | grep coder-claude` shows volume names containing UUIDs, not human-readable usernames
- [ ] **`ignore_changes`:** `terraform plan` on a workspace with no user changes shows no `docker_volume` diff
- [ ] **Skel safety:** `ls /etc/skel/.claude 2>/dev/null` returns empty (no skel Claude paths in the workspace image)
- [ ] **Devcontainer gap acknowledged:** README or operator runbook notes that `devcontainer.json` does not persist `~/.claude.json` (only `~/.claude/` is mounted)
- [ ] **Module version:** `grep 'version' templates/docker/main.tf | grep claude` shows `5.2.0`, not a v4 pin

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Concurrent-write clobbering (lost history/todos) | MEDIUM | Stop all but one workspace for the owner; data already lost cannot be recovered; restore from a manual backup of `~/.claude/` if one was taken |
| File-vs-directory mount trap | MEDIUM | Remove the mis-declared `docker_volume` resource, re-apply to destroy the directory-type volume, re-add with `CLAUDE_CONFIG_DIR` approach; re-authenticate |
| Owner-name keying + username rename → orphaned volume | HIGH | Locate old volume via `docker volume ls`; copy contents to new UUID-keyed volume using a helper container (`docker run --rm -v old:/src -v new:/dst alpine cp -a /src/. /dst/`); remove old volume |
| Empty volume root-owned → login fails silently | LOW | `docker exec <container> sudo chown -R coder:coder ~/.claude` if the container is running, or add the fix to startup script and restart workspace |
| Module overwrites shared config on start | MEDIUM | Pin module to a version with idempotent config writes; manually restore config from a backup of `~/.claude/` |
| Credential corruption from concurrent refresh | MEDIUM | `claude auth logout && claude auth login` in one workspace while all others are stopped; the shared volume now holds a fresh, valid credential |
| Skel pollution of shared Claude volume | LOW | `docker run --rm -v <claude-vol>:/data alpine rm -rf /data/<skel-files>`; ensure `/etc/skel` is cleaned in the image |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Concurrent-write clobbering | v1.1 Phase 1 — README runbook | `docker inspect` two running workspaces; confirm caveat is in README |
| File-vs-directory mount for `.claude.json` | v1.1 Phase 1 — volume design + `CLAUDE_CONFIG_DIR` | `ls /home/coder/.claude.json` returns "No such file" in a running workspace |
| Owner-name keying + missing `ignore_changes` | v1.1 Phase 1 — volume resource declaration | `terraform plan` no-ops on a workspace with no user changes |
| Empty volume root-owned | v1.1 Phase 1 — startup script | `ls -la /home/coder/.claude` shows `coder:coder` ownership after first start |
| Module version selection + idempotency | v1.1 Phase 1 — module wiring | Module version is 5.2.0; config in `~/.claude/` unchanged after second `terraform apply` |
| Credential location split | v1.1 Phase 1 — volume design | No `.claude.json` file in home root; auth persists across workspace recreation |
| Skel shadowing | v1.1 Phase 1 — startup script audit | No Claude paths in `/etc/skel`; `~/.claude/` contents after first start are from the shared volume, not skel |
| Stale auth / token refresh race | v1.1 Phase 1 — README runbook | Concurrent-workspace section of README documents this risk |

---

## Sources

- `templates/docker/main.tf` — existing volume naming pattern (`workspace.id` + `ignore_changes = [name]`), skel-seeding startup script, established `data.coder_workspace_owner.me` data sources (HIGH — direct codebase read)
- `.devcontainer/devcontainer.json` — confirmed gap: mounts `/home/node/.claude` only; `~/.claude.json` not mounted (HIGH — direct codebase read)
- `CLAUDE.md` — `coder/claude-code v5.2.0` is current maintained; v4 only needed for `coder_ai_task` module wiring; `ANTHROPIC_API_KEY` lives in gitignored `.env` (HIGH — project documentation)
- `.planning/PROJECT.md` — v1.1 milestone scope, deferred items, constraints (HIGH — project documentation)
- Docker named volume behavior (directory ownership, subpath mount semantics) — well-established Docker Engine behavior, consistent across versions (HIGH — community consensus)
- OAuth token refresh single-client assumption — standard OAuth 2.0 PKCE behavior; concurrent refresh invalidation is a known failure mode (HIGH — protocol specification)

---
*Pitfalls research for: Portable Claude Code config — shared Docker volume in Coder workspace template*
*Researched: 2026-06-17*
