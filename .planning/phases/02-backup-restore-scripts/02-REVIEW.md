---
phase: 02-backup-restore-scripts
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - scripts/backup.sh
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

Reviewed `scripts/backup.sh`, focusing on the rewritten integrity-check block (commit `8b5be56`) that
replaced the broken `pg_restore --list /dev/stdin` stdin-pipe pattern with a `docker compose cp`-based
seekable in-container check. The core fix is correct: copying the dump into the container as a real
seekable regular file is the right way to make `pg_restore --list` succeed for valid custom-format
archives, and capturing the exit code into `PGRESTORE_EXIT` before cleanup is sound.

However, the block's own header comment **over-claims its cleanup guarantees**. It asserts the temp file
is removed "on ALL exit paths (success, failure, or unexpected abort under `set -e`)" — but there is no
`trap`, so several abort paths leak resources. The most important inconsistency is that a `docker compose cp`
failure aborts the script under `set -e` while leaving the host dump file in place (unlike every other
failure branch, which `rm -f`s it). There is also a container-side temp-file leak on signal/abort, and a
plain `du`/`rm` of an unquoted-safe-but-still-fragile path. No security-critical injection or secret-leak
defects were found in the new code.

## Warnings

### WR-01: Header comment over-claims cleanup guarantees — no `trap`, so abort paths leak

**File:** `scripts/backup.sh:111-113, 121-138`
**Issue:** The comment states the in-container temp file "is removed on ALL exit paths (success, failure,
or unexpected abort under `set -e`)." This is false. Cleanup at line 138 only runs if control reaches it
sequentially. There is no `trap ... EXIT/INT/TERM`. Concretely:

- If the process receives `SIGINT`/`SIGTERM` (e.g., cron job killed, Ctrl-C) after `docker compose cp`
  (line 125) succeeds but before line 138, the in-container file `/tmp/coder-verify-$$-...` leaks and is
  never reaped. Over many runs this accumulates inside the long-lived `database` container.
- If `docker compose exec ... pg_restore --list` itself were to terminate the script via a signal rather
  than a non-zero exit (the `if !` only catches ordinary non-zero exits), line 138 is skipped.

The claim "removed on unexpected abort under `set -e`" is the specific falsehood: `set -e` aborts mean the
script exits *without* running line 138.

**Fix:** Register a `trap` so cleanup is guaranteed regardless of exit path, and drop the misleading prose:
```bash
CONTAINER_DUMP="/tmp/coder-verify-$$-$(basename "${DUMP_FILE}")"
cleanup_container_tmp() {
  docker compose exec -T database rm -f "${CONTAINER_DUMP}" >/dev/null 2>&1 || true
}
trap cleanup_container_tmp EXIT INT TERM

docker compose cp "${DUMP_FILE}" "database:${CONTAINER_DUMP}"
# ... run pg_restore --list ...
# remove the explicit line-138 cleanup; the trap now owns it
```

### WR-02: `docker compose cp` failure leaves an unverified host dump on disk (inconsistent with other failure branches)

**File:** `scripts/backup.sh:125`
**Issue:** Line 125 has no `|| ...` guard and runs under `set -e`. If the `cp` into the container fails
(container restarting, disk full in container, name resolution race), the script aborts *immediately* at
line 125 and exits non-zero — but the host dump file `${DUMP_FILE}` is **left in place**. Every other
failure path in this script (`zero-byte` guard at line 89, integrity-fail at line 142) explicitly
`rm -f "${DUMP_FILE}"` so callers/schedulers never see a half-trusted artifact. A `cp` failure means the
dump was *never integrity-checked*, yet it survives — the most dangerous outcome, because an operator may
later assume any `.dump` present on disk passed verification.

**Fix:** Treat a `cp` failure like the other integrity failures — remove the dump and exit 1:
```bash
if ! docker compose cp "${DUMP_FILE}" "database:${CONTAINER_DUMP}"; then
  echo "ERROR: failed to copy dump into container for verification: ${DUMP_FILE}" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi
```

### WR-03: `pg_dump` failure under a pipe + `set -o pipefail` — exit-code attribution and partial file

**File:** `scripts/backup.sh:66-74`
**Issue:** The `pg_dump` invocation is the left side of a redirection to `${DUMP_FILE}` (not a pipe, so
`pipefail` does not apply here — good), but if `docker compose exec ... pg_dump` fails *after* writing some
bytes, `set -e` aborts the script at line 74 and the partially written `${DUMP_FILE}` is left on disk
without cleanup. The downstream zero-byte and integrity guards never run because the script already exited.
This is the same class of "unverified/partial artifact survives" problem as WR-02, on the more common
failure path (DB unreachable, auth failure, dump interrupted). The header docstring promises exit code `1`
when "pg_dump itself fails" but says nothing about the leftover partial file.

**Fix:** Guard the dump explicitly and clean up on failure (a single `trap ... EXIT` that removes
`${DUMP_FILE}` unless a success flag is set is the most robust pattern):
```bash
if ! PGPASSWORD="${POSTGRES_PASSWORD}" docker compose exec -T database \
     pg_dump -U "${POSTGRES_USER}" -Fc --no-owner --no-acl "${POSTGRES_DB}" > "${DUMP_FILE}"; then
  echo "ERROR: pg_dump failed" >&2
  rm -f "${DUMP_FILE}"
  exit 1
fi
```

### WR-04: PID-only temp-name uniqueness is weaker than the comment implies

**File:** `scripts/backup.sh:116, 121`
**Issue:** The comment (T-02-03-03) claims "PID (`$$`) in the name prevents concurrent runs from colliding."
The `DUMP_FILE` name already embeds a second-resolution UTC timestamp (`%Y%m%d-%H%M%S`), and `$$` is the
*host* shell PID. Two concurrent backups that start within the same second and (after PID wraparound or in
separate PID namespaces) share a PID would collide on both the host dump name and the container temp name.
This is a low-probability edge, but the comment asserts a guarantee the code does not provide. Note also
`$$` is the host PID, which has no meaning inside the container namespace — it functions only as an opaque
disambiguator, not a real container-side PID.

**Fix:** Use a stronger unique suffix and stop over-claiming:
```bash
CONTAINER_DUMP="/tmp/coder-verify-$$-${RANDOM}-$(basename "${DUMP_FILE}")"
# or, preferred: run `mktemp` inside the container and capture the path
```

## Info

### IN-01: `du -sh` for size reporting is portable but slow/over-featured; `stat` is exact

**File:** `scripts/backup.sh:149`
**Issue:** `du -sh` reports *disk usage* (block-rounded, filesystem-dependent), not the logical file size,
and shells out to a full directory-summary tool for a single file. For a backup-size report this can
mislead (e.g., a 1-byte file reports "4.0K"). Not a correctness bug, but the reported figure is not the
dump's true byte count.
**Fix:** Use `stat` for an exact byte count, or `ls -lh` / `du --apparent-size` if a human-readable string
is desired: `DUMP_SIZE="$(stat -c %s "${DUMP_FILE}") bytes"`.

### IN-02: Comment references brittle absolute line numbers in other files

**File:** `scripts/backup.sh:40, 64`
**Issue:** Comments say "mirror compose.yaml exactly (lines 47-49)" and "Service name ... per compose.yaml".
Hard-coded line-number references (`lines 47-49`) rot the moment `compose.yaml` is edited and will silently
mislead a future maintainer. (Confirmed already drifting: `ports:` is at line 7 / line 44 in the current
`compose.yaml`.)
**Fix:** Reference the variable names or the service name, not line numbers:
"mirror the `POSTGRES_*` defaults in `compose.yaml`".

### IN-03: Stdout/stderr split on the verification step diverges from the documented intent on cp

**File:** `scripts/backup.sh:125, 132`
**Issue:** The `pg_restore --list` call carefully routes stderr to the caller and suppresses stdout
(`>/dev/null`), but `docker compose cp` at line 125 emits its own progress/info to stderr unsuppressed.
On a successful, non-interactive cron run this adds noise to the captured stderr stream that a scheduler
may misinterpret as a warning. Minor consistency issue.
**Fix:** Quiet the cp progress when run non-interactively, e.g. redirect its stdout and keep only real
errors, or accept the noise and document it.

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
