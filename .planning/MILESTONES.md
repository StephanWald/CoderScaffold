# Milestones

## v1.1 Portable Claude Code Setup (Shipped: 2026-06-18)

**Phases completed:** 1 phases, 3 plans, 2 tasks

**Key accomplishments:**

- Per-owner Docker volume (UUID-keyed, prevent_destroy) mounted at a neutral path with startup_script symlinks wiring ~/.claude and ~/.claude.json, plus the claude-code module v5.2.0 and anthropic_api_key variable — all wrapped in an inline [REUSABLE] drop-in block.
- Added `### Claude Code` subsection to README Workspace Template section covering first-run OAuth login, the four shared items (auth/settings/skills/MCP servers), per-owner volume seeding, concurrent-write caveat, and manual orphaned-volume cleanup.
- Idempotent migrate-before-delete guards added to startup_script (CR-01, WR-01) and README cleanup comment corrected to state permanent data destruction (WR-03) — closes all remaining phase 04 verification gaps.

**Known deferred items at close:** 2 (see STATE.md Deferred Items)

- Phase 04 owner-isolation (SC-4 / UAT Test 5) — verified by code inspection only; not live-tested (no second owner account available). 4/5 UAT checks passed live. Re-run `/gsd-verify-work 04` to close.
- Phase 04 security review — `/gsd-secure-phase 04` not run; no 04-SECURITY.md. Run before production reliance.

**Verification note:** Live deploy UAT surfaced and fixed two deploy-blocking template defects that static review had passed — G1 (unsupported `order`/`agent_name` module args blocked `coder templates push`) and G2 (`prevent_destroy` on the per-owner volume made workspaces undeletable). Both resolved inline during the UAT session.

---

## v1.0 MVP (Shipped: 2026-06-17)

**Phases completed:** 3 phases, 7 plans, 12 tasks

**Key accomplishments:**

- Hardened compose.yaml with pinned v2.33.8 image, dual restart policies, /healthz healthcheck, env-sourced config, and named-volume Postgres — verified healthy on macOS Docker Desktop (both services Up/healthy, /healthz returns OK, Coder UI loads).
- .env.example documenting all compose variables with safe placeholders, and README.md operator runbook covering bring-up sequence, host bind-mount opt-in with chown prerequisite, first-admin bootstrap, and the 9-point reverse-proxy contract — scoped to the named-volume default established in Plan 01-01.
- Non-interactive pg_dump -Fc backup script with PGPASSWORD auth, timestamped ./backups/ output, chmod 600 hardening, zero-byte guard, and pg_restore --list structural integrity check
- Non-interactive pg_restore --clean --if-exists with stop/start coder lifecycle management via EXIT trap, argument validation (ASVS V5), and README operational documentation covering both backup/restore scripts with DESTRUCTIVE warning and cron-safety note
- `docker compose cp`-based seekable integrity check in backup.sh — eliminates the pg_restore /dev/stdin seek failure that caused every backup to exit 1
- Complete Coder Docker workspace Terraform template with code-server 1.5.0 (VS Code) and jetbrains-gateway 1.2.6 (IntelliJ IDEA), persistent /home/coder via Docker volume with lifecycle guard, and host.docker.internal connectivity for local + production deployments
- Operator README section for pushing the Docker template, resolving Docker socket GID failures, understanding local vs production agent connectivity, and home persistence.

---
