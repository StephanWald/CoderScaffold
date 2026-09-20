#!/usr/bin/env bash
# claude-share-selftest.sh — self-test for the per-owner shared Claude volume
# (~/.claude-shared → docker volume coder-<owner-uuid>-claude).
#
# Run INSIDE a workspace, ideally in two workspaces of the SAME owner:
#
#   ./claude-share-selftest.sh plumbing    # deterministic mount/symlink/cross-write checks
#   ./claude-share-selftest.sh seed        # plant a canary fact into shared user memory
#   ./claude-share-selftest.sh knowledge   # A/B: does `claude -p` retrieve the canary?
#   ./claude-share-selftest.sh all         # plumbing + seed + knowledge
#   ./claude-share-selftest.sh cleanup     # remove canary + selftest artifacts
#
# Comparing two workspaces: every output line NOT prefixed "[local]" is
# canonical — run `plumbing` in both and diff; the diffs must be empty.
#
#   for ws in ws-a ws-b; do
#     coder ssh "$ws" -- 'bash -s -- all' < claude-share-selftest.sh > "out-$ws.txt" &
#   done; wait
#   diff <(grep -v '^\[local\]' out-ws-a.txt) <(grep -v '^\[local\]' out-ws-b.txt)
#
# Exit code: 0 = all checks passed, 1 = at least one FAIL.

set -u

SHARED="$HOME/.claude-shared"
CFG="${CLAUDE_CONFIG_DIR:-$SHARED/dot-claude}"
SELFTEST="$SHARED/selftest"
WS="${CODER_WORKSPACE_NAME:-$(hostname)}"
TRIALS="${TRIALS:-3}"
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-120}"
MARKER="<!-- share-selftest-canary -->"

PASS=0 FAIL=0
pass()  { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
fail()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
local_() { printf '[local] %s\n' "$1"; }

# ── Layer 1: plumbing (deterministic — must be identical across workspaces) ──
plumbing() {
  echo "== PLUMBING =="
  local_ "workspace: $WS  $(date -u +%FT%TZ)"

  # 1. shared dir is a real mountpoint (not just a directory on the home volume)
  if awk -v m="$SHARED" '$2 == m { found=1 } END { exit !found }' /proc/self/mounts; then
    pass "$SHARED is a mountpoint"
  else
    fail "$SHARED is NOT a mountpoint — volume mount missing"
  fi

  # 2. symlinks point into the shared volume
  [ "$(readlink "$HOME/.claude")" = "$SHARED/dot-claude" ] \
    && pass "~/.claude → shared dot-claude" \
    || fail "~/.claude symlink wrong: $(readlink "$HOME/.claude" 2>/dev/null || echo '<not a symlink>')"

  [ -L "$HOME/.claude.json" ] && [ "$(readlink -f "$HOME/.claude.json")" = "$(readlink -f "$SHARED/dot-claude/.claude.json")" ] \
    && pass "~/.claude.json resolves into shared volume" \
    || fail "~/.claude.json does not resolve into shared volume"

  # 3. CLAUDE_CONFIG_DIR is set to the physical shared dir
  [ "${CLAUDE_CONFIG_DIR:-}" = "$SHARED/dot-claude" ] \
    && pass "CLAUDE_CONFIG_DIR = $SHARED/dot-claude" \
    || fail "CLAUDE_CONFIG_DIR unset or wrong: '${CLAUDE_CONFIG_DIR:-}'"

  # 4. ownership + writability
  [ "$(stat -c '%U' "$SHARED")" = "coder" ] \
    && pass "shared volume owned by coder" \
    || fail "shared volume owned by $(stat -c '%U' "$SHARED")"

  local probe="$SHARED/.write-probe-$$"
  if touch "$probe" 2>/dev/null; then pass "shared volume writable"; rm -f "$probe"
  else fail "shared volume NOT writable"; fi

  # 5. shared config files are valid JSON (detects concurrent-write corruption)
  for f in "$CFG/.claude.json" "$CFG/settings.json"; do
    if [ -f "$f" ]; then
      if node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" 2>/dev/null; then
        pass "valid JSON: ${f#"$SHARED"/}"
      else
        fail "CORRUPT JSON: ${f#"$SHARED"/}"
      fi
    else
      fail "missing: ${f#"$SHARED"/}"
    fi
  done

  # 6. cross-workspace visibility: drop a nonce, wait, count peers.
  #    Run in two workspaces in parallel → each must see the other's nonce.
  mkdir -p "$SELFTEST/nonces"
  find "$SELFTEST/nonces" -name '*.nonce' -mmin +60 -delete 2>/dev/null
  echo "$WS $(date -u +%FT%TZ)" > "$SELFTEST/nonces/$WS.nonce"
  sleep 5
  local nonces peers
  nonces=$(ls "$SELFTEST/nonces"/*.nonce 2>/dev/null | wc -l)
  peers=$(ls "$SELFTEST/nonces" | grep -v "^$WS\.nonce$" | sed 's/\.nonce$//' | paste -sd, -)
  local_ "nonces visible: $nonces (peers: ${peers:-none})"
  if [ "$nonces" -ge 2 ]; then
    pass "cross-workspace write visible (sees peer nonce)"
  else
    fail "no peer nonce visible — run this in a second workspace within 60 min (or in parallel)"
  fi

  # 7. canonical fingerprint of the shared knowledge — must diff empty
  #    between two workspaces of the same owner.
  echo "== FINGERPRINT =="
  CFG="$CFG" node -e '
    const fs = require("fs"), path = process.env.CFG;
    const read = f => { try { return JSON.parse(fs.readFileSync(f, "utf8") || "{}"); } catch { return {}; } };
    const top = read(path + "/.claude.json");
    const settings = read(path + "/settings.json");
    console.log("mcpServers:", Object.keys(top.mcpServers || {}).sort().join(",") || "<none>");
    console.log("permissions.defaultMode:", (settings.permissions || {}).defaultMode || "<unset>");
    console.log("gsd-core:", fs.existsSync(path + "/gsd-core") ? "present" : "absent");
  '
  # user-level memory + skills inventory (sorted, relative — comparable)
  echo "user CLAUDE.md: $( [ -f "$CFG/CLAUDE.md" ] && sha256sum "$CFG/CLAUDE.md" | cut -c1-16 || echo absent )"
  echo "memory files:"
  find "$CFG/projects" -name 'MEMORY.md' 2>/dev/null | sed "s|^$CFG/||" | sort | sed 's/^/  /'
  echo "canary: $( [ -f "$SELFTEST/canary.txt" ] && echo seeded || echo not-seeded )"
}

# ── Layer 2: seed a canary fact into shared user-level memory ────────────────
seed() {
  echo "== SEED =="
  mkdir -p "$SELFTEST"
  if [ ! -f "$SELFTEST/canary.txt" ]; then
    printf 'zephyr-%s\n' "$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')" > "$SELFTEST/canary.txt"
    local_ "generated new canary"
  fi
  local tok; tok=$(cat "$SELFTEST/canary.txt")
  local cm="$CFG/CLAUDE.md"
  if ! grep -qF "$MARKER" "$cm" 2>/dev/null; then
    cat >> "$cm" <<EOF

$MARKER
## Team facts (share self-test)
The internal build mnemonic is "$tok". When asked for the internal build
mnemonic, answer with exactly this value.
EOF
    pass "canary appended to shared user CLAUDE.md"
  else
    pass "canary already present in shared user CLAUDE.md"
  fi
  local_ "canary token: $tok"
}

# ── Layer 2: A/B knowledge-retrieval test ─────────────────────────────────────
# Arm A: claude with the shared config → must answer with the canary.
# Arm B (control): identical config copy with the canary stripped → must NOT.
# The A-minus-B delta is the measured contribution of the shared knowledge.
knowledge() {
  echo "== KNOWLEDGE (trials=$TRIALS) =="
  if ! command -v claude >/dev/null 2>&1; then fail "claude CLI not found"; return; fi
  if [ ! -f "$SELFTEST/canary.txt" ]; then fail "no canary — run 'seed' first"; return; fi
  local tok q a_hits=0 b_hits=0 ans
  tok=$(cat "$SELFTEST/canary.txt")
  q="What is the internal build mnemonic? Reply with only the mnemonic."

  # control config: full copy of shared config minus the canary block
  local ctl; ctl=$(mktemp -d)
  cp -a "$CFG/." "$ctl/" 2>/dev/null
  [ -f "$ctl/CLAUDE.md" ] && sed -i "/$MARKER/,\$d" "$ctl/CLAUDE.md"

  for i in $(seq 1 "$TRIALS"); do
    ans=$(cd /tmp && timeout "$CLAUDE_TIMEOUT" claude -p "$q" 2>/dev/null)
    case "$ans" in *"$tok"*) a_hits=$((a_hits+1));; esac
    ans=$(cd /tmp && CLAUDE_CONFIG_DIR="$ctl" timeout "$CLAUDE_TIMEOUT" claude -p "$q" 2>/dev/null)
    case "$ans" in *"$tok"*) b_hits=$((b_hits+1));; esac
    local_ "trial $i done"
  done
  rm -rf "$ctl"

  echo "shared-config recall:  $a_hits/$TRIALS"
  echo "control (no canary):   $b_hits/$TRIALS"
  [ "$a_hits" -eq "$TRIALS" ] \
    && pass "shared knowledge retrieved in every trial" \
    || fail "shared knowledge NOT reliably retrieved ($a_hits/$TRIALS)"
  [ "$b_hits" -eq 0 ] \
    && pass "control never knew the canary (no leakage — delta is attributable to sharing)" \
    || fail "control answered with canary $b_hits times — test invalid (fact leaked outside shared memory?)"
}

# ── MemPalace probe: is it installed, initialized, and does memory travel? ────
# Evidence layers:
#   1. CLI + MCP registration present (template wiring reached this workspace)
#   2. palace initialized (~/.mempalace exists)
#   3. cross-workspace canary: seed a drawer here, search for a peer's drawer.
#      NOTE: ~/.mempalace lives on the PER-WORKSPACE home volume, not the shared
#      ~/.claude-shared volume — cross-visibility is EXPECTED TO FAIL today.
#      This probe measures that gap; it turns PASS if the palace is ever moved
#      onto the shared volume.
mempalace_probe() {
  echo "== MEMPALACE =="
  if command -v mempalace >/dev/null 2>&1; then
    pass "mempalace CLI present ($(command -v mempalace))"
  else
    fail "mempalace CLI not installed — capability can never fire here"
    return
  fi

  CFGJSON="$CFG/.claude.json" node -e '
    const c = JSON.parse(require("fs").readFileSync(process.env.CFGJSON, "utf8") || "{}");
    process.exit((c.mcpServers || {}).mempalace ? 0 : 1);
  ' 2>/dev/null \
    && pass "mempalace MCP server registered in shared Claude config" \
    || fail "mempalace MCP server NOT registered"

  if [ -d "$HOME/.mempalace" ]; then
    pass "palace initialized (~/.mempalace exists)"
  else
    fail "palace never initialized — mempalace init did not run or failed"
    return
  fi

  # is the palace on the shared volume or the per-workspace home volume?
  if [ -L "$HOME/.mempalace" ] && [ "$(readlink -f "$HOME/.mempalace")" = "$SHARED/mempalace" ]; then
    pass "palace lives on the SHARED volume — cross-workspace memory possible"
  else
    local_ "palace is per-workspace (home volume) — captures do NOT cross workspaces"
  fi

  # cross-workspace canary via search (mirrors the nonce test, semantic layer)
  local mtok="palace-canary-$WS"
  mkdir -p "$SELFTEST"
  echo "$mtok" >> "$SELFTEST/palace-canaries.txt"
  printf 'MemPalace self-test drawer from %s: token %s\n' "$WS" "$mtok" \
    > "/tmp/palace-canary-$WS.md"
  mempalace mine "/tmp/palace-canary-$WS.md" >/dev/null 2>&1 \
    || local_ "mempalace mine failed (non-fatal — check CLI version/flags)"
  local peer_hits=0 peer_total=0 t
  while read -r t; do
    [ "$t" = "$mtok" ] && continue
    peer_total=$((peer_total+1))
    mempalace search "$t" 2>/dev/null | grep -q "$t" && peer_hits=$((peer_hits+1))
  done < "$SELFTEST/palace-canaries.txt"
  local_ "peer palace canaries found: $peer_hits/$peer_total"
  if [ "$peer_total" -eq 0 ]; then
    local_ "no peer canaries yet — run this in a second workspace to measure sharing"
  elif [ "$peer_hits" -gt 0 ]; then
    pass "MemPalace memory crosses workspaces"
  else
    local_ "EXPECTED GAP: peer canaries not retrievable — palace is per-workspace"
  fi
}

cleanup() {
  echo "== CLEANUP =="
  [ -f "$CFG/CLAUDE.md" ] && sed -i "/$MARKER/,\$d" "$CFG/CLAUDE.md" && pass "canary removed from CLAUDE.md"
  rm -rf "$SELFTEST" && pass "selftest artifacts removed"
}

case "${1:-all}" in
  plumbing)  plumbing ;;
  seed)      seed ;;
  knowledge) knowledge ;;
  mempalace) mempalace_probe ;;
  cleanup)   cleanup ;;
  all)       plumbing; seed; knowledge; mempalace_probe ;;
  *) echo "usage: $0 {plumbing|seed|knowledge|mempalace|all|cleanup}"; exit 2 ;;
esac

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
