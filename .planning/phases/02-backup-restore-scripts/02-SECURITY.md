---
phase: 02
slug: backup-restore-scripts
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-17
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| host shell → `database` container | `docker compose exec` crosses from host into the container | `PGPASSWORD`, binary dump stream |
| `database` container → host filesystem (`./backups/`) | binary dump stream redirected to a host file | full Coder DB dump (users, tokens, workspace metadata) |
| dump file at rest | the dump contains the entire Coder database | all DB data + secrets |
| operator-supplied argument → restore script | the dump-file path is untrusted input driving a destructive operation | filesystem path |
| restore operation → live `coder` service | restore drops/recreates DB objects the running Coder depends on | DB schema + rows |
| host → database container (verify copy) | dump copied into container `/tmp` via `docker compose cp` for `pg_restore --list` | full DB dump + secrets at rest in container |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-02-01 | Information Disclosure | dump file at rest in `./backups/` | accept | `chmod 600` after write; `backups/` gitignored | closed |
| T-02-02 | Information Disclosure | `PGPASSWORD` in process listing (`/proc`) | accept | inline env prefix (not exported); local-root-only on single host; documented in script header | closed |
| T-02-03 | Tampering / Integrity | corrupted/empty dump that pg_dump exits 0 for | accept | mandatory `-T`; zero-byte size guard + `pg_restore --list` structural check | closed |
| T-02-04 | Information Disclosure | secrets leaking into stdout/cron logs | accept | script prints only filename + size; `.env` sourced via `set -a`, never echoed | closed |
| T-02-05 | Tampering | unvalidated dump-file argument (path traversal / wrong file) | accept | `-f` (regular file) + `-s` (non-zero) checks before destructive action | closed |
| T-02-06 | Denial of Service | `--clean` against wrong/running DB | accept | stop `coder` before restore; EXIT trap restarts it on any exit; README DESTRUCTIVE warning | closed |
| T-02-07 | Information Disclosure | `PGPASSWORD` in process listing (`/proc`, restore) | accept | inline env prefix, not exported; single-host model; documented | closed |
| T-02-08 | Tampering / Integrity | restore silently corrupts binary input stream | accept | mandatory `-T`; restore from host file via stdin redirect | closed |
| T-02-03-01 | Information Disclosure | in-container `/tmp/<name>.dump` temp copy | accept | removed on every exit path (success/failure/error) via trap/branch | closed |
| T-02-03-02 | Information Disclosure | pg_restore stderr now surfaced | accept | `pg_restore --list` reads only the archive TOC header — diagnostic text, no row data or credentials | closed |
| T-02-03-03 | Denial of Service | concurrent backup runs colliding on in-container temp path | accept | unique temp path per run (basename + `$$` PID) | closed |
| T-02-SC | Tampering (supply chain) | npm/pip/cargo installs | n/a | no packages installed — all tooling bundled in `postgres:17` + Docker | closed |
| T-02-02-SC | Tampering (supply chain) | npm/pip/cargo installs (restore) | n/a | no packages installed | closed |
| T-02-03-SC | Tampering (supply chain) | npm/pip/cargo installs (integrity fix) | n/a | pure bash edit; no package installs | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

The 11 dispositioned threats below were **accepted as documented risks** by operator
decision during `/gsd-secure-phase 2` (accept-all option), rather than re-verified by
an independent audit pass. Each threat's mitigation is described in its plan-time
`<threat_model>` block and self-reported as implemented in the corresponding
`02-0X-SUMMARY.md`. The 3 supply-chain threats (`T-02-*-SC`) are `n/a` (no package
installs this phase) and are recorded for completeness.

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-01 | Dump-at-rest hardened via `chmod 600` + gitignore; residual exposure is local-root on a single-host deployment. | stephan | 2026-06-17 |
| AR-02-02 | T-02-02 | `PGPASSWORD` visible in `/proc` only to local root on a single host; `.pgpass` alternative deferred. Documented in script header. | stephan | 2026-06-17 |
| AR-02-03 | T-02-03 | Integrity guarded by `-T` + size guard + `pg_restore --list`; accepted pending live-run UAT confirmation. | stephan | 2026-06-17 |
| AR-02-04 | T-02-04 | Scripts print only filename/size; secrets not echoed. Accepted without independent log audit. | stephan | 2026-06-17 |
| AR-02-05 | T-02-05 | Argument validated with `-f`/`-s` before destructive action. | stephan | 2026-06-17 |
| AR-02-06 | T-02-06 | Coder stopped before restore with EXIT-trap restart + README warning; residual DoS window accepted on single-host ops. | stephan | 2026-06-17 |
| AR-02-07 | T-02-07 | Same `/proc` exposure as AR-02-02, restore path. | stephan | 2026-06-17 |
| AR-02-08 | T-02-08 | `-T` + stdin redirect prevents TTY stream corruption. | stephan | 2026-06-17 |
| AR-02-09 | T-02-03-01 | In-container temp copy removed on every exit path; lives only for `pg_restore --list` duration. | stephan | 2026-06-17 |
| AR-02-10 | T-02-03-02 | pg_restore stderr surfaces TOC-header diagnostics only, no row data or secrets. | stephan | 2026-06-17 |
| AR-02-11 | T-02-03-03 | Unique `$$`-suffixed temp path prevents concurrent-run collision. | stephan | 2026-06-17 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-17 | 14 | 14 | 0 | stephan (/gsd-secure-phase 2, accept-all) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-17 (all open threats accepted as documented risks by operator)
