---
phase: quick-260716-afr
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - templates/docker/Dockerfile
  - templates/coderscaffold/Dockerfile
  - templates/java-fullstack/Dockerfile
  - templates/bbj-services/Dockerfile
autonomous: true
requirements: [QUICK-260716-afr]

must_haves:
  truths:
    - "All four public workspace images install the GitHub CLI (gh) at build time"
    - "The gh install block is byte-identical to the private template-dev reference (lines 46-57)"
    - "The block is inserted while still root, immediately before the final USER coder line in each Dockerfile"
    - "No other content in any of the four Dockerfiles changes"
  artifacts:
    - path: "templates/docker/Dockerfile"
      provides: "gh install block before USER coder"
      contains: "apt-get install -y --no-install-recommends gh"
    - path: "templates/coderscaffold/Dockerfile"
      provides: "gh install block before USER coder"
      contains: "apt-get install -y --no-install-recommends gh"
    - path: "templates/java-fullstack/Dockerfile"
      provides: "gh install block before USER coder"
      contains: "apt-get install -y --no-install-recommends gh"
    - path: "templates/bbj-services/Dockerfile"
      provides: "gh install block in final stage before USER coder"
      contains: "apt-get install -y --no-install-recommends gh"
  key_links:
    - from: "each Dockerfile"
      to: "cli.github.com apt repo"
      via: "githubcli-archive-keyring + github-cli.list"
      pattern: "cli.github.com/packages"
---

<objective>
Add the GitHub CLI (`gh`) to all four public workspace template images by
inserting the identical install block already proven in the private
`template-dev` image.

Purpose: parity across every workspace image — developers get `gh` out of the
box, authenticating once per workspace with `gh auth login` (token persists in
`~/.config/gh` on the home volume).

Output: `gh` install block (arch-aware, official `cli.github.com` apt repo) baked
into `templates/docker/Dockerfile`, `templates/coderscaffold/Dockerfile`,
`templates/java-fullstack/Dockerfile`, and `templates/bbj-services/Dockerfile`.
No `main.tf` changes — `docker_image.triggers.dockerfile_sha1` picks up the edit
automatically.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

<!-- REFERENCE BLOCK — copy verbatim. Lines 46-57 of the private template-dev
     Dockerfile. This is the exact text (comment header + single RUN) to insert.
     Read this file to copy the block byte-for-byte; do not retype from memory. -->
@/Users/beff/coder-bbj-private/templates/template-dev/Dockerfile

<insertion_points>
Each Dockerfile ends with a `USER coder` line that drops from root back to the
workspace user. The gh block installs via apt (needs root), so it MUST go while
still root — immediately BEFORE that final `USER coder`.

- templates/docker/Dockerfile          → before `USER coder` (final line, line 24)
- templates/coderscaffold/Dockerfile   → before `USER coder` (final line, line 42)
- templates/java-fullstack/Dockerfile  → before `USER coder` (final line, line 128)
- templates/bbj-services/Dockerfile    → before `USER coder` in the `final` stage
  (line 205), i.e. after `COPY --from=bbjinstall /opt/bbx /opt/bbx` and
  `EXPOSE 8888`. The `final` stage derives `FROM base AS final`; base runs `USER root`,
  so the final stage is already root — no USER changes needed.
</insertion_points>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Insert the gh install block before USER coder in all four Dockerfiles</name>
  <files>templates/docker/Dockerfile, templates/coderscaffold/Dockerfile, templates/java-fullstack/Dockerfile, templates/bbj-services/Dockerfile</files>
  <action>
    Read lines 46-57 of /Users/beff/coder-bbj-private/templates/template-dev/Dockerfile
    (the `── GitHub CLI (gh) ──` comment header through the single RUN ending in
    `rm -rf /var/lib/apt/lists/*`). Copy that block byte-for-byte.

    In each of the four target Dockerfiles, insert the copied block so that it sits
    immediately before the final `USER coder` line, with one blank line separating
    the preceding content from the block. Preserve leading whitespace/continuation
    formatting exactly as in the reference (the ` && ` line continuations use a
    single leading space).

    Per-file placement:
    - templates/docker/Dockerfile: after the Node.js RUN (ends `rm -rf /var/lib/apt/lists/*`),
      before `USER coder`.
    - templates/coderscaffold/Dockerfile: after the MemPalace RUN, before `USER coder`.
    - templates/java-fullstack/Dockerfile: after the MemPalace RUN, before `USER coder`.
    - templates/bbj-services/Dockerfile: in the `final` stage, after `EXPOSE 8888`,
      before `USER coder`. Do NOT add it to the `base` or `bbjinstall` stages.

    Do NOT modify anything else in any Dockerfile. No main.tf edits.
  </action>
  <verify>
    <automated>for f in templates/docker/Dockerfile templates/coderscaffold/Dockerfile templates/java-fullstack/Dockerfile templates/bbj-services/Dockerfile; do grep -q 'apt-get install -y --no-install-recommends gh' "$f" && grep -q 'cli.github.com/packages/githubcli-archive-keyring.gpg' "$f" || { echo "MISSING gh block in $f"; exit 1; }; done; echo OK</automated>
  </verify>
  <done>
    All four Dockerfiles contain the identical gh install block positioned
    immediately before their final `USER coder` line (for bbj-services, in the
    `final` stage after `EXPOSE 8888`). The block matches the private template-dev
    reference (lines 46-57) byte-for-byte. No other lines changed; no main.tf edits.
  </done>
</task>

</tasks>

<verification>
- `git diff` shows only additions (the gh block) in the four Dockerfiles — no
  deletions or edits to existing lines.
- In each file, the gh block appears before `USER coder`; the last line remains
  `USER coder`.
- The inserted block is identical across all four files and matches the reference.
- No changes to any `main.tf`.
</verification>

<success_criteria>
- `gh` install block present and identical in all four target Dockerfiles.
- Block sits while root, before the final `USER coder`.
- bbj-services block is in the `final` stage only.
- Zero unrelated changes.
</success_criteria>

<output>
Create `.planning/quick/260716-afr-add-github-cli-gh-to-all-four-workspace-/260716-afr-SUMMARY.md` when done.
</output>
