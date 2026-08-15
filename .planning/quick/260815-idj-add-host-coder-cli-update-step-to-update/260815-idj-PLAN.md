---
phase: quick-260815-idj
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/update-coder.sh
  - README.md
autonomous: true
requirements: [QUICK-260815-idj]

must_haves:
  truths:
    - "After a successful server upgrade, the host `coder` CLI is re-installed to match TARGET_VERSION (no more 'version mismatch: client vX, server vY' warning on the next templates push)"
    - "A failure of the host CLI update never fails the script — the server upgrade still exits 0 with a WARN naming the manual command"
    - "`--no-cli-update` skips the new step entirely, mirroring `--no-backup`"
    - "`--help` and `--dry-run` both show the new step and the new flag"
    - "`bash -n scripts/update-coder.sh` passes (strict-mode-safe: no `-e` trip on the CLI path)"
  artifacts:
    - path: "scripts/update-coder.sh"
      provides: "Step 5/5 host CLI version-alignment block + --no-cli-update flag + renumbered steps 1/5..5/5"
      contains: "--no-cli-update"
    - path: "README.md"
      provides: "Updating Coder section mentions host CLI alignment + the skip flag"
      contains: "--no-cli-update"
  key_links:
    - from: "scripts/update-coder.sh Step 5/5"
      to: "CODER_ACCESS_URL (sourced from .env earlier in the script)"
      via: "server-hosted install script preferred over the official installer fallback"
      pattern: "CODER_ACCESS_URL.*install\\.sh"
    - from: "scripts/update-coder.sh usage()"
      to: "header comment block"
      via: "sed -n '2,Np' line range must end on the last header comment line"
      pattern: "sed -n '2,[0-9]+p'"
---

<objective>
`scripts/update-coder.sh` upgrades the Coder *server* container but leaves the host `coder`
CLI on its old version. In production this surfaced as:

    version mismatch: client v2.34.3+4653f32, server v2.35.3+65e2bfb

on the very next `scripts/push-templates.sh` run. Add a warn-and-continue host-CLI
alignment step that runs after the server is healthy and before the optional template push.

Purpose: the admin host that runs the upgrade is the same host that pushes templates —
the CLI must follow the server automatically.
Output: renumbered 5-step `scripts/update-coder.sh` with a new Step 5/5, a `--no-cli-update`
flag, refreshed header docs, and a README note.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@scripts/update-coder.sh
@scripts/push-templates.sh

<environment_facts>
<!-- Verified on this machine during planning — do not re-discover. -->
- `coder` CLI IS installed here: /usr/local/bin/coder
- `coder version` first line format: `Coder v2.34.6+660dc56 Tue Jul 14 07:12:15 UTC 2026`
  → parse with: `coder version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1`
- `.env` exists; `CODER_VERSION=v2.34.6`; **`CODER_ACCESS_URL` is NOT set in this .env**
  → the official-installer fallback branch is the one that would run on this dev host
- `docker` + `docker compose` present, but NO running stack → only `--help` and `--dry-run`
  are safe to execute (both exit before touching compose state)
- `shellcheck` is NOT installed here → its check is conditional in <verify>
</environment_facts>

<current_structure>
Existing numbered steps in the script body (all strings must be renumbered to /5):
- line ~168 `Step 1/4: backing up the database...`  / ~177 `Step 1/4: pre-update backup SKIPPED`
- line ~183 `Step 2/4: pinning CODER_VERSION=...`
- line ~201 `Step 3/4: pulling ...`
- line ~212 `Step 4/4: waiting for coder to become healthy...`
- health-wait `while :; do ... done` loop ends ~line 235, then `RUNNING_VERSION=...` (~238),
  then the `--push-templates` block (~243). **The new step goes between `RUNNING_VERSION`
  and the `--push-templates` block.**

`usage()` is `sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'` — the `46` is a
hardcoded line number that currently over-runs the header and leaks `set -euo pipefail`
plus the "Path resolution" banner into `--help` output. It MUST be recomputed after the
header grows.
</current_structure>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add the Step 5/5 host CLI alignment block and the --no-cli-update flag</name>
  <files>scripts/update-coder.sh</files>
  <action>
Edit the script body only (header comments are Task 2).

1. Argument parsing: add `DO_CLI_UPDATE=1` next to the existing `DO_BACKUP=1` initializers,
   and a `--no-cli-update)  DO_CLI_UPDATE=0 ;;` case immediately after the `--no-backup` case
   so the flag mirrors the existing pattern exactly.

2. Renumber every existing step string from `Step N/4` to `Step N/5` (five occurrences:
   two for Step 1, one each for Steps 2, 3, 4). Change nothing else about those blocks.

3. Dry-run block: add a line reflecting the new step between the "wait for healthy" line and
   the push-templates suffix, using the same `$([[ ... ]] && echo ...)` idiom already present.
   The healthy line must no longer carry the push-templates suffix — move it onto the new
   last line. Result shape:
       [dry-run]        wait for healthy →
       [dry-run]        align host coder CLI to <TARGET>[ (skipped)][ → push templates]

4. Insert the new step AFTER the `RUNNING_VERSION="$(...)"` assignment and BEFORE the
   `# Optional: re-push templates` banner. Use the same `# ---` section-banner comment style
   as the surrounding steps, with a short rationale comment explaining the client/server
   version-mismatch warning this prevents.

   Declare `HOST_CLI_AFTER=""` before the block so the summary reference is `set -u` safe.

   Logic, in this order:
   - `if [[ "${DO_CLI_UPDATE}" -eq 0 ]]` → echo `Step 5/5: host CLI update SKIPPED (--no-cli-update).`
   - `elif ! command -v coder >/dev/null 2>&1` → echo a WARN to stderr that no `coder` CLI was
     found on PATH so there is nothing to align, and that push-templates.sh will fail-fast with
     install instructions if this host is meant to push templates. Do NOT install from scratch.
   - else: parse the host version with
     `HOST_CLI_VERSION="$(coder version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"`
     (the trailing `|| true` inside the command substitution is required — `pipefail` is active
     and `grep` exits 1 when the format is unexpected).
     - If `HOST_CLI_VERSION` equals `TARGET_VERSION` → echo `Step 5/5: host coder CLI already
       matches ${TARGET_VERSION}.`, set `HOST_CLI_AFTER="${HOST_CLI_VERSION}"`.
     - Otherwise run the install. Choose the installer with an explicit if/else — build and run
       the real pipeline in each branch, and separately assign a `CLI_INSTALL_HINT` string
       holding the same command as text for the WARN message. Do NOT build one command string
       and run it through `sh -c`/`eval`.
         * `CODER_ACCESS_URL` non-empty (`${CODER_ACCESS_URL:-}`): prefer the server's own
           installer — `curl -fsSL --max-time 60 "${CODER_ACCESS_URL%/}/install.sh" | sh`.
           This is the branch that guarantees an exact server match.
         * otherwise: `curl -fsSL --max-time 60 https://coder.com/install.sh | sh -s -- --version "${TARGET_VERSION#v}"`
           (official installer takes the version without the leading `v`).
       Wrap the invocation in `if ... ; then ... else ... fi` — never a bare command — so `set -e`
       cannot abort the script here.
     - On installer success: `hash -r 2>/dev/null || true` (the binary path may have changed),
       re-parse the version into `HOST_CLI_AFTER` with the same parse expression. If it now
       equals `TARGET_VERSION`, echo success; if it does not, emit a WARN naming both versions
       and `${CLI_INSTALL_HINT}` — still non-fatal.
     - On installer failure: WARN to stderr that the host CLI update failed (note it may need
       root/sudo to write to /usr/local/bin), print `Run manually: ${CLI_INSTALL_HINT}`, and
       continue. Never `exit`.

5. Summary block at the bottom: after the existing `Reported` line, add
   `[[ -n "${HOST_CLI_AFTER}" ]] && echo "  Host CLI       : ${HOST_CLI_AFTER}"`
   aligned with the existing two-space/column style.

Strict-mode discipline: every new external command is inside an `if` condition, a `$( ... || true )`,
or ends with `|| true`. No new `exit` statements — the script's exit code for a successful server
upgrade stays 0 regardless of what the CLI step does.
  </action>
  <verify>
    <automated>bash -n /Users/beff/coder/scripts/update-coder.sh && grep -c 'Step [1-5]/5' /Users/beff/coder/scripts/update-coder.sh | grep -qE '^([6-9]|1[0-9])$' && ! grep -q 'Step [0-9]/4' /Users/beff/coder/scripts/update-coder.sh && grep -q 'DO_CLI_UPDATE=0' /Users/beff/coder/scripts/update-coder.sh && grep -q 'install\.sh' /Users/beff/coder/scripts/update-coder.sh && echo TASK1_OK</automated>
  </verify>
  <done>Syntax check passes; no `Step N/4` strings remain; `--no-cli-update` sets `DO_CLI_UPDATE=0`; the new block sits between `RUNNING_VERSION=` and the push-templates banner; no new `exit` on the CLI path.</done>
</task>

<task type="auto">
  <name>Task 2: Update the header docs, fix the usage() line range, and refresh the README</name>
  <files>scripts/update-coder.sh, README.md</files>
  <action>
scripts/update-coder.sh header comment block:
1. Add item `5.` to the numbered narrative at the top: align the host `coder` CLI with the new
   server version (via the server's own `install.sh` when `CODER_ACCESS_URL` is set, otherwise
   the official installer pinned to the target version) so `coder templates push` from this host
   does not warn about a client/server version mismatch. State that this step is warn-only.
2. `Usage:` — add one example line: `./scripts/update-coder.sh <version> --no-cli-update  # leave the host CLI alone`.
3. `Flags:` — add, aligned with the existing column:
   `#   --no-cli-update    Skip the post-upgrade host 'coder' CLI version alignment.`
4. `Exit codes:` — extend the `0` line to state that a failed host CLI update is a WARN only and
   does not change the exit code. Add a one-line note that the installer may need root or
   passwordless sudo; unattended runs without it should pass `--no-cli-update`.
5. `LIVE VERIFICATION DEFERRED` banner — add a sentence that the new host CLI alignment path is
   likewise statically checked only (no live installer run from the authoring environment).
6. **Recompute the `usage()` sed range.** Find the line number of the last header comment line
   (the closing `# ----...` of the LIVE VERIFICATION banner, immediately before
   `set -euo pipefail`) and set `usage() { sed -n '2,<N>p' ... }` to that number. The current
   `46` already over-runs into `set -euo pipefail` and the "Path resolution" banner — after this
   fix `--help` must print the header and nothing else.

README.md, "Updating Coder" section (~lines 409-428):
7. Extend the sentence at line 411-412 so the described sequence ends with "...waits for the
   healthcheck, then aligns the host `coder` CLI with the new server version."
8. Add one example to the fenced bash block:
   `./scripts/update-coder.sh v2.33.9 --no-cli-update   # skip the host CLI alignment`
   with a brief comment that the CLI step is warn-only and may need sudo.
Keep the existing README tone and line width; change nothing else.
  </action>
  <verify>
    <automated>bash -n /Users/beff/coder/scripts/update-coder.sh && /Users/beff/coder/scripts/update-coder.sh --help | grep -q -- '--no-cli-update' && ! /Users/beff/coder/scripts/update-coder.sh --help | grep -q 'set -euo pipefail' && ! /Users/beff/coder/scripts/update-coder.sh --help | grep -q 'Path resolution' && grep -q -- '--no-cli-update' /Users/beff/coder/README.md && echo TASK2_OK</automated>
  </verify>
  <done>`--help` prints exactly the header block (no `set -euo pipefail`, no "Path resolution" banner) and documents `--no-cli-update`; README's Updating Coder section mentions CLI alignment and the skip flag.</done>
</task>

<task type="auto">
  <name>Task 3: Static + dry-run verification gate</name>
  <files>scripts/update-coder.sh</files>
  <action>
Run the full gate and fix anything it surfaces (no new features).

1. `bash -n scripts/update-coder.sh` must pass.
2. `command -v shellcheck` — if present, run `shellcheck scripts/update-coder.sh`; warning-level
   findings are acceptable, error-level must be fixed. If absent (expected on this host), record
   "shellcheck not installed — skipped" in the SUMMARY rather than installing it.
3. `./scripts/update-coder.sh --help` — confirm the new flag and the 5-step narrative render,
   and that no shell code leaks into the output.
4. `./scripts/update-coder.sh --dry-run` — safe here (it exits before any compose state change).
   Confirm the output shows the CLI alignment line. Then `./scripts/update-coder.sh --dry-run
   --no-cli-update` and confirm the same line renders with the `(skipped)` marker.
5. Confirm the exit status of both dry-run invocations is 0.

Do NOT run the script without `--dry-run`/`--help`: there is no running Coder stack on this
machine, and the live upgrade + installer path stays deferred to the production host (consistent
with the script's existing LIVE VERIFICATION DEFERRED banner). Record that deferral in the SUMMARY.
  </action>
  <verify>
    <automated>cd /Users/beff/coder && bash -n scripts/update-coder.sh && ./scripts/update-coder.sh --dry-run | grep -qi 'host coder CLI' && ./scripts/update-coder.sh --dry-run --no-cli-update | grep -qi 'skipped' && ./scripts/update-coder.sh --dry-run >/dev/null && echo GATE_OK</automated>
  </verify>
  <done>bash -n passes; shellcheck run or explicitly recorded as unavailable; both dry-run variants exit 0 and render the CLI step (plain and skipped); live installer path documented as deferred.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| host → remote installer | `curl … | sh` executes remote code on the admin host as the invoking user (with sudo escalation inside the installer) |
| .env → script | `CODER_ACCESS_URL` is operator-controlled config interpolated into the installer URL |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-idj-01 | Tampering | `curl … /install.sh \| sh` | mitigate | HTTPS only, `curl -fsSL` (fails closed on non-2xx / TLS error), `--max-time 60`; never `-k`/`--insecure`; only two sources allowed — the operator's own `CODER_ACCESS_URL` or `https://coder.com/install.sh` |
| T-idj-02 | Elevation of Privilege | host CLI install to /usr/local/bin | accept | The installer performs its own sudo escalation; the script never invokes sudo itself and degrades to a WARN when escalation is unavailable. Operator already has root on the host they are upgrading. |
| T-idj-03 | Tampering | `CODER_ACCESS_URL` from .env | accept | `.env` is gitignored, mode 0600, and operator-authored; it already supplies the DSN and session token to sibling scripts — same trust level |
| T-idj-SC | Tampering | package-manager installs | n/a | No npm/pip/cargo installs in this task |
</threat_model>

<verification>
- `bash -n scripts/update-coder.sh` exits 0
- `shellcheck scripts/update-coder.sh` clean at error level (skipped + recorded if not installed)
- `./scripts/update-coder.sh --help` shows `--no-cli-update` and a 5-step narrative, and leaks no shell code
- `./scripts/update-coder.sh --dry-run` and `--dry-run --no-cli-update` both exit 0 and show the CLI step
- `grep -n 'Step [0-9]/4' scripts/update-coder.sh` returns nothing
</verification>

<success_criteria>
- A successful server upgrade re-installs the host `coder` CLI to match `TARGET_VERSION`, eliminating the `version mismatch: client … server …` warning on the next `push-templates.sh` run
- The CLI step never changes the script's exit code: missing CLI, failed download, or failed install all produce a WARN plus the exact manual command, and the run still ends `exit 0`
- `--no-cli-update` fully skips the step; the flag is documented in the header, `--help`, `--dry-run`, and the README
- Steps are consistently numbered 1/5 … 5/5 with no `/4` strings left behind
- Live execution of the installer path remains deferred to a host with a running stack, recorded in the SUMMARY and the script's LIVE VERIFICATION DEFERRED banner
</success_criteria>

<output>
Create `.planning/quick/260815-idj-add-host-coder-cli-update-step-to-update/260815-idj-SUMMARY.md` when done
</output>
