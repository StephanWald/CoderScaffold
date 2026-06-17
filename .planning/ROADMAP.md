# Roadmap: Coder Production Scaffold

## Overview

Starting from the upstream proof-of-concept `compose.yaml`, this scaffold is hardened in three tightly-ordered phases. Phase 1 converts the compose stack into a production-grade deployment: host bind-mount persistence, pinned images, restart policies, a healthcheck, `.env`-driven secrets, and correct public/wildcard URL configuration — plus the operator documentation that makes it trustworthy. Phase 2 builds backup and restore scripts on top of the persistence layout Phase 1 establishes. Phase 3 delivers the Docker workspace Terraform template, which depends on Phase 1's working access and wildcard URLs to be fully testable. AI/MCP integration is explicitly deferred to v2.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Compose Hardening & Configuration** - Production-grade compose stack with persistence, pinned image, healthcheck, `.env` secrets, and public/wildcard URLs
- [ ] **Phase 2: Backup & Restore Scripts** - Non-interactive, cron-friendly `pg_dump`/`pg_restore` scripts using the bind-mount layout from Phase 1
- [ ] **Phase 3: Docker Workspace Template** - Terraform template provisioning workspaces with code-server, JetBrains Gateway, persistent home, and reliable agent connectivity

## Phase Details

### Phase 1: Compose Hardening & Configuration

**Goal**: The operator can `docker compose up` and reach the Coder UI at a real public URL with no convenience tunnel, with Postgres data living on a host bind mount that survives container recreation
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: SRV-01, SRV-02, SRV-03, SRV-04, SRV-05, CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, OPS-01, OPS-02, OPS-03
**Success Criteria** (what must be TRUE):

  1. Operator can `docker compose up` and reach the Coder UI at the configured `CODER_ACCESS_URL` with no `*.try.coder.app` convenience tunnel active
  2. Stopping and recreating the containers does not destroy the Postgres database; the data directory is visible on the host at `./data/postgres` (or the configured path)
  3. A new contributor can clone the repo, copy `.env.example` to `.env`, fill in their values, and bring up the stack — every required variable is documented with a safe placeholder
  4. The README documents the external reverse-proxy contract (HTTP `:7080`, wildcard TLS, `Host`/WebSocket headers) and the first-admin bootstrap sequence clearly enough for an operator to follow without prior Coder knowledge
  5. After a host reboot, both services restart automatically and the Coder healthcheck returns healthy before dependent services start

**Plans**: 2 plansPlans:
**Wave 1**

- [x] 01-01-PLAN.md — Walking Skeleton: harden compose.yaml (bind mount, pinned v2.33.8, restart, /healthz healthcheck, env-sourced config) + .gitignore [Wave 1]

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Configuration contract + operator runbook: .env.example + README.md (chown prerequisite, first-admin bootstrap, reverse-proxy contract) [Wave 2]

### Phase 2: Backup & Restore Scripts

**Goal**: An operator can take a verified backup of the Coder database and restore it into a fresh instance without interactive prompts
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: BAK-01, BAK-02, BAK-03
**Success Criteria** (what must be TRUE):

  1. Running `scripts/backup.sh` produces a custom-format dump (`pg_dump -Fc`) in `./backups/` and exits `0`; the script reads all connection config from `.env` and requires no interactive input
  2. A backup produced by `backup.sh` restores cleanly into a freshly initialized database via `scripts/restore.sh` — post-restore, the Coder server starts and existing workspaces and users are visible
  3. Both scripts return non-zero exit codes on failure, making them safe for use with external schedulers or backup tools (e.g. `set -e`, cron wrappers, monitoring scripts)

**Plans**: 2 plans

Plans:

**Wave 1**

- [x] 02-01-PLAN.md — backup.sh: non-interactive, integrity-verified `pg_dump -Fc` to `./backups/` (chmod 600, exit codes) [Wave 1]

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 02-02-PLAN.md — restore.sh (stop/restore/start coder + EXIT trap, arg validation) + README backup/restore section + end-of-phase round-trip [Wave 2]

### Phase 3: Docker Workspace Template

**Goal**: A developer can create a Coder workspace from the Docker template and get a working VSCode (code-server) session and JetBrains Gateway connection, with their home directory persisting across stop/start cycles
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: TPL-01, TPL-02, TPL-03, TPL-04, TPL-05, TPL-06
**Success Criteria** (what must be TRUE):

  1. A workspace created from `templates/docker/` starts successfully, the workspace agent shows "Connected", and the workspace app URLs resolve correctly under the wildcard subdomain
  2. Opening the code-server app in the browser launches a functional VSCode session inside the workspace container
  3. JetBrains Gateway can connect to the workspace using the `coder/jetbrains-gateway` module wiring
  4. Stopping and starting a workspace preserves the contents of `/home` — files created before the stop are present after the restart
  5. Workspace provisioning succeeds on a host where the Docker socket GID differs from the default; the template documents the `group_add` / GID handling so operators know how to resolve socket permission issues

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Compose Hardening & Configuration | 2/2 | Complete | 2026-06-17 |
| 2. Backup & Restore Scripts | 1/2 | In Progress|  |
| 3. Docker Workspace Template | 0/TBD | Not started | - |
