---
quick_id: 260619-a5w
title: Fix SSH host key verification for private-repo clones (java-fullstack)
date: 2026-06-19
status: complete
commit: a69f0d2
---

# Quick Task 260619-a5w — Summary

Fixed `Host key verification failed` when the java-fullstack template clones a
repo over SSH (e.g. the optional `git_repo` parameter, `git@github.com:...`).

## Root cause

A fresh workspace container had no `known_hosts` entry for the Git host. The
non-interactive `ssh` invoked by `coder gitssh` refuses unverified hosts, so the
clone aborted at host-key verification — *before* authentication. This was a
gap in the image, not a credential problem. (Coder's per-user managed key handles
auth; that key still must be registered with the Git host separately.)

## Change

`templates/java-fullstack/Dockerfile`:
- `ssh-keyscan` pre-seeds host keys for github.com, gitlab.com, bitbucket.org,
  ssh.dev.azure.com into the **system** `/etc/ssh/ssh_known_hosts` (outside the
  volume-shadowed `/home/coder`, so it always applies).
- `/etc/ssh/ssh_config.d/10-accept-new.conf` sets `StrictHostKeyChecking
  accept-new` globally — trust-on-first-use for any other host (self-hosted
  GitLab, etc.) instead of rejection.

`README.md`: new "Cloning a private repository (SSH)" subsection — Coder manages
a per-user SSH key (no personal key needed in the workspace); register it once at
the Git host; the first-start clone of a private repo may need a retry because it
runs before the key is registered.

## Verification

- `docker build` of the adoptium-21 variant succeeds with the new step.
- `ssh-keygen -F <host>` (the same lookup ssh performs) finds github.com,
  gitlab.com, bitbucket.org in the baked `known_hosts` → ssh will verify, not
  reject.
- `ssh -G github.com` reports `stricthostkeychecking accept-new`.
- (Outbound port 22 is blocked in this build sandbox, so a full `ssh -T` connect
  could not run here; the known_hosts presence is the authoritative fix for the
  reported error and the user's host clearly has port-22 egress.)

## Notes

- Authentication to a private repo still requires the Coder-managed public key to
  be added to the Git host — that is a user action, documented in the README.
- Applied to java-fullstack only (the template with the SSH-clone feature);
  docker/coderscaffold clone over HTTPS and are unaffected.
</content>
