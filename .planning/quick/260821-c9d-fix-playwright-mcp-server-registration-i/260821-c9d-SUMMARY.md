---
phase: quick-260821-c9d
plan: "01"
subsystem: templates
tags: [playwright, mcp, browser, chromium, headless, terraform]
status: complete
completed: "2026-08-21T08:52:09Z"
duration: "~5min"
requires: []
provides:
  - "Playwright MCP server registered with --browser chromium --headless in python-ai, java-fullstack, bbj-services"
affects:
  - templates/python-ai/main.tf
  - templates/java-fullstack/main.tf
  - templates/bbj-services/main.tf
tech_stack:
  added: []
  patterns: []
key_files:
  modified:
    - templates/python-ai/main.tf
    - templates/java-fullstack/main.tf
    - templates/bbj-services/main.tf
decisions:
  - "Pass --browser chromium --headless flags to @playwright/mcp in all 3 template startup_scripts so the baked /ms-playwright chromium is selected over the missing Google Chrome channel"
metrics:
  duration: "~5min"
  completed: "2026-08-21T08:52:09Z"
  tasks: 1
  commits: 1
actuals:
  tokens: 800
  tasks: 1
  commits: 1
---

# Phase quick-260821-c9d Plan 01: Fix Playwright MCP Server Registration Summary

**One-liner:** Pass `--browser chromium --headless` to `@playwright/mcp@latest` in all 3 workspace templates so the baked `/ms-playwright` chromium is used instead of the missing Google Chrome channel.

## What Was Built

In each of the three workspace templates (`python-ai`, `java-fullstack`, `bbj-services`), the `cfg.mcpServers.playwright` args array in the `startup_script` node one-liner was extended from the two-element form:

```
args: ["-y", "@playwright/mcp@latest"]
```

to the five-element form:

```
args: ["-y", "@playwright/mcp@latest", "--browser", "chromium", "--headless"]
```

This is the only change. Command (`npx`), package spec (`@playwright/mcp@latest`), indentation, and all other MCP registrations (webforJ, MemPalace) are untouched.

## Why

Without `--browser chromium`, `@playwright/mcp` defaults to the `chrome` channel, which resolves to `/opt/google/chrome/chrome` — not installed in any of these images. The Dockerfiles bake Playwright's bundled chromium into `/ms-playwright` (via `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`). Without `--headless`, the MCP server tries to open a display that workspaces do not have (`$DISPLAY` unset). The result: the first `browser_navigate` call fails with `Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome`.

## Commits

| Hash | Message |
|------|---------|
| df8482e | fix(quick-260821-c9d): pass --browser chromium --headless to @playwright/mcp in all 3 templates |

## Verification Results

All automated checks from the plan passed:

- New args form (`--browser", "chromium", "--headless"`) appears exactly once in each of the 3 files (3/3).
- Old two-element args form (`["-y", "@playwright/mcp@latest"] }`) no longer appears in any of the 3 files.
- `git diff --stat` shows exactly 3 files changed, 3 insertions, 3 deletions.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- templates/python-ai/main.tf contains `--browser", "chromium", "--headless"`: FOUND
- templates/java-fullstack/main.tf contains `--browser", "chromium", "--headless"`: FOUND
- templates/bbj-services/main.tf contains `--browser", "chromium", "--headless"`: FOUND
- Commit df8482e exists: FOUND
- Old two-element args form absent from all 3 files: CONFIRMED
