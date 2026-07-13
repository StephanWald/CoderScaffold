# BBjServices Coder Workspace Template

A Coder workspace template that provisions a full development environment
(VS Code, JetBrains Gateway, Claude Code) **and** runs BasisHub BBjServices
as a live server on port 8888, exposed via a Coder app.

Forked from `templates/java-fullstack/`. BBjServices is baked into the
workspace image at build time from an operator-supplied host folder
(the BBj installer JAR, certificate, and this template's Dockerfile are
never committed to git).

---

## Prerequisites

Before pushing this template you need:

1. **A running BLS license server** — a reachable host:port running the
   BASIS License Server (BLS). Note the host:port (e.g. `bls.example.com:2002`).

2. **A BBj installer JAR** — downloaded from the BasisHub customer portal
   (license-gated). The filename matches `BBj*.jar`.

3. **A certificate file** — `certificate.bls` from BasisHub, associated with
   your BLS license server.

4. **A running Coder server** — from this repo's `compose.yaml`:
   ```
   docker compose up -d
   ```

---

## Setup

### Step 1: Prepare the host asset folder

Create the host asset folder (default `./bbj-assets`, relative to this repo):

```bash
mkdir -p ./bbj-assets
```

Copy the operator-supplied assets into it:

```bash
cp /path/to/BBj-installer.jar ./bbj-assets/BBj.jar    # or BBj*.jar glob
cp /path/to/certificate.bls   ./bbj-assets/
```

Then **ship the template's own files into the same folder** — this folder is
the Docker build context, so the Dockerfile and answer file must be co-located
with the JAR and certificate:

```bash
cp templates/bbj-services/Dockerfile           ./bbj-assets/
cp templates/bbj-services/playback.properties  ./bbj-assets/
```

> The template keeps its own copies of `Dockerfile` and `playback.properties`
> under version control. The operator copies them into `BBJ_ASSETS_PATH` before
> each template push. If you update the template files, re-copy them before pushing.

### Step 2: Set environment variables

Copy `.env.example` to `.env` (gitignored) and fill in the BBjServices section:

```bash
cp .env.example .env
# Edit .env — set real values for:
#   BBJ_ASSETS_PATH=./bbj-assets          (or an absolute path)
#   BBJ_LICENSE_SERVER=bls.example.com:2002
```

> Never commit real values to `.env.example` or any tracked file.

### Step 3: Restart the Coder server

The `compose.yaml` bind-mounts `BBJ_ASSETS_PATH` read-only at `/mnt/bbj-assets`
inside the coder service. Restart to pick up the new variables:

```bash
docker compose up -d
```

### Step 4: Push the template

```bash
coder templates push bbj-services --directory templates/bbj-services/
```

The Coder provisioner will build the image from the `/mnt/bbj-assets` context,
injecting the `LICENSE_SERVER` build-arg. The BBj silent install runs inside
the Docker build — this is the step that requires a reachable BLS server and
a valid JAR + certificate.

### Step 5: Create a workspace

In the Coder dashboard, create a new workspace from the `bbj-services` template.
Choose a JDK at creation time (Adoptium 21 is the default and recommended choice).

Once the workspace starts, the agent `startup_script` launches BBjServices in
the background. After a brief startup delay, click the **BBjServices** button
in the Coder dashboard to reach the HTTP interface on port 8888.

---

## Flags (known limitations and configuration requirements)

### FLAG-01: Subdomain routing requires CODER_WILDCARD_ACCESS_URL

The `coder_app "bbjservices"` is configured with `subdomain = true`, which
routes the 8888 app via a wildcard subdomain (e.g. `bbjservices--<workspace>.<apps-domain>`).

**Requirements for subdomain routing:**
- `CODER_WILDCARD_ACCESS_URL` must be set (e.g. `*.coder.example.com`)
- An external reverse proxy must route `*.<apps-domain>` to the Coder server

**On the committed default** (`CODER_ACCESS_URL=127.0.0.1`, no wildcard), the
BBjServices button will not route correctly. To use locally without wildcard DNS:

Change `subdomain = true` to `subdomain = false` in `main.tf` before pushing —
this switches to path-based routing (`/proxy/port/8888/`), which works without
a wildcard subdomain but may affect BBjServices internal URL generation.

### FLAG-02: JDK 25 requires a BBj build that supports it

The `adoptium-25` JDK option is available but **experimental**. The upstream
BBjServices release ships with JDK 21 support. Using JDK 25 requires a BBj
version that explicitly supports JDK 25 — confirm this with BasisHub before
selecting it. If you choose JDK 25 and the BBj installer rejects it, the image
build will fail.

**Recommendation:** Use the default `adoptium-21` unless you have confirmed
BBj support for JDK 25.

### FLAG-03: /opt/bbx is baked into the image, not persisted

The BBj installation lives at `/opt/bbx` inside the workspace image. This
directory is **baked at image build time** and is **not persisted** across
image rebuilds. If you change `BBJ_LICENSE_SERVER`, swap the JAR, or change
the JDK selection, Terraform rebuilds the image and the BBj install runs again.

Configuration changes made inside `/opt/bbx` at runtime (e.g. via the
Enterprise Manager) will be **lost on the next image rebuild**.

`/home/coder` **is** persistent (Docker volume) and survives image rebuilds
and workspace stop/start cycles.

If you need `/opt/bbx` to persist configuration across rebuilds, a Docker
volume for `/opt/bbx` can be added to the `docker_container` resource in
`main.tf` (operator's choice — not included by default to keep the template simple).

---

## Verifying the deployment

### Static validation (runs in this repo, no BBj assets required)

```bash
cd templates/bbj-services
terraform init -backend=false
terraform validate
terraform fmt -check
```

This validates the Terraform syntax and provider schema. It does **not**
require the real BBj JAR, certificate, or a reachable BLS server — the
`try()` guards in `triggers` make validation succeed without them.

### Live verification (operator step — requires real assets)

Static validation is NOT sufficient to declare this template working. The
following steps require the real BBj JAR, `certificate.bls`, and a reachable
BLS server — assets this repository does NOT contain. **Full end-to-end
verification CANNOT be done in this repo** and is the operator's responsibility:

1. **Image build** — after `coder templates push`, create a workspace and
   confirm the workspace image builds successfully. The critical step is the
   BBj silent install (`java -jar BBj.jar -p playback.properties`) — it must
   complete without error. A failure here means the JAR is missing, the
   certificate is wrong, or the BLS server is unreachable.

2. **BBjServices starts** — inspect the workspace's startup log and confirm
   BBjServices launched. You can also check the in-workspace log:
   ```bash
   cat /tmp/bbjservices.log
   ```

3. **Port 8888 is reachable** — in the Coder dashboard, click the
   **BBjServices** app button. Confirm the BBjServices HTTP interface loads.
   If it does not load, check the healthcheck status in the Coder dashboard
   and the log at `/tmp/bbjservices.log` inside the workspace.

4. **BLS server connectivity** — if BBjServices starts but rejects connections
   with a license error, confirm the BLS server is reachable from inside the
   workspace container:
   ```bash
   nc -zv <BBJ_LICENSE_SERVER_HOST> <BBJ_LICENSE_SERVER_PORT>
   ```

---

## Architecture

```
compose.yaml
  coder service
    /mnt/bbj-assets (read-only bind mount of BBJ_ASSETS_PATH)
      BBj*.jar        ← operator-supplied, license-gated
      certificate.bls ← operator-supplied
      Dockerfile      ← copied from templates/bbj-services/
      playback.properties ← copied from templates/bbj-services/

templates/bbj-services/
  Dockerfile          ← version-controlled; operator copies into BBJ_ASSETS_PATH
  main.tf             ← Coder template (this file)
  playback.properties ← BBj silent-install answer file; version-controlled
  README.md           ← this file

Workspace container
  /opt/java/default   ← Adoptium JDK (baked at build, not persisted)
  /opt/bbx/           ← BBjServices install (baked at build, not persisted)
  /home/coder         ← persistent Docker volume (survives rebuilds)
  port 8888           ← BBjServices HTTP (started by agent startup_script)
```

## Security notes

- `BBj*.jar` and `certificate.bls` are license-gated assets. They live only
  in the gitignored host folder and the workspace image — never in git.
- `BBJ_LICENSE_SERVER` is set in the gitignored `.env` file. Only the
  placeholder appears in `.env.example`.
- The `coder_app "bbjservices"` uses `share = "owner"` — access to port 8888
  is restricted to the workspace owner only.
- The host bind mount is `:ro` (read-only) — the coder provisioner cannot
  write back into the operator's asset folder.
