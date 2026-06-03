#!/usr/bin/env bash
# zskills-hook-version: 2026.06.1
# log-permission-request.sh — PermissionRequest hook. Session-logging.
#
# Fires ONLY when a permission dialog would appear (Claude Code does NOT
# fire this for auto-allowed tool calls). It is PURELY OBSERVATIONAL.
#
# HARD CONTRACT — PASSIVE / FAIL-OPEN:
#   * It MUST `exit 0` with NO stdout output (and emit NO JSON decision)
#     so the user's permission dialog is shown UNCHANGED.
#   * It MUST NEVER block, approve, or deny.
#   * ANY internal error MUST still result in `exit 0` with empty stdout —
#     a logging failure must never interfere with the permission flow or
#     corrupt prompts.
# To uphold fail-open even if the embedded Python misbehaves, the entire
# logging step writes to stderr only (the harness ignores PermissionRequest
# stderr) and is wrapped so its exit status can never propagate. stdout is
# only ever written to via the renderer's own (silent) file writes — never
# the hook's stdout.
#
# It appends each event as ONE JSON line to a per-session sidecar
# `permissions-<session>.jsonl` in the resolved log dir:
#   {ts, tool_name, tool_input_summary, tool_use_id}
# (ts = ISO-8601; tool_input_summary = a short, single-line, truncated
# summary). Fields are read from the hook's JSON stdin (session_id,
# tool_name, tool_input, tool_use_id). The Stop renderer merges this
# sidecar into the rendered markdown by timestamp with a [PERMISSION] tag.
#
# Log-dir resolution + the logging.enabled master toggle match
# log-session-stop.sh exactly (shared precedence: ZSKILLS_LOG_DIR env >
# logging.dir config > tempfile.gettempdir()/zskills-session-logs/
# <project>/).

# D16(a) plugin-lane conditional-skip shim. Must be the first executable
# line. Event-agnostic, so it de-dupes the PermissionRequest event when
# both install lanes are active.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

set -u

# Read stdin once. Never fail the hook on a read error.
INPUT=$(cat 2>/dev/null) || { exit 0; }

# Resolve Python. If absent, we simply cannot log — fail open silently.
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
[ -n "$PYTHON" ] || exit 0

# Empty / whitespace-only stdin: nothing to log, but STILL exit 0 with no
# stdout (fail-open). The Python below also tolerates this, but short-
# circuiting here keeps the contract obvious.
if [ -z "${INPUT//[[:space:]]/}" ]; then
  exit 0
fi

# All logging happens inside Python and writes ONLY to the sidecar file
# (never to this hook's stdout). The hook JSON is passed via the
# ZSKILLS_HOOK_INPUT env var (NOT stdin): stdin is consumed by the `<<'PY'`
# heredoc that delivers the script body. The outer `exit 0` guarantees
# fail-open: even a Python crash cannot change the hook's exit code or emit
# a decision. Both stdout AND stderr from Python are discarded so nothing
# can ever leak into the permission flow.
  ZSKILLS_HOOK_INPUT="$INPUT" \
  ZSKILLS_LOG_DIR="${ZSKILLS_LOG_DIR:-}" \
  ZSKILLS_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" \
  "$PYTHON" - >/dev/null 2>&1 <<'PY'
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

PERMISSION_SUMMARY_MAX = 200


def read_config(project_dir):
    cfg_path = os.path.join(project_dir, ".claude", "zskills-config.json")
    enabled = True
    log_dir_cfg = ""
    try:
        with open(cfg_path) as f:
            cfg = json.load(f)
        logging = cfg.get("logging", {})
        if isinstance(logging, dict):
            if "enabled" in logging:
                enabled = bool(logging.get("enabled"))
            d = logging.get("dir", "")
            if isinstance(d, str):
                log_dir_cfg = d
    except Exception:
        pass
    return enabled, log_dir_cfg


def resolve_log_dir(project_dir, cfg_dir):
    env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
    if env_dir:
        return env_dir
    if cfg_dir:
        return cfg_dir
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    base = base.replace(os.sep, "_").replace("/", "_")
    return os.path.join(tempfile.gettempdir(), "zskills-session-logs", base)


def summarize_input(tool_name, tool_input):
    """Short, single-line summary of the tool input, truncated."""
    if isinstance(tool_input, dict):
        for key in ("command", "file_path", "pattern", "url", "query",
                    "description", "path"):
            val = tool_input.get(key)
            if isinstance(val, str) and val:
                summary = f"{key}={val}"
                break
        else:
            try:
                summary = json.dumps(tool_input, separators=(",", ":"))
            except Exception:
                summary = str(tool_input)
    else:
        summary = str(tool_input) if tool_input else ""
    # Single-line.
    summary = summary.replace("\r", " ").replace("\n", " ")
    if len(summary) > PERMISSION_SUMMARY_MAX:
        summary = summary[:PERMISSION_SUMMARY_MAX] + "..."
    return summary


def main():
    # Security: tighten the process umask BEFORE any file creation so the
    # permission sidecar lands at mode 0o600 (owner read/write only). The
    # sidecar records verbatim tool-input summaries (Bash commands, URLs
    # with tokens, file paths) and must never be world-readable on a shared
    # /tmp. The explicit os.open mode below is belt-and-suspenders in case
    # the umask is relaxed by a future caller.
    os.umask(0o077)

    raw = os.environ.get("ZSKILLS_HOOK_INPUT", "")
    try:
        hook_input = json.loads(raw) if raw else None
    except Exception:
        return
    if not isinstance(hook_input, dict):
        return

    project_dir = os.environ.get("ZSKILLS_PROJECT_DIR", os.getcwd())
    enabled, cfg_dir = read_config(project_dir)
    if not enabled:
        return

    session_id = hook_input.get("session_id", "unknown") or "unknown"
    tool_name = hook_input.get("tool_name", "") or ""
    tool_input = hook_input.get("tool_input", {})
    tool_use_id = hook_input.get("tool_use_id", "") or ""

    event = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "tool_name": tool_name,
        "tool_input_summary": summarize_input(tool_name, tool_input),
        "tool_use_id": tool_use_id,
    }

    log_dir = resolve_log_dir(project_dir, cfg_dir)
    try:
        os.makedirs(log_dir, exist_ok=True)
    except OSError:
        return
    sidecar = os.path.join(log_dir, f"permissions-{session_id}.jsonl")
    try:
        # Explicit creation mode 0o600 (owner read/write only) — the umask
        # set at the top of main() already enforces this, but passing the
        # mode to os.open makes it robust even if the umask is relaxed.
        fd = os.open(sidecar, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as f:
            f.write(json.dumps(event) + "\n")
    except OSError:
        return


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
PY

# Unconditional fail-open. Regardless of what the logging step did, the
# permission dialog must proceed untouched: exit 0, no stdout, no decision.
exit 0
