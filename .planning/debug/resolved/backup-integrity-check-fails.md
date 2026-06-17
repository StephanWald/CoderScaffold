---
status: resolved
trigger: "backup.sh integrity-check fails: 'ERROR: Dump file failed integrity check' on macOS against live stack — dump file is non-empty (passes zero-byte guard) but pg_restore --list /dev/stdin via docker compose exec -T fails. goal: find_root_cause_only."
created: 2026-06-17T00:00:00Z
updated: 2026-06-17T12:00:00Z
resolution: "Fixed by gap-closure Plan 02-03 (commit 8b5be56) — integrity check now docker-compose-cps the dump into the container as a seekable file, lists it, and removes it on all paths. Re-verification scored 8/8 must-haves."
---

## Current Focus

hypothesis: CONFIRMED. Root cause is that `pg_restore --list` on a custom-format (-Fc) archive requires a SEEKABLE regular file; the script feeds it `/dev/stdin` (a non-seekable stream across the `docker compose exec -T` boundary), so the check fails for every valid dump. The #8909 binary-stdin-corruption issue is a real but SECONDARY overlapping fault on the same line. The dump on disk is valid; only the verification method is broken.
test: [complete — static analysis + PostgreSQL 17 docs + docker/compose issue corroboration]
expecting: [complete]
next_action: [diagnose-only complete — return ROOT CAUSE FOUND to caller; /gsd-plan-phase --gaps to plan the fix]

## Symptoms

expected: backup.sh writes a non-empty `pg_dump -Fc` dump to ./backups/, verifies it via `pg_restore --list`, and exits 0 (SC-1, BAK-01).
actual: |
  macOS, real running stack:
  WARN: .env not found at /Users/beff/coder/.env; using defaults
  Starting backup: /Users/beff/coder/backups/coder-20260617-091007.dump
  ERROR: Dump file failed integrity check: /Users/beff/coder/backups/coder-20260617-091007.dump
  (exits 1)
errors: "ERROR: Dump file failed integrity check"
reproduction: Run `./scripts/backup.sh` against a live stack (Test 1 in 02-UAT.md). No Docker daemon in THIS environment — static investigation only.
started: Discovered during UAT of Phase 2 (first functional test of backup.sh).

## Eliminated

- hypothesis: "The dump file on disk is genuinely invalid/corrupt (pg_dump produced a bad archive)."
  evidence: "The WRITE path (lines 66-74) redirects pg_dump stdout OUT of `docker compose exec -T` to the host file. Per docker/compose #8909, the corruption is on the INPUT (stdin INTO exec) direction; stdout-redirect-to-file is the documented SAFE direction. The file also passed the `-s` zero-byte guard at line 87. RESEARCH.md A3/#8909 finding both state the WRITE direction is safe. No evidence the dump itself is bad."
  timestamp: 2026-06-17T00:00:00Z

- hypothesis: "The failure is PRIMARILY the docker/compose #8909 binary-stdin-corruption bug (the lead in the request)."
  evidence: "PARTIAL ELIMINATION — #8909 is real and contributes, but it is NOT the necessary-and-sufficient root cause. A more fundamental defect exists that fails 100% deterministically even with ZERO binary corruption: `pg_restore --list` on a CUSTOM-FORMAT archive requires a SEEKABLE regular file, and `/dev/stdin` (a redirected stream across the exec boundary) is a non-seekable pipe. The #8909 corruption is a second, overlapping fault on the same line — but the seek requirement alone guarantees failure. Treating #8909 as the sole cause would risk a fix that still fails (e.g. switching to `docker exec -i` fixes corruption but the dump is still arriving on non-seekable stdin → --list still fails)."
  timestamp: 2026-06-17T00:00:00Z

## Evidence

- timestamp: 2026-06-17T00:00:00Z
  checked: "backup.sh WRITE path (lines 66-74) vs integrity-check READ path (lines 98-101)"
  found: "Direction asymmetry. WRITE: `docker compose exec -T database pg_dump ... > DUMP_FILE` — binary flows OUT of exec via stdout redirect (safe direction). READ: `docker compose exec -T database pg_restore --list /dev/stdin < DUMP_FILE` — binary dump flows IN via stdin redirect (the broken direction per #8909) AND pg_restore reads it via `/dev/stdin`."
  implication: "Only the verification step uses the problematic stdin-INTO-exec direction. The dump WRITE is safe. So the dump on disk is valid; the verification is the fault. Confirms the strong lead's framing — but see next entries for the deeper cause."

- timestamp: 2026-06-17T00:00:00Z
  checked: "PostgreSQL 17 official pg_restore docs for the -l/--list + custom-format input requirement (postgresql.org/docs/17/app-pgrestore.html and /docs/current/)"
  found: "Authoritative: `-l/--list` is supported ONLY for custom and directory formats, AND 'the input must be a regular file or directory (not, for example, a pipe or standard input).' Reason: the custom format's TOC stores block offsets and pg_restore SEEKS to read them; stdin/pipes are not seekable. pg_backup_custom.c checks seekability at archive init."
  implication: "DECISIVE. `pg_restore --list /dev/stdin` cannot work for a -Fc custom-format dump — by design, independent of Docker. `/dev/stdin` fed by `< DUMP_FILE` through the `docker compose exec` boundary is a non-seekable stream inside the container, not a regular seekable file. The integrity check is structurally guaranteed to fail for EVERY valid custom-format dump. This is the primary root cause."

- timestamp: 2026-06-17T00:00:00Z
  checked: "docker/compose #8909, #10418, #1876 (compose-cli) — stdin handling of `docker compose exec -T`"
  found: "#8909: `docker compose exec -T` corrupts binary INPUT piped via stdin. #10418/#1876: `-T` mishandles stdin/EOF (can close bash's stdin). Confirmed the corruption is INPUT-direction; stdout-to-file is safe. macOS Docker Desktop routes exec stdin through the VM gRPC stream, which is exactly the path that mangles binary/EOF."
  implication: "SECOND overlapping fault on lines 98-101. Even if the seek requirement were somehow satisfied, the binary dump arriving via `docker compose exec -T` stdin could be corrupted/truncated. Both defects point to the same fix direction: do NOT pipe the binary dump through `docker compose exec` stdin for verification."

- timestamp: 2026-06-17T00:00:00Z
  checked: "Whether `set -euo pipefail` / `2>&1 >/dev/null` masked the real pg_restore error (request asked to consider this)"
  found: "Line 101 ends with `> /dev/null 2>&1`, discarding pg_restore's actual stderr. The user only sees the script's own generic 'failed integrity check' message — NOT pg_restore's real diagnostic (which would be something like 'pg_restore: error: could not read from input file' or 'did not find magic string in file header' / 'input file does not appear to be a valid archive')."
  implication: "Not a root cause, but a CONTRIBUTING diagnosability defect: the `2>&1 >/dev/null` redirect hid the underlying error and made this look ambiguous (corruption vs. seek). The gap fix should surface pg_restore stderr on failure so future failures are self-explaining."

- timestamp: 2026-06-17T00:00:00Z
  checked: "restore.sh (lines 100-109) for the same anti-pattern"
  found: "restore.sh pipes the dump via `docker compose exec -T database pg_restore -d DB ... < DUMP_FILE` (no --list; full restore). IMPORTANT distinction: a FULL pg_restore (restoring into a DB, NOT --list) CAN read a custom-format archive from a non-seekable stream — it does a single forward pass and only NEEDS seeking for --list, selective (-L/-t) restore, or parallel (-j). So restore.sh does NOT hit the seek defect. It IS still exposed to the #8909 binary-stdin-corruption risk on macOS, but that is a separate, lower-confidence concern and is OUT OF SCOPE for this diagnosis (the UAT failure is backup.sh only)."
  implication: "Scope the gap fix to backup.sh's integrity check. Do NOT assume restore.sh is broken by the same root cause — its code path differs materially (no --list = no mandatory seek)."

- timestamp: 2026-06-17T00:00:00Z
  checked: "Evaluate suggested fix directions for cron-safe robustness"
  found: "Two candidate fixes. (A) `docker compose cp DUMP_FILE database:/tmp/verify.dump` then `docker compose exec -T database pg_restore --list /tmp/verify.dump` then remove it — gives pg_restore a real SEEKABLE regular file inside the container, defeating BOTH the seek defect and the #8909 stdin defect (cp is not the corrupt stdin path). Most robust; fully non-interactive/cron-safe; only needs writable /tmp in container (always true). (B) host-side `pg_restore --list DUMP_FILE` when a host pg_restore exists — also seekable & avoids docker stdin, but requires postgres client tools on the host (not guaranteed; the design explicitly runs pg via the container) and risks client/server version skew. (C) drop the structural check, keep only a stronger header/magic-byte check on the host (e.g. verify the file begins with the `PGDMP` custom-format magic) — weakest, but zero new deps."
  implication: "Recommended for the gap plan: option (A) `docker compose cp` into the container then `pg_restore --list <in-container-path>` (cleanup after). It is the only option that fixes BOTH overlapping defects, needs no host postgres tooling, stays inside the container-only execution model the design mandates, and is cron-safe. Also surface pg_restore stderr on failure (remove the `2>&1` swallow)."

## Resolution

root_cause: |
  backup.sh's integrity-check step (lines 98-101) is structurally incapable of succeeding for a valid pg_dump -Fc (custom-format) archive, for a reason MORE fundamental than the #8909 lead:

  PRIMARY: `pg_restore --list` requires SEEKABLE input. Per the official PostgreSQL 17 docs, `-l/--list` works only for custom/directory formats AND "the input must be a regular file or directory (not, for example, a pipe or standard input)" — because the custom format stores TOC block offsets and pg_restore seeks to read them. The script feeds the dump as `/dev/stdin` via a shell redirect across the `docker compose exec -T` boundary, which is a NON-SEEKABLE stream inside the container, not a regular file. So `pg_restore --list /dev/stdin` fails for EVERY valid custom-format dump, deterministically — Docker or not.

  SECONDARY (overlapping): the same line also relies on `docker compose exec -T` to carry the binary dump IN via stdin, which is the documented-broken direction (docker/compose #8909, #10418), particularly on macOS Docker Desktop where exec stdin crosses the VM stream. Even with a seekable target this path can corrupt/truncate binary input.

  CONTRIBUTING (diagnosability): line 101's `> /dev/null 2>&1` swallowed pg_restore's real error, hiding which defect fired and making the failure look ambiguous.

  The dump WRITE (lines 66-74, pg_dump stdout redirected OUT to a host file) is the SAFE direction and produces a valid dump. The dump on disk is fine; only the verification method is broken.
fix: "(diagnose-only — not applied) Replace the stdin-piped `pg_restore --list /dev/stdin` check with one that gives pg_restore a seekable regular file and avoids `docker compose exec` stdin: `docker compose cp` the dump into the container (e.g. /tmp), run `pg_restore --list <in-container-path>`, then remove it. Also stop swallowing pg_restore stderr (drop `2>&1`/`>/dev/null` on the error path) so real failures are self-explaining. Scope: backup.sh only — restore.sh's full-restore path does not require seeking and is not affected by this root cause."
verification: "(diagnose-only — not applied)"
files_changed: []
