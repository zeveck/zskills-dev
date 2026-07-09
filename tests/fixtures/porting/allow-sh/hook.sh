#!/usr/bin/env bash
# Ported hook — hash-form allow-marker fixture (an HTML comment would be a
# syntax error in a shell file, so the marker dispatches to the # form).
set -euo pipefail
# codex-port-allow: plugin-root reason: assumptions manifest confirms the compat alias (probe plugins.env.claude-plugin-root-alias passed)
exec bash "${CLAUDE_PLUGIN_ROOT}/hooks/example.sh"
