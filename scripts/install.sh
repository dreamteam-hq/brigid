#!/usr/bin/env bash
# install.sh — install Brigid game dev agent into a project
#
# Usage:
#   cd ~/gh/me/dev-cm
#   bash ~/gh/dreamteam-hq/brigid/scripts/install.sh
#
# Flags:
#   --dev [path]   Use local marketplace directory
#   --no-brain     Skip brain bootstrap
#
# Idempotent — safe to run multiple times.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_YAML="${SCRIPT_DIR}/../agent.yaml"
source "${HOME}/gh/dreamteam-hq/brain/scripts/install-lib.sh"
agent_install "$AGENT_YAML" "$@"
