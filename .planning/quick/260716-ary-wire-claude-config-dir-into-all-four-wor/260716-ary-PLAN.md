---
phase: quick-260716-ary
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/docker/main.tf
  - templates/coderscaffold/main.tf
  - templates/java-fullstack/main.tf
  - templates/bbj-services/main.tf
autonomous: true
requirements: [QUICK-260716-ary]
must_haves:
  truths:
    - "All four public templates set CLAUDE_CONFIG_DIR in coder_agent.main env to the physical shared dir"
    - "All four startup_scripts migrate the legacy dot-claude.json into dot-claude/.claude.json once, then leave the legacy path as a symlink"
    - "GSD >= 1.7.0 install/update no longer hits the symlink write-confinement guard inside workspaces"
    - "terraform fmt is clean and terraform validate passes for every edited template"
  artifacts:
    - path: templates/docker/main.tf
      provides: "CLAUDE_CONFIG_DIR env var + config-dir migration block"
      contains: "CLAUDE_CONFIG_DIR"
    - path: templates/coderscaffold/main.tf
      provides: "CLAUDE_CONFIG_DIR env var + config-dir migration block"
      contains: "CLAUDE_CONFIG_DIR"
    - path: templates/java-fullstack/main.tf
      provides: "CLAUDE_CONFIG_DIR env var + config-dir migration block"
      contains: "CLAUDE_CONFIG_DIR"
    - path: templates/bbj-services/main.tf
      provides: "CLAUDE_CONFIG_DIR env var + config-dir migration block"
      contains: "CLAUDE_CONFIG_DIR"
  key_links:
    - from: "coder_agent.main.env.CLAUDE_CONFIG_DIR"
      to: "$CLAUDE_SHARED/dot-claude/.claude.json"
      via: "startup_script migration + legacy symlink"
      pattern: "ln -sf \"dot-claude/.claude.json\""
---

<objective>
Wire `CLAUDE_CONFIG_DIR` into all four PUBLIC workspace templates so GSD >= 1.7.0
install/update works inside workspaces. GSD 1.7.0's write-confinement guard refuses
to install/update when the config root (`~/.claude`) is a symlink — which it is in
every template (per-owner shared volume: `~/.claude` → `~/.claude-shared/dot-claude`).
GSD resolves the root from `CLAUDE_CONFIG_DIR` before falling back to `~/.claude`;
Claude Code honors the same variable and then reads `$CLAUDE_CONFIG_DIR/.claude.json`
instead of `~/.claude.json` — hence the one-time migration.

This mirrors EXACTLY the reference implementation already merged in the private repo:
`/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf`.

Purpose: Make `/gsd-update` work with no flags in every workspace; keep the legacy
`dot-claude.json` path coherent so all prior references (webforJ / MemPalace MCP
registration blocks) keep working through a symlink.
Output: Two additions per template across four `main.tf` files.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

<reference>
Copy the two additions VERBATIM from the reference file:
@/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf

Reference addition 1 — env block (bbj-ls-dev lines 259–271): the two comment
lines + `CLAUDE_CONFIG_DIR` line, placed after `GIT_COMMITTER_EMAIL` and before
the next env var (blank line separator preserved).

Reference addition 2 — startup_script block (bbj-ls-dev lines 166–182): the
comment header, the guarded one-time `cp -f` migration, the `echo '{}'` fallback,
and the final `ln -sf "dot-claude/.claude.json" "$CLAUDE_SHARED/dot-claude.json"`.
</reference>

<anchors>
<!-- Anchors verified identical in all four target files. -->

env block — each file's `env = {` ends with this line (add block AFTER it):
```
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
```
- templates/docker/main.tf: line 261 (env closes at 262 with only GIT_* keys)
- templates/coderscaffold/main.tf: line 318
- templates/java-fullstack/main.tf: line 332 (env also has JAVA_HOME/MAVEN_HOME after)
- templates/bbj-services/main.tf: line 404 (env also has JAVA_HOME/MAVEN_HOME after)

startup_script — insert config-dir block AFTER this line and BEFORE the
"# ── Claude permissions — force bypassPermissions" comment:
```
    ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"
```
- templates/docker/main.tf: ln at 188, permissions comment at 190
- templates/coderscaffold/main.tf: ln at 196, permissions comment at 198
- templates/java-fullstack/main.tf: ln at 216, permissions comment at 218
- templates/bbj-services/main.tf: ln at 299, permissions comment at 301
</anchors>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Mirror the two CLAUDE_CONFIG_DIR additions into all four public templates</name>
  <files>templates/docker/main.tf, templates/coderscaffold/main.tf, templates/java-fullstack/main.tf, templates/bbj-services/main.tf</files>
  <action>
For EACH of the four files, make the two additions copied VERBATIM from the reference
file `/Users/beff/coder-bbj-private/templates/bbj-ls-dev/main.tf`. Do NOT change the
MCP registration blocks, the bypassPermissions block, or anything else.

Addition 1 — coder_agent.main `env = { ... }` map. Immediately after the
`GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"` line, insert a blank
line then these three lines (reference lines 265–267):
  - `# Real (symlink-free) Claude config dir — see the CLAUDE_CONFIG_DIR block`
  - `# in startup_script. Makes GSD updates work and is honored by Claude Code.`
  - `CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"`
In docker and coderscaffold the env map has only GIT_* keys, so this becomes the last
key. In java-fullstack and bbj-services the map continues with JAVA_HOME/MAVEN_HOME —
the new block goes BETWEEN GIT_COMMITTER_EMAIL and those (same position as reference).

Addition 2 — startup_script. Immediately AFTER the line
`ln -sf "$CLAUDE_SHARED/dot-claude.json" "$HOME/.claude.json"` and BEFORE the
`# ── Claude permissions — force bypassPermissions in every workspace ───────`
comment, insert the block VERBATIM from reference lines 166–182: the
`# ── CLAUDE_CONFIG_DIR — symlink-free config root for Claude Code AND GSD ──`
comment header (7 comment lines), the guarded one-time migration
(`[ ! -L ... ] && [ -f ... ] && [ ! -f ... ]` then `cp -f dot-claude.json dot-claude/.claude.json`),
the `[ ! -f dot-claude/.claude.json ]` → `echo '{}' >` fallback, and the final
`ln -sf "dot-claude/.claude.json" "$CLAUDE_SHARED/dot-claude.json"`. Preserve one
blank line before and after the block to match surrounding style. There is NO literal
`${` inside this block, so no heredoc escaping is needed.

After editing all four files, run `terraform fmt` in each template directory so the
env map `=` alignment is normalized (CLAUDE_CONFIG_DIR is 17 chars; GIT_COMMITTER_EMAIL
governs alignment — let fmt handle it, do not hand-align).
  </action>
  <verify>
    <automated>cd /Users/beff/coder && for f in docker coderscaffold java-fullstack bbj-services; do grep -q 'CLAUDE_CONFIG_DIR = "/home/coder/.claude-shared/dot-claude"' templates/$f/main.tf && grep -q 'ln -sf "dot-claude/.claude.json" "\$CLAUDE_SHARED/dot-claude.json"' templates/$f/main.tf && grep -q 'CLAUDE_CONFIG_DIR — symlink-free config root' templates/$f/main.tf || { echo "MISSING in $f"; exit 1; }; done && for f in docker coderscaffold java-fullstack bbj-services; do terraform -chdir=templates/$f fmt -check >/dev/null 2>&1 || { echo "fmt not clean in $f"; exit 1; }; done && echo "ALL FOUR OK"</automated>
  </verify>
  <done>
All four templates contain the CLAUDE_CONFIG_DIR env var, the config-dir comment
header, the migration `cp -f`, the `echo '{}'` fallback, and the final legacy-symlink
`ln -sf`. `terraform fmt -check` is clean in all four template directories. The
bypassPermissions and MCP registration blocks are unchanged.
  </done>
</task>

</tasks>

<verification>
Per-file grep assertions confirm both additions landed. `terraform fmt -check` clean
in all four directories confirms env-map alignment and formatting are correct. If
`terraform` is available, `terraform -chdir=templates/<name> validate` (after
`init -backend=false`) should also pass — the SDK notes prior template plans treated
terraform validate/fmt as the authoritative gate.

Diff sanity: exactly two hunks per file (env addition + startup_script block); no
changes to bypassPermissions or webforJ/MemPalace MCP blocks.
</verification>

<success_criteria>
- CLAUDE_CONFIG_DIR wired identically into all four public templates, mirroring
  bbj-ls-dev exactly.
- Legacy `dot-claude.json` becomes a symlink into `dot-claude/.claude.json` after
  one-time migration, so GSD reads a symlink-free root and prior writes stay coherent.
- terraform fmt clean; nothing outside the two intended additions changed.
</success_criteria>

<output>
Create `.planning/quick/260716-ary-wire-claude-config-dir-into-all-four-wor/260716-ary-SUMMARY.md` when done.
</output>
