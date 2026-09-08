# Research Workspace Template

A Coder workspace template for research projects — it provides the full `python-ai` toolchain
(batteries-included Python + AI tooling) PLUS a preinstalled **Feynman AI research agent**
(`@companion-ai/feynman`), aimed at teams who want paper reading, web search, research drafting,
experiment planning, and citation management available out of the box alongside their development
environment.

## What it provides

- **Selectable CPython** — 3.13 (default), 3.12, or 3.11. The version is a **build-time**
  choice (prompted at workspace creation); selecting a different version rebuilds the workspace
  image and produces a separately-cached layer. Other versions remain available at runtime via
  `uv python install <version>` without a rebuild.
- **uv** (Astral) — the fast Python package + project manager; `uv` and `uvx` are on the
  system PATH from the first login.
- **Pre-baked dev tools** — `ruff` (linter/formatter), `mypy` (type checker), `pytest`
  (test runner), `ipython` (interactive REPL) — all system-wide shims in `/usr/local/bin`.
- **AI SDKs** — `anthropic` and `claude-agent-sdk` are importable from the default `python`
  with no venv activation: `python -c "import anthropic, claude_agent_sdk"` succeeds in a
  fresh login shell.
- **JupyterLab** — `jupyter lab` is on PATH; the workspace shows a JupyterLab app button.
- **Node.js LTS** — `node`, `npm`, `npx` for Claude Code CLI, GSD installs, and the node
  JSON merges in the startup script.
- **VS Code** (browser, via code-server) + **VS Code Desktop** (SSH, local client) +
  **PyCharm Professional** (JetBrains Gateway).
- **Claude Code** — latest CLI, pre-wired via the per-owner shared volume; first login is
  interactive OAuth — no API key required by default.
- **webforJ MCP server** — `https://mcp.webforj.com/` registered in every workspace for this
  owner automatically.
- **MemPalace MCP** — local AI memory; `mempalace mcp serve` wired into the shared Claude
  config.
- **GSD** (gsd-core) — installed once into the per-owner shared Claude volume.
- **Feynman AI research agent** (`@companion-ai/feynman`) — the open-source AI research agent
  that reads papers, searches the web, writes research drafts, plans experiments, and cites
  claims. Installed via `npm install -g @companion-ai/feynman` so `feynman` is on the system
  PATH from the first login in every workspace.
- **Optional git clone** — prompted at workspace creation; when supplied, the repo is cloned
  on first start and all editors open that checkout.

## Using Feynman

**First run — interactive setup:**

```bash
feynman setup
```

This wizard configures Feynman for your account (API keys, preferences). Configuration is
per-user and persists on the home volume — it survives workspace stop/start. Do not run
`feynman setup` at build time; it is an interactive, per-user wizard.

**Workbench — local research UI:**

```bash
feynman serve
```

This starts a local Feynman workbench server and prints an authenticated localhost URL
(with a session token). Use `--no-auth` to print a plain URL. Because Feynman's default
port is not documented in advance (read it from the `feynman serve` output), there is
intentionally **no coder_app button** for the workbench — reach it by forwarding the port
it prints:

```bash
# On your local machine, forward the port Feynman printed (e.g. 4242):
coder port-forward <workspace-name> --tcp 4242:4242
# Then open the localhost URL from feynman serve in your local browser.
```

The printed port may vary; always read it from `feynman serve`'s output.

## Why toolchains live in /opt (not /home/coder)

`/home/coder` is a persistent Docker volume that **shadows** anything baked into that path
at image build time. Every `uv` install, Python shim, and tool binary targets `/opt/uv-python`,
`/opt/uv-tools`, or `/usr/local/bin` — outside the volume mount — so the toolchain is present
from the very first shell in every workspace, even after a fresh start.

**Feynman follows the same rule.** It is installed via `npm install -g @companion-ai/feynman`
(system path: `/usr/lib/node_modules`, with binaries symlinked into `/usr/bin`), which is
outside the `/home/coder` volume. The official curl-based installer from feynman.is targets
`~/.local/bin` and `~/.local/share/feynman`, which live under `/home/coder` and would be
masked by the home volume at runtime — they vanish on every restart. npm global install is
the correct system-path method for this image.

## Cloning a private repository (SSH)

For SSH URLs (`git@github.com:owner/repo.git`), Coder authenticates with a per-user key it
manages for you. Two things make it work:

1. **Host key verification** — handled by the image: GitHub, GitLab, Bitbucket, and Azure
   DevOps are pre-seeded into the system `known_hosts`; any other host is trusted on first use
   (`StrictHostKeyChecking=accept-new`).
2. **Authorize Coder's key with your Git host** — copy the key Coder prints (or run
   `coder publickey`) and add it once at <https://github.com/settings/ssh/new>. The key is
   stored centrally by Coder and covers all your workspaces.

The first-start clone is non-fatal and idempotent — if the key isn't registered yet, restart
the workspace or run the `git clone` manually once.

## Push and configure

```bash
# Push (or use ./scripts/push-templates.sh to push every template automatically)
coder templates push research --directory templates/research/ -y

# Server-side display metadata (not Terraform-managed — set after the first push)
coder templates edit research \
  --display-name "Research" \
  --description "Research workspace: Python (3.13/3.12/3.11), ruff/mypy/pytest/ipython, anthropic + claude-agent-sdk, JupyterLab, VS Code, PyCharm, Claude Code + MCP + GSD, Feynman AI research agent." \
  --icon "/icon/python.svg"
```

> Re-run `coder templates edit` after every re-push to keep the display metadata — it is not
> preserved automatically on re-push.

`./scripts/push-templates.sh` discovers and pushes every `templates/*/` directory that
contains a `.tf` file. The `research` template requires **no `--variable` flags** at push time
(`anthropic_api_key` defaults to `""` — OAuth is the standard path). The script needs no
edits — it auto-discovers `templates/research/` alongside all other templates.

---

## DEFERRED LIVE-VERIFICATION CHECKLIST

The following checks **MUST be run on a real Coder host** with the `coder` CLI installed and
a running Coder server before trusting this template in production. Static HCL checks
(`terraform fmt -check`, offline `terraform validate`) have been performed. Live checks are
deferred per project memory: "Infra needs a live deploy gate."

- [ ] `coder templates push research --directory templates/research/ -y` succeeds
- [ ] Workspace builds for each python_version: 3.13, 3.12, and 3.11
- [ ] `python --version` output matches the selected python_version; `python -c "import anthropic, claude_agent_sdk"` succeeds in a fresh login shell
- [ ] `ruff`, `mypy`, `pytest`, `ipython`, `jupyter`, `uv`, and `uvx` are all on PATH
- [ ] IDE buttons appear and open correctly: VS Code (browser), VS Code Desktop, PyCharm Professional (JetBrains Gateway)
- [ ] JupyterLab app button appears in the workspace and launches JupyterLab successfully
- [ ] Confirm the vscode-desktop module (`registry.coder.com/coder/vscode-desktop/coder @ 1.1.0`) and jupyterlab module (`registry.coder.com/coder/jupyterlab/coder @ 1.1.0`) source/version pins resolve at push time; bump pins if the registry has newer versions or if either module does not exist (activate the commented `coder_app` fallback for JupyterLab)
- [ ] Claude Code, webforJ MCP server, MemPalace MCP server, and GSD are all present and functional in the owner-shared volume
- [ ] Second/third start emits no startup_script errors (idempotence gate)
- [ ] `feynman --version` succeeds in a fresh login shell (system PATH; not shadowed by the home volume)
- [ ] `feynman setup` runs and its config persists across a workspace stop/start
- [ ] `feynman serve` starts and the workbench is reachable via `coder port-forward` on the port it prints
- [ ] `./scripts/push-templates.sh` discovers and pushes `research` alongside the other templates
