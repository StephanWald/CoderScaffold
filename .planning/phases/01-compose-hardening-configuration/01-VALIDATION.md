---
phase: 01
slug: compose-hardening-configuration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-16
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> This is a Docker Compose + documentation phase: there is no application code and
> no unit-test framework. Validation is **operational** (smoke tests via `docker compose`
> commands) and **manual review** (README contract checks), not automated unit tests.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — operational smoke tests + manual review |
| **Config file** | none |
| **Quick run command** | `docker compose config -q && docker compose ps` |
| **Full suite command** | `docker compose down && docker compose up -d && docker compose ps && docker compose exec -T coder curl -fsS http://localhost:7080/healthz` |
| **Estimated runtime** | ~60 seconds (cold `up` to healthy) |

---

## Sampling Rate

- **After every task commit:** `docker compose config -q` (validates the compose file still parses)
- **After every plan wave:** Full smoke sequence — `down → up -d → ps → /healthz curl`
- **Before `/gsd-verify-work`:** Full smoke sequence green AND all manual README checks reviewed
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Req ID | Behavior | Test Type | Automated Command | Manual Check |
|--------|----------|-----------|-------------------|--------------|
| SRV-01 | Postgres data survives container recreation | smoke | `docker compose down && docker compose up -d && docker compose exec -T database pg_isready` | `./data/postgres` (or `$CODER_PG_DATA_DIR`) exists on host with content after recreation |
| SRV-02 | Coder runs at pinned version | smoke | `docker compose config \| grep 'image:.*coder'` shows `v2.33.8` | — |
| SRV-03 | Services restart automatically | smoke | `docker compose restart && docker compose ps` | Both services show `Up`; `restart: unless-stopped` present on both |
| SRV-04 | Coder healthcheck passes | smoke | `docker compose exec -T coder curl -fsS http://localhost:7080/healthz` returns `OK` | `healthcheck:` block present on coder service |
| SRV-05 | Postgres initializes cleanly on bind mount | smoke | `docker compose logs database \| grep "database system is ready"` | Requires `chown 999:999` pre-step (see OPS-03) |
| CFG-01 | `.env.example` documents all variables | manual | `grep -c '^[A-Z]' .env.example` ≥ documented var count | Every required var has a safe placeholder + comment |
| CFG-02 | `.env` is gitignored | smoke | `git check-ignore -v .env` returns a `.gitignore` match | `.env.example` is NOT ignored |
| CFG-03 | No `*.try.coder.app` tunnel when access URL set | manual | `docker compose logs coder \| grep -i tunnel` shows no tunnel started | With real `CODER_ACCESS_URL` set in `.env` |
| CFG-04 | Wildcard apps URL documented | manual | `grep CODER_WILDCARD_ACCESS_URL .env.example` | Placeholder uses subdomain, not TLD (cookie scope) |
| CFG-05 | DB credentials sourced from `.env` | smoke | `docker compose config \| grep CODER_PG_CONNECTION_URL` shows resolved `.env` values | DSN has no hardcoded password in `compose.yaml` |
| OPS-01 | README reverse-proxy contract complete | manual | Human review against D-06 (9 requirements: `:7080`, wildcard TLS, `Host`, WebSocket `Upgrade`/`Connection`, `X-Forwarded-*`, no buffering, DERP) | — |
| OPS-02 | README first-admin bootstrap documented | manual | Human review | Covers: up → wait healthy → open URL → create admin |
| OPS-03 | README chown prerequisite is prominent | manual | Human review | Appears BEFORE the `docker compose up` step; states the symptom (DB won't initialize) |

*Status legend: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — this phase creates/edits only `compose.yaml`, `.gitignore`, `.env.example`, and `README.md`. There are no source files and no test files to scaffold. The "test suite" is the operational smoke sequence above.

*Existing infrastructure (Docker Compose CLI) covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Reverse-proxy contract completeness | OPS-01 | Prose contract; no automated proxy in scaffold | Review README §reverse-proxy against the 9-point D-06 checklist |
| First-admin bootstrap clarity | OPS-02 | Browser-driven first-run; cannot be scripted in scope | Follow README bootstrap steps end-to-end in a browser |
| chown prerequisite prominence | OPS-03 | Editorial placement judgment | Confirm chown step precedes `up` and names the failure symptom |
| Wildcard apps URL resolution | CFG-04 | Requires a real public domain + DNS | Browser-verify a workspace app resolves under `*.<apps-domain>` |
| Dev-tunnel disabled in production | CFG-03 | Requires real `CODER_ACCESS_URL` | Inspect `docker compose logs coder` for absence of tunnel startup |

---

## Validation Sign-Off

- [ ] Every requirement (SRV/CFG/OPS) has a smoke command or a documented manual check
- [ ] Sampling continuity: smoke sequence runnable after each wave
- [ ] Wave 0 gaps: none (confirmed)
- [ ] No watch-mode flags (`-T` used on all `exec` to avoid TTY hangs)
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter once the executor confirms the map covers every task

**Approval:** pending
