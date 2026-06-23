#!/usr/bin/env bash
#
# PostCompact hook for dt-brigid.
#
# Fires after context compaction completes. Re-surfaces agent identity +
# foundational facts so they survive into the post-compaction window.
# Exit 0 always.
#
# Spec: dreamteam-hq/docent:docs/specs/session-lifecycle-hooks.md
# Pattern: dreamteam-hq/iris:docs/designs/wave-b-iris.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/session-payload.sh
. "$SCRIPT_DIR/lib/session-payload.sh"

emit_session_payload "PostCompact"
exit 0
