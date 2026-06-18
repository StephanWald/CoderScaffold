# Phase 4: Portable Claude Config - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 4-Portable Claude Config
**Areas discussed:** File-vs-directory mount architecture, Claude CLI version, ANTHROPIC_API_KEY variable, Reusable snippet form, Operator runbook depth, Orphaned-volume cleanup

---

## File-vs-directory mount architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Accept symlink approach | Lock the ARCHITECTURE.md recommendation: neutral `~/.claude-shared` mount + symlinks for `~/.claude` and `~/.claude.json` via startup_script. HIGH-confidence; no empirical spike. | ✓ |
| Spike CLAUDE_CONFIG_DIR first | Empirically test CLAUDE_CONFIG_DIR in the current CLI before writing Terraform, in case the research is stale. | |

**User's choice:** Accept symlink approach
**Notes:** Resolves the roadmap's explicitly-flagged open architecture decision. CLAUDE_CONFIG_DIR is undocumented (issue #25762 open/unimplemented; #3833 closed "not planned"); the symlink path uses stable documented config locations. → D-01, D-02.

---

## Claude CLI version

| Option | Description | Selected |
|--------|-------------|----------|
| Pin claude_code_version | Pin the CLI for reproducibility, matching the repo's pin-everything ethos. | |
| Latest on each start | `install_claude_code=true`, no pin — newest CLI fetched each workspace start. Always current; non-reproducible. | ✓ |

**User's choice:** Latest on each start
**Notes:** Deliberate exception to the repo's pin-everything convention for the rapidly-moving CLI. Churn trade-off accepted. → D-06.

---

## ANTHROPIC_API_KEY variable

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as empty-default escape hatch | Include `anthropic_api_key` (sensitive, default `""`) — inert so OAuth login works; available as optional override. | ✓ |
| Omit the variable entirely | Don't wire `anthropic_api_key` at all this phase, guaranteeing nothing can shadow interactive login. | |

**User's choice:** Keep as empty-default escape hatch
**Notes:** Default `""` keeps first-run OAuth/subscription login (CLAUDE-05) intact; API-key auth as a *default* stays deferred to AI-04. → D-07.

---

## Reusable snippet form

| Option | Description | Selected |
|--------|-------------|----------|
| Inline annotated block in main.tf | Embed the `[REUSABLE]…[END REUSABLE]` block directly in `templates/docker/main.tf`. Self-contained, copy-pasteable. | ✓ |
| Separate documented file | Extract to a dedicated `.md`/`.tf.example` partial referenced from README. More discoverable; second place to sync. | |

**User's choice:** Inline annotated block in main.tf
**Notes:** No extra file to keep in sync; copy-paste from the working template. → D-08.

---

## Operator runbook depth

| Option | Description | Selected |
|--------|-------------|----------|
| Focused runbook (4 required topics) | First-run login, what's shared, seeding behavior, concurrent-write caveat. Matches the repo's concise README style. | ✓ |
| Extended runbook (+ operations) | Adds volume inspection, manual cleanup procedure, and first-run permission troubleshooting. | |

**User's choice:** Focused runbook (the 4 required topics)
**Notes:** Covers exactly the SC-mandated topics; no extended troubleshooting appendix. (Manual cleanup still documented — see next area.) → D-09.

---

## Orphaned-volume cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Document the manual step | Note the orphaned-volume situation + `docker volume rm` in the README. No tooling. | ✓ |
| Defer to backlog, mention briefly | One-line acknowledgment; track an automated script as future QOL. | |
| Ship a cleanup script | Add a `scripts/` helper to find/remove orphaned volumes. Expands scope. | |

**User's choice:** Document the manual step
**Notes:** Consistent with the v1.1 "document the caveat, don't engineer around it" posture (mirrors the concurrent-write decision). → D-10.

---

## Claude's Discretion

- Exact `startup_script` shell wording for the chown-guard / mkdir / symlink block (must stay idempotent and run before the claude-code module).
- README operator subsection placement/heading and exact prose of the four runbook topics and the cleanup note.
- Whether `anthropic_api_key` carries a doc comment pointing at console.anthropic.com.
- Volume `labels {}` ordering/label set (UUID keying + `coder.purpose` label fixed).
- `main.tf` header-comment update to mention the claude-code module and new volume.

## Deferred Ideas

- API-key auth as a first-class default (AI-04, later milestone).
- Automated orphaned-volume cleanup script (future QOL).
- Pinning `claude_code_version` (revisit if CLI churn breaks workspaces).
- Fixing the repo's own `.devcontainer/devcontainer.json` `~/.claude.json` gap (out of scope).
- Coder Tasks (`coder_ai_task`), `coder exp mcp` server, in-workspace MCP provisioning (AI-01/02/03).
