---
quick_id: 260819-8bm
slug: docker-access-all-templates
date: 2026-08-19
status: in-progress
---

# Quick Task: Docker-outside-of-Docker access in all workspace templates

## Goal

Give every workspace template the same docker-outside-of-docker (DooD) access
that `python-ai` (and `flutter`) already have: the workspace can run `docker` /
`docker compose` against the HOST daemon via a bind-mounted `/var/run/docker.sock`.

## Findings (why this is main.tf-only)

- All templates build on `codercom/enterprise-base:ubuntu`, which **already ships**
  `docker-ce-cli` + `docker-compose-plugin` + buildx (docker 29.5.3, compose v5.1.4).
  Verified via commit `6978c76` — a hand-rolled apt block breaks the build
  (`NO_PUBKEY 7EA0A9C3F273FCD8`, exit 100). So **no Dockerfile install**; the only
  functional change is the socket mount + group membership in `main.tf`.
- `flutter` is **already fully done** — no changes.
- Remaining templates: `bbj-services`, `coderscaffold`, `docker`, `java-fullstack`.

## Per-template changes (main.tf)

1. Add `docker_group_id` variable (default `"999"`) right after `variable "docker_socket"`.
2. Add the host-socket `volumes {}` block + `group_add = [var.docker_group_id]` inside
   `resource "docker_container" "workspace"`, after the `/home/coder/.claude-shared`
   volume and before the `labels` blocks. (Verbatim from python-ai/flutter.)
3. For `coderscaffold` and `docker` only: replace the existing "This template does NOT
   mount /var/run/docker.sock ... group_add commented" comment block (which is now
   false) with a short note that the socket IS mounted below.

## Per-template changes (Dockerfile)

Add the flutter/python-ai "NOTHING TO INSTALL HERE" DooD documentation comment just
before `USER coder` (documentation only — keeps all templates consistent, warns future
editors not to re-add the build-breaking apt block).

## Verification

- `terraform fmt -check` and `terraform validate` (or at minimum `terraform fmt`) per
  changed template.
- [LIVE-VERIFY] Real gate is `coder templates push` + workspace create + `docker ps`
  inside the workspace — static validation cannot confirm socket reachability
  (see memory: infra-needs-live-deploy-gate).

## Out of scope

- `flutter` (already done), `python-ai` (the reference).
- `docker_group_id` default stays 999; operators override per host.
