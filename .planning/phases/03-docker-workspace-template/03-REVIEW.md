---
phase: 03-docker-workspace-template
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - templates/docker/main.tf
  - README.md
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the new Coder Docker workspace Terraform template (`templates/docker/main.tf`) and
the `## Workspace Template` section of `README.md` (everything from line 294 onward). The
Postgres backup/restore/migration content earlier in the README is Phase 2's surface and was
explicitly out of scope; the prior review's WR-03/WR-04 targeted that migration content and are
**not** repeated here.

The template is well-structured and the documented high-risk pitfalls are handled correctly:
`coder_agent` has no `count` (token and `init_script` always generated even when stopped), the
persistent `docker_volume` is keyed on the **immutable workspace UUID** rather than the mutable
name (the real source of rename-safety), `docker_image` uses `keep_locally = true`, and
`docker_container` plus both editor modules use `count = start_count`. Provider/module versions
match the CLAUDE.md pins (`coder/coder ~> 2.18`, `kreuzwerker/docker ~> 4.4`, code-server
`1.5.0`, jetbrains-gateway `1.2.6`). The agent token is passed via `env`, the Docker socket is
**not** mounted into workspace containers (only the server has socket access), and no secrets are
hardcoded.

No BLOCKER-class defects were found (no command injection, no data-loss path, no socket exposure
into workspaces). Three WARNINGs stand — two re-confirmed from the prior review (the over-broad
`replace()` regex and the over-broad `ignore_changes = all` with a misattributing comment) and
one new (container-name case handling). Info items are documentation/robustness nits.

## Warnings

### WR-01: `replace()` regex rewrites every `localhost`/`127.0.0.1` in the init script, not just the access-URL host

**File:** `templates/docker/main.tf:197`
**Issue:**
```hcl
entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
```
Because the second argument is wrapped in `/.../`, Terraform treats it as a **regex applied
globally** to the entire rendered `init_script`. The documented intent (comments at lines
162-171, 194-196) is to rewrite only the Coder **access-URL host** so the agent can reach the
server from inside the container. As written it rewrites *every* occurrence of `localhost` or
`127.0.0.1` anywhere in the script — including any that appear in env exports, log lines,
comments, or future agent-script additions the Coder server may emit. Today the blast radius is
bounded (the only meaningful loopback reference in the init script is the access URL), so this is
a latent fragility rather than an active break: a future agent script that legitimately
references `127.0.0.1` for an in-container purpose (a health-probe loopback, a bind address)
would be silently corrupted, producing the exact "Connecting… forever" symptom the README
documents as the success path. There is no validation that the substitution only touched the URL.

This finding **stands** from the prior review.

**Fix:** Anchor the match to the URL scheme/host boundary so only the access-URL host is
rewritten:
```hcl
entrypoint = ["sh", "-c", replace(
  coder_agent.main.init_script,
  "/(https?://)(localhost|127\\.0\\.0\\.1)/",
  "$${1}host.docker.internal"
)]
```
At minimum, document that the substitution is global and assumes `127.0.0.1`/`localhost` never
appears in the init script except as the access-URL host.

### WR-02: `ignore_changes = all` is broader than needed and the comment misattributes rename-safety to it

**File:** `templates/docker/main.tf:122-126`
**Issue:**
```hcl
# Prevent Terraform from destroying the home volume on workspace rename
# or template update. Without this, all home data would be lost. (Pitfall 2)
lifecycle {
  ignore_changes = all
}
```
Two problems. (1) **Misattribution:** the volume `name` is derived from
`data.coder_workspace.me.id` (the immutable UUID), so a workspace rename does not change the
name and would not trigger a replace regardless of this block. The rename-safety comes from the
UUID-keyed name (line 120), not from `ignore_changes`. Also, `ignore_changes` only suppresses
in-place *attribute updates* — it does not by itself prevent destruction — so the comment
"Prevent Terraform from destroying the home volume" overstates what the block does. (2)
**Over-breadth:** `all` freezes drift detection on *every* attribute, including the
`coder.owner`, `coder.owner_id`, and `coder.workspace_name_at_creation` labels. If a workspace
is transferred to a new owner, those labels become permanently stale and Terraform will never
reconcile them — degrading any operator tooling that queries volumes by owner label.

This finding **stands** from the prior review.

**Fix:** Either drop the lifecycle block (the UUID name already provides rename-safety) or scope
it to the attribute that actually needs protection and correct the comment:
```hcl
# The volume name is keyed on the immutable workspace ID (UUID), so a rename
# never changes it. ignore_changes on [name] guards against a future name-format
# change forcing a destroy/recreate (which would lose all home data).
lifecycle {
  ignore_changes = [name]
}
```

### WR-03: Container name can collide for names differing only in case (and casing is applied asymmetrically)

**File:** `templates/docker/main.tf:191`
**Issue:**
```hcl
name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
```
`lower()` is applied to the workspace name but **not** to the owner name. Docker container names
must be unique on the host, so any two workspaces that resolve to the same string would cause the
second provision to fail with a name conflict. The asymmetric casing (owner not lowered,
workspace lowered) also makes the final name hard to predict and undermines the apparent intent
of the `lower()` normalization. Coder constrains usernames/workspace names to a limited charset
today, so this is an edge case rather than a guaranteed break — hence WARNING, not BLOCKER — but
the inconsistency is a latent collision/conflict risk.

**Fix:** Normalize both segments consistently, or add a uniqueness suffix from the immutable ID:
```hcl
name = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
# stronger: append "-${substr(data.coder_workspace.me.id, 0, 8)}" to guarantee uniqueness
```

## Info

### IN-01: Default workspace image is an unpinned mutable tag

**File:** `templates/docker/main.tf:42`
**Issue:** `default = "codercom/enterprise-base:ubuntu"` is a floating tag. Combined with
`keep_locally = true`, an existing host caches the first pull, but a fresh host pulls whatever
`:ubuntu` resolves to that day — undermining the reproducibility stance CLAUDE.md takes for the
Coder image ("Never use `:latest` … breaks reproducibility"). The inline comment (lines 38-40)
already suggests pinning to a digest; the shipped default does not. Documented and operator-owned,
so no change required for v1.
**Fix:** Pin the committed default to a `@sha256:` digest, or add a README note that the default
tag is unpinned by design.

### IN-02: Metadata key numbering skips `2_`

**File:** `templates/docker/main.tf:90, 98, 106`
**Issue:** The `coder_agent` metadata keys are `0_cpu_usage`, `1_ram_usage`, `3_home_disk` — the
`2_` slot is skipped. Keys only need to be unique and they sort lexically, so this is harmless,
but the gap looks like a removed metadata block that was not renumbered and may confuse future
maintainers.
**Fix:** Renumber the disk key to `2_home_disk` for a contiguous sequence.

### IN-03: README "Workspace Agent Connectivity" presents the rewrite as automatic for all local deployments

**File:** `README.md:374-392`
**Issue:** The section states the `host.docker.internal` rewrite is "baked into the container
entrypoint automatically" for local deployments. In fact the rewrite only fires when the access
URL literally contains `localhost`/`127.0.0.1` (see WR-01). An operator who sets a local-but-non-
loopback value (e.g. `http://0.0.0.0:7080`) would get no rewrite and hit the documented
"Connecting… forever" symptom with no documented cause.
**Fix:** Note that the automatic rewrite specifically keys on `localhost`/`127.0.0.1` in
`CODER_ACCESS_URL`; other values are treated as production and require a host-reachable URL.

### IN-04: README "extra_hosts" terminology does not match the template

**File:** `README.md:375-376`
**Issue:** The connectivity section says the template adds `host.docker.internal` "via an
`extra_hosts` / `host-gateway` entry." The `kreuzwerker/docker` provider uses a
`host { host = ...; ip = ... }` block (main.tf:204-207), not an `extra_hosts` attribute.
`extra_hosts` is Docker Compose / `docker run` terminology; an operator grepping the template for
`extra_hosts` will not find it.
**Fix:** Reword to reference the `host { ... ip = "host-gateway" }` block actually used, or keep
`extra_hosts` only as a parenthetical analogy.

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
