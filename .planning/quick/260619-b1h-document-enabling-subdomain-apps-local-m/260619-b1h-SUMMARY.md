---
quick_id: 260619-b1h
title: Enable subdomain apps — macOS nip.io recipe + Apache wildcard proxy
date: 2026-06-19
status: complete
commit: 1d51959
---

# Quick Task 260619-b1h — Summary

Wired the documentation/operator path to enable **subdomain apps** (Coder's fix
for path-prefix breakage of apps that emit absolute URLs).

## Context

The server plumbing already existed: `compose.yaml` forwards
`CODER_WILDCARD_ACCESS_URL` (CFG-04) and `.env.example` documents both
`CODER_ACCESS_URL` and `CODER_WILDCARD_ACCESS_URL` with the cookie-scope warning.
The README's "Reverse-proxy contract" lists the wildcard-TLS / Host / WebSocket
requirements proxy-agnostically. What was missing: a concrete **Apache** config
(the user's production target) and a **local macOS** way to actually test
subdomain apps before having a domain.

## Change (README only — no code/compose change needed)

New "Subdomain apps (shareable links)" section:
- **What/why** — path-prefix proxying can't rewrite absolute URLs in app bodies;
  subdomain apps serve each app at its own hostname root, so absolute refs work.
- **Enable** — set `CODER_ACCESS_URL` + `CODER_WILDCARD_ACCESS_URL` in `.env`
  (already forwarded by compose); use a dedicated wildcard, not a TLD.
- **Local macOS recipe** — LAN-IP `nip.io` wildcard
  (`http://<dashed-lan-ip>.nip.io:7080` + `*.<dashed-lan-ip>.nip.io:7080`).
  Resolves for both the Mac browser and the workspace container, and sidesteps
  the template's `127.0.0.1 → host.docker.internal` rewrite (matches only a
  literal loopback access URL).
- **Production Apache vhost** — `ServerAlias *.coder.example.com`, wildcard TLS,
  `ProxyPreserveHost On`, `X-Forwarded-Proto https`,
  `ProxyPass / http://127.0.0.1:7080/ upgrade=any` (WebSocket + DERP in one
  directive, Apache ≥ 2.4.47), HTTP→HTTPS host-preserving redirect, DNS +
  upstream-address notes, and a pre-2.4.47 `mod_proxy_wstunnel` fallback note.
- **Note** — add a `coder_app` with `subdomain = true` for a first-class app
  button instead of code-server's `/proxy/<port>/`.

Updated the "add your own proxy config" line to point at the new Apache example.

## Answers to the user's questions

- **"Can you wire that?"** — yes; activation is two `.env` vars (already forwarded
  by compose) + a wildcard-capable proxy. Documented end to end.
- **"Does it work with my own domain later?"** — yes; identical mechanism. Local
  = LAN-IP nip.io over HTTP; production = your domain with the Apache vhost doing
  wildcard TLS. Only the two values change.

## Verification

- In-page anchors resolve: `#subdomain-apps-shareable-links` and
  `#reverse-proxy-contract` match real `##` headings.
- Apache directives reviewed against the README reverse-proxy contract (Host
  passthrough, X-Forwarded-Proto, WebSocket + DERP upgrade, wildcard TLS).
- No live proxy stood up here (no domain/cert in this env) — Apache vhost is a
  documented template, consistent with the repo's "external-proxy responsibility"
  stance and the "infra needs a live deploy gate" caveat.

## Notes / follow-ups

- `.env.example` already carries production examples; a local nip.io example was
  not added there because that file is read/write-blocked in this environment —
  the local recipe lives in the README instead.
- Optional next step (offered, not done): add a ready-made `coder_app`
  (`subdomain = true`) for a dev-server port to the java-fullstack template.
</content>
