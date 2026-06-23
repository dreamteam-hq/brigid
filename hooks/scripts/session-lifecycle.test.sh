#!/usr/bin/env bash
#
# Regression tests for session-lifecycle handlers:
#   hooks/scripts/{session-start,pre-compact,post-compact}.sh
#   hooks/scripts/lib/session-payload.sh
#
# Mirrors the test-case table in dreamteam-hq/docent:docs/specs/session-lifecycle-hooks.md.
# Re-namespaced from dt-docent original for dt-brigid.
#
# Usage: bash hooks/scripts/session-lifecycle.test.sh
# Exits non-zero on any failed assertion.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SESSION_START="$SCRIPT_DIR/session-start.sh"
PRE_COMPACT="$SCRIPT_DIR/pre-compact.sh"
POST_COMPACT="$SCRIPT_DIR/post-compact.sh"

for f in "$SESSION_START" "$PRE_COMPACT" "$POST_COMPACT"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: handler not found at $f" >&2
    exit 2
  fi
done

PASS=0
FAIL=0
FAILED_NAMES=""

# Set up a temporary "project" with .claude/settings.json + CLAUDE.md
TMP_PROJ="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJ"' EXIT

mkdir -p "$TMP_PROJ/.claude"
cat >"$TMP_PROJ/.claude/settings.json" <<'JSON'
{
  "agent": "dt-brigid:brigid"
}
JSON

cat >"$TMP_PROJ/CLAUDE.md" <<'MD'
# test project

## Some other heading

irrelevant body

## Foundational Facts (Non-Negotiable)

- ObservableGodot tier boundaries are inviolable — C++ ↔ managed via C-ABI only.
- No AI artifacts in KervanaLLC repos — branches + draft PRs only, no pushing, no Co-Authored-By.
- Use extension_api.4.6.1.json for API signatures, not docs or memory.

## Trailing heading

trailing body
MD

# Project that has settings but NO facts block.
TMP_NO_FACTS="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJ" "$TMP_NO_FACTS"' EXIT
mkdir -p "$TMP_NO_FACTS/.claude"
cat >"$TMP_NO_FACTS/.claude/settings.json" <<'JSON'
{ "agent": "dt-brigid:brigid" }
JSON
cat >"$TMP_NO_FACTS/CLAUDE.md" <<'MD'
# bare project
No facts block here.
MD

# Project that has settings + CLAUDE.md but facts block is empty.
TMP_EMPTY_FACTS="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJ" "$TMP_NO_FACTS" "$TMP_EMPTY_FACTS"' EXIT
mkdir -p "$TMP_EMPTY_FACTS/.claude"
cat >"$TMP_EMPTY_FACTS/.claude/settings.json" <<'JSON'
{ "agent": "dt-brigid:brigid" }
JSON
cat >"$TMP_EMPTY_FACTS/CLAUDE.md" <<'MD'
# project

## Foundational Facts (Non-Negotiable)

## Next heading
body
MD

# Project with NO configured agent.
TMP_NO_AGENT="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJ" "$TMP_NO_FACTS" "$TMP_EMPTY_FACTS" "$TMP_NO_AGENT"' EXIT

# ── helpers ──────────────────────────────────────────────────────────
_run() {
  local handler="$1"
  local payload="$2"
  printf '%s' "$payload" | bash "$handler"
}

_run_capture() {
  local handler="$1"
  local payload="$2"
  local tmp_err
  tmp_err="$(mktemp)"
  STDOUT="$(printf '%s' "$payload" | bash "$handler" 2>"$tmp_err")"
  RC=$?
  STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_err"
}

_pass() {
  PASS=$((PASS + 1))
  printf "  PASS  %s\n" "$1"
}

_fail() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES="$FAILED_NAMES
    - $1
      stdout: $STDOUT
      stderr: $STDERR
      rc: $RC"
  printf "  FAIL  %s\n" "$1"
  printf "        stdout: %s\n" "$STDOUT"
  printf "        stderr: %s\n" "$STDERR"
  printf "        rc: %d\n" "$RC"
}

# Assert JSON output with hookEventName == <event> and additionalContext
# contains all of the given substrings.
assert_payload_contains() {
  local name="$1"; shift
  local handler="$1"; shift
  local cwd="$1"; shift
  local event="$1"; shift

  local payload
  payload="$(jq -n --arg cwd "$cwd" '{cwd: $cwd, session_id: "test"}')"

  _run_capture "$handler" "$payload"

  if [ "$RC" -ne 0 ]; then
    _fail "$name (non-zero exit $RC)"
    return
  fi

  if ! printf '%s' "$STDOUT" | jq -e ".hookSpecificOutput.hookEventName == \"$event\"" >/dev/null 2>&1; then
    _fail "$name (hookEventName mismatch)"
    return
  fi

  local ctx
  ctx="$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  for needle in "$@"; do
    if ! printf '%s' "$ctx" | grep -F -q -- "$needle"; then
      _fail "$name (missing substring: $needle)"
      return
    fi
  done

  _pass "$name"
}

# Assert empty stdout and exit 0.
assert_empty() {
  local name="$1"; shift
  local handler="$1"; shift
  local payload="$1"; shift

  _run_capture "$handler" "$payload"
  if [ "$RC" -eq 0 ] && [ -z "$STDOUT" ]; then
    _pass "$name"
  else
    _fail "$name (expected empty stdout, exit 0)"
  fi
}

# Assert empty stdout, exit 0, and stderr warning marker present.
assert_warn() {
  local name="$1"; shift
  local handler="$1"; shift
  local payload="$1"; shift

  _run_capture "$handler" "$payload"
  if [ "$RC" -eq 0 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | grep -q "\[dt-brigid session-lifecycle\]"; then
    _pass "$name"
  else
    _fail "$name (expected empty stdout, exit 0, stderr warning)"
  fi
}

echo "Running session-lifecycle regression tests (dt-brigid)..."
echo

# ── happy-path: configured agent + facts block ──────────────────────
assert_payload_contains "SessionStart: identity + facts emitted" \
  "$SESSION_START" "$TMP_PROJ" "SessionStart" \
  "dt-brigid:brigid" \
  "ObservableGodot tier boundaries are inviolable" \
  "Reload these on every turn"

assert_payload_contains "PreCompact: identity + facts emitted" \
  "$PRE_COMPACT" "$TMP_PROJ" "PreCompact" \
  "dt-brigid:brigid" \
  "ObservableGodot tier boundaries are inviolable" \
  "Reload these on every turn"

assert_payload_contains "PostCompact: identity + facts emitted" \
  "$POST_COMPACT" "$TMP_PROJ" "PostCompact" \
  "dt-brigid:brigid" \
  "ObservableGodot tier boundaries are inviolable" \
  "Reload these on every turn"

# ── no configured agent ─────────────────────────────────────────────
PAYLOAD_NO_AGENT="$(jq -n --arg cwd "$TMP_NO_AGENT" '{cwd: $cwd, session_id: "test"}')"
assert_empty "SessionStart: no configured agent → silent" \
  "$SESSION_START" "$PAYLOAD_NO_AGENT"
assert_empty "PreCompact: no configured agent → silent" \
  "$PRE_COMPACT" "$PAYLOAD_NO_AGENT"
assert_empty "PostCompact: no configured agent → silent" \
  "$POST_COMPACT" "$PAYLOAD_NO_AGENT"

# ── configured agent, no CLAUDE.md facts block ──────────────────────
assert_payload_contains "SessionStart: identity + first-reach only when no facts block" \
  "$SESSION_START" "$TMP_NO_FACTS" "SessionStart" \
  "dt-brigid:brigid" \
  "First-reach:"
# And make sure the trailing "Reload these on every turn" is NOT present.
PAYLOAD_NO_FACTS="$(jq -n --arg cwd "$TMP_NO_FACTS" '{cwd: $cwd, session_id: "test"}')"
_run_capture "$SESSION_START" "$PAYLOAD_NO_FACTS"
ctx_check="$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""')"
if printf '%s' "$ctx_check" | grep -q "Reload these on every turn"; then
  _fail "SessionStart: no-facts payload erroneously includes 'Reload these on every turn'"
else
  _pass "SessionStart: no-facts payload omits 'Reload these on every turn'"
fi

# ── facts file present but block empty ──────────────────────────────
assert_payload_contains "SessionStart: empty facts block treated as missing" \
  "$SESSION_START" "$TMP_EMPTY_FACTS" "SessionStart" \
  "dt-brigid:brigid" \
  "First-reach:"
PAYLOAD_EMPTY_FACTS="$(jq -n --arg cwd "$TMP_EMPTY_FACTS" '{cwd: $cwd, session_id: "test"}')"
_run_capture "$SESSION_START" "$PAYLOAD_EMPTY_FACTS"
ctx_check="$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""')"
if printf '%s' "$ctx_check" | grep -q "Foundational facts (non-negotiable)"; then
  _fail "SessionStart: empty-facts payload erroneously includes facts header"
else
  _pass "SessionStart: empty-facts payload omits facts header"
fi

# ── malformed JSON stdin ────────────────────────────────────────────
assert_warn "SessionStart: malformed JSON stdin → warning + exit 0" \
  "$SESSION_START" "not json"
assert_warn "PreCompact: malformed JSON stdin → warning + exit 0" \
  "$PRE_COMPACT" "not json"
assert_warn "PostCompact: malformed JSON stdin → warning + exit 0" \
  "$POST_COMPACT" "not json"

# ── empty stdin (no payload at all) ─────────────────────────────────
# With no stdin, cwd defaults to PWD. Whether anything is emitted depends on
# whether PWD has a configured agent. The contract is just "exit 0 cleanly,
# no crash." We assert exit 0; stdout may be empty or a payload.
_run_capture "$SESSION_START" ""
if [ "$RC" -eq 0 ]; then
  _pass "SessionStart: empty stdin → exit 0"
else
  _fail "SessionStart: empty stdin → non-zero exit"
fi

# ── agent from stdin (not settings.json) ────────────────────────────
PAYLOAD_AGENT_IN_STDIN="$(jq -n --arg cwd "$TMP_NO_AGENT" '{cwd: $cwd, session_id: "test", agent: "dt-brigid:brigid"}')"
_run_capture "$SESSION_START" "$PAYLOAD_AGENT_IN_STDIN"
if [ "$RC" -eq 0 ] && printf '%s' "$STDOUT" | jq -e '.hookSpecificOutput.additionalContext | contains("dt-brigid:brigid")' >/dev/null 2>&1; then
  _pass "SessionStart: agent from stdin (no settings.json) emits payload"
else
  _fail "SessionStart: agent from stdin (no settings.json) emits payload"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf "Failures:%s\n" "$FAILED_NAMES"
  exit 1
fi
exit 0
