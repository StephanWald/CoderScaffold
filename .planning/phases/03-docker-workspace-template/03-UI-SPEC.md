---
phase: 3
slug: docker-workspace-template
status: draft
shadcn_initialized: false
preset: none
created: 2026-06-17
---

# Phase 3 — UI Design Contract

> Visual and interaction contract for Phase 3: Docker Workspace Template.
>
> **Scope note:** This phase produces a Coder Terraform template (`templates/docker/`), not a
> custom-built web frontend. No design system, component library, or custom CSS is introduced.
> The UI surfaces controlled by this phase are:
>
> 1. **Coder workspace dashboard** — template metadata, parameter labels, and workspace app
>    buttons (code-server "VS Code", JetBrains Gateway "IntelliJ IDEA") rendered by Coder's
>    own UI using the values declared in `main.tf`.
> 2. **Pre-built third-party editors** — code-server and IntelliJ IDEA are configured via
>    Coder registry modules; their internal editor UI is out of scope.
>
> This contract covers: template display name / description, workspace app display
> names / icons / ordering, agent metadata labels (CPU/RAM/disk), workspace naming
> convention, and operator-facing copy in README additions. Typography, color, and
> spacing tokens are not applicable — Coder's own design system controls the dashboard.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — Coder dashboard renders template metadata; no custom design system |
| Preset | not applicable |
| Component library | not applicable |
| Icon library | Coder built-in icon set via `icon` field in `coder_app` resource (SVG path references) |
| Font | not applicable — inherits Coder dashboard font |

---

## Spacing Scale

Not applicable. This phase does not produce HTML/CSS. All spacing is determined by Coder's
own dashboard shell.

Exceptions: not applicable

---

## Typography

Not applicable. Font sizes, weights, and line-heights are controlled by Coder's dashboard.
The only typography this phase controls is the text content of string fields declared in
`main.tf` (display names, descriptions, labels) — governed by the Copywriting Contract below.

---

## Color

Not applicable. Colors are determined by Coder's dashboard theme. This phase does not
introduce any color tokens or CSS.

---

## Template Metadata Contract

These values appear verbatim in the Coder dashboard and must be set exactly as specified.

### Template-level display (set via `coder_workspace_metadata` or template upload)

| Field | Value | Source |
|-------|-------|--------|
| Template display name | `Docker Workspace` | D-01 (codercom/enterprise-base:ubuntu, single template) |
| Template description | `Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start.` | Describes what the developer gets; no marketing language |
| Template icon | `/icon/docker.png` | Coder built-in Docker icon (standard for Docker-based templates) |

### Workspace app buttons (what the developer sees after "Connected")

Apps appear in this order in the Coder workspace dashboard. Order is declared by the
sequence of `coder_app` blocks in `main.tf`.

| Order | Display Name | Icon | Open Behavior | Source |
|-------|-------------|------|---------------|--------|
| 1 | `VS Code` | `/icon/code.svg` | Opens in new browser tab | TPL-02, D-05, code-server module 1.5.0 |
| 2 | `IntelliJ IDEA` | `/icon/intellij.svg` | Opens JetBrains Gateway SSH URL | TPL-03, D-06, jetbrains-gateway module 1.2.6 |

**Rationale for ordering:** VS Code (browser) is zero-install for the developer; it appears
first as the primary quick-access app. IntelliJ IDEA requires Gateway installed locally;
it appears second as the secondary native IDE path. Consistent with Coder's own documentation
examples.

### Agent metadata display

Metadata lines appear in the workspace detail view under the agent. Declare the following
`metadata` blocks on the `coder_agent` resource:

| Label | Value expression | Update interval |
|-------|-----------------|-----------------|
| `CPU Usage` | `top -bn1 \| grep "Cpu(s)" \| awk '{print $2}' \| sed 's/%us,//'` | 10s |
| `RAM Usage` | `free -h \| awk '/^Mem/ {print $3 "/" $2}'` | 10s |
| `Disk` | `df -h /home/coder \| awk 'NR==2 {print $3 "/" $2}'` | 60s |

These are standard Coder metadata patterns from the upstream Docker template. No custom
labels are introduced. Display name `Disk` measures the persistent home volume (TPL-04, D-07).

---

## Workspace Naming Convention

Coder auto-generates workspace names from the developer's username + a slug. This phase
does not override the default naming scheme — no `coder_parameter` blocks for name
customization (D-03: bare form, no parameters).

The per-workspace home volume is named using the Coder-canonical pattern:
`coder-{workspace_id}-home` or equivalent deterministic key derived from workspace ID,
ensuring one volume per workspace and preventing cross-workspace collision.

---

## Create-Workspace Form Contract

Per D-03 and D-04, the create-workspace form is **bare — no `coder_parameter` blocks**.

| Parameter | Status | Rationale |
|-----------|--------|-----------|
| Base image selector | Not present | Fixed to `codercom/enterprise-base:ubuntu` (D-01/D-04) |
| IDE selector | Not present | Fixed to code-server + IntelliJ (D-05/D-06) |
| Git repo to clone | Not present | Deferred (see Deferred Ideas in CONTEXT.md) |
| Dotfiles URL | Not present | Deferred to QOL-01 v2 |
| CPU/memory limits | Not present | Deferred to QOL-03 v2 |

Developer experience: click template → click "Create Workspace" → workspace starts →
click "VS Code" or "IntelliJ IDEA". No form fields to fill.

---

## Copywriting Contract

All copy appears in Coder's dashboard UI, README additions, or Terraform comments.
This is the complete copywriting surface controlled by this phase.

### Dashboard copy (values in main.tf)

| Element | Copy |
|---------|------|
| Template description | `Docker container workspace with VS Code (browser) and JetBrains Gateway (IntelliJ IDEA). Home directory persists across stop/start.` |
| VS Code app display name | `VS Code` |
| IntelliJ IDEA app display name | `IntelliJ IDEA` |
| Agent metadata label — CPU | `CPU Usage` |
| Agent metadata label — RAM | `RAM Usage` |
| Agent metadata label — disk | `Disk` |

### README additions (operator-facing)

The README (from Phase 1) is extended with a new "Workspace Template" section.
Required copy elements:

| Element | Copy |
|---------|------|
| Section heading | `## Workspace Template` |
| "Create a workspace" instruction | `In the Coder dashboard, click **Templates → Docker Workspace → Create Workspace**, then click **Create**. No parameters to fill.` |
| Socket GID callout heading | `### Docker Socket Permissions` |
| Socket GID callout body | `If workspace provisioning fails with a permission error on /var/run/docker.sock, the Docker socket GID on your host differs from the container default. Uncomment the group_add block in compose.yaml and set the GID to your host docker group (stat -c '%g' /var/run/docker.sock).` |
| Agent connectivity note heading | `### Workspace Agent Connectivity` |
| Agent connectivity note body (local) | `For local deployments (CODER_ACCESS_URL=http://127.0.0.1:7080), the template adds host.docker.internal via extra_hosts so the workspace agent can reach the Coder server inside the container. No additional configuration required.` |
| Agent connectivity note body (production) | `For production deployments with a real CODER_ACCESS_URL (IP or domain reachable from workspace containers), host.docker.internal is not used. Set CODER_ACCESS_URL to a URL that workspace containers on the host network can reach.` |
| Home persistence note | `Workspace home directories (/home/coder) are stored in per-workspace Docker volumes and survive workspace stop/start cycles. Deleting a workspace deletes its home volume.` |

### Error states (operator-visible, in README)

| Scenario | Copy |
|----------|------|
| Socket permission failure | `workspace provisioning fails with a permission error on /var/run/docker.sock` → directs to Socket GID section |
| Agent not connecting (local) | `workspace agent shows "Connecting" indefinitely` → directs to Connectivity section, verify CODER_ACCESS_URL and host.docker.internal |
| Agent not connecting (production) | `verify CODER_ACCESS_URL is reachable from workspace containers — 127.0.0.1 will not work for non-Docker templates` |

### Destructive actions

| Action | Confirmation approach |
|--------|----------------------|
| Delete workspace | Handled by Coder dashboard (built-in confirmation dialog — not controlled by this template) |
| Remove home volume | Handled by Coder dashboard on workspace deletion — README notes volume deletion is permanent |

---

## Registry Safety

No shadcn or custom component registries apply to this phase (not a frontend).
The Coder registry modules used are official first-party modules from `registry.coder.com`.

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| `registry.coder.com` (Coder official) | `coder/code-server@1.5.0`, `coder/jetbrains-gateway@1.2.6` | First-party Coder registry; no third-party vetting required. Versions pinned per CLAUDE.md Recommended Stack. |
| Third-party shadcn | none | not applicable |

**Module pin rationale (from CLAUDE.md):**
- `coder/code-server 1.5.0` — 3,085,088 downloads; most-used editor module; requires `coder/coder >= 2.5`, Terraform `>= 1.9`
- `coder/jetbrains-gateway 1.2.6` — 3,490,057 downloads; most-used IDE module; requires `coder/coder >= 2.5`, Terraform `>= 1.0`

Both pins satisfy the `coder/coder ~> 2.18` provider constraint and the server version `v2.33.8`.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending

---

## Assumptions & Rationale

| Decision | Assumption | Rationale |
|----------|------------|-----------|
| App ordering (VS Code first) | Developer preference for zero-install path first | VS Code in browser requires no local tool install; IntelliJ IDEA requires Gateway. Most developers reach for the browser first. |
| Template icon `/icon/docker.png` | Coder's built-in icon path is stable | Standard path used by upstream Coder Docker template examples |
| App icons (`/icon/code.svg`, `/icon/intellij.svg`) | Coder's built-in icon set includes these paths | Consistent with Coder registry module documentation for these exact modules |
| Metadata labels (CPU/RAM/Disk) | Standard Coder metadata pattern | Copied from upstream Coder Docker template; accepted convention in the ecosystem |
| Home volume label `Disk` (not `Home`) | Operator-clarity: "Disk" communicates storage usage | "Disk" is the conventional Coder metadata label for storage; "Home" could imply a directory listing |

*UI-SPEC created: 2026-06-17 — auto-mode, no interactive questions (infrastructure phase with no custom frontend)*
