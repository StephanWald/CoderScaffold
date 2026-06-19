---
quick_id: 260619-ej7
slug: wire-google-oidc-login-into-coder-compos
date: 2026-06-19
---

# Quick Task: Wire Google OIDC login into Coder compose deployment

## Goal

Enable Google sign-in (via Coder's generic OIDC mechanism) as a pre-wired,
opt-in capability of the Docker Compose deployment, with logins restrictable
to one or more email domains (default `basis.cloud`). Secrets stay out of git.

## Approach

Coder speaks OIDC; Google is a standard OIDC provider. Coder **activates** OIDC
only when `CODER_OIDC_CLIENT_ID` is non-empty, so we can pre-wire every variable
with safe defaults and the zero-config quickstart still boots with OIDC off until
real credentials are supplied via `.env`.

### Variables

| Variable | compose default | Meaning |
|----------|-----------------|---------|
| `CODER_OIDC_ISSUER_URL` | `https://accounts.google.com` | Google's OIDC discovery endpoint |
| `CODER_OIDC_CLIENT_ID` | `` (empty → OIDC disabled) | OAuth client ID from Google Cloud |
| `CODER_OIDC_CLIENT_SECRET` | `` (empty) | OAuth client secret (sensitive) |
| `CODER_OIDC_SCOPES` | `openid,profile,email` | Standard scopes; `email` needed for domain match |
| `CODER_OIDC_EMAIL_DOMAIN` | `basis.cloud` | Comma-separated allowed email domains |

## Tasks

1. **compose.yaml** — add the five `CODER_OIDC_*` env vars to the `coder`
   service `environment:` block using `${VAR:-default}` fallbacks, with a
   comment block explaining OIDC is opt-in (activates when client ID is set).
2. **.env.example** — add a "Google OIDC login (optional)" section with
   placeholders, the Google Cloud setup pointer, the exact redirect URI, and a
   note that `CODER_OIDC_EMAIL_DOMAIN` restricts logins on the Coder side.

## Out of scope

- README narrative docs (vars are self-documented inline).
- TLS / reverse-proxy config (external-proxy responsibility, already noted).

## Verification

- `docker compose config` parses without error (var interpolation valid).
- Defaults leave OIDC disabled (empty client ID) → quickstart unaffected.
- `.env` remains gitignored; only `.env.example` placeholders committed.
