# Project Research Summary

**Project:** Coder Production Scaffold
**Domain:** Self-hosted developer-platform deployment (Docker Compose)
**Researched:** 2026-06-16
**Confidence:** HIGH

## Executive Summary

This project is a production-ready Docker Compose scaffold for self-hosting Coder. The upstream baseline (`compose.yaml` in this repo) is intentionally a proof-of-concept starting point; making it production-ready requires a specific set of hardening steps — host bind-mount Postgres, version-pinned images, an `.env` secrets pattern, and correct public/wildcard URL routing. None are complex in isolation, but missing any one causes data-loss risk, broken workspaces, or an operationally fragile system. The scaffold's value beyond upstream is a complete Terraform workspace template wiring code-server, JetBrains Gateway, Claude Code, persistent home, and Coder Tasks.

The recommended approach is a sequence of tightly ordered phases driven by hard dependencies: (1) compose hardening + URL/secrets configuration, (2) backup/restore scripts, (3) the Docker workspace Terraform template, (4) Coder Tasks + MCP integration, and an optional (5) v1.x quality-of-life layer. The main risks are operational rather than architectural — Coder's documentation is strong and the patterns are established. The four highest-impact risks (access URL misconfig, Postgres bind-mount ownership, silent `pg_dump` corruption, and `claude-code` v5 dropping `coder_ai_task`) are all avoidable with deliberate scaffold design.

## Key Findings

### Recommended Stack

Pin everything; never run `:latest` in production. The Coder server tracks a "stable" line; Postgres data lives on a host bind mount so backups and persistence are first-class. The workspace template uses the maintained `kreuzwerker/docker` provider (not the archived `hashicorp/docker`) alongside the `coder/coder` provider and pinned registry modules.

**Core technologies:**
- `ghcr.io/coder/coder:v2.33.8` (stable track): Coder control plane — pinned for reproducibility; mainline `v2.34.x` carries more risk without staging.
- `postgres:17` on host bind mount `./data/postgres`: durable DB — requires `sudo chown -R 999:999` before first start (image runs as UID 999).
- `kreuzwerker/docker ~> 4.4` + `coder/coder ~> 2.18` (Terraform): workspace provisioning — `coder_ai_task` needs provider ≥ 2.13 and server ≥ 2.28.
- `coder/code-server 1.5.0`, `coder/jetbrains-gateway 1.2.6`, `coder/claude-code 5.2.0` (registry modules): IDE + agent wiring — all pinned; `claude-code` v5 dropped `coder_ai_task` so it must be declared independently.
- `coder exp mcp server` (stdio): exposes the Coder instance to external agents; HTTP MCP transport is still experimental.

See `.planning/research/STACK.md` for the full version matrix and rationale.

### Expected Features

**Must have (table stakes):**
- Postgres host bind mount + version pin + restart policies + Coder healthcheck — production durability
- `.env`/`.env.example` secrets pattern; `CODER_ACCESS_URL` + `CODER_WILDCARD_ACCESS_URL` set correctly
- External reverse-proxy contract documented (TLS + wildcard apps routing)
- `pg_dump`/`pg_restore` scripts (non-interactive, cron-friendly)
- First-admin bootstrap documentation
- Docker workspace template: code-server (VSCode), JetBrains Gateway (IntelliJ), persistent home, `ANTHROPIC_API_KEY` wiring, `coder_ai_task`, MCP

**Should have (competitive):**
- In-workspace MCP servers (filesystem/git/fetch) preconfigured for the agent
- Dotfiles module, workspace resource limits

**Defer (v2+):**
- Bundled TLS proxy, scheduled backup automation, multi-host/Kubernetes, managed Postgres, OIDC/SSO, monitoring stack

See `.planning/research/FEATURES.md`.

### Architecture Approach

A two-container Compose stack (Coder + Postgres) plus an operator-managed external reverse proxy. Workspace containers are provisioned via the mounted Docker socket on the same host. Wildcard subdomain routing (`*.apps.<domain>`) is load-bearing — every workspace app gets its URL there, so the proxy must hold a wildcard TLS cert and forward those hostnames to `:7080` preserving the `Host` header and WebSocket upgrade headers.

**Major components:**
1. `coder` container — coderd control plane; serves HTTP on `7080`, provisions workspaces via Docker socket
2. `database` container — Postgres 17 on host bind mount; backup/restore target
3. Workspace containers — ephemeral, Docker-provisioned; run code-server / JetBrains backend / agent
4. External reverse proxy (out of scope to build) — TLS termination + wildcard routing; contract documented

File layout: `compose.yaml`, `.env`/`.env.example`, `scripts/backup.sh`, `scripts/restore.sh`, `templates/docker/main.tf`, `data/postgres/`, `backups/`. See `.planning/research/ARCHITECTURE.md`.

### Critical Pitfalls

1. **`CODER_ACCESS_URL=127.0.0.1`** (baked into upstream compose) — workspaces stick on "Connecting…" — set the real public URL in `.env`.
2. **Postgres bind-mount ownership ≠ UID 999** — DB crashes on first start — `sudo chown -R 999:999 ./data/postgres` before first `up`.
3. **`pg_dump` without `-T` (no-TTY)** — silently corrupt binary dump that exits 0 and only fails at restore — always `docker compose exec -T` with `-Fc`.
4. **`claude-code` v5 dropped `coder_ai_task`** — Coder Tasks UI silently empty — declare `coder_ai_task` directly in the template.
5. **`CODER_WILDCARD_ACCESS_URL` unset / proxy not routing it** — workspace app buttons 404 — set both URL vars + wildcard proxy rule + wildcard TLS cert.

See `.planning/research/PITFALLS.md` for all 16 with warning signs and prevention.

## Implications for Roadmap

Based on research, suggested phase structure (granularity: standard):

### Phase 1: Compose Hardening & Environment Baseline
**Rationale:** Everything downstream breaks without correct URLs, persistence, and secrets; pure low-complexity config with hard upstream dependencies.
**Delivers:** Hardened `compose.yaml` (pinned image, restart policy, Coder healthcheck, Postgres host bind mount), `.env`/`.env.example`, `CODER_ACCESS_URL` + `CODER_WILDCARD_ACCESS_URL`, telemetry decision, documented proxy contract + bootstrap ordering.
**Addresses:** Persistence, secrets, public URL, proxy contract (table stakes).
**Avoids:** Pitfalls 1, 2, 5 + bootstrap-ordering trap.

### Phase 2: Backup & Restore Scripts
**Rationale:** Depends on Phase 1 bind-mount layout; validate on a clean DB before production data accumulates.
**Delivers:** `scripts/backup.sh` (`docker compose exec -T` + `-Fc` → `./backups/`) and `scripts/restore.sh`, non-interactive and cron-friendly.
**Uses:** `pg_dump`/`pg_restore` patterns from STACK.md.
**Avoids:** Pitfall 3 (TTY corruption) + restore-into-live-DB mistakes.

### Phase 3: Docker Workspace Terraform Template
**Rationale:** Highest-complexity phase; depends on Phase 1 (access/wildcard URLs must work for apps to be testable).
**Delivers:** `templates/docker/main.tf` wiring agent, persistent home volume, code-server, JetBrains Gateway, `host.docker.internal` networking, Docker socket GID handling.
**Implements:** Workspace-container component.

### Phase 4: Coder Tasks & MCP Integration
**Rationale:** Additive on top of the Phase 3 template.
**Delivers:** `coder_ai_task` resource, `claude-code 5.x` module with `ANTHROPIC_API_KEY`, in-workspace MCP servers, and `coder exp mcp server` exposure docs.
**Avoids:** Pitfall 4 (`coder_ai_task` must be declared directly).

### Phase 5: v1.x Quality-of-Life (optional)
**Rationale:** After core is validated.
**Delivers:** Dotfiles module, backup retention, workspace resource limits.

### Phase Ordering Rationale
- Hard dependency chain: hardened URLs/persistence (1) → backups need the bind-mount path (2) → template needs working URLs (3) → Tasks/MCP are additive on the template (4).
- Phases 1–2 are pure ops/config; complexity concentrates in 3–4 where Terraform provider composition and the experimental Tasks/MCP surface live.

### Research Flags
Phases likely needing deeper research during planning:
- **Phase 3:** Docker provider + Coder provider composition, `host.docker.internal` entrypoint pattern.
- **Phase 4:** `coder_ai_task` schema against the live provider; HTTP MCP experiment flag status; `claude-code` v5 `coder_app` slug/`open_in` for the Tasks button.

Phases with standard patterns (skip research-phase):
- **Phase 1, Phase 2, Phase 5:** well-documented, established patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions confirmed via GitHub releases API + registry + Context7 |
| Features | HIGH | Coder docs + module registry + upstream compose examined directly |
| Architecture | HIGH | Official install + Caddy proxy tutorials confirm contract |
| Pitfalls | HIGH | Deterministic image/CLI behaviors; upstream compose carries the URL warning itself |

**Overall confidence:** HIGH

### Gaps to Address
- HTTP MCP endpoint (`oauth2,mcp-server-http`) is experimental in v2.33.x — treat as best-effort in Phase 4 (design around stdio).
- Docker socket GID varies by host distro — document as operator-resolved, not hardcoded (Phase 3).
- Wildcard TLS cert for `*.apps.<domain>` needs a DNS challenge — prominently flag as an operator prerequisite (Phase 1 docs).
- `claude-code` v5 `coder_app` slug/`open_in` for the Tasks UI button — validate against a live v2.33.x instance in Phase 4.

## Sources

### Primary (HIGH confidence)
- Coder GitHub releases API — server version (`v2.33.8`) and provider (`v2.18.0`)
- registry.coder.com — module versions (code-server, jetbrains-gateway, claude-code)
- Coder official docs (Docker install, Caddy reverse proxy, Templates, Tasks, MCP) — config + contracts
- docker-library/postgres issues — bind-mount UID 999 behavior

### Secondary (MEDIUM confidence)
- Community Docker `pg_dump`/`pg_restore` patterns — `-T`/`-Fc` conventions
- Coder docs on experimental MCP HTTP transport — flagged subject to change

---
*Research completed: 2026-06-16*
*Ready for roadmap: yes*
