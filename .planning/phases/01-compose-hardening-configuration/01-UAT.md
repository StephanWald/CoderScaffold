---
status: complete
phase: 01-compose-hardening-configuration
source: [01-VERIFICATION.md]
started: "2026-06-17"
updated: "2026-06-17"
---

## Current Test

[testing complete]

## Tests

### 1. .env.example variable coverage cross-check
expected: All compose ${VAR} references documented with safe placeholders; password is the obviously-fake `change-me-in-production`; wildcard is a subdomain; CODER_PG_DATA_DIR is a commented opt-in; telemetry/first-user vars absent.
result: pass

### 2. Reverse-proxy contract — D-06 9-point human review
expected: README reverse-proxy section is complete enough for a stranger to configure any proxy correctly — :7080 upstream (coder:7080 for containerized proxies), wildcard TLS, verbatim Host, WebSocket Upgrade/Connection, DERP Upgrade passthrough, no response buffering, X-Forwarded-For, X-Forwarded-Proto, "must support WebSockets". (Already reviewed and approved by the user at the 01-02 checkpoint.)
result: pass

### 3. End-to-end smoke re-test after code-review fixes (fd8697c)
expected: |
  After the fd8697c fixes (added database healthcheck start_period: 30s), the stack still
  comes up clean:
    docker compose down && docker compose up -d
    docker compose ps          # both coder + database -> Up (healthy)
    docker compose exec -T coder curl -fsS http://localhost:7080/healthz   # -> OK
  Data persists across down/up (named volume coder_pgdata). UI loads at CODER_ACCESS_URL.
result: pass

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
