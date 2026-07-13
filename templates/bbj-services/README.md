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

Copy **all version jars** side-by-side into the asset folder using the **exact filenames**
referenced in your `combinations.json` (see below). Jars must be staged next to each other —
the combo selector picks the exact named file, not a glob:

```bash
cp /path/to/BBj-25.12-installer.jar  ./bbj-assets/BBj-25.12.jar
cp /path/to/BBj-26.01-installer.jar  ./bbj-assets/BBj-26.01.jar  # if offering JDK 25 combo
cp /path/to/certificate.bls           ./bbj-assets/
```

Next, **copy and configure the combinations list**:

```bash
cp templates/bbj-services/combinations.example.json ./bbj-assets/combinations.json
# Edit combinations.json — list ONLY combos whose BBj version + JDK pairing you have
# confirmed is valid. The Coder create-workspace dropdown lists exactly these combos.
# The JDK is derived from the combo — there is no separate JDK picker.
```

Then **ship the template's own files into the same folder** — this folder is
the Docker build context, so the Dockerfile and answer file must be co-located
with the jars and certificate:

```bash
cp templates/bbj-services/Dockerfile           ./bbj-assets/
cp templates/bbj-services/playback.properties  ./bbj-assets/
```

> The template keeps its own copies of `Dockerfile`, `playback.properties`, and
> `combinations.example.json` under version control. The operator copies them into
> `BBJ_ASSETS_PATH` before each template push. If you update the template files,
> re-copy them before pushing.

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
Choose a **BBj stack** (combo) from the dropdown — the JDK is derived from it automatically.
The dropdown lists exactly the combos in your `combinations.json`; an unsupported BBj×JDK
pairing cannot be selected.

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

### FLAG-02: JDK 25 compatibility is enforced by combo curation

The `adoptium-25` JDK is only available when the admin has explicitly listed a
combo pairing it with a BBj version that supports it (e.g. `bbj-26.01-jdk25` in
`combinations.json`). Because the JDK is derived from the selected combo, an
unsupported BBj×JDK pairing **cannot be selected** from the dropdown.

**Operator responsibility:** Only list a JDK-25 combo in `combinations.json` after
confirming with BasisHub that the paired BBj version supports JDK 25. If you include
a JDK-25 combo and the BBj installer rejects it, the image build will fail during
`coder templates push` or workspace creation.

### FLAG-03: /opt/bbx is baked into the image, not persisted

The BBj installation lives at `/opt/bbx` inside the workspace image. This
directory is **baked at image build time** and is **not persisted** across
image rebuilds. If you change `BBJ_LICENSE_SERVER`, swap the JAR, or select a
different BBj stack combo, Terraform rebuilds the image and the BBj install runs again.

Configuration changes made inside `/opt/bbx` at runtime (e.g. via the
Enterprise Manager) will be **lost on the next image rebuild**.

`/home/coder` **is** persistent (Docker volume) and survives image rebuilds
and workspace stop/start cycles.

If you need `/opt/bbx` to persist configuration across rebuilds, a Docker
volume for `/opt/bbx` can be added to the `docker_container` resource in
`main.tf` (operator's choice — not included by default to keep the template simple).

---

## Pre-warming images with bbj-build-combos.sh

`scripts/bbj-build-combos.sh` pre-warms one Docker image per combo before any workspace
is created. It reads the **same `combinations.json`** the template reads (from
`BBJ_ASSETS_PATH`) so it can never drift out of sync.

```bash
./scripts/bbj-build-combos.sh
```

Because the script builds on the **same host Docker daemon** with the **same context and
build args** as the in-template Terraform build, it warms the BuildKit layer cache. When
a user creates a workspace, the in-template build is a near-instant cache hit — the
expensive BBj silent install is already done. This keeps workspace creation fast for the
first user of each combo.

**On-demand build is the always-works fallback.** The in-template `docker_image` build
runs unconditionally at workspace creation time even if you never run this script. The
first user of an un-warmed combo waits for the full image build (dominated by the BBj
silent install); subsequent users are cache hits.

**Requirements (operator step — cannot run here):**
- `jq` must be on PATH (`apt-get install jq` or `brew install jq`)
- Real BBj installer jars must exist in `BBJ_ASSETS_PATH` (e.g. `BBj-25.12.jar`)
- `certificate.bls` and `playback.properties` must be in `BBJ_ASSETS_PATH`
- A reachable BLS license server (`BBJ_LICENSE_SERVER`)

The script cannot be run end-to-end in this repository — no real jars or certificate
are present here. `bash -n` (syntax) and `shellcheck` are the verifiable steps in this repo.

**Exit codes:** `0` = all combos built; `1` = one or more failed; `2` = jq not found.

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
following steps require the real BBj jars, `certificate.bls`, and a reachable
BLS server — assets this repository does NOT contain. **Full end-to-end
verification CANNOT be done in this repo** and is the operator's responsibility:

0. **(Optional but recommended) Pre-warm all combo images** — run
   `./scripts/bbj-build-combos.sh` after staging the assets. This verifies
   every combo builds and warms the BuildKit layer cache so workspace creation
   is fast. Check the per-combo PASS/FAIL summary and fix any failures before
   pushing the template.

1. **Per-combo image build** — after `coder templates push`, create a workspace
   for each combo in your `combinations.json` and confirm the image builds
   successfully. The critical step is the BBj silent install
   (`java -jar BBj.jar -p playback.properties`) — it must complete without error.
   A failure here means the jar is missing, the certificate is wrong, or the
   BLS server is unreachable.

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
      combinations.json     ← copied from combinations.example.json, edited by operator
      BBj-25.12.jar         ← operator-supplied, license-gated (one per combo)
      BBj-26.01.jar         ← operator-supplied, license-gated (one per combo)
      certificate.bls       ← operator-supplied
      Dockerfile            ← copied from templates/bbj-services/
      playback.properties   ← copied from templates/bbj-services/

templates/bbj-services/
  Dockerfile                ← version-controlled; operator copies into BBJ_ASSETS_PATH
  main.tf                   ← Coder template (this file)
  playback.properties       ← BBj silent-install answer file; version-controlled
  combinations.example.json ← example combo list; operator copies to BBJ_ASSETS_PATH/combinations.json
  README.md                 ← this file

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
