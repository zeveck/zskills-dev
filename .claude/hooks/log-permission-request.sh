#!/usr/bin/env bash
# zskills-hook-version: 2026.06.5
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
# logging.dir config > per-OS cache default — see issue #1059). The sidecar
# lands in the SAME resolved log dir the Stop hook reads from, so identical
# resolution is what keeps them in agreement. This hook does NOT write the
# registry; the Stop hook publishes the dir.

# D16(a) plugin-lane conditional-skip shim. Must be the first executable
# line. Event-agnostic, so it de-dupes the PermissionRequest event when
# both install lanes are active.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

set -u

# Read stdin once. Never fail the hook on a read error.
INPUT=$(cat 2>/dev/null) || { exit 0; }

# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}
# Resolve Python. If absent, we simply cannot log — fail open silently.
PYTHON="$(zskills_resolve_python || true)"
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
import platform
import subprocess
import sys
from datetime import datetime, timezone

PERMISSION_SUMMARY_MAX = 200


def read_config(project_dir):
    # Defaults: enabled=False — session logging is OFF by default. A missing
    # / unparseable config, or an absent logging.enabled field, leaves
    # logging off. The consumer opts in with logging.enabled:true. KEEP
    # IDENTICAL to log-session-stop.sh read_config.
    cfg_path = os.path.join(project_dir, ".claude", "zskills-config.json")
    enabled = False
    log_dir_cfg = ""
    include_repo = True
    include_user = False
    file_mode = "0600"
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
            if "include_repo" in logging:
                include_repo = bool(logging.get("include_repo"))
            if "include_user" in logging:
                include_user = bool(logging.get("include_user"))
            fm = logging.get("file_mode", "")
            if isinstance(fm, str) and fm:
                file_mode = fm
    except Exception:
        pass
    return enabled, log_dir_cfg, include_repo, include_user, file_mode


# KEEP IDENTICAL to log-session-stop.sh / session-logs.sh (issue #1059).
def sanitize_segment(seg):
    """Make a string safe as a SINGLE cross-platform path segment. Replace
    os.sep, /, \\, the Windows-reserved chars (: * ? " < > |) and whitespace
    with _, strip leading/trailing dots/spaces; empty -> 'unknown'."""
    if not seg:
        return "unknown"
    bad = set(os.sep) | {"/", "\\", ":", "*", "?", '"', "<", ">", "|"}
    out = []
    for ch in seg:
        if ch in bad or ch.isspace():
            out.append("_")
        else:
            out.append(ch)
    result = "".join(out).strip(". ")
    return result or "unknown"


def project_base(project_dir):
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    return sanitize_segment(base)


def resolve_user():
    """Precedence: ZSKILLS_LOG_USER env > git config user.email >
    getpass.getuser() > 'unknown'. Resolved at RUNTIME, never stored in
    config. The git subprocess fail-opens to the getpass/unknown fallback so
    it never blocks the permission dialog."""
    user = os.environ.get("ZSKILLS_LOG_USER", "")
    if not user:
        try:
            out = subprocess.run(
                ["git", "config", "user.email"],
                capture_output=True, text=True, timeout=5)
            if out.returncode == 0:
                user = out.stdout.strip()
        except Exception:
            user = ""
    if not user:
        try:
            import getpass
            user = getpass.getuser()
        except Exception:
            user = ""
    return sanitize_segment(user)


def default_cache_base(project_dir):
    """Per-OS stable cache BASE (replaces tempfile.gettempdir()). The <repo>
    segment is a composition step, not baked in here."""
    system = platform.system()
    if system == "Windows":
        root = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    elif system == "Darwin":
        root = os.path.join(os.path.expanduser("~"), "Library", "Caches")
    else:
        root = (os.environ.get("XDG_CACHE_HOME")
                or os.path.join(os.path.expanduser("~"), ".cache"))
    return os.path.join(root, "zskills-session-logs")


def resolve_base(project_dir, cfg_dir):
    env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
    if env_dir:
        return env_dir
    if cfg_dir:
        return cfg_dir
    return default_cache_base(project_dir)


def compose_log_dir(project_dir, cfg_dir, include_repo, include_user):
    """Compose <base>/[<repo>]/[<user>]. KEEP IDENTICAL to the Stop hook so
    the sidecar lands in the SAME composed dir the Stop renderer reads."""
    path = resolve_base(project_dir, cfg_dir)
    if include_repo:
        path = os.path.join(path, project_base(project_dir))
    if include_user:
        path = os.path.join(path, resolve_user())
    return path


def parse_file_mode(file_mode):
    try:
        m = int(file_mode, 8)
    except (ValueError, TypeError):
        return 0o600
    if m < 0 or m > 0o777:
        return 0o600
    return m


def derive_dir_mode(file_mode_int):
    dir_mode = file_mode_int
    for shift in (6, 3, 0):
        triad = (file_mode_int >> shift) & 0o7
        if triad & 0o6:
            dir_mode |= (0o1 << shift)
    return dir_mode


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
    raw = os.environ.get("ZSKILLS_HOOK_INPUT", "")
    try:
        hook_input = json.loads(raw) if raw else None
    except Exception:
        return
    if not isinstance(hook_input, dict):
        return

    project_dir = os.environ.get("ZSKILLS_PROJECT_DIR", os.getcwd())
    enabled, cfg_dir, include_repo, include_user, file_mode = \
        read_config(project_dir)
    if not enabled:
        return

    # Security: derive the file + directory modes and tighten the process
    # umask BEFORE any file creation so the permission sidecar lands at
    # exactly file_mode (default 0o600, owner read/write only). The sidecar
    # records verbatim tool-input summaries (Bash commands, URLs with tokens,
    # file paths) and must never be world-readable on a shared mount. The
    # explicit os.open mode below is belt-and-suspenders in case the umask is
    # relaxed. POSIX-only: Windows has no rwx bits (os.umask is a no-op;
    # NTFS/SMB use ACLs), so the mode application is guarded.
    file_mode_int = parse_file_mode(file_mode)
    dir_mode = derive_dir_mode(file_mode_int)
    is_windows = platform.system() == "Windows"
    if not is_windows:
        os.umask(0o777 & ~dir_mode)

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

    log_dir = compose_log_dir(project_dir, cfg_dir, include_repo,
                              include_user)
    try:
        if is_windows:
            os.makedirs(log_dir, exist_ok=True)
        else:
            os.makedirs(log_dir, mode=dir_mode, exist_ok=True)
    except OSError:
        return
    sidecar = os.path.join(log_dir, f"permissions-{session_id}.jsonl")
    try:
        # Explicit creation mode = file_mode (default 0o600) — the umask set
        # in main() already enforces this, but passing the mode to os.open
        # makes it robust even if the umask is relaxed. On Windows os.open's
        # mode arg is effectively ignored; pass file_mode_int anyway.
        fd = os.open(sidecar, os.O_WRONLY | os.O_CREAT | os.O_APPEND,
                     file_mode_int)
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
