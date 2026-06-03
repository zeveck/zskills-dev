#!/bin/bash
# session-logs.sh -- resolve / export the zskills session-log directory.
#
# Tier-1, owned by `update-zskills`. Models its shape on the sibling
# port.sh: a tiny resolver around the same precedence the session-logging
# hooks (hooks/log-session-stop.sh, hooks/log-permission-request.sh) use.
#
# Usage:
#   bash session-logs.sh            # print the resolved log dir to stdout
#   bash session-logs.sh <dest>     # copy the session logs to <dest>
#
# Log-dir resolution precedence (MUST match the hooks):
#   ZSKILLS_LOG_DIR env
#     > logging.dir   (from .claude/zskills-config.json)
#     > Python tempfile.gettempdir()/zskills-session-logs/<project>/
# The default is computed via Python's tempfile.gettempdir() (NOT the bash
# ${TMPDIR:-/tmp} idiom) so it is correct cross-platform incl. Windows.
# <project> = the project-dir basename (path-separator-safe).

set -u

# PROJECT_ROOT from invocation context (git toplevel; fall back to PWD).
# CLAUDE_PROJECT_DIR, when set by the harness, takes precedence so the
# config + <project> basename match the hooks' view of the project.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

# Resolve Python (per `## Python is required`).
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

# Resolve the log dir using the exact precedence the hooks implement.
LOG_DIR="$(
  ZSKILLS_LOG_DIR="${ZSKILLS_LOG_DIR:-}" \
  ZSKILLS_PROJECT_DIR="$PROJECT_ROOT" \
  "$PYTHON" - <<'PY'
import json, os, sys, tempfile

project_dir = os.environ.get("ZSKILLS_PROJECT_DIR", os.getcwd())

# logging.dir from config (defaults: enabled=True, dir="").
cfg_dir = ""
try:
    with open(os.path.join(project_dir, ".claude", "zskills-config.json")) as f:
        cfg = json.load(f)
    logging = cfg.get("logging", {})
    if isinstance(logging, dict):
        d = logging.get("dir", "")
        if isinstance(d, str):
            cfg_dir = d
except Exception:
    pass

env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
if env_dir:
    print(env_dir)
elif cfg_dir:
    print(cfg_dir)
else:
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    base = base.replace(os.sep, "_").replace("/", "_")
    print(os.path.join(tempfile.gettempdir(), "zskills-session-logs", base))
PY
)"

if [ -z "$LOG_DIR" ]; then
  echo "session-logs.sh: failed to resolve log dir" >&2
  exit 1
fi

# No args: print the resolved dir.
if [ "$#" -eq 0 ]; then
  echo "$LOG_DIR"
  exit 0
fi

# One dest arg: copy the logs there. Literal-safe cp (no rm -rf on a
# variable path, per the repo's block-unsafe rules). Create the
# destination, then copy the contents of the resolved log dir into it.
DEST="$1"
if [ ! -d "$LOG_DIR" ]; then
  echo "session-logs.sh: no log dir to copy at $LOG_DIR" >&2
  exit 1
fi
mkdir -p "$DEST" || { echo "session-logs.sh: cannot create $DEST" >&2; exit 1; }

# Copy every regular file/dir under the resolved log dir into DEST. Use a
# trailing /. so the contents (not the dir itself) land in DEST. cp -a
# preserves modes/timestamps; no recursive delete is performed.
if cp -a "$LOG_DIR/." "$DEST/"; then
  echo "session-logs.sh: copied logs from $LOG_DIR to $DEST"
  exit 0
else
  echo "session-logs.sh: copy from $LOG_DIR to $DEST failed" >&2
  exit 1
fi
