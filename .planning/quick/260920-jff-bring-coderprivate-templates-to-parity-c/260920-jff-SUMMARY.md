---
phase: quick-260920-jff
plan: "01"
subsystem: CoderPrivate workspace templates
tags: [codex, mempalace, selftest, bbj-dev, bbj-ls-dev, parity]
status: complete

dependency_graph:
  requires:
    - quick-260920-e63  # Codex CLI tracer (canonical patterns from c8667b5)
    - quick-260920-d6x  # selftest bake + Self-Test apps (canonical patterns from 5c0783c)
    - quick-260920-cw8  # MemPalace relocation (WR-01/WR-03 pattern)
  provides:
    - PARITY-CODEX      # CoderPrivate bbj templates now have Codex CLI parity with public fleet
    - PARITY-MEMPALACE  # CoderPrivate bbj templates now have MemPalace relocation parity
    - PARITY-SELFTEST   # CoderPrivate bbj templates now have Self-Test bake parity
  affects:
    - /workspaces/CoderPrivate/modules/bbj-base/main.tf
    - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/CoderPrivate/scripts/claude-share-selftest.sh
    - /workspaces/CoderPrivate/scripts/push-templates.sh

tech_stack:
  added:
    - "@openai/codex 0.155.1 (ARG-pinned npm -g, final stage, both bbj Dockerfiles)"
    - "claude-share-selftest.sh baked at /usr/local/bin/claude-share-selftest (both bbj images)"
  patterns:
    - "WR-01 migrate + WR-03 non-fatal for MemPalace and Codex sharing blocks in bbj-base"
    - "Asset-context selftest staging (COPY resolves against BBj build context = /mnt/bbj-assets)"
    - "selftest_sha1 = try(filesha1(asset-context-path), '') rebuild trigger"

key_files:
  created:
    - /workspaces/CoderPrivate/scripts/claude-share-selftest.sh
  modified:
    - /workspaces/CoderPrivate/modules/bbj-base/main.tf
    - /workspaces/CoderPrivate/templates/bbj-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/Dockerfile
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/CoderPrivate/scripts/push-templates.sh

decisions:
  - "MemPalace relocation + Codex sharing blocks placed in modules/bbj-base (shared by both bbj templates) — single edit reaches both bbj-dev and bbj-ls-dev"
  - "No mempalace init added — none exists in the shared module; MCP server already registered; init guard would be wrong (symlink always present)"
  - "template-dev excluded: no Node/claude/mempalace prerequisites; selftest probes and MemPalace init would all fail — not part of this fleet by design"
  - "GSD mempalace.enabled flip skipped: neither bbj-dev nor bbj-ls-dev clones a GSD-managed .planning/config.json repo — nothing to enable"
  - "selftest_sha1 hashes the ASSET-context copy (var.bbj_context_path/claude-share-selftest.sh), not path.module — the build context is the asset folder, not the template dir"
  - "try() on selftest_sha1 yields '' when staged copy is absent locally, so terraform validate/fmt pass without it on the operator's dev machine"
  - "Plan gate had two BRE regex bugs: grep -vc >/dev/null exits 1 (redirect artifact); grep -q with dollar-sign in pattern treats $ as end-of-line anchor — both are false negatives, actual content is correct (verified with -F and Python)"

metrics:
  duration: "~7 minutes"
  completed: "2026-09-20T14:11:16Z"
  tasks: 3
  commits: 3
  plan_head_before: 8b3cf4d7e994cd5ca1529b0eb50c9462d39b932a

actuals:
  tokens: 18000
  tasks: 3
  commits: 3
---

# Phase quick-260920-jff Plan 01: Bring CoderPrivate templates to parity (Codex + MemPalace + Self-Test) Summary

**One-liner:** Codex CLI sharing + MemPalace palace relocation + selftest bake in CoderPrivate bbj-dev and bbj-ls-dev via shared `modules/bbj-base` + per-Dockerfile final-stage additions.

## What Was Built

Three parity items from the public fleet are now in the CoderPrivate BBj templates:

### Task 1 — bbj-base module: MemPalace relocation + Codex sharing + CODEX_HOME (Commit 4c608b7)

`/workspaces/CoderPrivate/modules/bbj-base/main.tf` — shared module covering both bbj-dev and bbj-ls-dev:

- **MemPalace palace relocation block** (PARITY-MEMPALACE): inserted before `${var.extra_startup_script}`. Creates `$CLAUDE_SHARED/mempalace`; WR-01 migrates a pre-existing real `~/.mempalace` (`cp -an` + remove-only-on-copy-success-or-empty guard); `ln -sfn` creates the symlink. All steps WR-03 warn-and-continue. No `mempalace init` added — the MCP server is already registered by the existing block; there is no init call in this module.

- **Codex CLI sharing block** (PARITY-CODEX): verbatim shape from c8667b5. Creates `$CLAUDE_SHARED/codex`; same WR-01 migrate + WR-03 guard for `~/.codex`; `ln -sfn` symlink.

- **`CODEX_HOME = "/home/coder/.claude-shared/codex"`** added to the static `env = merge({...}, var.extra_env)` map after `CLAUDE_CONFIG_DIR`, physical symlink-free path mirroring the existing pattern.

### Task 2 — Both bbj Dockerfiles: Codex install + selftest COPY in final stage (Commit d72de3f)

`templates/bbj-dev/Dockerfile` and `templates/bbj-ls-dev/Dockerfile` — in the `final` stage (`FROM base AS final`), before `USER coder`:

- `ARG CODEX_VERSION=0.155.1` + `RUN npm install -g @openai/codex@${CODEX_VERSION}` — ARG re-declared in final stage (ARG scope is per-stage in multi-stage builds); node/npm present from base stage inherited by final; system path survives home-volume shadow.
- `COPY claude-share-selftest.sh /usr/local/bin/claude-share-selftest` + `RUN chmod 0755 ...` — COPY resolves against the BBj asset build context (`var.bbj_context_path` = `/mnt/bbj-assets`), NOT the template directory. The script is staged there by `push-templates.sh`.
- `templates/template-dev/Dockerfile` untouched.

### Task 3 — Self-Test apps + selftest_sha1 triggers + canonical selftest + push script (Commit 1d361cf)

- **`scripts/claude-share-selftest.sh`** committed to CoderPrivate — byte-identical copy of `/workspaces/coder/scripts/claude-share-selftest.sh`, chmod 0755. This is the committed canonical source; the staged copies in `/mnt/bbj-assets/` are build artifacts, not committed.

- **`selftest_sha1` rebuild trigger** in both `templates/bbj-dev/main.tf` and `templates/bbj-ls-dev/main.tf` `docker_image.main` triggers maps:
  ```
  selftest_sha1 = try(filesha1("${var.bbj_context_path}/claude-share-selftest.sh"), "")
  ```
  Hashes the ASSET-context copy (not `path.module`) — critical difference from the public templates. `try()` yields `""` when the staged copy is absent locally so `terraform validate`/`fmt` pass without it.

- **`coder_app "self_test"`** in both main.tf files: command-type (no `url`, no `healthcheck`, no `count`, no `share`), `agent_id = module.base.agent_id`, `slug = "self-test"`, `display_name = "Self-Test"`, `command = "/usr/local/bin/claude-share-selftest all"`, `icon = "/icon/terminal.svg"`, `order = 8` (after existing max order 7 in bbj-dev; order 8 in bbj-ls-dev which had max 3 before this change).

- **`scripts/push-templates.sh`** extended: inside the `if [[ -n "${ASSETS}" ]]` block (after the two Dockerfile staging lines), stages the canonical selftest into the asset folder with warn-and-continue if the canonical source is absent. No `.gitignore` change needed — the staged copy goes into the external asset folder (`/mnt/bbj-assets`), not a template directory.

## Verification Gates Passed

| Check | Result |
|-------|--------|
| `modules/bbj-base/main.tf`: CLAUDE_SHARED/codex block | PASS |
| `modules/bbj-base/main.tf`: CLAUDE_SHARED/mempalace block | PASS |
| `modules/bbj-base/main.tf`: CODEX_HOME env | PASS |
| `modules/bbj-base/main.tf`: no mempalace init call | PASS |
| bbj-dev Dockerfile: ARG CODEX_VERSION=0.155.1 in final stage | PASS |
| bbj-dev Dockerfile: npm install -g @openai/codex | PASS |
| bbj-dev Dockerfile: selftest COPY + chmod | PASS |
| bbj-ls-dev Dockerfile: same as bbj-dev | PASS |
| template-dev: untouched | PASS |
| bbj-dev main.tf: selftest_sha1 (asset-context) | PASS |
| bbj-dev main.tf: Self-Test coder_app | PASS |
| bbj-ls-dev main.tf: selftest_sha1 (asset-context) | PASS |
| bbj-ls-dev main.tf: Self-Test coder_app | PASS |
| scripts/claude-share-selftest.sh: executable + byte-identical | PASS |
| scripts/push-templates.sh: selftest staging line | PASS |
| `bash -n scripts/push-templates.sh` | PASS |
| `terraform fmt -check templates/bbj-dev/` | PASS |
| `terraform fmt -check templates/bbj-ls-dev/` | PASS |
| `terraform init -backend=false` (bbj-dev) | PASS |
| `terraform init -backend=false` (bbj-ls-dev) | PASS |
| `terraform validate` (bbj-dev) | PASS |
| `terraform validate` (bbj-ls-dev) | PASS |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Plan Gate Bugs (documented, not deviations)

Two bugs in the plan's automated verify patterns were discovered; the actual file content is correct in both cases:

1. **`grep -vc ... >/dev/null` exits 1**: Task 1's gate uses `grep -vc '^[[:space:]]*#' modules/bbj-base/main.tf >/dev/null` — in bash, redirecting `grep -vc` output to `/dev/null` causes exit code 1 even when grep finds matches. The file has 326 non-comment lines (verified). False negative; content is correct.

2. **BRE regex `$` anchor**: The Task 3 gates use `grep -q 'pattern with "${var.bbj_context_path}"...'` — the `$` in `"${var.bbj_context_path}"` is treated as an end-of-line anchor in BRE mode, causing the match to fail even when the text is present. Verified correct with `grep -F` (fixed-string) and Python `in` operator.

## Scope Exclusions (recorded per plan)

- **template-dev**: No Node, no Claude CLI, no mempalace CLI — selftest's node-based JSON/fingerprint checks, the `claude -p` knowledge arm, and the MemPalace probe would all fail. Excluded by design; untouched.
- **GSD `mempalace.enabled` flip**: Neither bbj-dev (clones `components`) nor bbj-ls-dev (clones `bbj-language-server` + `bbj-ls`) clones a GSD-managed `.planning/config.json` repo. Nothing to enable.

## Deferred Gates

- **Live deploy** (infra-needs-live-deploy-gate): Push templates (`scripts/push-templates.sh`), rebuild a bbj-dev and bbj-ls-dev workspace each, verify:
  - `codex --version` prints `0.155.1` (or similar)
  - `readlink ~/.codex` → `/home/coder/.claude-shared/codex`
  - `readlink ~/.mempalace` → `/home/coder/.claude-shared/mempalace`
  - Self-Test button opens a web terminal and runs `/usr/local/bin/claude-share-selftest all`
  - Cross-workspace Codex auth: sign in to Codex in one workspace, confirm authenticated in a second same-owner workspace

## Self-Check: PASSED

- All 7 target files exist and were modified as required
- 3 commits in CoderPrivate with `feat(quick-260920-jff):` prefix: 4c608b7, d72de3f, 1d361cf
- terraform fmt -check + init -backend=false + validate PASS for both templates
- bash -n PASS for push-templates.sh
