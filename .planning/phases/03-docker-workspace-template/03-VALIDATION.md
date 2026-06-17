---
phase: 3
slug: docker-workspace-template
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-17
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> **Phase type note:** This is a Terraform workspace-template phase. Terraform has no
> unit-test framework applicable to this template (per RESEARCH.md § Validation Architecture).
> Validation is therefore (a) automated **structural grep gates** + `terraform fmt -check` /
> `terraform validate` when the CLI is present, and (b) **manual end-of-phase UAT** against the
> five ROADMAP success criteria. No Wave 0 test scaffolding is required.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | none — infra/Terraform phase (no unit-test framework for HCL templates) |
| **Config file** | none |
| **Quick run command** | `grep` structural gate emitting `GATE_PASS` (embedded in each task `<automated>`) |
| **Full suite command** | `command -v terraform && terraform -chdir=templates/docker fmt -check && terraform -chdir=templates/docker validate` (when CLI present), else structural grep gates |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run the task's `<automated>` grep gate (must print `GATE_PASS`)
- **After every plan wave:** Run `terraform fmt -check` + `terraform validate` if the CLI is available
- **Before `/gsd-verify-work`:** All structural gates green; live UAT (SC-1..SC-5) ready to run against a real Coder server
- **Max feedback latency:** ~5 seconds (grep gates)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-T1 | 01 | 1 | TPL-01, TPL-04, TPL-05, TPL-06 | T-03-01 (Docker socket EoP) | Workspace container has NO host Docker socket mount | structural grep + `terraform fmt/validate` | grep gate → `GATE_PASS` (provider pin, host-gateway, `ignore_changes = all`, UUID-keyed home volume, no `hashicorp/docker`, no `coder_parameter`) | ✅ | ⬜ pending |
| 03-01-T2 | 01 | 1 | TPL-02, TPL-03 | — | Pinned first-party registry modules only | structural grep + `terraform fmt/validate` | grep gate → `GATE_PASS` (code-server 1.5.0, jetbrains-gateway 1.2.6, `jetbrains_ides = ["IU"]`, ≥3 `start_count`) | ✅ | ⬜ pending |
| 03-02-T1 | 02 | 2 | TPL-01, TPL-05, TPL-06 | — | Operator docs for socket GID + connectivity | structural grep + human-check UAT | grep gate → `GATE_PASS` (README `## Workspace Template` section, push/edit commands, GID `stat` command, connectivity guidance) | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — no test scaffolding needed. Validation is structural grep gates + `terraform fmt/validate` (no framework install) + manual UAT.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Workspace starts; agent shows "Connected"; app URLs resolve under wildcard subdomain | TPL-01 (SC-1) | Requires a live Coder server + provisioner; not reproducible in CI without a running control plane | Push `templates/docker/`, create a workspace, confirm agent "Connected" and app buttons render |
| code-server opens a functional VSCode session in the browser | TPL-02 (SC-2) | Requires a running workspace container + browser session | Click the "VS Code" app button; confirm the editor loads and can open a terminal/file |
| JetBrains Gateway connects to the workspace | TPL-03 (SC-3) | Requires the JetBrains Gateway client installed locally | Use the IntelliJ IDEA button / Gateway flow; confirm a remote IDE session establishes |
| `/home` contents persist across stop/start | TPL-04 (SC-4) | Requires a real stop/start lifecycle on the Docker volume | Create a file in `/home/coder`, stop then start the workspace, confirm the file is present |
| Provisioning succeeds where Docker socket GID differs; docs explain `group_add`/GID | TPL-05 (SC-5) | Requires a host with a non-default Docker group GID | Follow the README socket-GID section (`stat -c '%g' /var/run/docker.sock` → `group_add`); confirm provisioning succeeds |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify (structural grep gates) — no Wave 0 dependencies needed for an infra phase
- [x] Sampling continuity: every task carries an automated gate (no 3-consecutive-task gap)
- [x] Wave 0 covers all MISSING references (none — no test framework applicable)
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-17
