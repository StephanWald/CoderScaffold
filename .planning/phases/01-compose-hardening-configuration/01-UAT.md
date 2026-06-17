---
status: testing
phase: 01-compose-hardening-configuration
source: [01-VERIFICATION.md]
started: "2026-06-17"
updated: "2026-06-17"
---

## Current Test

number: 1
name: .env.example variable coverage cross-check
expected: |
  Every variable interpolated in compose.yaml is documented in .env.example with a
  safe placeholder. 6 active variables (CODER_ACCESS_URL, CODER_WILDCARD_ACCESS_URL,
  CODER_VERSION, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB); CODER_PG_DATA_DIR
  present as a commented opt-in; CODER_TELEMETRY_ENABLE and CODER_FIRST_USER_* absent;
  no real secrets. (Already reviewed and approved by the user at the 01-02 checkpoint;
  re-confirmable by opening .env.example directly — the sandbox blocked automated read here.)
awaiting: user response

## Tests

### 1. .env.example variable coverage cross-check
expected: All compose ${VAR} references documented with safe placeholders; password is the obviously-fake `change-me-in-production`; wildcard is a subdomain; CODER_PG_DATA_DIR is a commented opt-in; telemetry/first-user vars absent.
result: [pending]

### 2. Reverse-proxy contract — D-06 9-point human review
expected: README reverse-proxy section is complete enough for a stranger to configure any proxy correctly — :7080 upstream (coder:7080 for containerized proxies), wildcard TLS, verbatim Host, WebSocket Upgrade/Connection, DERP Upgrade passthrough, no response buffering, X-Forwarded-For, X-Forwarded-Proto, "must support WebSockets". (Already reviewed and approved by the user at the 01-02 checkpoint.)
result: [pending]

### 3. End-to-end smoke re-test after code-review fixes (fd8697c)
expected: |
  After the fd8697c fixes (added database healthcheck start_period: 30s), the stack still
  comes up clean:
    docker compose down && docker compose up -d
    docker compose ps          # both coder + database -> Up (healthy)
    docker compose exec -T coder curl -fsS http://localhost:7080/healthz   # -> OK
  Data persists across down/up (named volume coder_pgdata). UI loads at CODER_ACCESS_URL.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
