#!/usr/bin/env bash
# zskills-hook-version: 2026.06.0
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
# hook): ZSKILLS_LOG_DIR env > logging.dir config > Python
# tempfile.gettempdir()/zskills-session-logs/<project>/. The `logging`
# config object also carries `enabled` (default true) — when false this
# hook no-ops immediately. Resolution + the master-toggle read happen
# INSIDE the embedded Python (cross-platform tempdir, no jq).
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

# Resolve Python. Override via ZSKILLS_PYTHON for Windows / non-standard
# distros where only `python` exists. Default: python3, then python.
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
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
import json
import os
import re
import sys
import tempfile
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
    """Return (enabled, dir) from .claude/zskills-config.json logging.*.

    Defaults: enabled=True, dir="". A missing / unparseable config means
    defaults (logging on)."""
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
    """Precedence: ZSKILLS_LOG_DIR env > logging.dir config >
    tempfile.gettempdir()/zskills-session-logs/<project>/."""
    env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
    if env_dir:
        return env_dir
    if cfg_dir:
        return cfg_dir
    project_base = os.path.basename(os.path.normpath(project_dir)) or "project"
    # Path-separator-safe: basename already strips separators, but guard
    # against any residual separator from odd inputs.
    project_base = project_base.replace(os.sep, "_").replace("/", "_")
    return os.path.join(tempfile.gettempdir(), "zskills-session-logs",
                        project_base)


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
    enabled, cfg_dir = read_config(project_dir)
    if not enabled:
        return

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

    log_dir = resolve_log_dir(project_dir, cfg_dir)
    try:
        os.makedirs(log_dir, exist_ok=True)
    except OSError:
        return

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
