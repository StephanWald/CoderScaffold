---
phase: 03-docker-workspace-template
plan: "02"
subsystem: documentation
tags: [readme, workspace-template, operator-docs, tpl-01, tpl-05, tpl-06]
dependency_graph:
  requires: ["03-01"]
  provides: ["README ## Workspace Template section"]
  affects: ["README.md"]
tech_stack:
  added: []
  patterns:
    - "Failure symptom documentation block (bold lead + diagnostic command + root cause)"
    - "Callout blockquote for distro-specific caveats"
    - "Numbered operator steps with inline code fencing"
key_files:
  created: []
  modified:
    - README.md
decisions:
  - "Socket GID callout documents Ubuntu/Debian/Alpine GID variation — cannot be hardcoded, operator must run stat command on their specific host (TPL-05/D-08)"
  - "Production connectivity note explicitly warns that 127.0.0.1 will not work for non-Docker templates, directing operators to set a real reachable CODER_ACCESS_URL (TPL-06/D-10)"
  - "Display name / description / icon documented as post-push step via coder templates edit — not Terraform-managed (RESEARCH.md Pitfall 6)"
metrics:
  duration: "<1 minute"
  completed: "2026-06-17"
  tasks_completed: 1
  files_modified: 1
---

# Phase 03 Plan 02: Workspace Template Documentation Summary

**One-liner:** Operator README section for pushing the Docker template, resolving Docker socket GID failures, understanding local vs production agent connectivity, and home persistence.

## What Was Built

Added the `## Workspace Template` section (102 lines) to `README.md`, covering all operator-facing concerns for the `templates/docker/` template delivered in Plan 01:

- **Push workflow** (`### Push the template`): `coder templates push docker --directory templates/docker/ -y` with the `-y` flag noted for CI use, followed by `coder templates edit docker --display-name ... --description ... --icon ...` with an explicit note that template metadata is server-side (not Terraform-managed) and must be re-applied on re-push.

- **Create-a-workspace path** (`### Create a workspace`): Dashboard click path — Templates → Docker Workspace → Create Workspace → Create, no parameters. Describes the two app buttons that appear post-connect: VS Code (browser) and IntelliJ IDEA (JetBrains Gateway).

- **Docker Socket Permissions** (`### Docker Socket Permissions`): Three-step operator procedure — `stat -c '%g' /var/run/docker.sock`, uncomment `group_add` block in `compose.yaml` with discovered GID, restart `docker compose up -d coder`. Callout notes GID varies by distro (Ubuntu 998, Debian 999, Alpine 101). Failure symptom block: `docker compose logs coder` shows `permission denied` on Docker socket ops.

- **Workspace Agent Connectivity** (`### Workspace Agent Connectivity`): Local path (host.docker.internal + host-gateway, automatic, zero-config) vs production path (real CODER_ACCESS_URL reachable from workspace containers). Failure symptom block: agent shows "Connecting" indefinitely — local check (confirm 127.0.0.1 default, template rewrites automatically) vs production check (verify CODER_ACCESS_URL reachability, 127.0.0.1 will not work).

- **Home directory persistence**: `/home/coder` in per-workspace Docker volume survives stop/start; deleted with the workspace.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. This plan produces operator documentation only. All documented commands and behaviors are grounded in `templates/docker/main.tf` (Plan 01) and `compose.yaml`. No placeholder copy.

## Threat Flags

No new threat surface introduced. This plan adds documentation only. The documented `group_add` socket grant is the pre-existing, accepted server design from Phase 1 (T-03D-01 in plan threat register — disposition: accept). The README uses placeholder/example URLs only; no real secrets are committed (T-03D-02 — disposition: mitigate, satisfied).

## Self-Check: PASSED

- [x] README.md modified: `grep -q '^## Workspace Template' README.md` — FOUND
- [x] Push command present: `grep -q 'coder templates push docker --directory templates/docker/' README.md` — FOUND
- [x] Edit command present: `grep -q 'coder templates edit docker' README.md` — FOUND
- [x] Socket GID command: `grep -q "stat -c '%g' /var/run/docker.sock" README.md` — FOUND
- [x] Connectivity docs: `grep -q 'host.docker.internal' README.md` — FOUND
- [x] Create path: `grep -q 'Docker Workspace → Create Workspace' README.md` — FOUND
- [x] Home persistence: `grep -q '/home/coder' README.md` — FOUND
- [x] Automated gate: GATE_PASS printed
- [x] Task commit ff53e00 exists in git log

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add ## Workspace Template section to README.md | ff53e00 | README.md (+102 lines) |
