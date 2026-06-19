---
quick_id: 260619-bix
title: update-coder.sh + Updating Coder docs
date: 2026-06-19
status: complete
---

# Quick Task 260619-bix

Add a safe, repeatable Coder update path (script + docs).

## Task
- scripts/update-coder.sh: --check; pin vX.Y.Z in .env (reject :latest); back up
  DB first (abort on failure); pull + recreate; wait healthy; --no-backup,
  --push-templates, --dry-run, --help. Non-interactive, meaningful exit codes.
- README "Updating Coder": script + manual + committed-default bump + rollback.

## Verify
- bash -n + shellcheck clean; --help/--check/--dry-run work; bad version rejected.

## Done
Operators can update Coder (e.g. v2.33.8 → v2.33.9) with a pre-update backup and
health gate, or by hand; rollback documented.
