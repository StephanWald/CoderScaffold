---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Portable Claude Code Setup
status: Awaiting next milestone
stopped_at: Phase 04 marked complete (UAT 4/5 live-passed, owner-isolation acknowledged gate). Milestone v1.1 100% complete.
last_updated: "2026-06-18T04:15:34.156Z"
last_activity: 2026-06-18 — Milestone v1.1 completed and archived
progress:
  total_phases: 1
  completed_phases: 1
  total_plans: 3
  completed_plans: 3
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-18)

**Core value:** A Coder server you can stand up, point at a real public URL, and trust with persistent data — Postgres state survives container recreation and can be backed up/restored.
**Current focus:** Milestone v1.1 archived (2026-06-18). Planning next milestone — scope v2 with `/gsd-new-milestone`.

## Current Position

Phase: Milestone v1.1 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-07-16 — Completed quick task 260716-afr: GitHub CLI (gh) baked into all 4 workspace template images

## Performance Metrics

**Velocity:**

- Total plans completed: 9
- Average duration: ~90 min
- Total execution time: ~1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-compose-hardening-configuration | 2 | ~135min | ~67min |
| 02 | 3 | - | - |
| 03 | 2 | - | - |
| 04 | 3 | - | - |

**Recent Trend:**

- Last 5 plans: 01-01 (~90min, 2 tasks, 2 files), 01-02 (~45min, 2 tasks, 2 files)
- Trend: —

*Updated after each plan completion*

| Phase 01-compose-hardening-configuration P01 | 90min | 2 tasks + 1 checkpoint | 2 files |
| Phase 01-compose-hardening-configuration P02 | 45min | 2 tasks + 1 checkpoint | 2 files |
| Phase 02-backup-restore-scripts P01 | 4min | 2 tasks | 1 files |
| Phase 02-backup-restore-scripts P02 | 2min | 3 tasks | 2 files |
| Phase 03-docker-workspace-template P01 | 2min | 2 tasks | 1 files |
| Phase 03 P02 | 1min | 1 tasks | 1 files |
| Phase 04-portable-claude-config P01 | 28min | 3 tasks | 1 files |
| Phase 04-portable-claude-config P02 | 1min | 1 tasks | 1 files |
| Phase 04-portable-claude-config P03 | 2min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-roadmap: TLS via external reverse proxy — scaffold is HTTP-only on :7080
- Pre-roadmap: Backup = scripts only, cron-friendly — no scheduler in v1
- Pre-roadmap: AI/MCP deferred to v2 — v1 focuses on production foundation
- [Phase 01-01]: Pin Coder image default to v2.33.8 (stable track) via CODER_VERSION variable; keep CODER_REPO overridable
- [Phase 01-01 REVISED]: Default Postgres storage to named volume coder_pgdata (cross-platform, no chown required); host bind mount opt-in via CODER_PG_DATA_DIR=./data/postgres. Replaces locked "host bind mount" roadmap decision. Rationale: VirtioFS on macOS/Windows Docker Desktop denies chown on bind-mounted PGDATA; pg_dump logical backups are storage-backend-transparent so bind mount was never required for backups.
- [Phase 01-01]: CODER_ACCESS_URL defaults to http://127.0.0.1:7080 (full URL with protocol required by Coder; real URL in .env disables dev tunnel)
- [Phase 01-01]: CODER_WILDCARD_ACCESS_URL defaults empty (wildcard apps disabled in quickstart; set in .env for production)
- [Phase 01-02]: CODER_PG_DATA_DIR is commented opt-in in .env.example (not active) — prevents bind-mount crash-loop when operator copies .env.example to .env on macOS/Windows without editing the path
- [Phase 01-02]: README quick-start uses named-volume path (no chown required by default); chown + failure symptom scoped to the "Optional: host bind mount" subsection
- [Phase 02-backup-restore-scripts]: chmod 600 applied to dump file immediately after write (ASVS V4 — dump contains user/workspace data including tokens)
- [Phase 02-backup-restore-scripts]: PGPASSWORD as inline env prefix on docker compose exec — limits variable lifetime to single exec call, not exported
- [Phase 02-backup-restore-scripts]: Two-step dump verification: zero-byte size guard + pg_restore --list structural check (catches TTY corruption where pg_dump exits 0 but produces corrupt/empty output)
- [Phase 02-backup-restore-scripts P02]: EXIT trap registered immediately after docker compose stop coder — coder restarted even if pg_restore fails under set -e (Pitfall 6)
- [Phase 02-backup-restore-scripts P02]: Argument validation (-f regular file + -s non-zero size) placed before sourcing .env and before any service stop — no destructive action on invalid input (ASVS V5, T-02-05)
- [Phase 02-backup-restore-scripts P02]: Restore reads dump via stdin redirect (< ${DUMP_FILE}), not as pg_restore filename arg — avoids docker/compose exec binary corruption pattern (#8909)
- [Phase ?]: Display name / description / icon documented as post-push step via coder templates edit — not Terraform-managed (RESEARCH.md Pitfall 6)
- [Phase 04 — pre-planning OPEN]: CLAUDE_CONFIG_DIR (env var, simpler) vs neutral-mount+symlinks (reliable, no undocumented behavior) — must be resolved empirically before coding; default recommendation is symlinks (Option B)
- [Phase 04-01]: Neutral-mount + symlink approach locked (D-01) — CLAUDE_CONFIG_DIR rejected (undocumented, issue #25762 open, #3833 closed not planned)
- [Phase 04-01]: Volume name coder-${owner-uuid}-claude keyed on owner UUID not username — rename-safe (D-03)
- [Phase 04-01]: prevent_destroy=true on claude_config_volume — workspace deletion never destroys shared auth (D-03)
- [Phase 04-01]: anthropic_api_key variable defaults to "" — OAuth first-run login is default path, API key is inert override (D-07)
- [Phase 04-01]: claude_code_version intentionally unpinned — latest-on-start (D-06, deliberate exception to pin-everything ethos)
- [Phase 04-01]: [REUSABLE] drop-in snippet shipped inline in main.tf — no separate example file (D-08)
- [Phase 04-01]: terraform/tofu not in env — grep assertions served as authoritative validation gate for this plan
- [Phase 04-03]: Guard A uses [ ! -L ] && [ -e ] (not just [ -d ]) to catch any non-symlink entity at ~/.claude — strictly safer for upgrade path
- [Phase 04-03]: cp -an (archive + no-clobber) for directory migration — preserves timestamps, never overwrites existing shared content
- [Phase 04-03]: WR-02 optional chown hardening skipped — wrapping the existing chown block would require restructuring 04-01 logic; plan explicitly permitted skipping it

### Pending Todos

None. All planned work for milestone v1.1 is complete.

### Blockers/Concerns

- Phase 3: Docker socket GID varies by host distro — RESOLVED in templates/docker/main.tf commented block (TPL-05/D-08)
- Phase 3: `host.docker.internal` handling for workspace agent — RESOLVED via host.docker.internal/host-gateway + replace() entrypoint in templates/docker/main.tf (TPL-06/D-09)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260618-6ho | Bulk `coder templates push` script with login check (scripts/push-templates.sh) | 2026-06-18 | b9c10ef | [260618-6ho-create-coder-template-push-all-script-wi](./quick/260618-6ho-create-coder-template-push-all-script-wi/) |
| 260618-h3d | Maintainer `.gitignore` + `devcontainer.json` + new `templates/coderscaffold/` workspace template (clones StephanWald/CoderScaffold) | 2026-06-18 | dd53a2e | [260618-h3d-maintainer-gitignore-devcontainer-json-n](./quick/260618-h3d-maintainer-gitignore-devcontainer-json-n/) |
| 260619-93j | Preconfigure webforJ MCP server (`https://mcp.webforj.com/`) in workspace Claude config (both templates' startup_script) | 2026-06-19 | 4bd4d3b | [260619-93j-preconfigure-claude-code-in-workspace-co](./quick/260619-93j-preconfigure-claude-code-in-workspace-co/) |
| 260619-9ii | New `templates/java-fullstack/` template: build-time JDK selector (Adoptium/Oracle 21/25), optional git-clone param, Maven 3.9.16, Node LTS; image build live-verified | 2026-06-19 | f78975d | [260619-9ii-new-java-fullstack-workspace-template-op](./quick/260619-9ii-new-java-fullstack-workspace-template-op/) |
| 260619-a5w | Fix SSH `Host key verification failed` for private-repo clones in java-fullstack (bake forge known_hosts + accept-new); README private-repo SSH guide | 2026-06-19 | a69f0d2 | [260619-a5w-fix-ssh-host-key-verification-for-privat](./quick/260619-a5w-fix-ssh-host-key-verification-for-privat/) |
| 260619-b1h | Enable subdomain apps: README guide — local macOS nip.io recipe + production Apache wildcard reverse-proxy vhost (compose/.env already forward the vars) | 2026-06-19 | 1d51959 | [260619-b1h-document-enabling-subdomain-apps-local-m](./quick/260619-b1h-document-enabling-subdomain-apps-local-m/) |
| 260619-bix | Add `scripts/update-coder.sh` (--check, backup→pin→pull→recreate→health-gate, --push-templates/--dry-run) + README "Updating Coder" section; latest stable v2.33.9 | 2026-06-19 | f66b9f8 | [260619-bix-add-scripts-update-coder-sh-backup-then-pul](./quick/260619-bix-add-scripts-update-coder-sh-backup-then-pul/) |
| 260619-ej7 | Wire Google OIDC login into compose + .env.example: opt-in `CODER_OIDC_*` vars (issuer/client/scopes), disabled by default (empty client id), `basis.cloud` email-domain restriction | 2026-06-19 | 79ef750 | [260619-ej7-wire-google-oidc-login-into-coder-compos](./quick/260619-ej7-wire-google-oidc-login-into-coder-compos/) |
| 260629-9k5 | Enable MemPalace by default in `coderscaffold` + `java-fullstack` templates: system-wide `mempalace` CLI (/opt venv), MCP server registered in workspace Claude config (mirrors webforJ), guarded `mempalace init` post-clone, + GSD `mempalace.enabled` capability flip in config.json | 2026-06-29 | e459f20 | [260629-9k5-enable-mempalace-by-default-in-coderscaf](./quick/260629-9k5-enable-mempalace-by-default-in-coderscaf/) |
| 260713-m12 | New `templates/bbj-services/` Coder workspace template: forks java-fullstack, bakes BBjServices via silent install from operator host context (BBJ_ASSETS_PATH), Adoptium 21/25 only, coder_app on 8888, non-fatal background launch; compose.yaml bind mount + .env.example vars; terraform validate + fmt -check gate passed | 2026-07-13 | aa5e349 | [260713-m12-create-coder-workspace-template-template](./quick/260713-m12-create-coder-workspace-template-template/) |
| 260713-mlt | Replace standalone `jdk` coder_parameter with `bbj_stack` combo dropdown backed by combinations.json (try(jsondecode(file(...)), local.default_combinations)); Dockerfile ARG BBJ_JAR_NAME; new combinations.example.json + bbj-build-combos.sh (per-combo pre-warm, jq required, exit codes); README + .env.example updated; terraform validate + fmt-check + shellcheck gate passed | 2026-07-13 | 1f8251f | [260713-mlt-add-bbj-stack-combo-selector-to-bbj-serv](./quick/260713-mlt-add-bbj-stack-combo-selector-to-bbj-serv/) |
| 260716-8p8 | Claude bypassPermissions by default in all 4 templates: idempotent startup_script block merges `permissions.defaultMode=bypassPermissions` into per-owner shared `~/.claude/settings.json` (Docker volume only — never the operator host); terraform validate gate passed on all 4 | 2026-07-16 | 2e7849d | [260716-8p8-add-claude-bypasspermissions-block-to-al](./quick/260716-8p8-add-claude-bypasspermissions-block-to-al/) |
| 260716-9pg | bbj-services: BBjServices launch moved from startup_script background job (`nohup setsid … &` + pidfile) to dedicated `coder_script.bbjservices` (foreground `exec sudo --launchd`, `:8888` port guard only) — fixes Coder "output pipes were not closed after 10s" warning/kill risk; terraform validate + fmt gate passed | 2026-07-16 | b886ef0 | [260716-9pg-convert-bbj-services-bbjservices-launch-](./quick/260716-9pg-convert-bbj-services-bbjservices-launch-/) |
| 260716-afr | GitHub CLI (gh) in all 4 workspace images: official cli.github.com apt repo block (arch-aware) inserted before final `USER coder` in each Dockerfile; block build-verified against enterprise-base (gh 2.96.0); auth per-user via `gh auth login` (persists on home volume) | 2026-07-16 | 7452918 | [260716-afr-add-github-cli-gh-to-all-four-workspace-](./quick/260716-afr-add-github-cli-gh-to-all-four-workspace-/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| AI/MCP | Coder Tasks + claude-code + MCP servers (AI-01..04) | v2 | 2026-06-16 |
| QoL | Dotfiles module, backup retention, workspace resource limits (QOL-01..03) | v2 | 2026-06-16 |
| verification | Phase 01 — 01-VERIFICATION.md status human_needed (functional; formal UAT not recorded) | acknowledged at v1.0 close | 2026-06-17 |
| verification | Phase 02 — 02-VERIFICATION.md status human_needed (functional; formal UAT not recorded) | acknowledged at v1.0 close | 2026-06-17 |
| verification | Phase 04 — owner-isolation (SC-4) not live-tested; no second owner account. Verified by code inspection only. Re-run `/gsd-verify-work 04` to close live. | acknowledged gate at phase close | 2026-06-18 |
| security | Phase 04 — `/gsd-secure-phase 04` not run; no 04-SECURITY.md. Run before production reliance. | open debt | 2026-06-18 |

## Session Continuity

Last session: 2026-07-13
Stopped at: Quick task 260713-mlt complete — bbj_stack combo selector added to templates/bbj-services/; terraform validate + fmt-check + shellcheck gates passed.
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
