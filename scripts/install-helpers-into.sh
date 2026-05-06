#!/bin/bash
# install-helpers-into.sh — Copy the 4 skill-version helper scripts from
# this zskills source clone (`$PORTABLE/scripts/`) into a consumer repo's
# `scripts/` directory.
#
# These four helpers are dependencies of `block-stale-skill-version.sh`
# (the PreToolUse hook installed by `/update-zskills` Step C). Without
# them, the hook fails-open on every consumer commit, defeating the
# lock-step skill-version enforcement chain. Plan B (Phase 4) introduces
# this driver as the single source of truth invoked by both:
#
#   (a) `/update-zskills` Step D prose (the real install path), and
#   (b) `tests/test-block-stale-skill-version-sandbox.sh` (the integration
#       test that proves end-to-end deny-on-stale-version).
#
# Sharing the code path closes the C2 review finding: tests prove the
# binary works AND the install path works, because they invoke the same
# script. If the driver is broken, both surfaces fail together (visible
# signal, no false greens).
#
# Usage:
#   bash install-helpers-into.sh <consumer-root>
#
# Where <consumer-root> is the destination repo's root directory. The
# driver creates `<consumer-root>/scripts/` if absent (Round 2 N7 — fresh
# installs may have no `scripts/` dir yet) and copies each helper with
# per-file collision policy (Round 2 N3):
#
#   - existing identical → SKIP (logged, no-op)
#   - existing different → COPY (overwrite + chmod +x, logged)
#   - missing            → COPY (logged)
#
# Per Round 2 N6: `.git` in <consumer-root> is NOT required. `cp` to a
# nonexistent destination already errors clearly; the `.git` check was
# defense-against-typo, not load-bearing.
#
# Per Round 2 N5: `${CLAUDE_PROJECT_DIR:-$PWD}` is used to resolve
# `$PORTABLE` so the driver works under `set -u` even when the harness
# env var is unset. The script's own location is the authoritative source
# (it lives at `$PORTABLE/scripts/install-helpers-into.sh`), so we resolve
# `$PORTABLE` from `$0` rather than from environment.
#
# Exit codes:
#   0  all helpers copied or skipped successfully
#   1  bad usage / missing source helper / cp/chmod/mkdir failure

set -eu

if [ $# -ne 1 ]; then
  echo "ERROR: usage: $(basename "$0") <consumer-root>" >&2
  exit 1
fi

CONSUMER_ROOT="$1"

if [ ! -d "$CONSUMER_ROOT" ]; then
  echo "ERROR: not a directory: $CONSUMER_ROOT" >&2
  exit 1
fi

# Resolve $PORTABLE = the zskills source clone root. The driver lives at
# $PORTABLE/scripts/install-helpers-into.sh, so $PORTABLE is two dirs up
# from this file. Use the script's own path rather than $CLAUDE_PROJECT_DIR
# so the driver is invocable from anywhere.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTABLE="$(cd "$SCRIPT_DIR/.." && pwd)"

# The 4 helpers required by block-stale-skill-version.sh.
HELPERS=(
  skill-version-stage-check.sh
  skill-content-hash.sh
  frontmatter-get.sh
  frontmatter-set.sh
)

# Ensure consumer's scripts/ exists (Round 2 N7 — fresh installs may have
# no scripts/ dir; cp would fail "No such file or directory").
mkdir -p "$CONSUMER_ROOT/scripts"

for h in "${HELPERS[@]}"; do
  src="$PORTABLE/scripts/$h"
  dst="$CONSUMER_ROOT/scripts/$h"

  if [ ! -f "$src" ]; then
    echo "ERROR: missing source helper: $src" >&2
    exit 1
  fi

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  SKIP: $h (identical)"
    continue
  fi

  cp "$src" "$dst"
  chmod +x "$dst"
  echo "  COPY: $h"
done

exit 0
