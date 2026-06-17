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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 3 | 7 | Initial scaffold; established GSD chain (discuss→plan→execute→verify) and cross-platform-first documentation discipline |

### Cumulative Quality

| Milestone | Requirements | Complete | Code-review findings (fixed) |
|-----------|--------------|----------|------------------------------|
| v1.0 | 22 | 22/22 | 3 warnings fixed (0 critical) |

### Top Lessons (Verified Across Milestones)

1. Infrastructure/template work requires live UAT — structural checks alone produce false confidence. *(v1.0)*
