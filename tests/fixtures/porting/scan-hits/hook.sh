#!/usr/bin/env bash
# Non-markdown scan surface for the known-hit fixture (no fences here — every
# line is scanned with the code-context pattern set).
SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT}/skills"
FALLBACK="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
echo "$SKILLS_ROOT $FALLBACK"
