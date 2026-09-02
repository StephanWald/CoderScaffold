---
phase: quick-260902-hto
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
  - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
autonomous: true
requirements: [QUICK-260902-hto]
estimate:
  tokens: 45000
  raw_tokens: 30000
  tasks: 2
  confidence: high

must_haves:
  truths:
    - "Both private BBj Dockerfiles install the tmux package in their base stage."
    - "Both contain /etc/profile.d/10-tmux-autoattach.sh with content identical to the public bbj-services snippet (all guards)."
    - "Both source that snippet from /etc/bash.bashrc for interactive non-login shells."
    - "Both write /etc/tmux.conf with `set -g mouse on` and `set -g history-limit 50000`."
  artifacts:
    - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
  key_links:
    - "All four tmux blocks live in the base stage (before the bbjinstall/final split) so the final runtime image inherits them via FROM base."
---

<objective>
Bring the two CoderPrivate BBj templates (bbj-dev, bbj-ls-dev) to tmux parity with the six public templates: durable interactive sessions (tmux auto-attach) plus a system-wide tmux config. Both private Dockerfiles currently have zero tmux content.

Purpose: web-terminal / `coder ssh` sessions in these private engineering images survive client disconnect/hibernate (durable `tmux new -A -s main`), and get mouse-scroll + 50k scrollback — matching the already-shipped public template behavior.

Output: two edited Dockerfiles in the SEPARATE /workspaces/CoderPrivate git repo, one atomic commit there. No public-repo source changes.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

# Donor implementation (public, DO NOT EDIT — copy blocks FROM it):
@/workspaces/coder/templates/bbj-services/Dockerfile

# Targets (in the SEPARATE /workspaces/CoderPrivate git repo):
@/workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
@/workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Add all four tmux blocks to bbj-dev base stage (end-to-end, one file)</name>
  <files>/workspaces/CoderPrivate/templates/bbj-dev/Dockerfile</files>
  <read_first>
    Donor blocks in /workspaces/coder/templates/bbj-services/Dockerfile:
    - line 168: apt-get install layer that includes tmux (folded with e2fsprogs util-linux)
    - lines 172-200: the printf'd /etc/profile.d/10-tmux-autoattach.sh block (header comment + printf + chmod 0644)
    - lines 202-214: the /etc/bash.bashrc sourcing hook block
    - lines 216-232: the printf'd /etc/tmux.conf block (mouse on + history-limit 50000, chmod 0644)
    bbj-dev structure: base stage FROM at line 39; bbjinstall split, final at 317, USER coder at 367.
  </read_first>
  <action>
    Copy the tmux content from the donor into the bbj-dev base stage (between line 39 (FROM base) and the stage's end / bbjinstall split), placing all blocks BEFORE the bbjinstall/final split so final inherits them via FROM base — mirror the donor's inline comment that states exactly this.

    Four elements, verbatim content preferred over reinvention:
    (a) tmux package install. bbj-dev has no e2fsprogs/util-linux casefold layer to fold into, so add a small DEDICATED apt block matching this file's block style (box-drawing header + prose comment + chained apt-get update then apt-get install -y --no-install-recommends tmux then apt-get clean then rm -rf /var/lib/apt/lists/*). Note in the comment that tmux is installed system-wide (outside the volume-shadowed /home/coder) and in the base stage so final inherits.
    (b) the /etc/profile.d/10-tmux-autoattach.sh printf block — copy the donor's printf argument lines VERBATIM (lines 185-198 content) plus the redirect to /etc/profile.d/10-tmux-autoattach.sh and chmod 0644. Keep the donor's explanatory header comment.
    (c) the /etc/bash.bashrc sourcing hook — copy donor lines 210-214 content verbatim (the append to /etc/bash.bashrc of the guarded source line) with its comment.
    (d) the /etc/tmux.conf printf block — copy donor lines 227-232 content verbatim (set -g mouse on, set -g history-limit 50000, chmod 0644) with its comment.

    Keep one-purpose-per-block commenting conventions of this file (box-drawing headers). Do not touch main.tf, the bbjinstall stage, the final stage, or USER coder. Do NOT edit any public /workspaces/coder file.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate && for t in '10-tmux-autoattach' 'tmux.conf' 'history-limit 50000' 'mouse on'; do grep -q "$t" templates/bbj-dev/Dockerfile || { echo "MISSING: $t"; exit 1; }; done; grep -Eq 'apt-get install.*tmux' templates/bbj-dev/Dockerfile || { echo "MISSING: tmux apt install"; exit 1; }; echo "bbj-dev parity OK"</automated>
  </verify>
  <done>bbj-dev Dockerfile base stage contains all four tmux elements (apt install, profile.d snippet, bash.bashrc hook, tmux.conf); grep parity check against bbj-services passes; no public files changed.</done>
</task>

<task type="auto">
  <name>Task 2: Replicate the same four tmux blocks in bbj-ls-dev base stage, then verify both</name>
  <files>/workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile</files>
  <read_first>
    Same donor blocks as Task 1 (bbj-services Dockerfile lines 168-232). Task 1's applied edit to bbj-dev is the working reference for exactly what to insert.
    bbj-ls-dev structure: base stage FROM at line 70; bbjinstall split, final at 293, USER coder at 330. bbj-ls-dev also has no e2fsprogs/util-linux casefold layer, so use the same dedicated tmux apt block as bbj-dev.
  </read_first>
  <action>
    Insert the identical four tmux blocks (dedicated tmux apt block, /etc/profile.d/10-tmux-autoattach.sh printf, /etc/bash.bashrc hook, /etc/tmux.conf printf) into the bbj-ls-dev base stage, placed BEFORE the bbjinstall/final split so final inherits via FROM base — mirror the donor's inline comment noting exactly that. Content parity with bbj-services (and with the bbj-dev edit from Task 1): the guards, comments, and semantics must match; verbatim block copy is preferred over reinvention.

    Match this file's own block style (box-drawing headers, one-purpose-per-block comments). Do not touch main.tf, the bbjinstall stage, the final stage, or USER coder. Do NOT edit any public /workspaces/coder file.

    After editing, run the combined parity + snippet-validity checks in verify.
  </action>
  <verify>
    <automated>cd /workspaces/CoderPrivate && for f in bbj-dev bbj-ls-dev; do for t in '10-tmux-autoattach' 'tmux.conf' 'history-limit 50000' 'mouse on'; do grep -q "$t" templates/$f/Dockerfile || { echo "MISSING $t in $f"; exit 1; }; done; grep -Eq 'apt-get install.*tmux' templates/$f/Dockerfile || { echo "MISSING tmux apt install in $f"; exit 1; }; done; echo "both files: tmux parity OK"</automated>
  </verify>
  <done>Both private Dockerfiles pass the four-element grep parity check plus the tmux apt-install check. Content mirrors bbj-services (verbatim snippet copy). No public files changed.</done>
</task>

</tasks>

<verification>
Static parity (authoritative gate here — docker CLI/live build is the operator gate):

1. Four-element grep parity in BOTH private Dockerfiles (matched against bbj-services):
   `cd /workspaces/CoderPrivate && for f in bbj-dev bbj-ls-dev; do echo "== $f =="; grep -nE '10-tmux-autoattach|tmux\.conf|history-limit 50000|mouse on|apt-get install.*tmux' templates/$f/Dockerfile; done`

2. Snippet validity — the auto-attach snippet is printf'd verbatim from a donor already proven valid (sh -n in quick 260823-8wn), so exact copy suffices. IF any adaptation was made to the snippet body, extract the printf'd content and run `sh -n` on it; otherwise skip.

3. Best-effort build lint (docker CLI supports --check here): `docker build --check -f templates/bbj-dev/Dockerfile templates/bbj-dev 2>&1 | tail -5` and same for bbj-ls-dev. WARN-and-continue — a build-context/base-image failure here is NOT a blocker (these images build from the operator asset context, not this repo). terraform validate NOT needed (main.tf untouched).
</verification>

<success_criteria>
- Both /workspaces/CoderPrivate BBj Dockerfiles contain, in the base stage: tmux installed via apt; /etc/profile.d/10-tmux-autoattach.sh (content identical to public snippet, all guards); /etc/bash.bashrc sourcing hook; /etc/tmux.conf with mouse on + history-limit 50000.
- All four blocks precede the bbjinstall/final split so final inherits them.
- Content parity with bbj-services (verbatim block copy).
- One atomic commit in the SEPARATE /workspaces/CoderPrivate git repo. No changes committed to /workspaces/coder.
</success_criteria>

<commit_note>
All changes are in /workspaces/CoderPrivate — a SEPARATE git repo from the /workspaces/coder planning root. Commit there with `git -C /workspaces/CoderPrivate ...` as ONE atomic commit (e.g. `feat(templates): tmux auto-attach + system tmux.conf for bbj-dev/bbj-ls-dev`). Do NOT stage or commit anything under /workspaces/coder except this plan/SUMMARY (handled by the quick-task workflow's own docs commit).
</commit_note>

<live_gate>
Static grep parity is the only gate satisfiable here. Per project memory infra-needs-live-deploy-gate: image rebuild + workspace restart + web-terminal reconnect test is the OPERATOR's verification. The SUMMARY MUST flag that runtime is NOT verified — operator re-runs the private push-templates.sh, rebuilds bbj-dev + bbj-ls-dev images, restarts a workspace of each, and confirms: web terminal auto-attaches to `tmux`, session survives a browser disconnect/reconnect, mouse-wheel scrolls into scrollback, and 50k history holds.
</live_gate>

<output>
Create `.planning/quick/260902-hto-add-tmux-auto-attach-tmux-conf-to-coderp/260902-hto-SUMMARY.md` when done.
</output>
