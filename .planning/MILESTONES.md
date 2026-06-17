# Milestones

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
