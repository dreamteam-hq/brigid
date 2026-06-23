#!/usr/bin/env bash
#
# PreCompact hook for dt-brigid.
#
# Fires before context compaction. Re-surfaces agent identity + foundational
# facts to prevent them from being compacted away. Exit 0 always.
#
# Spec: dreamteam-hq/docent:docs/specs/session-lifecycle-hooks.md
# Pattern: dreamteam-hq/iris:docs/designs/wave-b-iris.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/session-payload.sh
. "$SCRIPT_DIR/lib/session-payload.sh"

emit_session_payload "PreCompact"
exit 0
