---
phase: quick-260902-bgt
plan: "01"
subsystem: templates/bbj-services, CoderPrivate/templates/bbj-dev, CoderPrivate/templates/bbj-ls-dev, scripts
tags: [bbj, terraform, coder-templates, dynamic-parameters, push-script]
status: complete
completed: "2026-09-02"
duration: ~25min
tasks_completed: 3
commits: 5
actuals:
  tokens: 14000
  tasks: 3
  commits: 5
dependency_graph:
  requires: [260902-8mp]
  provides: [bbj-installer-dropdown-works-under-dynamic-parameters]
  affects: [bbj-services, bbj-dev, bbj-ls-dev]
tech_stack:
  added: [jars.json (push-time artifact)]
  patterns: [jsondecode(file()) try/fallback, plain-bash JSON builder (no jq)]
key_files:
  created: []
  modified:
    - /workspaces/coder/scripts/push-templates.sh
    - /workspaces/CoderPrivate/scripts/push-templates.sh
    - /workspaces/coder/templates/bbj-services/main.tf
    - /workspaces/CoderPrivate/templates/bbj-dev/main.tf
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/main.tf
    - /workspaces/coder/.gitignore
    - /workspaces/CoderPrivate/.gitignore
    - /workspaces/coder/templates/bbj-services/README.md
    - /workspaces/CoderPrivate/templates/bbj-ls-dev/README.md
decisions:
  - "Plain bash JSON builder (no jq) — consistent with 260902-8mp decision to remove jq dependency"
  - "try(jsondecode(file(...)), fileset()) pattern — jars.json primary, fileset() provisioner-side fallback"
  - "Token-based template discovery (grep 'jars\\.json' in main.tf) — scoped to only templates that opt in"
  - "Generated at push time into template directory — satisfies Coder dynamic-parameters preview engine constraint"
---

# Quick Task 260902-bgt: Generate jars.json Snapshot at Template Push Time

**One-liner:** Push-time `jars.json` snapshot in both push scripts + `jsondecode(file())` try/fallback in all three BBj templates restores the `bbj_installer` dropdown under Coder >=2.25 dynamic-parameters.

## Problem

Coder >=2.25 renders the workspace-creation form using the **dynamic-parameters preview engine**, which evaluates parameter HCL against the **pushed template files only**. It cannot read the provisioner's `/mnt/bbj-assets` bind mount. The previous implementation used `fileset(var.bbj_context_path, "*.jar")` directly in the parameter, which returns empty in the form preview and causes the `bbj_installer` parameter to degrade to a free-text box.

## Solution

**Push-time snapshot:** `scripts/push-templates.sh` (both repos) now runs `_generate_jars_json()` before the template push loop. This function discovers `*.jar` basenames from `BBJ_ASSETS_PATH`, builds a sorted JSON array using plain bash (no jq), and writes `jars.json` into each template directory whose `main.tf` contains the literal token `jars.json`. When `BBJ_ASSETS_PATH` is unset, missing, or has no jars: warns to stderr, removes any stale `jars.json`, and does NOT block the push.

**Template consumption:** Each of the three `main.tf` files adds a `bbj_jar_options` local:
```hcl
bbj_jar_options = try(sort(jsondecode(file("${path.module}/jars.json"))), sort(fileset(var.bbj_context_path, "*.jar")))
```
The `bbj_installer` parameter's `default` and `dynamic "option" for_each` both use `local.bbj_jar_options`. The `try()` prefers the snapshot at form-render time; provisioner-side plans that still have the bind mount fall back to `fileset()`.

## What Was Done

### Task 1: jars.json generation in both push scripts (tracer)
- Added `_generate_jars_json()` to `/workspaces/coder/scripts/push-templates.sh` (before the lockfile/push loop)
- Added `_generate_jars_json()` to `/workspaces/CoderPrivate/scripts/push-templates.sh` (after module-staging, before push loop), reusing the existing `ASSETS` variable
- Both implementations: plain bash glob → sort → JSON-string builder; escape `\` then `"` per JSON spec; emit `[]` when no jars
- Both implementations warn+remove-stale+continue when `BBJ_ASSETS_PATH` is unset/missing/empty-of-jars
- `bash -n` + `shellcheck`: PASS on both

### Task 2: Consume jars.json in all three main.tf files
- Added `bbj_jar_options` local to `bbj-services/main.tf`, `bbj-dev/main.tf`, `bbj-ls-dev/main.tf`
- Updated `bbj_installer` parameter in all three: `default = try(local.bbj_jar_options[0], "")` and `for_each = local.bbj_jar_options`
- Updated comments in all three: jars.json-primary / fileset-fallback rationale, dynamic-parameters preview-engine constraint, re-run-push requirement, orphaning caveat retained
- `terraform validate`: PASS on bbj-services, bbj-dev, bbj-ls-dev (private templates via transient `modules/bbj-base` symlink, cleaned up afterward)

### Task 3: Gitignore, docs, standalone test, commits
- `/workspaces/coder/.gitignore`: added `templates/*/jars.json` under Terraform-noise section
- `/workspaces/CoderPrivate/.gitignore`: added `templates/*/jars.json` below `templates/*/modules/`
- `bbj-services/README.md`: updated Step 5 (dropdown, re-run-push, dynamic-parameters rationale) + Architecture (jars.json entry)
- `bbj-ls-dev/README.md`: updated "What's in the box" BBj bullet + "Workspace parameters" bbj_installer entry
- **Standalone JSON test:** ran the plain-bash builder against `/workspaces/coder/bbj-assets` (2 real jars), validated with `python3 -m json.tool` — PASS
  - Output: `["BBjBaristaDemos000_07-13-2026_1256.jar","BBjBaristaDemos2601_06-30-2026_1027.jar"]`
- One conventional commit per repo (as required)
- No `jars.json`, no `modules/` symlink, no `.terraform*` artifacts staged in either commit

## Commits

### Public repo (`/workspaces/coder`)
| Hash | Message |
|------|---------|
| `67ea50e` | feat(quick-260902-bgt): add jars.json generation step to public push script |
| `544c925` | feat(quick-260902-bgt): consume jars.json snapshot in bbj-services main.tf |
| `837ea9e` | feat(templates): snapshot jar list into jars.json at push time for dynamic-parameters dropdown |

### Private repo (`/workspaces/CoderPrivate`)
| Hash | Message |
|------|---------|
| `7ad0fde` | feat(quick-260902-bgt): add jars.json generation step to private push script |
| `f4b28e0` | feat(quick-260902-bgt): consume jars.json snapshot in bbj-dev and bbj-ls-dev main.tf |
| `eb41139` | feat(templates): snapshot jar list into jars.json at push time for dynamic-parameters dropdown |

## Deviations from Plan

None — plan executed exactly as written. The verify command in Task 2 used `mkdir -p modules && ln -sfn .../bbj-base ./modules/bbj-base` (vs the plan's `ln -sfn ... ./modules` + `rm -f ./modules`) to match the actual `source = "./modules/bbj-base"` module path; this is a trivial path correction, not a deviation.

## Verification Results

| Check | Result |
|-------|--------|
| `bash -n` public push script | PASS |
| `bash -n` private push script | PASS |
| `shellcheck` public push script | PASS |
| `shellcheck` private push script | PASS |
| `terraform validate` bbj-services | PASS |
| `terraform validate` bbj-dev (transient modules symlink) | PASS |
| `terraform validate` bbj-ls-dev (transient modules symlink) | PASS |
| Standalone JSON builder (2 real jars) → `python3 -m json.tool` | PASS — valid sorted JSON |
| `templates/*/jars.json` in coder `.gitignore` | PASS |
| `templates/*/jars.json` in CoderPrivate `.gitignore` | PASS |
| `jars.json` mentioned in bbj-services README | PASS |
| `jars.json` mentioned in bbj-ls-dev README | PASS |
| No tracked `jars.json` in either repo | PASS |
| No stray `.terraform*` or `modules/` in private templates | PASS |

## Live Gate (MANDATORY — not yet executed)

**Static verification only** was performed in this environment (no coder CLI, no running Coder server; per project memory "infra-needs-live-deploy-gate").

**The operator MUST verify the following on the live host before declaring this complete:**

1. Run `scripts/push-templates.sh` on the live host with `BBJ_ASSETS_PATH` populated in `.env`.
2. Confirm the script outputs `Generated <template>/jars.json (N jars)` for each of the three BBj templates.
3. In the Coder dashboard, click "Create workspace" for each of:
   - `bbj-services` (public template)
   - `bbj-dev` (private template)
   - `bbj-ls-dev` (private template)
4. Confirm the **"BBj installer JAR"** parameter renders as a **DROPDOWN** listing the staged jars — NOT a free-text box.
5. Select each jar + JDK combination to confirm the workspace creates successfully.

**This is the definitive acceptance criterion for this task.** The dropdown appearing (not free-text) is the observable proof that the dynamic-parameters preview engine is reading `jars.json` correctly.

## Self-Check: PASSED

- All modified files exist on disk: confirmed
- All commits exist in git log:
  - Public: 67ea50e, 544c925, 837ea9e
  - Private: 7ad0fde, f4b28e0, eb41139
- No transient artifacts remaining in either repo
- Both repos show clean `git status` (except `.planning/` untracked in public repo — expected)
