---
phase: quick-260716-9pg
plan: 01
subsystem: infra
tags: [terraform, coder, coder_script, bbj-services]

requires:
  - phase: quick-260713-m12
    provides: templates/bbj-services/main.tf (background BBjServices launch, WR-03 non-fatal)
provides:
  - coder_script.bbjservices resource running BBjServices in the foreground via exec
  - Removal of the background nohup/setsid launch + pidfile from startup_script
affects: [templates/bbj-services]

tech-stack:
  added: []
  patterns: ["coder_script for long-running foreground daemons instead of backgrounding from startup_script"]

key-files:
  created: []
  modified: [templates/bbj-services/main.tf]

key-decisions:
  - "Mirrored bbj-dev's proven coder_script.bbjservices pattern verbatim (foreground exec, :8888 port guard only, no pidfile)"
  - "Dropped the pidfile idempotency check entirely — bbj-services (unlike bbj-dev) has no bbj-restart script consuming it, so the port check is sufficient and simpler"
  - "Updated the file's header comment (resource list + architecture bullets) to reflect the new coder_script-based launch, since leaving the old background-launch description would have been stale/misleading"

requirements-completed: [QUICK-9pg]

duration: ~10min
completed: 2026-07-16
---

# Quick Task 260716-9pg: Convert bbj-services BBjServices launch to coder_script Summary

**Moved BBjServices from a backgrounded `nohup setsid` job inside `startup_script` to its own `coder_script.bbjservices` resource running in the foreground via `exec sudo`, guarded only by the `:8888` port check.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-07-16T05:03:17Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Removed the `sudo nohup setsid /opt/bbx/bin/bbjservices --launchd` background block, its `/tmp/bbjservices.log` redirect, and `/tmp/bbjservices.pid` writes from `coder_agent.main.startup_script`
- Replaced it with an adapted NOTE comment (no svn wording, since bbj-services has no svn checkout) explaining that backgrounded processes inherit the script's output pipes and Coder may kill them after 10s of unclosed pipes
- Added a new `resource "coder_script" "bbjservices"` (copied verbatim from the private `bbj-dev` template, lines 397-424) immediately before `resource "docker_volume" "home_volume"`, wired via `agent_id = coder_agent.main.id`
- Updated the file's top-of-file architecture comment (resource list + bullet describing the launch mechanism) so it no longer describes the removed background-launch behavior

## Task Commits

1. **Task 1: Move BBjServices launch into a dedicated coder_script resource** - `b886ef0` (feat)

**Plan metadata:** committed separately by the orchestrator (docs commit), per this task's constraints — SUMMARY.md left uncommitted.

## Files Created/Modified
- `templates/bbj-services/main.tf` - Removed backgrounded BBjServices launch from `startup_script`; added `coder_script.bbjservices` (foreground `exec sudo`, `:8888` port guard, no pidfile); updated header comment block

## Decisions Made
- Verbatim-copied the bbj-dev `coder_script.bbjservices` block including its comment header (as the plan explicitly instructed), even though that header mentions `bbj-restart` — a script that exists in the private bbj-dev template but not in bbj-services. Left as-is per explicit plan instruction to mirror verbatim; the sentence is accurate in spirit (nothing else in bbj-services consumes a pidfile either) even though bbj-services has no `bbj-restart` command.
- Updated the file's header comment (Rule 1 — auto-fix stale documentation) since the old bullet ("BBjServices is started in the background by the agent startup_script") became factually wrong after this change and was directly part of the file this task modifies.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated stale header comment describing the old background-launch mechanism**
- **Found during:** Task 1
- **Issue:** The file's top-of-file architecture comment block (lines ~10-11 and the Resources list) described BBjServices as "started in the background by the agent startup_script" and omitted `coder_script` from the Resources list. Left unchanged, this would have been actively misleading documentation immediately after the launch mechanism moved.
- **Fix:** Updated the bullet to describe the new `coder_script.bbjservices` foreground-exec mechanism and added a `coder_script` line to the Resources list.
- **Files modified:** templates/bbj-services/main.tf
- **Verification:** Visual diff review; no functional/terraform impact (comment-only change).
- **Committed in:** b886ef0 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 stale-doc bug fix)
**Impact on plan:** Comment-only correction to keep the file's own documentation accurate after the task's structural change. No scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required. `terraform` is not installed on this host, so `terraform fmt -check` / `terraform validate` were skipped per the task's explicit constraints; structural `grep` checks confirmed the required resource, wiring, and absence of the old background-launch artifacts. The orchestrator will validate with dockerized terraform afterward.

## Next Phase Readiness
- `templates/bbj-services/main.tf` now mirrors the proven bbj-dev coder_script pattern for BBjServices; ready for terraform validate/fmt gate by the orchestrator and for `coder templates push`.
- No blockers.

---
*Phase: quick-260716-9pg*
*Completed: 2026-07-16*

## Self-Check: PASSED
- FOUND: templates/bbj-services/main.tf
- FOUND: b886ef0 (commit exists in git log)
- FOUND: .planning/quick/260716-9pg-convert-bbj-services-bbjservices-launch-/260716-9pg-SUMMARY.md
