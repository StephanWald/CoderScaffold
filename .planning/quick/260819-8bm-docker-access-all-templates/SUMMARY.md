---
quick_id: 260819-8bm
slug: docker-access-all-templates
date: 2026-08-19
status: complete
commits:
  - 93b5589  # feat: main.tf socket mounts (4 templates)
  - 6b24ef9  # docs: Dockerfile DooD comments (4 templates)
---

# Summary: Docker-outside-of-Docker access in all workspace templates

## What was done

Extended the docker-outside-of-docker (DooD) access that `python-ai` and
`flutter` already had to the remaining four templates: **bbj-services**,
**coderscaffold**, **docker**, **java-fullstack**.

Per template (`main.tf`):
- Added `docker_group_id` variable (default `"999"`) with `stat -c '%g'
  /var/run/docker.sock` discovery docs.
- Bind-mounted the host `/var/run/docker.sock` into
  `docker_container.workspace` (after the `.claude-shared` volume, before labels).
- Added `group_add = [var.docker_group_id]` so the `coder` user can reach the socket.
- `coderscaffold` + `docker`: replaced the stale "This template does NOT mount
  /var/run/docker.sock" comment block with the now-correct description.

Per template (`Dockerfile`):
- Added the flutter/python-ai "NOTHING TO INSTALL HERE" DooD documentation
  comment before `USER coder` (comment-only).

## Key finding

No Dockerfile install is needed. The base image `codercom/enterprise-base:ubuntu`
**already ships** `docker-ce-cli` + `docker-compose-plugin` + buildx (docker 29.5.3,
compose v5.1.4). A hand-rolled apt block breaks the build with
`NO_PUBKEY 7EA0A9C3F273FCD8` (exit 100) — this is exactly the failure fixed in
python-ai commit `6978c76`. So the functional change is `main.tf`-only.

`flutter` was already fully done (var + socket mount + group_add present) — untouched.
`python-ai` is the reference — untouched.

## Verification

- `terraform fmt -check` — PASS on all 6 templates (no formatting drift).
- `terraform init -backend=false` + `terraform validate` — **Success! The
  configuration is valid.** on all 4 changed templates (docker, coderscaffold,
  bbj-services, java-fullstack). Confirms `var.docker_group_id` resolves.
- Init artifacts (`.terraform/`) cleaned; pre-existing committed
  `.terraform.lock.hcl` files restored (untouched by this task).

## LIVE-VERIFY DEFERRED (the real gate — see memory: infra-needs-live-deploy-gate)

Static `terraform validate` cannot confirm socket reachability. On the prod host:
1. `coder templates push` each of the 4 templates.
2. Create a workspace, then inside it: `docker ps` (should list HOST containers)
   and `docker compose up` a throwaway stack (siblings alongside the workspace).
3. If "permission denied": run `stat -c '%g' /var/run/docker.sock` on the host and
   override `docker_group_id` to match (999 is the Debian/Ubuntu default; Docker
   Desktop differs).

## Scope notes

- Socket access grants effective root on the host — fine for single-operator
  self-hosted, not for shared/multi-tenant. Documented in each template.
