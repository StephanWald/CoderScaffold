---
quick_id: 260619-ej7
slug: wire-google-oidc-login-into-coder-compos
date: 2026-06-19
status: complete
commit: 79ef750
---

# Summary: Wire Google OIDC login into Coder compose deployment

## What changed

- **compose.yaml** — added five `CODER_OIDC_*` env vars to the `coder` service
  `environment:` block, each with a `${VAR:-default}` fallback:
  - `CODER_OIDC_ISSUER_URL` → `https://accounts.google.com`
  - `CODER_OIDC_CLIENT_ID` → empty (OIDC stays disabled until set)
  - `CODER_OIDC_CLIENT_SECRET` → empty
  - `CODER_OIDC_SCOPES` → `openid,profile,email`
  - `CODER_OIDC_EMAIL_DOMAIN` → `basis.cloud`
- **.env.example** — added a "Google login (OIDC, optional)" section with
  placeholders, Google Cloud OAuth setup steps, the exact redirect URI
  (`…/api/v2/users/oidc/callback`), and a note that `CODER_OIDC_EMAIL_DOMAIN`
  restricts logins on the Coder side (comma-separated, no Google-side config
  required).

## Key decision

Coder activates OIDC only when `CODER_OIDC_CLIENT_ID` is non-empty. Defaulting
client id/secret to empty means the change is fully opt-in — the zero-config
quickstart boots unchanged, and Google sign-in turns on the moment real
credentials land in `.env`.

## Verification

- `docker compose config` parses cleanly (exit 0); var interpolation valid.
- Resolved defaults (no `.env`) confirm OIDC disabled (`CLIENT_ID=""`) and
  `CODER_OIDC_EMAIL_DOMAIN=basis.cloud`.
- `.env` confirmed gitignored; only `.env.example` placeholders committed.

## Not verified (limitation)

End-to-end Google sign-in was **not** live-tested — it requires real Google
OAuth credentials and a reachable HTTPS `CODER_ACCESS_URL`, neither available
in this environment. Validation was limited to config parsing and default
resolution. See [[infra-needs-live-deploy-gate]]: an operator should confirm
the login flow against a real deployment before relying on it.

## Domain restriction (user question)

Logins can be locked to `@basis.cloud` (or any comma-separated list) entirely
on the Coder side via `CODER_OIDC_EMAIL_DOMAIN` — no Google-side configuration
needed. Restricting the Google OAuth consent screen to "Internal" is optional
belt-and-suspenders.
