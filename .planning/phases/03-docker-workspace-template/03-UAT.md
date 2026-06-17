---
status: testing
phase: 03-docker-workspace-template
source: [03-VERIFICATION.md]
started: 2026-06-17T15:05:00Z
updated: 2026-06-17T15:05:00Z
---

## Current Test

number: 1
name: Create a workspace from templates/docker/ and confirm agent shows Connected
expected: |
  Workspace provisions a Docker container on the host; the Coder dashboard shows the agent
  status as Connected; wildcard-subdomain app URLs render the VS Code and IntelliJ IDEA app buttons
awaiting: user response

## Tests

### 1. Create a workspace from templates/docker/ and confirm agent shows Connected
expected: Workspace provisions a Docker container on the host; the Coder dashboard shows the agent status as Connected; wildcard-subdomain app URLs render the VS Code and IntelliJ IDEA app buttons
result: [pending]

### 2. Click the VS Code app button and confirm a functional browser VSCode session opens
expected: code-server loads in the browser, an editor pane appears, a terminal can be opened, and the working directory is /home/coder
result: [pending]

### 3. Use JetBrains Gateway to connect to the workspace via the IntelliJ IDEA button
expected: Gateway client launches on the developer machine, connects to the workspace container, and an IntelliJ IDEA remote session opens
result: [pending]

### 4. Stop the workspace, start it again, and confirm /home/coder files persist
expected: A file created under /home/coder before workspace stop is readable after workspace start — the docker_volume persisted across the stop/start lifecycle
result: [pending]

### 5. On a host where the Docker socket GID differs from the default, confirm provisioning succeeds after following README Docker Socket Permissions
expected: After running stat -c '%g' /var/run/docker.sock, uncommenting group_add in compose.yaml with the discovered GID, and restarting the Coder server, workspace provisioning completes without Docker socket permission errors
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
