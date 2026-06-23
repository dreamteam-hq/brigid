#!/usr/bin/env bash
#
# SessionStart hook for dt-brigid.
#
# Fires on fresh session, resume, and /clear (J.4 confirmed). Surfaces the
# configured agent identity + first-reach skills + foundational facts from
# the project's CLAUDE.md as a soft cue. Exit 0 always.
#
# Spec: dreamteam-hq/docent:docs/specs/session-lifecycle-hooks.md
# Pattern: dreamteam-hq/iris:docs/designs/wave-b-iris.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/session-payload.sh
. "$SCRIPT_DIR/lib/session-payload.sh"

emit_session_payload "SessionStart"
exit 0
