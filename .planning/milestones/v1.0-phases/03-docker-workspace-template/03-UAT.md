---
status: passed
phase: 03-docker-workspace-template
source: [03-VERIFICATION.md]
started: 2026-06-17T15:05:00Z
updated: 2026-06-17T15:40:00Z
---

## Current Test

number: 5
name: Docker socket GID provisioning (SC-5)
expected: Workspace provisioning completes without Docker socket permission errors after applying the group_add fix
awaiting: none — all tests passed

## Tests

### 1. Create a workspace from templates/docker/ and confirm agent shows Connected
expected: Workspace provisions a Docker container on the host; the Coder dashboard shows the agent status as Connected; wildcard-subdomain app URLs render the VS Code and IntelliJ IDEA app buttons
result: passed — user confirmed workspace builds and works

### 2. Click the VS Code app button and confirm a functional browser VSCode session opens
expected: code-server loads in the browser, an editor pane appears, a terminal can be opened, and the working directory is /home/coder
result: passed — user confirmed

### 3. Use JetBrains Gateway to connect to the workspace via the IntelliJ IDEA button
expected: Gateway client launches on the developer machine, connects to the workspace container, and an IntelliJ IDEA remote session opens
result: passed — user confirmed

### 4. Stop the workspace, start it again, and confirm /home/coder files persist
expected: A file created under /home/coder before workspace stop is readable after workspace start — the docker_volume persisted across the stop/start lifecycle
result: passed — user confirmed

### 5. On a host where the Docker socket GID differs from the default, confirm provisioning succeeds after following README Docker Socket Permissions
expected: After discovering the socket GID and setting group_add in compose.yaml, workspace provisioning completes without Docker socket permission errors
result: passed — initial provisioning failed with `permission denied` on `/var/run/docker.sock` (Docker Desktop on macOS); resolved by activating `group_add: ["0"]` in compose.yaml. README + compose.yaml updated to document the macOS/Docker Desktop (GID 0) and Linux (host docker GID) paths and the in-container `docker compose exec coder stat -c '%g'` discovery command (commit 6cd7c15).

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

None — SC-5 surfaced a real macOS/Docker Desktop documentation + default-config gap, fixed inline in commit 6cd7c15 (compose.yaml group_add default + README cross-platform socket docs).
