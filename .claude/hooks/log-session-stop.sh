#!/usr/bin/env bash
# zskills-hook-version: 2026.06.5
# log-session-stop.sh — Stop / SubagentStop hook. Session-logging.
#
# Re-renders the session transcript JSONL (the `transcript_path` field of
# the hook's JSON stdin) into a per-session MARKDOWN file in the resolved
# log dir, in the style of cc-session-logger: a session header, user
# prompts, assistant responses, tool calls with results, and edit diffs;
# long tool results collapse into <details> blocks. The markdown is
# regenerated FRESH each fire (overwrite, never append).
#
# Registered under BOTH the Stop and SubagentStop events (plugin-lane
# hooks.json and /update-zskills-lane .claude/settings.json). On
# SubagentStop it derives the subagent type/agent from the stdin fields
# and writes a parallel `<...>-subagent-<type>-<agent>.md` file.
#
# It ALSO merges the per-session permission sidecar
# (`permissions-<session>.jsonl`, written by log-permission-request.sh)
# into the rendered markdown BY TIMESTAMP, each emitted with a greppable
# `[PERMISSION]` tag. The sidecar persists across re-renders; the merge
# is what keeps the in-situ permission lines surviving the fresh render.
#
# Log-dir resolution precedence (shared with the helper + the permission
# hook): ZSKILLS_LOG_DIR env > logging.dir config > per-OS cache default
# (${XDG_CACHE_HOME:-~/.cache}/zskills-session-logs/<project> on Linux,
# ~/Library/Caches/... on macOS, %LOCALAPPDATA%\... on Windows). The
# `logging` config object also carries `enabled` (default FALSE — session
# logging is OFF unless the consumer opts in with logging.enabled:true) —
# when false (or absent) this hook no-ops immediately. Resolution + the
# master-toggle read happen INSIDE the embedded Python (cross-platform, no jq).
#
# PUBLISH-WHERE-IT-WROTE REGISTRY (issue #1059). The drift bug: the reader
# (session-logs.sh) used to re-resolve the path independently via
# tempfile.gettempdir(), which honors per-context $TMPDIR — so writer and
# reader diverged and logs became unfindable. The fix: after resolving its
# log dir, this hook RECORDS that absolute path into a shared registry at
# <main-repo-root>/.zskills/session-log-dirs, where main root =
# `git rev-parse --git-common-dir`/.. (so ALL worktrees of a repo share ONE
# registry — same anchor the tracking system uses). The reader then reads
# the registry instead of recomputing. The registry is self-describing,
# append-only, deduped, and race-safe (see record_log_dir() below).
#
# The markdown rendering is done in Python per the repo's "Python is
# required" rule (no jq). The interpreter is embedded as an inline
# heredoc so the renderer travels with the hook through BOTH install
# lanes (precedent: hooks/inject-bash-timeout.sh). Resolved via
# $ZSKILLS_PYTHON → python3 → python.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return. The shim is
# event-agnostic, so it correctly de-dupes the Stop / SubagentStop events.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

set -u

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
# Resolve Python. Override via ZSKILLS_PYTHON for Windows / non-standard
# distros where only `python` exists; each candidate is probe-RUN so a
# non-executable MS Store stub is skipped. Fail-open if none works.
PYTHON="$(zskills_resolve_python || true)"
[ -n "$PYTHON" ] || exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Everything happens inside Python. The project dir is needed both to
# resolve the default log dir (<project> basename) and to find the config
# (logging.enabled / logging.dir). The hook JSON is passed via the
# ZSKILLS_HOOK_INPUT env var — NOT stdin — because the embedded renderer is
# delivered to Python as a `<<'PY'` heredoc on stdin, so stdin is already
# consumed by the script body. CLAUDE_PROJECT_DIR is set by the harness;
# fall back to PWD when invoked outside it (tests).
  ZSKILLS_HOOK_INPUT="$INPUT" \
  ZSKILLS_LOG_DIR="${ZSKILLS_LOG_DIR:-}" \
  ZSKILLS_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" \
  TIMEZONE="${TIMEZONE:-${TZ:-UTC}}" \
  "$PYTHON" - <<'PY' 2>/dev/null || exit 0
import difflib
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import time
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

# JSONL line types to skip entirely.
SKIP_TYPES = frozenset({
    "file-history-snapshot",
    "queue-operation",
    "progress",
    "system",
})
INLINE_RESULT_MAX_LINES = 4
PERMISSION_SUMMARY_MAX = 200


def read_config(project_dir):
    """Return (enabled, dir, include_repo, include_user, file_mode) from
    .claude/zskills-config.json logging.*.

    Defaults: enabled=False, dir="", include_repo=True, include_user=False,
    file_mode="0600". Session logging is OFF by default — a missing /
    unparseable config, or an absent logging.enabled field, means logging
    stays off. The consumer opts in with logging.enabled:true. The path-
    composition + mode defaults preserve today's exact output byte-for-byte."""
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


# ── SHARED RESOLUTION (issue #1059) ──────────────────────────────────────
# KEEP IDENTICAL to skills/update-zskills/scripts/session-logs.sh. The
# project_base derivation, per-OS cache base, path composition, user
# resolution, and registry path/format are duplicated verbatim across the
# hook and the helper so writer and reader never diverge.
# tests/test-session-logging.sh asserts agreement.

def sanitize_segment(seg):
    """Make a string safe as a SINGLE cross-platform path segment (clients
    run on all OSes). Replace os.sep, /, \\, the Windows-reserved chars
    (: * ? " < > |) and whitespace with _, strip leading/trailing dots and
    spaces (illegal in Windows filenames); empty -> 'unknown'. KEEP
    IDENTICAL across the hook + helper + permission hook."""
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
    """The <repo> path segment: the project-dir basename, sanitized for a
    cross-platform-safe single segment. Unified between hook and helper."""
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    return sanitize_segment(base)


def resolve_user():
    """The <user> path segment, resolved at RUNTIME (never stored in the
    committed config). Precedence: ZSKILLS_LOG_USER env > git config
    user.email > getpass.getuser() > 'unknown'. Sanitized for a single
    cross-platform-safe path segment. KEEP IDENTICAL to the helper."""
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
    """Per-OS stable cache BASE (replaces tempfile.gettempdir(), which
    honored per-context $TMPDIR and caused writer/reader drift). Used when
    logging.dir is blank AND as the registry-absent fallback. NOTE: the
    <repo> segment is NOT baked in here — it is a composition step (see
    compose_log_dir) so include_repo can be applied uniformly.

      Linux/other : ${XDG_CACHE_HOME:-$HOME/.cache}/zskills-session-logs
      macOS       : $HOME/Library/Caches/zskills-session-logs
      Windows     : %LOCALAPPDATA%\\zskills-session-logs
                    (fallback: ~ when LOCALAPPDATA unset)
    """
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
    """The composition BASE: ZSKILLS_LOG_DIR env > logging.dir config >
    per-OS cache base. The <repo>/<user> segments are appended by
    compose_log_dir. KEEP IDENTICAL to the helper."""
    env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
    if env_dir:
        return env_dir
    if cfg_dir:
        return cfg_dir
    return default_cache_base(project_dir)


def compose_log_dir(project_dir, cfg_dir, include_repo, include_user):
    """Compose <base>/[<repo>]/[<user>]. With defaults (include_repo=True,
    include_user=False) the default-cache path is byte-identical to today's
    <cache>/zskills-session-logs/<repo>. KEEP IDENTICAL to the helper."""
    path = resolve_base(project_dir, cfg_dir)
    if include_repo:
        path = os.path.join(path, project_base(project_dir))
    if include_user:
        path = os.path.join(path, resolve_user())
    return path


def parse_file_mode(file_mode):
    """Parse the octal file_mode string (e.g. '0600') into an int; fall back
    to 0o600 on any malformed value. KEEP IDENTICAL across consumers."""
    try:
        m = int(file_mode, 8)
    except (ValueError, TypeError):
        return 0o600
    if m < 0 or m > 0o777:
        return 0o600
    return m


def derive_dir_mode(file_mode_int):
    """Derive the directory mode from a file mode by adding a search/exec
    bit to every triad that has read or write (0o660->0o770, 0o640->0o750,
    0o600->0o700). Dirs need the exec bit to be traversable. KEEP IDENTICAL
    across consumers."""
    dir_mode = file_mode_int
    for shift in (6, 3, 0):
        triad = (file_mode_int >> shift) & 0o7
        if triad & 0o6:  # has read or write
            dir_mode |= (0o1 << shift)
    return dir_mode


def main_repo_root(project_dir):
    """The shared anchor for the registry — the main repo root, so all
    worktrees of a repo share ONE registry. main root =
    `git rev-parse --git-common-dir`/.. (the same anchor the tracking
    system uses). Falls back to project_dir when git is unavailable or the
    dir is not a repo. KEEP IDENTICAL to the helper."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=project_dir, capture_output=True, text=True, timeout=5)
        if out.returncode == 0:
            common = out.stdout.strip()
            if common:
                if not os.path.isabs(common):
                    common = os.path.join(project_dir, common)
                return os.path.abspath(os.path.join(common, ".."))
    except Exception:
        pass
    return os.path.abspath(project_dir)


REGISTRY_HEADER = (
    "# zskills session logs are written to the dir(s) below (newest last).\n"
    "# Set logging.dir in .claude/zskills-config.json to pin one location.\n"
)


def record_log_dir(project_dir, log_dir, ts_iso):
    """Append the resolved absolute log dir to the shared registry at
    <main-repo-root>/.zskills/session-log-dirs — self-describing,
    append-only, deduped, race-safe.

    Race-safety mechanism: a `mkdir`-as-atomic-claim per path acts as the
    dedup gate (mkdir on an existing dir fails atomically, so exactly one
    concurrent writer wins the right to append a given path). The append
    itself is a single os.open(O_APPEND) write whose length is well under
    PIPE_BUF (>=512 on every POSIX target), so POSIX guarantees the line is
    written atomically and never interleaves with a concurrent writer's
    line. Together: no duplicate lines and no corruption under concurrency.
    """
    log_dir = os.path.abspath(log_dir)
    root = main_repo_root(project_dir)
    zsk = os.path.join(root, ".zskills")
    registry = os.path.join(zsk, "session-log-dirs")
    marks = os.path.join(zsk, "session-log-dirs.marks")
    try:
        os.makedirs(marks, exist_ok=True)
    except OSError:
        return
    # Atomic dedup claim: hash the path -> marker dir. mkdir fails if the
    # path was already recorded (by this or a concurrent writer).
    h = hashlib.sha256(log_dir.encode("utf-8", "replace")).hexdigest()[:32]
    mark = os.path.join(marks, h)
    try:
        os.mkdir(mark)
    except FileExistsError:
        return  # already recorded — dedup.
    except OSError:
        return
    # We won the claim: append the line. Seed the self-describing header on
    # first creation (when the file does not yet exist).
    line = "%s\t%s\n" % (ts_iso, log_dir)
    try:
        need_header = not os.path.exists(registry)
        fd = os.open(registry, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as f:
            if need_header:
                f.write(REGISTRY_HEADER)
            f.write(line)
    except OSError:
        # Roll back the claim so a later fire can retry the append.
        try:
            os.rmdir(mark)
        except OSError:
            pass


def parse_jsonl(path):
    records = []
    try:
        with open(path, "r") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    records.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue
    except OSError:
        return []
    return records


def should_skip(record):
    if record.get("type", "") in SKIP_TYPES:
        return True
    if record.get("isMeta"):
        return True
    return False


def group_records(records):
    """Group consecutive assistant records sharing message.id; interleave
    user records. Each item is one of:
      ("user", text, timestamp)
      ("tool_result", block, timestamp)
      ("assistant", [content_blocks], timestamp)
    """
    items = []
    groups = {}
    order = []

    def flush():
        for mid in order:
            grp = groups[mid]
            items.append(("assistant", grp["blocks"], grp["timestamp"]))
        groups.clear()
        order.clear()

    for record in records:
        if should_skip(record):
            continue
        rtype = record.get("type", "")
        msg = record.get("message", {})
        if not isinstance(msg, dict):
            continue
        timestamp = record.get("timestamp", "")

        if rtype == "user":
            flush()
            content = msg.get("content", "")
            role = msg.get("role", "")
            if role != "user":
                continue
            if isinstance(content, str):
                text = content.strip()
                if text:
                    items.append(("user", text, timestamp))
            elif isinstance(content, list):
                text_parts = []
                tool_results = []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type", "")
                    if btype == "text":
                        t = block.get("text", "").strip()
                        if t:
                            text_parts.append(t)
                    elif btype == "tool_result":
                        tool_results.append(block)
                if text_parts:
                    items.append(("user", "\n".join(text_parts), timestamp))
                for tr in tool_results:
                    items.append(("tool_result", tr, timestamp))

        elif rtype == "assistant":
            msg_id = msg.get("id", "")
            content = msg.get("content", [])
            if not isinstance(content, list):
                continue
            if msg_id and msg_id in groups:
                groups[msg_id]["blocks"].extend(content)
            else:
                key = msg_id or id(record)
                groups[key] = {"blocks": list(content), "timestamp": timestamp}
                order.append(key)

    flush()
    return items


def _clean_result_text(text):
    return re.sub(r'</?tool_use_error>', '', text).strip()


def _escape_html(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _unescape_html(text):
    return (text.replace("&lt;", "<").replace("&gt;", ">")
                .replace("&amp;", "&"))


def _truncate(text, n):
    return text if len(text) <= n else text[:n] + "..."


def _tool_header(name, inp):
    if not isinstance(inp, dict):
        return f"● {name}"
    if name == "Bash":
        cmd = inp.get("command", "").split("\n")[0]
        return f"● `Bash({_truncate(cmd, 120)})`"
    if name == "Read":
        return f"● `Read({inp.get('file_path', '')})`"
    if name == "Write":
        return f"● `Write({inp.get('file_path', '')})`"
    if name == "Edit":
        return f"● `Update({inp.get('file_path', '')})`"
    if name == "Glob":
        return f"● `Glob({inp.get('pattern', '')})`"
    if name == "Grep":
        pattern = inp.get("pattern", "")
        if pattern:
            return f"● Searched for `{_truncate(pattern, 80)}`"
        return "● Searched codebase"
    if name == "WebFetch":
        return f"● `WebFetch({_truncate(inp.get('url', ''), 100)})`"
    if name == "WebSearch":
        return f"● `WebSearch({inp.get('query', '')})`"
    if name in ("Task", "Agent"):
        desc = inp.get("description", "")
        agent = inp.get("subagent_type", "")
        if agent:
            return f"● `Task({agent}: {_truncate(desc, 100)})`"
        return f"● `Task({_truncate(desc, 100)})`"
    return f"● {name}"


def format_tool_result_content(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text", ""))
                elif block.get("type") == "image":
                    parts.append("[image]")
                else:
                    parts.append(str(block))
            elif isinstance(block, str):
                parts.append(block)
        return "\n".join(parts)
    return str(content) if content else ""


def _render_result_inline(lines, content, is_error=False):
    result_lines = content.split("\n")
    prefix = "  ⎿  **Error:** " if is_error else "  ⎿  "
    cont = "     "
    for i, rline in enumerate(result_lines):
        lines.append(f"{prefix}{rline}" if i == 0 else f"{cont}{rline}")
    lines.append("")


def _render_result_collapsed(lines, content, summary, is_error=False):
    if is_error:
        summary = f"<b>Error:</b> {summary}"
    lines.append("<details>")
    lines.append(f"<summary>{summary}</summary>")
    lines.append(f"<pre><code>{_escape_html(content)}</code></pre>")
    lines.append("</details>")
    lines.append("<br>")
    lines.append("")


def _render_tool_with_result(lines, header, result_content, is_error=False):
    content = _clean_result_text(result_content) if result_content else ""
    if not content:
        lines.append(header)
        lines.append("")
        return
    result_lines = content.split("\n")
    if len(result_lines) <= INLINE_RESULT_MAX_LINES:
        lines.append(header)
        _render_result_inline(lines, content, is_error)
    else:
        _render_result_collapsed(lines, content, _escape_html(header), is_error)


def to_epoch(ts):
    """ISO-8601 -> epoch seconds (float). Returns None on failure."""
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def render_markdown(items, permissions):
    """Render items into markdown. `permissions` is a list of dicts each
    with at least `ts`; they are merged BY TIMESTAMP with a [PERMISSION]
    tag. Items without a parseable timestamp are appended at their natural
    position; permission events are inserted just before the first item
    whose timestamp is >= the permission ts (stable, in-context)."""
    lines = []

    # First pass: collect tool results keyed by tool_use_id.
    tool_results_map = {}
    for item in items:
        if item[0] == "tool_result":
            tr = item[1]
            content = format_tool_result_content(tr.get("content", "")).strip()
            tid = tr.get("tool_use_id", "")
            if tid:
                tool_results_map[tid] = (content, tr.get("is_error", False))

    # Sort permissions by epoch; keep unparseable ones at the end.
    perms = sorted(
        permissions,
        key=lambda p: (to_epoch(p.get("ts")) is None, to_epoch(p.get("ts")) or 0.0),
    )
    perm_idx = 0

    def emit_permission(p):
        summary = p.get("tool_input_summary", "")
        tool = p.get("tool_name", "?")
        tid = p.get("tool_use_id", "")
        suffix = f" (tool_use_id: {tid})" if tid else ""
        ts = p.get("ts", "")
        lines.append(f"`[PERMISSION]` {ts} — {tool}: {summary}{suffix}")
        lines.append("")

    def flush_perms_up_to(epoch):
        nonlocal perm_idx
        while perm_idx < len(perms):
            pe = to_epoch(perms[perm_idx].get("ts"))
            if pe is None:
                break
            if epoch is not None and pe > epoch:
                break
            emit_permission(perms[perm_idx])
            perm_idx += 1

    # Second pass: render, interleaving permissions by timestamp.
    for item in items:
        kind = item[0]
        ts = item[2] if len(item) > 2 else ""
        flush_perms_up_to(to_epoch(ts))

        if kind == "user":
            text = item[1]
            quoted = "\n".join(f"> {l}" for l in text.split("\n"))
            lines.append(f"**User:**\n{quoted}")
            lines.append("")
        elif kind == "tool_result":
            continue
        elif kind == "assistant":
            blocks = item[1]
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type", "")
                if btype == "thinking":
                    continue
                elif btype == "text":
                    text = _unescape_html(block.get("text", "").strip())
                    if not text:
                        continue
                    if lines and lines[-1] != "":
                        lines.append("")
                    lines.append(text)
                    lines.append("")
                elif btype == "tool_use":
                    tool_name = block.get("name", "unknown")
                    tool_input = block.get("input", {})
                    header = _tool_header(tool_name, tool_input)
                    tool_id = block.get("id", "")
                    result = tool_results_map.get(tool_id)
                    result_content = result[0] if result else ""
                    result_is_error = result[1] if result else False
                    if tool_name == "Edit":
                        lines.append(header)
                        old = tool_input.get("old_string", "")
                        new = tool_input.get("new_string", "")
                        if old or new:
                            diff = list(difflib.unified_diff(
                                old.splitlines(), new.splitlines(),
                                lineterm="", n=2))
                            body = [l for l in diff
                                    if not l.startswith(("---", "+++"))]
                            if body:
                                lines.append("```diff")
                                lines.extend(body)
                                lines.append("```")
                        if result_content:
                            _render_result_inline(
                                lines, _clean_result_text(result_content),
                                result_is_error)
                        else:
                            lines.append("")
                    else:
                        _render_tool_with_result(
                            lines, header, result_content, result_is_error)
            if lines and lines[-1] != "":
                lines.append("")

    # Any remaining permissions (later than all items, or unparseable ts).
    while perm_idx < len(perms):
        emit_permission(perms[perm_idx])
        perm_idx += 1

    return "\n".join(lines)


def render_header(session_id, date_display, agent_type=None, agent_id=None):
    short_session = session_id[:8] if session_id else "unknown"
    if agent_type:
        short_agent = agent_id[:8] if agent_id else ""
        title = f"# Subagent: {agent_type}"
        if short_agent:
            title += f" `{short_agent}`"
        title += f" — {date_display}"
        meta = f"*Parent session: `{short_session}`*"
    else:
        title = f"# Session `{short_session}` — {date_display}"
        meta = None
    parts = [title, ""]
    if meta:
        parts.append(meta)
        parts.append("")
    parts.append("---")
    parts.append("")
    return "\n".join(parts)


def load_permissions(log_dir, session_id):
    """Read the per-session permission sidecar, one JSON object per line."""
    path = os.path.join(log_dir, f"permissions-{session_id}.jsonl")
    out = []
    try:
        with open(path) as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    out.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return out


def main():
    raw = os.environ.get("ZSKILLS_HOOK_INPUT", "")
    try:
        hook_input = json.loads(raw) if raw else None
    except (json.JSONDecodeError, ValueError):
        return
    if not isinstance(hook_input, dict):
        return

    project_dir = os.environ.get("ZSKILLS_PROJECT_DIR", os.getcwd())

    # Master toggle: logging.enabled=false => no-op.
    enabled, cfg_dir, include_repo, include_user, file_mode = \
        read_config(project_dir)
    if not enabled:
        return

    # Security: derive the file + directory modes and tighten the process
    # umask BEFORE any file creation so the ".tmp" write and the os.replace
    # final markdown both land at exactly file_mode (default 0o600, owner
    # read/write only). Session transcripts contain verbatim user prompts and
    # Bash tool I/O — including any credential a user cat-ed — so they must
    # never be world-readable on a shared mount. Setting the umask here
    # (rather than chmod after os.replace) also closes the tmp-window race.
    # POSIX-only: Windows has no rwx owner/group/other bits (os.umask is
    # effectively a no-op there; NTFS/SMB use ACLs), so the mode application
    # is guarded and Windows is a clean no-op.
    file_mode_int = parse_file_mode(file_mode)
    dir_mode = derive_dir_mode(file_mode_int)
    is_windows = platform.system() == "Windows"
    if not is_windows:
        os.umask(0o777 & ~dir_mode)

    event = hook_input.get("hook_event_name", "")
    session_id = hook_input.get("session_id", "unknown") or "unknown"

    # SubagentStop reads the subagent transcript + type/agent fields.
    is_subagent = (event == "SubagentStop") or bool(
        hook_input.get("agent_transcript_path"))
    if is_subagent:
        transcript_path = (hook_input.get("agent_transcript_path")
                           or hook_input.get("transcript_path", ""))
        agent_type = hook_input.get("agent_type") or "subagent"
        agent_id = hook_input.get("agent_id") or "unknown"
    else:
        transcript_path = hook_input.get("transcript_path", "")
        agent_type = None
        agent_id = None

    if not transcript_path or not os.path.isfile(transcript_path):
        return

    # Wait for the transcript to finish flushing (size stabilizes).
    prev = -1
    for _ in range(10):
        try:
            cur = os.path.getsize(transcript_path)
        except OSError:
            cur = 0
        if cur == prev:
            break
        prev = cur
        time.sleep(0.2)

    records = parse_jsonl(transcript_path)

    # Determine start timestamp -> date/time for filename + header.
    start_ts = None
    for r in records:
        ts = r.get("timestamp") if isinstance(r, dict) else None
        if ts:
            start_ts = ts
            break

    tz_name = os.environ.get("TIMEZONE", "UTC") or "UTC"
    date_str = None
    time_part = "0000"
    date_display = "unknown date"
    if start_ts:
        try:
            dt = datetime.fromisoformat(start_ts.replace("Z", "+00:00"))
            if ZoneInfo is not None:
                try:
                    dt = dt.astimezone(ZoneInfo(tz_name))
                except Exception:
                    pass
            date_str = dt.strftime("%Y-%m-%d")
            time_part = dt.strftime("%H%M")
            date_display = dt.strftime("%Y-%m-%d %H:%M")
        except Exception:
            date_str = None
    if not date_str:
        now = datetime.now()
        date_str = now.strftime("%Y-%m-%d")
        time_part = now.strftime("%H%M")
        date_display = now.strftime("%Y-%m-%d %H:%M")

    log_dir = compose_log_dir(project_dir, cfg_dir, include_repo,
                              include_user)
    try:
        if is_windows:
            os.makedirs(log_dir, exist_ok=True)
        else:
            os.makedirs(log_dir, mode=dir_mode, exist_ok=True)
    except OSError:
        return

    # Publish where we wrote into the shared registry so the reader can find
    # the logs without recomputing the path (issue #1059). Best-effort: a
    # registry failure must never abort the actual log write.
    try:
        now = datetime.now()
        if ZoneInfo is not None and tz_name:
            try:
                now = now.astimezone(ZoneInfo(tz_name))
            except Exception:
                now = now.astimezone()
        else:
            now = now.astimezone()
        reg_ts = now.strftime("%Y-%m-%dT%H:%M%z")
        # Normalize +HHMM -> +HH:MM for ISO-8601 readability.
        if len(reg_ts) >= 5 and reg_ts[-5] in "+-":
            reg_ts = reg_ts[:-2] + ":" + reg_ts[-2:]
        record_log_dir(project_dir, log_dir, reg_ts)
    except Exception:
        pass

    short_session = session_id[:8]
    if is_subagent:
        short_agent = (agent_id or "unknown")[:8]
        fname = (f"{date_str}-{time_part}-{short_session}"
                 f"-subagent-{agent_type}-{short_agent}.md")
    else:
        fname = f"{date_str}-{time_part}-{short_session}.md"
    out_path = os.path.join(log_dir, fname)

    items = group_records(records)
    permissions = load_permissions(log_dir, session_id)
    header = render_header(session_id, date_display, agent_type, agent_id)
    body = render_markdown(items, permissions)

    tmp = out_path + ".tmp"
    try:
        with open(tmp, "w") as f:
            f.write(header + body)
        # The umask set above already lands the .tmp at exactly file_mode;
        # an explicit chmod is belt-and-suspenders in case the umask was
        # relaxed by a future caller. POSIX-only (guarded for Windows).
        if not is_windows:
            try:
                os.chmod(tmp, file_mode_int)
            except OSError:
                pass
        os.replace(tmp, out_path)
    except OSError:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
PY

exit 0
