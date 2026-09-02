---
phase: quick-260902-hto
plan: "01"
status: complete
subsystem: templates/bbj-dev, templates/bbj-ls-dev (CoderPrivate)
tags: [tmux, durable-sessions, private-templates, bbj-dev, bbj-ls-dev]
dependency_graph:
  requires: [260823-8wn, 260823-qz4]
  provides: [bbj-dev tmux parity, bbj-ls-dev tmux parity]
  affects: [CoderPrivate/templates/bbj-dev/Dockerfile, CoderPrivate/templates/bbj-ls-dev/Dockerfile]
tech_stack:
  added: []
  patterns: [dedicated tmux apt block in base stage, /etc/profile.d auto-attach snippet, /etc/bash.bashrc hook, /etc/tmux.conf system config]
key_files:
  created: []
  modified:
    - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
decisions:
  - All four tmux blocks placed in the base stage (before bbjinstall/final split) so the final runtime image inherits them via FROM base — mirrors the donor bbj-services pattern
  - Dedicated tmux apt block used (not folded into another layer) because neither private Dockerfile has an e2fsprogs/util-linux casefold layer to combine with
  - Snippet content copied verbatim from the bbj-services donor (proven valid via sh -n in quick 260823-8wn) — reinvention avoided
metrics:
  duration: "~10 min"
  completed: "2026-09-02"
  tasks: 2
  commits: 1
actuals:
  tokens: 4500
  tasks: 2
  commits: 1
---

# Phase quick-260902-hto Plan 01: tmux auto-attach + system tmux.conf for bbj-dev/bbj-ls-dev Summary

**One-liner:** Added tmux install, `/etc/profile.d/10-tmux-autoattach.sh`, `/etc/bash.bashrc` hook, and `/etc/tmux.conf` (mouse on + 50k scrollback) to the base stage of both private BBj Dockerfiles, bringing them to parity with the six public templates.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 (tracer) | Add all four tmux blocks to bbj-dev base stage | 6a6b859 | templates/bbj-dev/Dockerfile |
| 2 | Replicate same four tmux blocks in bbj-ls-dev base stage, verify both | 6a6b859 | templates/bbj-ls-dev/Dockerfile |

Both tasks were committed atomically as a single commit in /workspaces/CoderPrivate.

## What Was Done

Four elements were added to the `base` stage of each private BBj Dockerfile, before the `bbjinstall`/`final` split so the final runtime image inherits them:

1. **tmux apt block** — dedicated `apt-get install -y --no-install-recommends tmux` block with box-drawing header and prose comment (system-wide, /usr, outside volume-shadowed /home/coder).
2. **/etc/profile.d/10-tmux-autoattach.sh** — verbatim copy of the bbj-services donor snippet: guards for interactive+TTY+not-in-tmux+tmux-on-PATH+not-VS-Code; `exec tmux new -A -s main`; chmod 0644.
3. **/etc/bash.bashrc hook** — appends the guarded source line to /etc/bash.bashrc for interactive non-login shells (Coder browser web terminal); idempotent (no double-attach, no recursion).
4. **/etc/tmux.conf** — `set -g mouse on` + `set -g history-limit 50000`; chmod 0644.

Content is verbatim from the bbj-services donor (quick tasks 260823-8wn + 260823-qz4).

## Verification

Static parity checks passed:

```
cd /workspaces/CoderPrivate && for f in bbj-dev bbj-ls-dev; do for t in '10-tmux-autoattach' 'tmux.conf' 'history-limit 50000' 'mouse on'; do grep -q "$t" templates/$f/Dockerfile; done; grep -Eq 'apt-get install.*tmux' templates/$f/Dockerfile; done
# → both files: tmux parity OK

docker build --check -f templates/bbj-dev/Dockerfile templates/bbj-dev
# → Check complete, no warnings found.

docker build --check -f templates/bbj-ls-dev/Dockerfile templates/bbj-ls-dev
# → Check complete, no warnings found.
```

## Live Gate (OPERATOR ACTION REQUIRED — not verified here)

Per project memory `infra-needs-live-deploy-gate`: static grep parity is the only gate satisfiable in this environment. **Runtime is NOT verified.**

The operator must:

1. Re-run `scripts/push-templates.sh` (or equivalent) to push the updated private templates.
2. Rebuild the `bbj-dev` and `bbj-ls-dev` workspace images (template push triggers image rebuild on next workspace start, or force-rebuild manually).
3. Start (or restart) a workspace of each type.
4. Open the web terminal for each workspace and confirm:
   - Terminal auto-attaches to a `tmux` session (`tmux new -A -s main`) — prompt shows inside tmux (check `echo $TMUX` or look for the tmux status bar).
   - Close the browser tab and reopen — session survives (reconnects to the same `main` session, no lost output).
   - Mouse wheel scrolls into scrollback (mouse mode active).
   - 50k-line scrollback holds (run `seq 1 60000` and scroll up past line 50000 to confirm).
5. Verify `coder ssh` sessions also auto-attach (interactive login shell path via /etc/profile.d).

## Deviations from Plan

None — plan executed exactly as written. Verbatim block copy from the bbj-services donor used throughout.

## Known Stubs

None.

## Self-Check: PASSED

- /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile — MODIFIED (confirmed via git diff)
- /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile — MODIFIED (confirmed via git diff)
- Commit 6a6b859 exists in /workspaces/CoderPrivate (confirmed via git log)
- No public /workspaces/coder source files changed
