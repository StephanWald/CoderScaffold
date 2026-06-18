# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-06-17
**Phases:** 3 | **Plans:** 7 | **Tasks:** 12

### What Was Built
- Hardened `compose.yaml`: pinned Coder `v2.33.8` + `postgres:17`, restart policies, `/healthz` healthcheck, env-driven config, named-volume Postgres (host bind mount opt-in via `CODER_PG_DATA_DIR`).
- Non-interactive backup/restore tooling: `scripts/backup.sh` (`pg_dump -Fc`, chmod 600, integrity check) and `scripts/restore.sh` (`pg_restore --clean`, stop/start lifecycle via EXIT trap, arg validation).
- `.env.example` + operator README runbook (reverse-proxy contract, first-admin bootstrap, bring-up sequence).
- Docker workspace Terraform template (`templates/docker/main.tf`): code-server 1.5.0 (VS Code) + jetbrains-gateway 1.2.6 (IntelliJ), UUID-keyed persistent `/home`, host-gateway connectivity.

### What Worked
- The discuss → research → plan → verify → execute → verify chain caught issues early: the plan-checker passed cleanly, and structural verification confirmed all pins/wiring before any live run.
- UAT did its job. SC-5 surfaced a real cross-platform defect (Docker Desktop socket GID + Linux-only `stat -c` docs) that purely-structural checks could never have caught — fixed inline before "shipped" meant anything.
- Code review added genuine value post-hoc (WR-01 over-broad `replace()`, WR-02 `ignore_changes = all`), and the fixes were small and safe.

### What Was Inefficient
- The requirements traceability table drifted: CFG-01/OPS-01..03 were delivered in Phase 1 Plan 02 but stayed `Pending` until milestone close. The per-plan tracking write didn't propagate; caught and corrected during close.
- Phases 1 & 2 verification stalled at `human_needed` and were never formally closed via verify-work, so they showed "Needs Review" at milestone time and had to be acknowledged as deferred.
- A backup-script seek failure (`/dev/stdin` not seekable for `pg_restore`) required a third Phase-2 plan (02-03) to fix — the stdin-pipe pattern wasn't validated against `pg_restore`'s seek requirement during planning.

### Patterns Established
- **Env-driven, self-documenting config:** every tunable overridable from `.env` with a sensible committed default and inline comment (extended to the workspace socket GID).
- **Cross-platform first:** Docker Desktop (macOS/Windows) vs Linux differences (VirtioFS chown, socket GID, BSD vs GNU `stat`) are now explicitly documented rather than assumed.
- **Authoritative checks over host assumptions:** prefer the in-container `docker compose exec coder stat -c '%g'` over host-side guesses.

### Key Lessons
1. Infrastructure phases need live UAT, not just structural gates — the highest-value bug (socket GID) only appeared on a real `terraform apply`.
2. Keep the requirements traceability table honest at plan-completion time; drift compounds and surfaces awkwardly at milestone close.
3. Validate I/O assumptions against the actual tool contract (e.g. `pg_restore` needs a seekable input) during planning, not after a failing run.
4. Close the verify-work loop per phase as you go; deferring it leaves phases in "Needs Review" limbo at milestone time.

### Cost Observations
- Model mix: planning on Opus; research/checker/executor/reviewer/verifier on Sonnet; orchestration on Opus.
- Notable: chunked subagent execution kept per-plan executor runs fast (1–4 min each after Phase 1).

---

## Milestone: v1.1 — Portable Claude Code Setup

**Shipped:** 2026-06-18
**Phases:** 1 (Phase 4) | **Plans:** 3 | **Tasks:** 2

### What Was Built
- Per-owner shared Claude config volume (keyed on owner UUID, auto-created/unmanaged) wired into the Docker workspace template via a neutral mount (`~/.claude-shared`) + `startup_script` symlinks for `~/.claude` and `~/.claude.json` — auth, settings, skills, and user-scoped MCP servers now carry across every workspace.
- `coder/claude-code` module v5.2.0 + inert `anthropic_api_key` variable (OAuth first-run login is the default path), wrapped in an inline `[REUSABLE]` drop-in block any future template can adopt.
- Idempotent migrate-before-delete upgrade guards (`[ ! -L ] && [ -e ]`, copy real config before writing `{}` placeholder) so pre-existing real `~/.claude`/`~/.claude.json` migrate with no auth-data loss (CR-01, WR-01).
- README operator runbook: first-run login, the four shared items, per-owner seeding, concurrent-write caveat, manual orphaned-volume cleanup.
- Beyond scope: workspace image now built from a Dockerfile with Node.js LTS, and GSD (gsd-core) seeded once into the shared `~/.claude`.

### What Worked
- Live deploy UAT was decisive — exactly the lesson carried forward from v1.0. It caught two deploy-blocking defects that static code review and goal-verification had both passed: G1 (unsupported `order`/`agent_name` module args broke `coder templates push`) and G2 (`prevent_destroy` on the per-owner volume made workspaces undeletable). Both fixed inline.
- Code review caught a genuine data-loss BLOCKER (CR-01) pre-deploy: the placeholder-write would have clobbered real auth on the upgrade path. The gap-closure plan (04-03) fixed it before any live run touched real credentials.
- Verifying module argument schemas against registry source (not assumption) after G1 prevented a second failed push cycle.

### What Was Inefficient
- The phase was marked complete prematurely twice before UAT (reverted in 18cfc28, 8ae65f4) — verification status flip-flopped between `human_needed` and `gaps_found`. The "structural checks pass = done" instinct kept asserting itself despite the v1.0 lesson.
- Two deploy blockers and a data-loss bug all reached UAT/review because nothing exercised an actual `terraform plan`/`coder templates push` during planning or execution — terraform/tofu weren't in the env, so grep assertions stood in as the validation gate.
- Owner isolation (SC-4) could not be live-tested — no second owner account — so it closes as an acknowledged gate rather than a verified pass.

### Patterns Established
- **Migrate-before-replace for shared-config upgrade paths:** never write a placeholder over a path that may hold real user data; copy/migrate first, guard with `[ ! -L ]` idempotency.
- **Unmanaged volume for cross-workspace persistence:** a resource that must outlive any single workspace should not be a per-workspace-managed `docker_volume` with `prevent_destroy` — reference it by name and let Docker auto-create it, or `coder delete` deadlocks.
- **Verify external module/provider arg schemas against registry source** before relying on them — module versions silently drop inputs across majors.

### Key Lessons
1. The v1.0 lesson held and deepened: live UAT on real infra is non-negotiable for template work — three of this milestone's most serious issues (G1, G2, CR-01) were invisible to every static gate.
2. `prevent_destroy` on a shared resource that a per-workspace plan owns is an anti-pattern — it protects data by making the workspace undeletable.
3. Resist marking a phase complete on structural evidence alone; this milestone reverted "complete" twice before live UAT actually justified it.
4. When the real validation tool (terraform/coder CLI) isn't in the env, treat grep/structural assertions as provisional, not authoritative — flag the gap loudly rather than letting it read as verified.

### Cost Observations
- Model mix: planning on Opus; research/checker/executor/reviewer/verifier on Sonnet; orchestration on Opus.
- Sessions: multiple (planning + execution + two UAT sessions, the first paused mid-deploy-debugging).
- Notable: most execution cost shifted from planning to live-deploy debugging — the inline G1/G2/CR-01 fixes consumed more effort than the original 3 plans combined.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 3 | 7 | Initial scaffold; established GSD chain (discuss→plan→execute→verify) and cross-platform-first documentation discipline |
| v1.1 | 1 | 3 | First AI-config slice; live deploy UAT promoted to a hard gate after it caught 2 deploy blockers + 1 data-loss bug that all static gates missed |

### Cumulative Quality

| Milestone | Requirements | Complete | Code-review findings (fixed) |
|-----------|--------------|----------|------------------------------|
| v1.0 | 22 | 22/22 | 3 warnings fixed (0 critical) |
| v1.1 | 7 | 7/7 | 1 BLOCKER (CR-01 data loss) + 2 warnings fixed; 2 deploy blockers (G1/G2) found & fixed in UAT |

### Top Lessons (Verified Across Milestones)

1. Infrastructure/template work requires live UAT — structural checks alone produce false confidence. *(v1.0, reconfirmed emphatically v1.1)*
2. A resource that must outlive a single workspace must not be per-workspace-managed with `prevent_destroy`, or deletion deadlocks. *(v1.1)*
3. Migrate-before-replace on shared-config upgrade paths — never write a placeholder over possibly-real user data. *(v1.1)*
