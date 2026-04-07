#!/usr/bin/env bash
# install.sh — install Brigid game dev agent into a project
#
# Usage:
#   cd ~/gh/me/dev-cm
#   bash ~/gh/dreamteam-hq/brigid/scripts/install.sh
#
#   # With brain prefix for project-scoped databases:
#   bash ~/gh/dreamteam-hq/brigid/scripts/install.sh --brain-prefix cm
#
#   # Dev mode (local marketplace for fast iteration):
#   bash ~/gh/dreamteam-hq/brigid/scripts/install.sh --dev [/path/to/plugins]
#
#   # Skip brain bootstrap (plugin-only install):
#   bash ~/gh/dreamteam-hq/brigid/scripts/install.sh --no-brain
#
# Idempotent — safe to run multiple times.
set -euo pipefail

# ── Parse args ───────────────────────────────────────────────
DEV_MODE=false
DEV_PATH=""
SKIP_BRAIN=false
BRAIN_PREFIX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      DEV_MODE=true
      if [[ "${2:-}" && ! "${2:-}" == --* ]]; then
        DEV_PATH="$2"; shift
      fi
      shift ;;
    --no-brain)
      SKIP_BRAIN=true
      shift ;;
    --brain-prefix)
      BRAIN_PREFIX="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Config ───────────────────────────────────────────────────
MARKETPLACE_NAME="dreamteam-hq"
PLUGINS=("dt-brain" "dt-brigid")
SCOPE="project"
AGENT="dt-brigid:brigid"
SETTINGS=".claude/settings.json"

if $DEV_MODE; then
  MARKETPLACE_SOURCE="${DEV_PATH:-$HOME/gh/dreamteam-hq/plugins}"
  if [[ ! -d "$MARKETPLACE_SOURCE" ]]; then
    echo "✘ dev marketplace not found: $MARKETPLACE_SOURCE" >&2
    echo "  clone it: git clone git@github.com:dreamteam-hq/plugins.git $MARKETPLACE_SOURCE" >&2
    exit 1
  fi
  echo "🔧 dev mode — marketplace: $MARKETPLACE_SOURCE"
else
  MARKETPLACE_SOURCE="dreamteam-hq/plugins"
fi

# ── Helpers ──────────────────────────────────────────────────
require() { command -v "$1" &>/dev/null || { echo "✘ $1 not found${2:+ ($2)}" >&2; exit 1; }; }

install_plugin() {
  local name="$1"
  if claude plugin list 2>/dev/null | grep -q "${name}@${MARKETPLACE_NAME}"; then
    echo "  ✓ ${name} — updating"
    claude plugin update "${name}@${MARKETPLACE_NAME}" --scope "$SCOPE" 2>/dev/null || true
  else
    echo "  ↓ ${name} — installing"
    claude plugin install "${name}@${MARKETPLACE_NAME}" --scope "$SCOPE"
  fi
  claude plugin enable "${name}@${MARKETPLACE_NAME}" --scope "$SCOPE" 2>/dev/null || true
}

# ── Prerequisites ────────────────────────────────────────────
echo "🔥 Brigid — install"
echo ""
require claude

# ── Marketplace ──────────────────────────────────────────────
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  echo "✓ marketplace: ${MARKETPLACE_NAME}"
  claude plugin marketplace update "$MARKETPLACE_NAME" 2>/dev/null || true
else
  echo "↓ adding marketplace: ${MARKETPLACE_SOURCE}"
  claude plugin marketplace add "$MARKETPLACE_SOURCE" --scope project
fi

# ── Plugins ──────────────────────────────────────────────────
echo ""
for p in "${PLUGINS[@]}"; do install_plugin "$p"; done

# ── Default Agent ────────────────────────────────────────────
mkdir -p .claude
echo ""
python3 - "$SETTINGS" "$AGENT" <<'PY'
import json, sys, os
path, desired = sys.argv[1], sys.argv[2]
settings = json.load(open(path)) if os.path.exists(path) else {}
current = settings.get("agent")
if current == desired:
    print(f"✓ agent: {desired}")
elif current:
    print(f"  current agent: {current}")
    print(f"  proposed:      {desired}")
    if input("  overwrite? [y/N] ").strip().lower() != "y":
        print("  skipped"); sys.exit(0)
    settings["agent"] = desired
    json.dump(settings, open(path, "w"), indent=2); open(path, "a").write("\n")
    print(f"✓ agent set to {desired}")
else:
    settings["agent"] = desired
    json.dump(settings, open(path, "w"), indent=2); open(path, "a").write("\n")
    print(f"✓ agent set to {desired}")
PY

# ── Brain Prefix ────────────────────────────────────────────
if [[ -n "$BRAIN_PREFIX" ]]; then
  python3 - "$SETTINGS" "$BRAIN_PREFIX" <<'PREFIX'
import json, os, sys
path, prefix = sys.argv[1], sys.argv[2]
settings = json.load(open(path)) if os.path.exists(path) else {}
settings.setdefault("pluginOptions", {}).setdefault("dt-brain", {})["brain_prefix"] = prefix
json.dump(settings, open(path, "w"), indent=2)
open(path, "a").write("\n")
print(f"✓ brain_prefix = {prefix}")
PREFIX
fi

# ── Brain Bootstrap ─────────────────────────────────────────
if ! $SKIP_BRAIN; then
  echo ""
  echo "── brain bootstrap ──"
  echo "  brain will be provisioned automatically on first session via dt-brain hook"
fi

# ── Diagnostics ──────────────────────────────────────────────
echo ""
claude plugin list 2>/dev/null || true

echo ""
python3 - "$SETTINGS" <<'SUMMARY'
import json, os, sys, pathlib

G="\033[32m"; Y="\033[33m"; C="\033[36m"; D="\033[2m"; B="\033[1m"; R="\033[0m"

home = os.path.expanduser("~")
cwd = os.getcwd().replace(home, "~")
settings_path = sys.argv[1]
settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
agent = settings.get("agent", "(none)")

installed_path = pathlib.Path(home, ".claude/plugins/installed_plugins.json")
if installed_path.exists():
    data = json.load(open(installed_path))
    seen = set()
    rows = []
    for plugin, entries in sorted(data["plugins"].items()):
        for e in entries:
            project = e.get("projectPath", "").replace(home, "~")
            if project == cwd and plugin not in seen:
                seen.add(plugin)
                rows.append((plugin, e.get("version","?"), e.get("scope","?"), e.get("enabled",True), e.get("installPath","")))

    print(f"\n{B}{C}🔥 Brigid — project loadout{R}\n")
    print(f"  {B}{'STATUS':<9} {'PLUGIN':<45} {'VERSION':<15} {'SCOPE'}{R}")
    print(f"  {D}{'─'*9} {'─'*45} {'─'*15} {'─'*8}{R}")
    for name, ver, scope, enabled, ipath in rows:
        s = f"{G}✓ on{R}  " if enabled else f"{Y}✗ off{R} "
        print(f"  {s}  {name:<45} {D}{ver:<15}{R} {scope}")
    print(f"  {D}{'─'*9} {'─'*45} {'─'*15} {'─'*8}{R}")
    print(f"  {D}agent:{R} {G}{agent}{R}\n")

    print(f"  {B}{'PLUGIN':<25} {'AGENTS':<8} {'COMMANDS':<10} {'SKILLS':<8} {'MCP'}{R}")
    print(f"  {D}{'─'*25} {'─'*8} {'─'*10} {'─'*8} {'─'*8}{R}")
    for name, ver, scope, enabled, ipath in rows:
        if not ipath:
            continue
        p = pathlib.Path(ipath)
        agents   = len(list(p.glob("agents/*.md")))   if (p/"agents").exists()   else 0
        commands = len(list(p.glob("commands/*.md")))  if (p/"commands").exists() else 0
        skills   = len([d for d in (p/"skills").iterdir() if d.is_dir() and d.name != "__pycache__"]) if (p/"skills").exists() else 0
        mcp      = len(json.load(open(p/".mcp.json")).get("mcpServers",{})) if (p/".mcp.json").exists() else 0
        short = name.split("@")[0]
        print(f"  {short:<25} {agents:<8} {commands:<10} {skills:<8} {mcp}")
    print(f"  {D}{'─'*25} {'─'*8} {'─'*10} {'─'*8} {'─'*8}{R}")

print(f"\n  {B}Config:{R} {C}{os.path.abspath(settings_path)}{R}")
print(f"  {D}(agent, enabled plugins, project settings){R}\n")
print(f"  Launch: {C}claude{R}")
print(f"  Invoke: {C}/brigid{R}\n")
SUMMARY
