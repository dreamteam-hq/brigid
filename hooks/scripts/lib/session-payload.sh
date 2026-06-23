#!/usr/bin/env bash
#
# Shared payload generator for SessionStart / PreCompact / PostCompact hooks.
#
# Sourced by hooks/scripts/{session-start,pre-compact,post-compact}.sh.
#
# Exposes one function:
#   emit_session_payload <event-name>
#
# The function reads a Claude Code hook JSON payload from stdin (already
# captured by the caller), resolves the configured agent identity from
# .claude/settings.json or the session input, reads the project's
# foundational-facts block out of CLAUDE.md if present, walks the
# session_lifecycle: block in the trigger map, and emits a JSON object
# of the form:
#
#   {"hookSpecificOutput": {"hookEventName": "<event>", "additionalContext": "..."}}
#
# All failure modes degrade to exit 0 with empty stdout — hook failure must
# never block the user.
#
# Spec: dreamteam-hq/docent:docs/specs/session-lifecycle-hooks.md
# Pattern reference: dreamteam-hq/iris:docs/designs/wave-b-iris.md
#
# Bash 3.2 compatible (macOS default /bin/bash). No `declare -A`, no
# `mapfile`, no `${var,,}`.

LOG_TAG="[dt-brigid session-lifecycle]"

# Resolve plugin root. CLAUDE_PLUGIN_ROOT is set by Claude Code when
# invoking hooks; fall back to walking up from the caller for local tests.
_resolve_plugin_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf '%s' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi
  # Walk up from this library file: lib -> scripts -> hooks -> plugin root.
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  (cd "$lib_dir/../../.." && pwd)
}

# Read .claude/settings.json "agent" field from a given cwd.
# Echoes the agent id (e.g. "dt-brigid:brigid") or empty.
_read_configured_agent() {
  local cwd="$1"
  local settings="$cwd/.claude/settings.json"
  if [ ! -f "$settings" ]; then
    return 0
  fi
  jq -r '.agent // empty' "$settings" 2>/dev/null || true
}

# Extract the foundational-facts block from a markdown file given a marker
# heading. Reads from start-of-marker until next H2 (^## ) or EOF, strips
# the marker line itself, trims trailing blank lines.
# Args: <markdown-file> <marker-heading>
# Echoes the body content; empty if file missing, marker missing, or body
# empty after stripping.
_extract_facts_block() {
  local file="$1"
  local marker="$2"
  if [ ! -f "$file" ] || [ -z "$marker" ]; then
    return 0
  fi
  python3 - "$file" "$marker" <<'PY' 2>/dev/null || true
import sys
path, marker = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
except Exception:
    sys.exit(0)
body = []
in_block = False
for line in lines:
    if not in_block:
        if line.rstrip() == marker:
            in_block = True
        continue
    # End the block at the next H2-or-higher heading.
    stripped = line.lstrip()
    if stripped.startswith("## ") and not stripped.startswith("### "):
        break
    body.append(line)
text = "".join(body).strip()
if text:
    print(text)
PY
}

# Parse the trigger map's session_lifecycle: block.
# Emits a JSON object on stdout:
#   {"identity": "...", "first_reach_csv": "...", "facts_source": "...", "facts_marker": "..."}
# Empty stdout if parse fails or block is missing.
# Args: <trigger-yaml-path>
_read_session_lifecycle() {
  local trigger_file="$1"
  if [ ! -f "$trigger_file" ]; then
    return 0
  fi
  python3 - "$trigger_file" <<'PY' 2>/dev/null || true
import json, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("[dt-brigid session-lifecycle] warning: PyYAML not installed; cannot parse trigger map\n")
    sys.exit(0)
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception as exc:
    sys.stderr.write("[dt-brigid session-lifecycle] warning: failed to parse %s: %s\n" % (path, exc))
    sys.exit(0)
sl = data.get("session_lifecycle")
if not isinstance(sl, dict):
    sys.stderr.write("[dt-brigid session-lifecycle] warning: trigger map missing session_lifecycle: block\n")
    sys.exit(0)
identity = (sl.get("identity") or "").strip()
first_reach = sl.get("first_reach") or []
if not isinstance(first_reach, list):
    first_reach = []
first_reach_csv = ", ".join(str(s) for s in first_reach if s)
facts_source = sl.get("facts_source") or ""
facts_marker = sl.get("facts_marker") or ""
sys.stdout.write(json.dumps({
    "identity": identity,
    "first_reach_csv": first_reach_csv,
    "facts_source": str(facts_source),
    "facts_marker": str(facts_marker),
}))
PY
}

# Build the additionalContext text.
# Args: <event> <agent_id> <identity> <first_reach_csv> <facts_body>
_compose_context() {
  local event="$1"
  local agent_id="$2"
  local identity="$3"
  local first_reach_csv="$4"
  local facts_body="$5"

  local header
  case "$event" in
    SessionStart) header="Brigid session-start." ;;
    PreCompact)   header="Brigid pre-compact." ;;
    PostCompact)  header="Brigid post-compact." ;;
    *)            header="Brigid session-lifecycle ($event)." ;;
  esac

  # Compose. Use printf to preserve newlines inside identity / facts_body.
  printf '%s' "$header"
  if [ -n "$agent_id" ]; then
    printf ' Configured agent: %s.' "$agent_id"
  fi
  if [ -n "$identity" ]; then
    printf '\n\n%s' "$identity"
  fi
  if [ -n "$first_reach_csv" ]; then
    printf '\n\nFirst-reach: %s.' "$first_reach_csv"
  fi
  if [ -n "$facts_body" ]; then
    printf '\n\nFoundational facts (non-negotiable):\n\n%s' "$facts_body"
    printf '\n\nReload these on every turn; do not let compaction reduce them to a single index line.'
  fi
}

# Main entry point.
# Args: <event-name>  (SessionStart | PreCompact | PostCompact)
# Reads stdin JSON, writes a JSON hook output to stdout. Exit 0 always.
emit_session_payload() {
  local event="$1"
  if [ -z "$event" ]; then
    echo "$LOG_TAG warning: emit_session_payload called without event name" >&2
    return 0
  fi

  # Capture stdin. If empty, treat as no-op.
  local stdin_payload
  stdin_payload="$(cat || true)"

  # Parse cwd + agent from stdin. jq tolerates missing fields.
  local cwd_in agent_in
  if [ -n "$stdin_payload" ]; then
    if ! printf '%s' "$stdin_payload" | jq -e . >/dev/null 2>&1; then
      echo "$LOG_TAG warning: stdin is not valid JSON; skipping $event" >&2
      return 0
    fi
    cwd_in="$(printf '%s' "$stdin_payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
    agent_in="$(printf '%s' "$stdin_payload" | jq -r '.agent // empty' 2>/dev/null || true)"
  fi

  # Fall back to PWD if cwd absent.
  local cwd="${cwd_in:-$PWD}"

  # Resolve configured agent: settings.json first, then session input.
  local agent_id
  agent_id="$(_read_configured_agent "$cwd")"
  if [ -z "$agent_id" ]; then
    agent_id="$agent_in"
  fi

  # If no configured agent, exit silently per spec.
  if [ -z "$agent_id" ]; then
    return 0
  fi

  local plugin_root
  plugin_root="$(_resolve_plugin_root)"
  local trigger_file="$plugin_root/hooks/triggers/dt-brigid.yaml"

  # Parse session_lifecycle: JSON-encoded identity / first_reach_csv / facts_source / facts_marker.
  local sl_json
  sl_json="$(_read_session_lifecycle "$trigger_file")"
  if [ -z "$sl_json" ]; then
    # Warning already on stderr from helper. Exit silently.
    return 0
  fi

  local identity first_reach facts_source facts_marker
  identity="$(printf '%s' "$sl_json" | jq -r '.identity // ""')"
  first_reach="$(printf '%s' "$sl_json" | jq -r '.first_reach_csv // ""')"
  facts_source="$(printf '%s' "$sl_json" | jq -r '.facts_source // ""')"
  facts_marker="$(printf '%s' "$sl_json" | jq -r '.facts_marker // ""')"

  # Resolve facts file path relative to cwd.
  local facts_body=""
  if [ -n "$facts_source" ] && [ -n "$facts_marker" ]; then
    local facts_path="$facts_source"
    case "$facts_path" in
      /*) ;;  # absolute, leave alone
      *) facts_path="$cwd/$facts_path" ;;
    esac
    facts_body="$(_extract_facts_block "$facts_path" "$facts_marker")"
  fi

  # Build context text.
  local context_text
  context_text="$(_compose_context "$event" "$agent_id" "$identity" "$first_reach" "$facts_body")"

  if [ -z "$context_text" ]; then
    return 0
  fi

  # Emit JSON. jq handles escaping for arbitrary text (newlines, quotes).
  jq -n \
    --arg event "$event" \
    --arg ctx "$context_text" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $ctx}}'
}
