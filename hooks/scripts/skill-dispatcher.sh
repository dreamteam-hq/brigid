#!/usr/bin/env bash
#
# UserPromptSubmit skill dispatcher for dt-brigid.
#
# Reads a Claude Code hook JSON payload from stdin, extracts the user's prompt,
# walks the trigger map at ${CLAUDE_PLUGIN_ROOT}/hooks/triggers/dt-brigid.yaml,
# and emits a non-blocking system message recommending which skills to load
# when a rule's pattern matches.
#
# First match wins. Exits 0 always — hook failures must never block the user.
#
# Spec: dreamteam-hq/docent:docs/specs/userpromptsubmit-skill-dispatcher.md
# Pattern: dreamteam-hq/iris:docs/designs/wave-b-iris.md
#
# Bash 3.2 compatible (macOS default /bin/bash). No `declare -A`, no `mapfile`,
# no `${var,,}`. Tested under /bin/bash explicitly.

set -e

LOG_TAG="[dt-brigid skill-dispatcher]"

# Resolve plugin root. CLAUDE_PLUGIN_ROOT is set by Claude Code when invoking
# hooks; fall back to walking up from this script's directory for local tests.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

TRIGGER_FILE="$PLUGIN_ROOT/hooks/triggers/dt-brigid.yaml"

# Read stdin into a variable. Use `cat` so an empty stdin yields an empty string
# rather than hanging.
STDIN_PAYLOAD="$(cat || true)"

if [ -z "$STDIN_PAYLOAD" ]; then
  # Empty stdin → nothing to do. Not an error.
  exit 0
fi

# Extract the prompt. If jq fails (malformed JSON), warn and exit 0.
PROMPT="$(printf '%s' "$STDIN_PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null || true)"

if [ -z "$PROMPT" ]; then
  # Could be malformed JSON or a payload without `prompt`. Sniff to decide
  # whether to warn.
  if ! printf '%s' "$STDIN_PAYLOAD" | jq -e . >/dev/null 2>&1; then
    echo "$LOG_TAG warning: stdin is not valid JSON; skipping dispatch" >&2
  fi
  exit 0
fi

if [ ! -f "$TRIGGER_FILE" ]; then
  echo "$LOG_TAG warning: trigger file not found at $TRIGGER_FILE" >&2
  exit 0
fi

# Parse the YAML trigger map into a tab-separated stream of rules:
#   id<TAB>pattern<TAB>skill_csv<TAB>hint
# One line per rule, in source order. Python 3 + PyYAML is the portable choice
# (PyYAML ships with most Python installs; yq is not universal).
RULES_TSV="$(python3 - "$TRIGGER_FILE" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write("[dt-brigid skill-dispatcher] warning: PyYAML not installed; cannot parse trigger map\n")
    sys.exit(0)

path = sys.argv[1]
try:
    with open(path, "r") as fh:
        data = yaml.safe_load(fh) or {}
except Exception as e:
    sys.stderr.write("[dt-brigid skill-dispatcher] warning: failed to parse %s: %s\n" % (path, e))
    sys.exit(0)

rules = data.get("rules") or []
for r in rules:
    rid = (r.get("id") or "").replace("\t", " ").replace("\n", " ")
    pat = (r.get("pattern") or "").replace("\t", " ").replace("\n", " ")
    skills = r.get("skills") or []
    if isinstance(skills, list):
        skills_csv = ", ".join(str(s).replace("\t", " ").replace("\n", " ") for s in skills)
    else:
        skills_csv = str(skills).replace("\t", " ").replace("\n", " ")
    hint = (r.get("hint") or "").replace("\t", " ").replace("\n", " ")
    if not rid or not pat:
        continue
    print("%s\t%s\t%s\t%s" % (rid, pat, skills_csv, hint))
PY
)"

if [ -z "$RULES_TSV" ]; then
  # No rules parsed (missing PyYAML, malformed YAML, or empty rules list).
  # Stderr warning, if any, already emitted by Python. Exit clean.
  exit 0
fi

# Walk rules in order. First match wins.
# IFS=$'\t' and read -r split on tabs; we accept patterns that may contain
# regex metacharacters as-is.
OLD_IFS="$IFS"
while IFS=$'\t' read -r RULE_ID PATTERN SKILLS HINT; do
  [ -z "$RULE_ID" ] && continue
  [ -z "$PATTERN" ] && continue

  # Strip a leading (?i) — BSD grep treats it as literal but we use -i anyway,
  # so this keeps the regex clean and portable.
  CLEAN_PATTERN="${PATTERN#'(?i)'}"

  # Case-insensitive POSIX-extended regex match.
  if printf '%s' "$PROMPT" | grep -E -i -q -- "$CLEAN_PATTERN" 2>/dev/null; then
    IFS="$OLD_IFS"
    # Build the system message.
    if [ -n "$HINT" ]; then
      MSG="Brigid: $RULE_ID detected. Load: $SKILLS. $HINT"
    else
      MSG="Brigid: $RULE_ID detected. Load: $SKILLS."
    fi

    # Emit JSON via jq so escaping is correct for arbitrary text.
    jq -n --arg msg "$MSG" \
      '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
    exit 0
  fi
done <<EOF
$RULES_TSV
EOF
IFS="$OLD_IFS"

# No rule matched. Stay silent.
exit 0
