# Phase 1: Compose Hardening & Configuration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-16
**Phase:** 1-Compose Hardening & Configuration
**Areas discussed:** First-admin bootstrap, Bind-mount permissions, Reverse-proxy docs depth, Committed defaults & dev tunnel

---

## First-admin bootstrap

| Option | Description | Selected |
|--------|-------------|----------|
| Documented manual UI | Operator hits CODER_ACCESS_URL; Coder's built-in first-run screen creates the admin. README documents steps. No secrets in env. | ✓ |
| Documented CLI flow | README walks through `coder login` / `coder server create-admin-user`. Scriptable/headless, more steps. | |
| Env-var autocreate | Set CODER_FIRST_USER_* in .env for zero-touch admin creation; admin password lives in .env. | |

**User's choice:** Documented manual UI
**Notes:** Compose `depends_on: service_healthy` already enforces DB-first ordering, so no manual start-order caveat is needed beyond "bring up → wait for healthy → open URL → create admin."

---

## Bind-mount permissions

| Option | Description | Selected |
|--------|-------------|----------|
| Documented manual chown | README documents `sudo chown -R 999:999 ./data/postgres` as a required pre-`up` step (OPS-03). | ✓ |
| Automation safety net | Init container/entrypoint chowns the data dir before Postgres starts so first `up` can't fail. | |
| Both: automate + document | Ship the init-container safety net AND document the manual step. | |

**User's choice:** Documented manual chown
**Notes:** Keeps compose clean and standard. Skipping the step is the #1 first-boot failure, so the README must make it prominent and state the failure symptom.

---

## Reverse-proxy docs depth

| Option | Description | Selected |
|--------|-------------|----------|
| Contract prose only | README describes requirements in words; operator adapts to their own proxy. | ✓ |
| Prose + one example | Contract prose plus one copy-paste reference config (e.g. Caddy). | |
| Prose + Caddy & nginx | Contract prose plus two reference snippets. | |

**User's choice:** Contract prose only
**Notes:** Keeps the scaffold proxy-agnostic and avoids implying a bundled proxy. Prose must cover :7080 upstream, wildcard TLS for *.<apps-domain>, preserved Host + WebSocket upgrade headers, no buffering.

---

## Committed defaults & dev tunnel

### CODER_ACCESS_URL committed default

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 127.0.0.1 default | Committed `${CODER_ACCESS_URL:-127.0.0.1}` fallback preserves quickstart + upstream compat; .env.example shows real placeholder. | ✓ |
| Blank / unset default | No default; operator must set a real URL before `up`. Safer but breaks zero-config quickstart. | |

**User's choice:** Keep 127.0.0.1 default

### coder_home dev-tunnel volume

| Option | Description | Selected |
|--------|-------------|----------|
| Keep coder_home volume | Leave in place; harmless in production, preserves quickstart convenience; document as safe-to-remove. | ✓ |
| Remove coder_home volume | Drop for a leaner production file; diverges from upstream. | |

**User's choice:** Keep coder_home volume

### Telemetry default

| Option | Description | Selected |
|--------|-------------|----------|
| Leave default (enabled) | Don't set CODER_TELEMETRY_ENABLE; Coder's default (true) applies; overridable via .env. | ✓ |
| Expose, default enabled | Add the var with `:-true` and document it for discoverability. | |
| Default to disabled | Set false for privacy-first posture; diverges from upstream. | |

**User's choice:** Leave default (enabled)
**Notes:** `.env.example` also documents CODER_WILDCARD_ACCESS_URL placeholder; avoid top-level domain (cookie-scope issues).

---

## Claude's Discretion

- Coder healthcheck mechanism (test command, interval/timeout/retries) — mirror the existing Postgres `pg_isready` pattern.
- `.env.example` layout, grouping, and comment wording (CFG-01).
- `restart: unless-stopped` placement on both services (SRV-03).
- Bind-mount path variable name/default (`CODER_PG_DATA_DIR`, `./data/postgres`) per SRV-01.

## Deferred Ideas

- Init-container/entrypoint chown automation (rejected for SRV-05 in favor of manual docs).
- Reference proxy config snippets (Caddy/nginx) — possible later optional `docs/examples/` aid.
- Env-var admin autocreate (`CODER_FIRST_USER_*`) — relevant for fully headless provisioning later.
- Telemetry default-off posture — left at Coder default.
