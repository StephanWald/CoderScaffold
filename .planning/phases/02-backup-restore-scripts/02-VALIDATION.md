---
phase: 2
slug: backup-restore-scripts
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-17
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None (shell scripts — `bash -n` syntax check + manual round-trip smoke test) |
| **Config file** | None — see Wave 0 |
| **Quick run command** | `bash -n scripts/backup.sh && bash -n scripts/restore.sh` |
| **Full suite command** | Manual smoke test against running stack (backup → restore into fresh DB → verify Coder starts with existing data) |
| **Estimated runtime** | ~2s (syntax) / ~2–5 min (manual round-trip) |

---

## Sampling Rate

- **After every task commit:** Run `bash -n scripts/backup.sh && bash -n scripts/restore.sh` (syntax check)
- **After every plan wave:** Manual smoke — run `./scripts/backup.sh`, verify a non-empty `.dump` lands in `./backups/`
- **Before `/gsd-verify-work`:** Full round-trip — backup → restore into a fresh stack → Coder server starts and existing workspaces/users are visible
- **Max feedback latency:** ~2s for syntax; round-trip is a phase-gate manual step

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-xx | 01 | 1 | BAK-01 | — | Reads creds from `.env`; no secrets echoed to stdout/logs | smoke (manual) + syntax | `bash -n scripts/backup.sh` | ❌ W0 | ⬜ pending |
| 2-0x-xx | 0x | 1–2 | BAK-02 | — | Stops `coder` before restore; restarts via trap on EXIT | smoke (manual) + syntax | `bash -n scripts/restore.sh` | ❌ W0 | ⬜ pending |
| 2-0x-xx | 0x | 1–2 | BAK-03 | — | `set -euo pipefail`; non-zero exit on any failure; no interactive prompts | smoke (manual) + syntax | `bash -n scripts/backup.sh && bash -n scripts/restore.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Note: shell scripts that `docker compose exec` against a live Postgres cannot be unit-tested without Docker-in-Docker. `bash -n` catches structural errors; functional correctness is verified by the manual round-trip below.*

---

## Wave 0 Requirements

- [ ] `scripts/` directory — must be created (does not exist yet)
- [ ] `scripts/backup.sh` — BAK-01
- [ ] `scripts/restore.sh` — BAK-02

*No test framework installed — shell scripts use `bash -n` for syntax and a manual round-trip for functional verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `backup.sh` produces a non-empty custom-format dump in `./backups/` and exits 0 | BAK-01 | Requires running Docker daemon + live `database` container | Bring stack up, run `./scripts/backup.sh`, confirm a timestamped `.dump` exists, is non-empty, and `echo $?` is `0` |
| Restored backup yields a working Coder server with existing users/workspaces visible | BAK-02 | Requires full round-trip against a freshly initialized DB | Wipe DB volume, `up -d`, run `./scripts/restore.sh <dump>`, confirm Coder starts and prior data is visible in the UI |
| Both scripts exit non-zero on failure | BAK-03 | Failure injection needs the live stack (db down, missing dump, bad creds) | Run each script with the stack down / a bogus dump path; confirm `echo $?` is non-zero and a meaningful message is printed |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` syntax verify or are flagged Manual-Only with justification
- [ ] Sampling continuity: no 3 consecutive tasks without automated (syntax) verify
- [ ] Wave 0 covers all MISSING references (`scripts/` dir, both scripts)
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s for syntax checks
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
