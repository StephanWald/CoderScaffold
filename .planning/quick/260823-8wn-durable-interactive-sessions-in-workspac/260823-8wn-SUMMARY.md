---
phase: quick-260823-8wn
plan: "01"
subsystem: workspace-templates
tags: [tmux, ssh, keepalive, durable-sessions, dockerfile, readme]
status: complete

dependency_graph:
  requires: []
  provides:
    - tmux baked into all six workspace images
    - /etc/profile.d/10-tmux-autoattach.sh in all six images
    - README durable-sessions/keepalive subsection
  affects:
    - templates/docker/Dockerfile
    - templates/coderscaffold/Dockerfile
    - templates/python-ai/Dockerfile
    - templates/java-fullstack/Dockerfile
    - templates/flutter/Dockerfile
    - templates/bbj-services/Dockerfile
    - README.md

tech_stack:
  added:
    - tmux (apt package, all six workspace images)
    - /etc/profile.d/10-tmux-autoattach.sh (POSIX-sh, image layer)
  patterns:
    - profile.d snippet pattern (same as 10-uv.sh, 10-java-maven.sh, 10-flutter.sh)
    - tmux new -A -s main (create-or-attach named session)
    - apt fold-in (adding package to an existing install layer where natural fit exists)

key_files:
  modified:
    - templates/docker/Dockerfile
    - templates/coderscaffold/Dockerfile
    - templates/python-ai/Dockerfile
    - templates/java-fullstack/Dockerfile
    - templates/flutter/Dockerfile
    - templates/bbj-services/Dockerfile
    - README.md

decisions:
  - "docker/coderscaffold: dedicated tmux apt layer (no existing generic install layer to fold into)"
  - "python-ai/java-fullstack: tmux folded into MemPalace apt layer (python3 python3-venv tmux)"
  - "flutter: tmux folded into Flutter build-deps apt layer (git curl file unzip ... tmux)"
  - "bbj-services: tmux + snippet in base stage (so final stage inherits via FROM base AS final)"
  - "verify script printf extraction regex has a bug (expects % immediately after 'printf ' but standard form is printf '%s\\n' with leading single-quote); verified snippet correctness via alternative python3 extraction + sh -n"
  - "README subsection placed between Workspace Agent Connectivity and Home directory persistence — reads most naturally adjacent to the connectivity material"

metrics:
  duration: "~20min"
  completed: "2026-08-23"
  tasks_completed: 2
  commits: 2
  files_changed: 7

actuals:
  tokens: 12000
  tasks: 2
  commits: 2
---

# Phase quick-260823-8wn Plan 01: Durable Interactive Sessions Summary

**One-liner:** tmux auto-attach baked into all six workspace images with guarded profile.d snippet + SSH keepalive documentation in README.

## What Was Built

### Task 1: tmux install + profile.d auto-attach snippet (6 Dockerfiles)

Commit: `75f0200`

In all six workspace Dockerfiles, added:

**(A) tmux install** — via apt, folded into an existing install layer where a natural fit exists:
- `docker`, `coderscaffold`: dedicated small apt layer (no existing generic tools layer)
- `python-ai`, `java-fullstack`: folded into the MemPalace layer (`python3 python3-venv tmux`)
- `flutter`: folded into the Flutter build-deps layer (`git curl file unzip ... tmux`)
- `bbj-services`: folded into the casefold tooling layer (`e2fsprogs util-linux tmux`) in the `base` stage — the `final` stage inherits it via `FROM base AS final`

**(B) `/etc/profile.d/10-tmux-autoattach.sh`** — POSIX-sh, chmod 0644, image layer (not `/home/coder`). Uses `printf '%s\n'` multi-line RUN, same style as the existing `10-uv.sh`, `10-java-maven.sh`, `10-flutter.sh` blocks.

Snippet guard chain (ALL must hold to auto-attach):
- Interactive shell: `case "$-" in *i*)` (POSIX)
- TTY: `[ -t 1 ]`
- Not already in tmux: `[ -z "$TMUX" ]`
- tmux on PATH: `command -v tmux >/dev/null 2>&1`
- Not VS Code Remote-SSH: `[ -z "$VSCODE_INJECTION" ] && [ -z "$VSCODE_IPC_HOOK_CLI" ]`

When all guards hold: `exec tmux new -A -s main` (create-or-attach session `main`). Fall-through path is always safe — the shell continues normally. One-shot `coder ssh -- <cmd>` and scp/rsync are excluded by the interactive + TTY guards.

### Task 2: README keepalive/durable-sessions subsection

Commit: `ad48464`

Added `### Durable interactive sessions (tmux + SSH keepalives)` between `### Workspace Agent Connectivity` and `### Home directory persistence`. Content covers:
- Server-side persistence: tmux auto-attach, rebuild caveat, VS Code/non-interactive inertness
- Client-side liveness: `coder config-ssh --ssh-option ServerAliveInterval=30 --ssh-option ServerAliveCountMax=3 --ssh-option TCPKeepAlive=yes` with hand-edit equivalent
- VS Code `remote.SSH` note: honors SSH config keepalives; `remote.SSH.connectTimeout` for slow reconnects
- Tie-in: tmux (server-side) + keepalives (client-side) solve both "session died" and "session hung"

## Verification Results

### Plan-specified automated checks (run via alternative extraction — see Deviations)

```
PASS: 10-tmux-autoattach.sh in 6/6 Dockerfiles
PASS: tmux referenced in all 6
PASS: bash-default block (usermod -s /bin/bash coder) intact in all 6
PASS: all 6 snippets pass sh -n
PASS: all 6 snippets contain 'exec tmux new -A -s main'
PASS: all 6 snippets guard on TMUX, VSCODE_INJECTION/VSCODE_IPC_HOOK_CLI, -t 1
PASS: README has ServerAliveInterval, ServerAliveCountMax, config-ssh, VS Code, tmux, rebuild tokens
```

### Out of scope (per plan constraints)

A full `docker image rebuild` is out of scope. The `sh -n` + grep checks are the agreed verification surface. Per the `infra-needs-live-deploy-gate` memory: a real workspace rebuild + browser-terminal reconnect test is the true end-to-end confirmation, flagged here for follow-up.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Verify script printf extraction regex does not match standard `printf '%s\n'` form**

- **Found during:** Task 1 verification
- **Issue:** The plan's Node.js verify script uses the regex `/printf %[^\n]*?\x27%s\\n\x27/` which expects a `%` character immediately after `printf ` (before the format string). All existing profile.d blocks in these Dockerfiles use `printf '%s\n'` (single-quote before `%s`), which does NOT satisfy the regex. The plan itself instructs using the same style as existing `10-uv.sh` / `10-java-maven.sh` / `10-flutter.sh` blocks — which use `printf '%s\n'`.
- **Fix:** Used an alternative python3-based extraction (anchored to the specific `printf ... > /etc/profile.d/10-tmux-autoattach.sh` RUN block) for the `sh -n` step. All correctness checks (snippet syntax, guard presence, `exec tmux new -A -s main`) pass. The snippet itself is correct; only the verify script regex is broken.
- **Files modified:** None (implementation unchanged; only verification method substituted)
- **Commit:** No separate commit — documented here

## Known Stubs

None. All six Dockerfiles have the tmux install + snippet wired completely. README section is fully documented.

## Threat Flags

None. The tmux install and profile.d snippet stay within the threat model documented in the plan (T-8wn-01: `sh -n` syntax-checked; T-8wn-02: standard Ubuntu apt; T-8wn-03: unprivileged coder user, per-container session).

## Self-Check

- [x] `templates/docker/Dockerfile` modified — confirmed
- [x] `templates/coderscaffold/Dockerfile` modified — confirmed
- [x] `templates/python-ai/Dockerfile` modified — confirmed
- [x] `templates/java-fullstack/Dockerfile` modified — confirmed
- [x] `templates/flutter/Dockerfile` modified — confirmed
- [x] `templates/bbj-services/Dockerfile` modified — confirmed (base stage)
- [x] `README.md` modified — confirmed
- [x] Commit `75f0200` exists (Task 1)
- [x] Commit `ad48464` exists (Task 2)
- [x] All verification checks passed

## Self-Check: PASSED
