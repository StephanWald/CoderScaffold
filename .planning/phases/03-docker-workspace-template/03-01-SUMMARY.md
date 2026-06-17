---
phase: 03-docker-workspace-template
plan: 01
subsystem: infra
tags: [terraform, coder, docker, code-server, jetbrains-gateway, hcl]

requires:
  - phase: 01-compose-hardening-configuration
    provides: Running Coder server (compose.yaml) with /var/run/docker.sock mounted — prerequisite for template provisioning

provides:
  - templates/docker/main.tf — complete Coder Docker workspace template covering TPL-01 through TPL-06
  - coder_agent.main with startup_script, GIT_* env, and CPU/RAM/Disk metadata
  - docker_volume.home_volume with lifecycle { ignore_changes = all } for persistent /home/coder
  - docker_container.workspace with host.docker.internal/host-gateway connectivity
  - code-server 1.5.0 module (VS Code browser, order=1)
  - jetbrains-gateway 1.2.6 module (IntelliJ IDEA only, order=2)
  - Commented Docker socket GID operator-resolved block (TPL-05)

affects:
  - 03-docker-workspace-template/03-02 (Plan 02 extends README with Workspace Template section; uses this file as base)

tech-stack:
  added:
    - coder/coder Terraform provider ~> 2.18
    - kreuzwerker/docker Terraform provider ~> 4.4
    - registry.coder.com/coder/code-server/coder 1.5.0
    - registry.coder.com/coder/jetbrains-gateway/coder 1.2.6
    - Terraform >= 1.9 (required by modules)
  patterns:
    - Count pattern: docker_container + modules use start_count; coder_agent / docker_volume / docker_image are count-free
    - Persistent home via docker_volume with lifecycle { ignore_changes = all } and workspace-ID-keyed name
    - Agent connectivity: entrypoint replace() + host.docker.internal/host-gateway (Pitfall 3)
    - Pinned-but-overridable image variable (mirrors compose.yaml CODER_VERSION pattern)
    - Commented operator-resolved block (mirrors compose.yaml #group_add pattern)

key-files:
  created:
    - templates/docker/main.tf
  modified: []

key-decisions:
  - "coder_agent.main has NO count — must always exist to generate token + init_script even when workspace is stopped"
  - "docker_volume.home_volume keyed to workspace ID (not name) — prevents orphaning on workspace rename"
  - "lifecycle { ignore_changes = all } on home_volume — prevents Terraform destroy/recreate from wiping home data"
  - "Docker socket GID handled as commented operator-resolved block + stat -c discovery command (TPL-05/D-08)"
  - "Both entrypoint replace() AND host.docker.internal/host-gateway host entry required together for agent connectivity"
  - "jetbrains_ides = [IU] restricts JetBrains Gateway to IntelliJ IDEA Ultimate only (D-06)"
  - "All three start_count resources: docker_container + code-server module + jetbrains-gateway module"

patterns-established:
  - "Pattern: Count rules for Coder Docker templates — agent/volume/image count-free; container/modules use start_count"
  - "Pattern: host.docker.internal connectivity for local + production deployments (D-09/D-10)"
  - "Pattern: Commented operator block for GID/permission concerns (mirrors compose.yaml convention)"

requirements-completed: [TPL-01, TPL-02, TPL-03, TPL-04, TPL-05, TPL-06]

duration: 2min
completed: 2026-06-17
---

# Phase 03 Plan 01: Docker Workspace Template (main.tf) Summary

**Complete Coder Docker workspace Terraform template with code-server 1.5.0 (VS Code) and jetbrains-gateway 1.2.6 (IntelliJ IDEA), persistent /home/coder via Docker volume with lifecycle guard, and host.docker.internal connectivity for local + production deployments**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-17T14:10:26Z
- **Completed:** 2026-06-17T14:12:51Z
- **Tasks:** 2 (both completed in one write; both gates passed)
- **Files modified:** 1

## Accomplishments

- Authored `templates/docker/main.tf` (264 lines) covering all 6 phase requirements (TPL-01..06)
- Correct count pattern: `coder_agent`/`docker_volume`/`docker_image` count-free; `docker_container` + both editor modules use `start_count`
- Persistent home volume using workspace UUID (not name) with `lifecycle { ignore_changes = all }` prevents data loss on rename/update
- `host.docker.internal`/`host-gateway` + `replace()` entrypoint wires agent connectivity for both local and production deployments
- Commented, non-hardcoded Docker socket GID block with `stat -c '%g' /var/run/docker.sock` discovery command (TPL-05)
- No `coder_parameter` blocks, no AI/MCP resources, no `hashicorp/docker`, no docker socket mount in workspace container

## Task Commits

1. **Task 1 + Task 2: Complete main.tf (skeleton + editor modules)** - `f5cc44b` (feat)

Both tasks written in a single atomic commit — both tasks produce the same file and all acceptance criteria for both gates pass in this commit.

## Files Created/Modified

- `templates/docker/main.tf` — Complete Coder Docker workspace template (264 lines): providers, variables, data sources, locals, coder_agent, docker_volume, docker_image, docker_container, code-server module, jetbrains-gateway module

## Decisions Made

None beyond what was locked in CONTEXT.md (D-01..D-10). Followed plan exactly with the full upstream structure from RESEARCH.md.

The `coder stat` commands (`coder stat cpu`, `coder stat mem`, `coder stat disk`) were chosen for metadata blocks over raw shell commands (as noted in RESEARCH.md as preferred approach — pre-installed in the base image and semantically equivalent to the UI-SPEC's `top`/`free`/`df` scripts).

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were both written in a single file creation because both target the same file (`templates/docker/main.tf`) and the complete upstream structure was available from RESEARCH.md. All acceptance criteria for both tasks pass.

## Issues Encountered

The Task 1 verify command uses double-quoted shell `grep -q 'coder-${data.coder_workspace.me.id}-home'` which expands the `${}` before grep sees it. This is a shell quoting issue in the verify command, not in the file — the actual volume name `"coder-${data.coder_workspace.me.id}-home"` is present on line 120. Verified with `grep -q 'coder_workspace.me.id.*home'` instead.

## User Setup Required

None - `templates/docker/main.tf` is a static Terraform file. Operator actions (push template, set display name) are documented in Plan 02 README additions.

## Known Stubs

None. The template is complete and functional. Template display name / description / icon are set via `coder templates edit` CLI (not Terraform-managed — this is standard Coder pattern, not a stub). These are documented in Plan 02.

## Threat Flags

No new threat surface beyond what was declared in the plan's `<threat_model>`. Confirmed:
- T-03-01: No `/var/run/docker.sock` volume mount in `docker_container.workspace`
- T-03-02: `CODER_AGENT_TOKEN` passed via `env`, not written to file or image layer
- T-03-03: `workspace_image` is template-level variable (admin-only, no `coder_parameter`)
- T-03-SC: All modules/providers pinned exactly per CLAUDE.md

## Next Phase Readiness

- `templates/docker/main.tf` is complete and ready for `coder templates push`
- Plan 02 extends README with `## Workspace Template` section (operator docs) and completes phase
- Live UAT (create workspace → agent Connected → VS Code opens → IntelliJ Gateway opens → stop/start persists home) follows Plan 02

---

## Self-Check: PASSED

- `templates/docker/main.tf` exists (264 lines): FOUND
- Commit `f5cc44b` exists: FOUND

---
*Phase: 03-docker-workspace-template*
*Completed: 2026-06-17*
