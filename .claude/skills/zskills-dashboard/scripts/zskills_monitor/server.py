#!/usr/bin/env python3
"""
zskills_monitor.server — localhost-only HTTP API for the zskills dashboard
(Phase 5 of ZSKILLS_MONITOR_PLAN).

stdlib-only. Wraps Phase 4's `collect_snapshot()` plus interactive
write-back for the queue + work-on-plans state. Static files from the
sibling `static/` directory serve the Phase 6 UI shell.

Canonical CLI (matches the `port.sh` invocation pattern):

    PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \\
      python3 -m zskills_monitor.server \\
        [--port N] [--main-root DIR]

Port resolution (per Phase 5 plan body):
    1. --port arg (highest)
    2. DEV_PORT env var
    3. dev_server.default_port from .claude/zskills-config.json
    4. bash skills/update-zskills/scripts/port.sh

PID file (`MAIN_ROOT/.zskills/dashboard-server.pid`) is written ONLY
after a successful bind, in `.env`-style key=value (Shared Schemas):

    pid=12345
    port=8080
    started_at=2026-04-25T10:00:00-04:00

Cross-process flock (fcntl, exclusive) protects every read-then-write
on the state files. Atomic writes use os.replace() into the same dir.
"""

from __future__ import annotations

import argparse
import contextlib
import errno
import fcntl
import json
import os
import pathlib
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, List, Optional, Tuple

# Phase 4 module — used for /api/state and plan-detail enrichment.
from zskills_monitor import collect as _collect


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BIND_HOST = "127.0.0.1"
DEFAULT_PORT_FALLBACK = 8080

# Validation regexes (defense-in-depth — applied after URL decode).
SLUG_RE = re.compile(r"^[a-z0-9-]+$")
ISSUE_RE = re.compile(r"^[0-9]+$")

# Trigger-command allowlist regex (URL-decoded).
TRIGGER_CMD_RE = re.compile(r"^/work-on-plans(\s|$)")

# State-file column shapes.
# NOTE: `completed` is intentionally NOT in either tuple — Completed is
# read-only on the API surface, derived per-snapshot from plan frontmatter
# `completed:` field (plans) / GitHub issue state (issues). The POST
# validator explicitly rejects `plans.completed` / `issues.completed`
# bodies with a specific error containing "completed column is read-only"
# (see _validate_queue_body); the generic unknown-column path is a
# secondary backstop.
PLAN_COLUMNS = ("drafted", "reviewed", "ready", "backlog")
ISSUE_COLUMNS = ("triage", "ready", "backlog")
DEFAULT_MODE_VALUES = ("phase", "finish")

# Sub-second alignment with the plan's date format
ISO_RE = re.compile(r"^[0-9T:+\-]+$")

# /api/issue gh subprocess timeout
GH_ISSUE_TIMEOUT_SECS = 15

# /api/trigger subprocess timeout
TRIGGER_TIMEOUT_SECS = 30


# ---------------------------------------------------------------------------
# Repo-root resolution (worktree-aware)
# ---------------------------------------------------------------------------


def resolve_main_root(start: Optional[str] = None) -> pathlib.Path:
    """Return MAIN_ROOT — the main checkout, even when invoked from a
    worktree. Delegates to collect._resolve_main_root which already
    implements the `git rev-parse --git-common-dir` walk.
    """
    src = start or os.getcwd()
    return _collect._resolve_main_root(src)


# ---------------------------------------------------------------------------
# Port resolution chain
# ---------------------------------------------------------------------------


_CFG_DEV_PORT_RE = re.compile(
    r'"dev_server"\s*:\s*\{[^}]*?"default_port"\s*:\s*([0-9]+)',
    re.DOTALL,
)


def _read_default_port_from_config(main_root: pathlib.Path) -> Optional[int]:
    """Read dev_server.default_port from .claude/zskills-config.json
    using a Python-re BASH_REMATCH-equivalent (mirrors port.sh shape).

    Returns int or None on any failure (missing file, no field, non-numeric).
    Errors are not raised — the caller falls through the resolution chain.
    """
    cfg_path = main_root / ".claude" / "zskills-config.json"
    try:
        body = cfg_path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _CFG_DEV_PORT_RE.search(body)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


def _invoke_port_sh(main_root: pathlib.Path) -> Tuple[Optional[int], str]:
    """Run port.sh and return (port, error_message). Search both
    `.claude/skills/update-zskills/scripts/port.sh` (installed layout)
    and `skills/update-zskills/scripts/port.sh` (source-tree).
    """
    candidates = [
        main_root / ".claude" / "skills" / "update-zskills" / "scripts" / "port.sh",
        main_root / "skills" / "update-zskills" / "scripts" / "port.sh",
    ]
    chosen: Optional[pathlib.Path] = None
    for c in candidates:
        if c.is_file() and os.access(c, os.X_OK):
            chosen = c
            break
    if chosen is None:
        return None, (
            "port resolution failed: port.sh not found or not executable; "
            "set DEV_PORT or restore .claude/skills/update-zskills/scripts/port.sh, "
            "or set dev_server.default_port in .claude/zskills-config.json"
        )
    try:
        result = subprocess.run(
            ["bash", str(chosen)],
            cwd=str(main_root),
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (subprocess.SubprocessError, OSError) as exc:
        return None, (
            f"port resolution failed: invoking port.sh raised {exc}; "
            "set DEV_PORT or restore .claude/skills/update-zskills/scripts/port.sh, "
            "or set dev_server.default_port in .claude/zskills-config.json"
        )
    out = result.stdout.strip()
    if result.returncode != 0 or not out.isdigit():
        return None, (
            f"port resolution failed: port.sh returned rc={result.returncode} "
            f"stdout={out!r} stderr={result.stderr.strip()!r}; "
            "set DEV_PORT or restore .claude/skills/update-zskills/scripts/port.sh, "
            "or set dev_server.default_port in .claude/zskills-config.json"
        )
    return int(out), ""


def resolve_port(
    main_root: pathlib.Path,
    *,
    cli_port: Optional[int] = None,
    env: Optional[Dict[str, str]] = None,
) -> int:
    """Resolve the bind port via the documented chain.

    Raises SystemExit(2) with a friendly stderr message when port.sh
    is the last resort and unavailable.
    """
    if cli_port is not None:
        return cli_port
    e = env if env is not None else os.environ
    raw = e.get("DEV_PORT", "")
    if raw and raw.isdigit():
        return int(raw)
    cfg_port = _read_default_port_from_config(main_root)
    if cfg_port is not None:
        return cfg_port
    port, err = _invoke_port_sh(main_root)
    if port is not None:
        return port
    print(err, file=sys.stderr)
    raise SystemExit(2)


# ---------------------------------------------------------------------------
# Config load (READ-ONLY on .claude/zskills-config.json)
# ---------------------------------------------------------------------------
#
# The server NEVER writes to .claude/zskills-config.json. The
# `dashboard.work_on_plans_trigger` field is declared in the schema and
# added by /update-zskills on install/update against existing configs
# (see skills/update-zskills/SKILL.md Step 3.6). If the field is absent
# at server startup (consumer hasn't run /update-zskills since the field
# was introduced), the server treats it as empty — the Run button is
# hidden, /api/trigger returns 501. No config mutation, no json.dumps
# reformatting churn.


def _read_config(main_root: pathlib.Path) -> Dict[str, Any]:
    """Read .claude/zskills-config.json. Returns {} if unreadable."""
    cfg_path = main_root / ".claude" / "zskills-config.json"
    try:
        body = cfg_path.read_text(encoding="utf-8")
    except OSError:
        return {}
    try:
        loaded = json.loads(body)
    except (json.JSONDecodeError, ValueError):
        return {}
    return loaded if isinstance(loaded, dict) else {}


def _resolve_paths(main_root: pathlib.Path) -> Dict[str, pathlib.Path]:
    """Resolve audit / plans / issues dirs from zskills-config.json.

    Mirrors the bash zskills-paths.sh helper and briefing.py.
    Use-as-is is absolute-only: only paths starting with `/` are absolute;
    all other forms are joined with main_root (Locked Decision 1).

    LOCKSTEP NOTE: when editing this body, mirror the change in
    collect.py:_resolve_paths — they are intentional duplicates per Phase
    4 helper-share decision (separate processes, no shared module).
    """
    cfg = _read_config(main_root)
    output = cfg.get("output", {}) if isinstance(cfg, dict) else {}
    if not isinstance(output, dict):
        output = {}
    plans_rel = output.get("plans_dir") or "plans"
    issues_rel = output.get("issues_dir") or "plans"

    def _resolve(rel: str) -> pathlib.Path:
        p = pathlib.Path(rel)
        return p if p.is_absolute() else main_root / rel

    return {
        "plans_dir": _resolve(plans_rel),
        "issues_dir": _resolve(issues_rel),
        "audit_dir": main_root / ".zskills" / "audit",
    }


# ---------------------------------------------------------------------------
# Locking + atomic write helper for the state files
# ---------------------------------------------------------------------------


_STATE_THREAD_LOCK = threading.Lock()


@contextlib.contextmanager
def _state_lock(main_root: pathlib.Path):
    """Acquire (cross-process flock + in-process threading.Lock) for the
    monitor-state.json read+modify+write critical section. Lock file is
    `.zskills/monitor-state.json.lock`.
    """
    zsk = main_root / ".zskills"
    zsk.mkdir(exist_ok=True)
    lock_path = zsk / "monitor-state.json.lock"
    # Open lock file (create if absent). LOCK_EX is a process-level lock.
    fd = os.open(
        str(lock_path), os.O_RDWR | os.O_CREAT, 0o644
    )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        with _STATE_THREAD_LOCK:
            yield
        fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def _atomic_write_json(target: pathlib.Path, data: Any) -> None:
    """Write JSON atomically: same-dir tmp + os.replace()."""
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(str(tmp), str(target))


# ---------------------------------------------------------------------------
# State-file readers
# ---------------------------------------------------------------------------


def _read_monitor_state(main_root: pathlib.Path) -> Dict[str, Any]:
    """Read .zskills/monitor-state.json. Returns the parsed dict, or a
    bootstrap empty doc on missing/unparseable file. Caller is expected
    to be holding the state lock for any read-modify-write.
    """
    path = main_root / ".zskills" / "monitor-state.json"
    if not path.is_file():
        return {
            "version": "1.2",
            "default_mode": "phase",
            "plans": {c: [] for c in PLAN_COLUMNS},
            "issues": {c: [] for c in ISSUE_COLUMNS},
        }
    try:
        body = path.read_text(encoding="utf-8")
        loaded = json.loads(body)
    except (OSError, json.JSONDecodeError, ValueError):
        # Treat as transient corruption — bootstrap.
        return {
            "version": "1.2",
            "default_mode": "phase",
            "plans": {c: [] for c in PLAN_COLUMNS},
            "issues": {c: [] for c in ISSUE_COLUMNS},
        }
    if not isinstance(loaded, dict):
        return {
            "version": "1.2",
            "default_mode": "phase",
            "plans": {c: [] for c in PLAN_COLUMNS},
            "issues": {c: [] for c in ISSUE_COLUMNS},
        }
    return loaded


def _read_work_state(
    main_root: pathlib.Path,
    *,
    error_log: Callable[[str], None],
) -> Tuple[Dict[str, Any], bool]:
    """Read .zskills/work-on-plans-state.json.

    Returns (doc, was_unparseable). On missing file, returns
    ({"state":"idle"}, False). On unparseable file, logs via
    `error_log` and returns ({"state":"idle"}, True).
    """
    path = main_root / ".zskills" / "work-on-plans-state.json"
    if not path.is_file():
        return {"state": "idle"}, False
    try:
        body = path.read_text(encoding="utf-8")
        loaded = json.loads(body)
        if not isinstance(loaded, dict):
            error_log(
                f"work-on-plans-state.json top-level is not an object: "
                f"{type(loaded).__name__}"
            )
            return {"state": "idle"}, True
        return loaded, False
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        error_log(f"work-on-plans-state.json unparseable: {exc}")
        return {"state": "idle"}, True


# ---------------------------------------------------------------------------
# Staleness rule (Shared Schemas)
# ---------------------------------------------------------------------------


_EVERY_RE = re.compile(r"^every\s+(\d+)([hm])\b", re.IGNORECASE)


def _parse_schedule_grace_secs(schedule: str) -> Optional[int]:
    """`every <N>{h|m}` → interval_secs + 1800 (30min grace).
    Returns None for unparseable schedules.
    """
    m = _EVERY_RE.match(schedule.strip()) if schedule else None
    if not m:
        return None
    n = int(m.group(1))
    unit = m.group(2).lower()
    secs = n * (3600 if unit == "h" else 60)
    return secs + 1800


def _is_stale(doc: Dict[str, Any]) -> Tuple[bool, str]:
    """Apply the Shared Schemas staleness rule.

    Returns (is_stale, reason). Reason is empty when fresh.
    """
    state = doc.get("state", "idle")
    if state == "scheduled":
        last_fire = doc.get("last_fire_at", "")
        if not last_fire:
            return False, ""
        grace = _parse_schedule_grace_secs(doc.get("schedule", ""))
        if grace is None:
            return False, ""
        try:
            last = datetime.fromisoformat(last_fire)
            now = datetime.now(tz=last.tzinfo) if last.tzinfo else datetime.now()
            if (now - last).total_seconds() > grace:
                return True, (
                    f"scheduled entry stale (last fire {last_fire})"
                )
        except (ValueError, TypeError):
            return False, ""
        return False, ""
    if state == "sprint":
        updated = doc.get("updated_at", "")
        if not updated:
            return False, ""
        try:
            last = datetime.fromisoformat(updated)
            now = datetime.now(tz=last.tzinfo) if last.tzinfo else datetime.now()
            if (now - last).total_seconds() > 1800:
                return True, (
                    f"sprint entry stale (last update {updated})"
                )
        except (ValueError, TypeError):
            return False, ""
        return False, ""
    return False, ""


# ---------------------------------------------------------------------------
# Body validation for POST /api/queue
# ---------------------------------------------------------------------------


def _validate_queue_body(body: Any) -> Optional[str]:
    """Return None if body is the correct queue shape, else an error
    string explaining the violation.
    """
    if not isinstance(body, dict):
        return "body is not an object"
    allowed_top = {"default_mode", "plans", "issues", "version", "updated_at"}
    for k in body.keys():
        if k not in allowed_top:
            return f"unexpected top-level key: {k}"
    if "default_mode" in body:
        dm = body["default_mode"]
        if dm not in DEFAULT_MODE_VALUES:
            return f"default_mode must be one of {DEFAULT_MODE_VALUES}"
    plans = body.get("plans")
    if not isinstance(plans, dict):
        return "plans must be an object"
    # Explicit reject for `completed` — read-only API surface (derived
    # per-snapshot from plan frontmatter `completed:`). Placed BEFORE the
    # generic unknown-column loop so the error message is specific and
    # diagnosable without server logs (DA6: hard-cut migration boundary).
    if "completed" in plans:
        return (
            "completed column is read-only on the API; cannot accept POSTs "
            "(derived per-snapshot from plan frontmatter completed: field)"
        )
    for col in plans.keys():
        if col not in PLAN_COLUMNS:
            return f"unexpected plans column: {col}"
    seen_slugs = set()
    for col in PLAN_COLUMNS:
        entries = plans.get(col, [])
        if not isinstance(entries, list):
            return f"plans.{col} must be a list"
        for entry in entries:
            if not isinstance(entry, dict):
                return f"plans.{col} entry must be an object"
            slug = entry.get("slug")
            if not isinstance(slug, str) or not SLUG_RE.match(slug):
                return f"plans.{col} entry slug invalid: {slug!r}"
            if slug in seen_slugs:
                return f"duplicate slug across plan columns: {slug}"
            seen_slugs.add(slug)
            if "mode" in entry and entry["mode"] is not None:
                if entry["mode"] not in DEFAULT_MODE_VALUES:
                    return f"plans.{col} entry mode invalid: {entry['mode']!r}"
            extra = set(entry.keys()) - {"slug", "mode"}
            if extra:
                return f"plans.{col} entry has unexpected keys: {sorted(extra)}"
    issues = body.get("issues")
    if not isinstance(issues, dict):
        return "issues must be an object"
    # Explicit reject for `completed` — read-only API surface (derived
    # per-snapshot from GitHub issue state). Placed BEFORE the generic
    # unknown-column loop so the error message is specific and diagnosable
    # without server logs (DA6: hard-cut migration boundary).
    if "completed" in issues:
        return (
            "completed column is read-only on the API; cannot accept POSTs "
            "(derived per-snapshot from GitHub issue state)"
        )
    for col in issues.keys():
        if col not in ISSUE_COLUMNS:
            return f"unexpected issues column: {col}"
    seen_issues = set()
    for col in ISSUE_COLUMNS:
        entries = issues.get(col, [])
        if not isinstance(entries, list):
            return f"issues.{col} must be a list"
        for n in entries:
            if not isinstance(n, int) or isinstance(n, bool):
                return f"issues.{col} entry must be int: {n!r}"
            if n in seen_issues:
                return f"duplicate issue across issue columns: {n}"
            seen_issues.add(n)
    return None


# ---------------------------------------------------------------------------
# Trigger-config validation (startup + POST /api/trigger)
# ---------------------------------------------------------------------------


def validate_trigger_config(
    main_root: pathlib.Path,
    cfg: Dict[str, Any],
) -> Optional[Dict[str, str]]:
    """Validate `dashboard.work_on_plans_trigger` if set. Returns an
    `errors[]` entry on failure, else None.
    """
    dashboard = cfg.get("dashboard")
    if not isinstance(dashboard, dict):
        return None
    trig = dashboard.get("work_on_plans_trigger", "")
    if not trig:
        return None
    try:
        resolved = (main_root / trig).resolve() if not pathlib.Path(trig).is_absolute() else pathlib.Path(trig).resolve()
    except (OSError, RuntimeError) as exc:
        return {
            "source": "dashboard.work_on_plans_trigger",
            "message": f"path could not be resolved: {exc}",
        }
    try:
        resolved.relative_to(main_root.resolve())
    except ValueError:
        return {
            "source": "dashboard.work_on_plans_trigger",
            "message": f"trigger path escapes MAIN_ROOT: {trig}",
        }
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        return {
            "source": "dashboard.work_on_plans_trigger",
            "message": f"trigger path not executable: {trig}",
        }
    return None


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------


class MonitorHandler(BaseHTTPRequestHandler):
    """HTTP handler for the monitor dashboard. Each instance has access
    to the bound `server.context` dict (set in `main()`).
    """

    server_version = "zskills-dashboard/0.1"
    sys_version = ""  # Suppress Python/<ver> in Server header

    # --------------------------------------------------------------- helpers

    def _ctx(self) -> Dict[str, Any]:
        return self.server.context  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        # Default BaseHTTPRequestHandler.log_message writes to stderr;
        # keep behavior — useful when running under nohup.
        sys.stderr.write(
            "[%s] %s - - %s\n" % (self.log_date_time_string(), self.address_string(), format % args)
        )

    def _send_json(self, code: int, payload: Any, *, no_store: bool = False) -> None:
        try:
            body = json.dumps(payload).encode("utf-8")
        except (TypeError, ValueError) as exc:
            body = json.dumps({"error": f"json encode failure: {exc}"}).encode("utf-8")
            code = 500
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if no_store:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, code: int, path: pathlib.Path, content_type: str) -> None:
        try:
            data = path.read_bytes()
        except OSError as exc:
            self._send_json(404, {"error": f"static file unreadable: {exc}"})
            return
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_request_body(self) -> Tuple[Optional[bytes], Optional[str]]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return None, "invalid Content-Length"
        if length < 0:
            return None, "negative Content-Length"
        if length == 0:
            return b"", None
        try:
            data = self.rfile.read(length)
        except OSError as exc:
            return None, f"socket read failed: {exc}"
        return data, None

    def _origin_ok(self) -> bool:
        """CSRF check — accept localhost same-host Origin (any port, any scheme).

        Policy:

        1. Missing Origin header  -> ACCEPT. Some browsers/proxies strip
           the Origin header on same-origin POSTs; treating missing-Origin
           as same-origin is the OWASP-recommended posture for
           localhost-bound services.
        2. Origin == "null"       -> ACCEPT. Browsers emit this for
           opaque-origin contexts (post-redirect, sandboxed iframes).
        3. Origin host portion is `127.0.0.1` or `localhost`. ACCEPT
           regardless of port or scheme.
        4. Anything else (e.g., http://evil.com)                 -> REJECT.

        Rationale for accepting any port on loopback (relaxed after the
        Phase 5b port-match check broke container-port-forwarded
        deployments — see issue trail PR #253 → #268):

        The cross-origin rejection invariant lives in rule 4. An attacker
        page at http://evil.example/ sends `Origin: http://evil.example`
        on its fetches — host fails the loopback check and rule 4 rejects
        with 403. A browser cannot forge `Origin: http://127.0.0.1:<n>`
        from a remote context — the Origin header is set by the browser
        from the page's actual location, not by JS. So the only way an
        `Origin: http://127.0.0.1:<port>` reaches the server is if the
        user is loading the page from their own loopback, which means
        they already control that surface and CSRF is moot.

        Port-matching adds zero security here; it only breaks
        port-forwarded dev environments (docker auto-forward, VS Code
        devcontainers, codespaces, `ssh -L`). In each of those cases,
        the browser sees the forwarded port (e.g., 8081) while the
        server binds the internal port (e.g., 8080), so a port-strict
        check produces a 403 on every POST despite identical loopback
        host. The relaxed policy accepts these.
        """
        origin = self.headers.get("Origin", "")
        # Rule 1 + 2: empty or "null" Origin -> accept.
        if origin == "" or origin == "null":
            return True
        # Rules 3 + 4: parse host portion; loopback is the only same-host
        # signal that matters (port is irrelevant on a non-routable host).
        try:
            parsed = urllib.parse.urlsplit(origin)
        except ValueError:
            return False
        host = (parsed.hostname or "").lower()
        return host in ("127.0.0.1", "localhost")

    # --------------------------------------------------------------- routing

    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        try:
            self._dispatch_get()
        except BrokenPipeError:
            return
        except Exception as exc:  # pragma: no cover — last-ditch surface
            try:
                self._send_json(500, {"error": f"server: {exc!r}"})
            except Exception:
                pass

    def do_POST(self) -> None:  # noqa: N802
        try:
            self._dispatch_post()
        except BrokenPipeError:
            return
        except Exception as exc:  # pragma: no cover
            try:
                self._send_json(500, {"error": f"server: {exc!r}"})
            except Exception:
                pass

    def _dispatch_get(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        # Path is already %-decoded by BaseHTTPRequestHandler? No — the
        # raw request line is preserved in self.path. Decode explicitly.
        decoded_path = urllib.parse.unquote(parsed.path)
        if decoded_path == "/":
            self._serve_static_index()
            return
        if decoded_path == "/app.js":
            self._serve_static_file("app.js", "application/javascript")
            return
        if decoded_path == "/app.css":
            self._serve_static_file("app.css", "text/css")
            return
        if decoded_path == "/api/health":
            self._handle_health()
            return
        if decoded_path == "/api/state":
            self._handle_state()
            return
        if decoded_path.startswith("/api/plan/"):
            slug = decoded_path[len("/api/plan/") :]
            self._handle_plan_detail(slug)
            return
        if decoded_path.startswith("/api/issue/"):
            num = decoded_path[len("/api/issue/") :]
            self._handle_issue(num)
            return
        if decoded_path == "/api/work-state":
            self._handle_work_state_get()
            return
        self._send_json(404, {"error": f"unknown path: {decoded_path}"})

    def _dispatch_post(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        decoded_path = urllib.parse.unquote(parsed.path)
        if decoded_path == "/api/queue":
            self._handle_queue_post()
            return
        if decoded_path == "/api/trigger":
            self._handle_trigger_post()
            return
        if decoded_path == "/api/work-state/reset":
            self._handle_work_state_reset()
            return
        self._send_json(404, {"error": f"unknown POST path: {decoded_path}"})

    # ------------------------------------------------------------- handlers

    def _serve_static_index(self) -> None:
        ctx = self._ctx()
        static_dir = ctx["static_dir"]
        index = static_dir / "index.html"
        if index.is_file():
            self._serve_index_with_cache_bust(index, static_dir)
            return
        # Phase 6 hasn't shipped UI yet — return a friendly placeholder
        # rather than 404 so /api/health and curl smoke land cleanly.
        body = (
            b"<!DOCTYPE html><meta charset=utf-8><title>zskills dashboard</title>"
            b"<p>Dashboard UI ships in Phase 6. The HTTP API is live; try "
            b"<code>/api/health</code> or <code>/api/state</code>.</p>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_static_file(self, name: str, content_type: str) -> None:
        ctx = self._ctx()
        path = ctx["static_dir"] / name
        if not path.is_file():
            self._send_json(404, {"error": f"{name} not present (Phase 6)"})
            return
        self._send_static(200, path, content_type)

    def _serve_index_with_cache_bust(
        self, index: pathlib.Path, static_dir: pathlib.Path
    ) -> None:
        # Substitute ?v=<mtime_ns> into the <link href> and <script src>
        # references so a browser cache picks up CSS/JS edits on the next
        # normal page reload (no hard-refresh required). mtime_ns auto-
        # updates on any file edit — independent of skill-versioning.
        try:
            html = index.read_bytes()
        except OSError as exc:
            self._send_json(500, {"error": f"index.html unreadable: {exc}"})
            return
        for asset, ref in (("app.css", b'href="/app.css"'), ("app.js", b'src="/app.js"')):
            try:
                mtime_ns = (static_dir / asset).stat().st_mtime_ns
            except OSError:
                continue  # asset missing → leave reference untouched
            replacement = ref[:-1] + f'?v={mtime_ns}"'.encode("ascii")
            html = html.replace(ref, replacement, 1)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)

    def _handle_health(self) -> None:
        ctx = self._ctx()
        # Self-heal the PID file if it was removed externally while we live
        # (e.g., a stale `rm` from another session). Cheap: existence check
        # short-circuits when the file is present, which is the hot path.
        # Suppressed during shutdown: the SIGTERM handler removed the file
        # intentionally, and re-writing it would race cleanup and leave a
        # pidfile pointing at a dying process.
        pid_path = ctx["main_root"] / ".zskills" / "dashboard-server.pid"
        shutting_down = ctx.get("shutting_down")
        is_shutting_down = shutting_down is not None and shutting_down.is_set()
        if not pid_path.exists() and not is_shutting_down:
            try:
                write_pid_file(ctx["main_root"], ctx["port"])
            except OSError:
                # Best-effort; do not fail the health check on a transient
                # filesystem error. The next health request will retry.
                pass
        payload = {
            "status": "ok",
            "uptime": int(time.time() - ctx["started_mono"]),
            "pid": os.getpid(),
            "port": ctx["port"],
        }
        self._send_json(200, payload)

    def _handle_state(self) -> None:
        ctx = self._ctx()
        main_root = ctx["main_root"]
        # Phase 4 collect_snapshot — produces JSON-serializable dict.
        # Issue #281: ctx['main_root'] is set ONCE at startup
        # (main(), bind+context block). All handlers (POST + GET) read
        # from ctx unmutated. Pass pre_resolved=True so collect_snapshot
        # does NOT redundantly invoke `_resolve_main_root` (a
        # subprocess `git rev-parse --git-common-dir`) on every state
        # GET, and — more importantly — so the GET path is structurally
        # symmetric with POST handlers (both anchor on ctx).
        try:
            snapshot = _collect.collect_snapshot(
                main_root, pre_resolved=True
            )
        except Exception as exc:
            self._send_json(500, {"error": f"collect_snapshot failed: {exc!r}"})
            return
        # Re-validate trigger config on every state read; surfaces config
        # errors live without restart.
        cfg = _read_config(main_root)
        trig_err = validate_trigger_config(main_root, cfg)
        if trig_err is not None:
            errs = list(snapshot.get("errors", []))
            errs.append(trig_err)
            snapshot["errors"] = sorted(
                errs, key=lambda r: (r.get("source", ""), r.get("message", ""))
            )
        # Per route table: Cache-Control: no-store
        self._send_json(200, snapshot, no_store=True)

    def _handle_plan_detail(self, slug: str) -> None:
        # Defense in depth: SLUG_RE is the only thing that gates the
        # in-memory dict lookup. Reject anything else with 400 (incl.
        # %2F / decoded path-separator escapes).
        if not slug or not SLUG_RE.match(slug):
            self._send_json(400, {"error": f"invalid slug: {slug!r}"})
            return
        ctx = self._ctx()
        main_root: pathlib.Path = ctx["main_root"]
        plans_dir = _resolve_paths(main_root)["plans_dir"]
        if not plans_dir.is_dir():
            self._send_json(404, {"error": f"plans dir not found: {plans_dir}"})
            return
        # Build slug→file dict every request — small cost, fresh data.
        slug_to_file: Dict[str, pathlib.Path] = {}
        for f in sorted(plans_dir.glob("*.md")):
            slug_to_file[_collect.slug_of(f)] = f
        if slug not in slug_to_file:
            self._send_json(404, {"error": f"plan not found: {slug}"})
            return
        plan_file = slug_to_file[slug]
        parsed = _collect.parse_plan(plan_file)
        if parsed is None:
            self._send_json(500, {"error": f"failed to parse plan: {slug}"})
            return
        # Drop the raw _content key (internal); enrich with report.
        parsed.pop("_content", "")
        report = _collect.parse_report(slug, main_root)
        parsed["report"] = report
        # Activity scoped to this plan (best-effort filter on slug field).
        all_activity = _collect._scan_tracking_markers(main_root, errors=[])
        parsed["activity"] = [
            a for a in all_activity if slug in str(a.get("pipeline", ""))
        ]
        self._send_json(200, parsed)

    def _handle_issue(self, num: str) -> None:
        if not num or not ISSUE_RE.match(num):
            self._send_json(400, {"error": f"invalid issue number: {num!r}"})
            return
        try:
            result = subprocess.run(
                [
                    "gh",
                    "issue",
                    "view",
                    num,
                    "--json",
                    "number,title,body,labels,comments,state",
                ],
                capture_output=True,
                text=True,
                timeout=GH_ISSUE_TIMEOUT_SECS,
            )
        except subprocess.TimeoutExpired:
            self._send_json(504, {"error": f"gh issue view {num}: timeout"})
            return
        except (subprocess.SubprocessError, FileNotFoundError, OSError) as exc:
            self._send_json(502, {"error": f"gh: {exc}"})
            return
        if result.returncode != 0:
            stderr_first = (result.stderr or "").splitlines()
            first = stderr_first[0] if stderr_first else f"rc={result.returncode}"
            self._send_json(502, {"error": first})
            return
        try:
            payload = json.loads(result.stdout)
        except (json.JSONDecodeError, ValueError) as exc:
            self._send_json(502, {"error": f"gh json parse: {exc}"})
            return
        self._send_json(200, payload)

    def _handle_queue_post(self) -> None:
        if not self._origin_ok():
            self._send_json(403, {"error": "Origin check failed"})
            return
        body_bytes, err = self._read_request_body()
        if err is not None or body_bytes is None:
            self._send_json(400, {"error": err or "unreadable body"})
            return
        try:
            payload = json.loads(body_bytes.decode("utf-8") or "null")
        except (json.JSONDecodeError, ValueError, UnicodeDecodeError) as exc:
            self._send_json(400, {"error": f"json parse: {exc}"})
            return
        bad = _validate_queue_body(payload)
        if bad is not None:
            self._send_json(400, {"error": bad})
            return
        ctx = self._ctx()
        main_root: pathlib.Path = ctx["main_root"]
        with _state_lock(main_root):
            existing = _read_monitor_state(main_root)
            existing_dm = existing.get("default_mode", "phase")
            new_doc = {
                "version": "1.2",
                "default_mode": payload.get("default_mode", existing_dm),
                "plans": {c: payload["plans"].get(c, []) for c in PLAN_COLUMNS},
                "issues": {c: payload["issues"].get(c, []) for c in ISSUE_COLUMNS},
                "updated_at": _now_iso(),
            }
            target = main_root / ".zskills" / "monitor-state.json"
            _atomic_write_json(target, new_doc)
        self._send_json(200, {"ok": True, "updated_at": new_doc["updated_at"], "state_updated_at": new_doc["updated_at"]})

    def _handle_trigger_post(self) -> None:
        if not self._origin_ok():
            self._send_json(403, {"error": "Origin check failed"})
            return
        body_bytes, err = self._read_request_body()
        if err is not None or body_bytes is None:
            self._send_json(400, {"error": err or "unreadable body"})
            return
        try:
            payload = json.loads(body_bytes.decode("utf-8") or "null")
        except (json.JSONDecodeError, ValueError, UnicodeDecodeError) as exc:
            self._send_json(400, {"error": f"json parse: {exc}"})
            return
        if not isinstance(payload, dict) or "command" not in payload:
            self._send_json(400, {"error": "body must be {command: <str>}"})
            return
        command = payload.get("command", "")
        if not isinstance(command, str):
            self._send_json(400, {"error": "command must be a string"})
            return
        if not TRIGGER_CMD_RE.match(command):
            self._send_json(400, {"error": "command must start with /work-on-plans"})
            return
        ctx = self._ctx()
        main_root: pathlib.Path = ctx["main_root"]
        cfg = _read_config(main_root)
        trig_path = ""
        if isinstance(cfg.get("dashboard"), dict):
            trig_path = cfg["dashboard"].get("work_on_plans_trigger", "")
        if not trig_path:
            self._send_json(501, {"command": command})
            return
        # Path resolution: against MAIN_ROOT, follow symlinks, then
        # re-check inside MAIN_ROOT.
        try:
            if pathlib.Path(trig_path).is_absolute():
                resolved = pathlib.Path(trig_path).resolve()
            else:
                resolved = (main_root / trig_path).resolve()
        except (OSError, RuntimeError) as exc:
            self._send_json(500, {"error": f"trigger path resolve failed: {exc}"})
            return
        try:
            resolved.relative_to(main_root.resolve())
        except ValueError:
            self._send_json(500, {"error": "trigger path escapes MAIN_ROOT"})
            return
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            self._send_json(
                500, {"error": f"trigger path not executable: {trig_path}"}
            )
            return
        # Environment scrubbing
        env = {
            k: v for k, v in os.environ.items()
            if k in {"PATH", "HOME", "USER", "LANG"}
        }
        if "PATH" not in env:
            env["PATH"] = "/usr/bin:/bin"
        try:
            result = subprocess.run(
                [str(resolved), command],
                cwd=str(main_root),
                env=env,
                capture_output=True,
                text=True,
                timeout=TRIGGER_TIMEOUT_SECS,
                shell=False,
            )
        except subprocess.TimeoutExpired as exc:
            stderr_text = (
                exc.stderr.decode("utf-8", errors="replace")
                if isinstance(exc.stderr, (bytes, bytearray))
                else (exc.stderr or "")
            )
            self._send_json(504, {"error": "trigger timeout", "stderr": stderr_text})
            return
        except (subprocess.SubprocessError, OSError) as exc:
            self._send_json(500, {"error": f"trigger invoke failed: {exc}"})
            return
        status = "triggered" if result.returncode == 0 else "error"
        self._send_json(
            200,
            {
                "status": status,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
            },
        )

    def _handle_work_state_get(self) -> None:
        ctx = self._ctx()
        main_root: pathlib.Path = ctx["main_root"]

        def err_log(msg: str) -> None:
            sys.stderr.write(f"[work-state] {msg}\n")

        # Phase 7: surface whether a /work-on-plans trigger is configured
        # so the Run/Status widget can pick the right idle render.
        cfg = _read_config(main_root)
        trigger_configured = False
        if isinstance(cfg.get("dashboard"), dict):
            trig = cfg["dashboard"].get("work_on_plans_trigger", "")
            trigger_configured = bool(trig)

        with _state_lock(main_root):
            doc, was_unparseable = _read_work_state(main_root, error_log=err_log)
            target = main_root / ".zskills" / "work-on-plans-state.json"
            if was_unparseable or not target.is_file():
                # Bootstrap-write idle.
                idle = {"state": "idle", "updated_at": _now_iso()}
                _atomic_write_json(target, idle)
                self._send_json(
                    200,
                    {"state": "idle", "trigger_configured": trigger_configured},
                )
                return
            stale, reason = _is_stale(doc)
            if stale:
                idle = {"state": "idle", "updated_at": _now_iso()}
                _atomic_write_json(target, idle)
                self._send_json(
                    200,
                    {
                        "state": "idle",
                        "warning": reason,
                        "trigger_configured": trigger_configured,
                    },
                )
                return
        out = dict(doc)
        out["trigger_configured"] = trigger_configured
        self._send_json(200, out)

    def _handle_work_state_reset(self) -> None:
        if not self._origin_ok():
            self._send_json(403, {"error": "Origin check failed"})
            return
        ctx = self._ctx()
        main_root: pathlib.Path = ctx["main_root"]
        with _state_lock(main_root):
            target = main_root / ".zskills" / "work-on-plans-state.json"
            idle = {"state": "idle", "updated_at": _now_iso()}
            _atomic_write_json(target, idle)
        self._send_json(200, idle)


# ---------------------------------------------------------------------------
# PID file (Shared Schemas: .env-style key=value)
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


def write_pid_file(main_root: pathlib.Path, port: int) -> pathlib.Path:
    pid_path = main_root / ".zskills" / "dashboard-server.pid"
    body = (
        f"pid={os.getpid()}\n"
        f"port={port}\n"
        f"started_at={_now_iso()}\n"
    )
    tmp = pid_path.with_suffix(pid_path.suffix + ".tmp")
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(body, encoding="utf-8")
    os.replace(str(tmp), str(pid_path))
    return pid_path


def remove_pid_file(pid_path: pathlib.Path) -> None:
    try:
        pid_path.unlink()
    except FileNotFoundError:
        return


# ---------------------------------------------------------------------------
# Server lifecycle
# ---------------------------------------------------------------------------


def _bind_or_die(host: str, port: int) -> ThreadingHTTPServer:
    try:
        server = ThreadingHTTPServer((host, port), MonitorHandler)
    except OSError as exc:
        if exc.errno in (errno.EADDRINUSE, errno.EACCES):
            sys.stderr.write(
                f"Port {port} is already in use. Run 'lsof -i :{port}' to "
                f"find the holder and stop it manually (no kill -9). If "
                f".zskills/dashboard-server.pid is stale, rm it and retry "
                f"/zskills-dashboard start.\n"
            )
            raise SystemExit(2)
        raise
    return server


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python3 -m zskills_monitor.server",
        description="Localhost HTTP API for the zskills dashboard (Phase 5).",
    )
    p.add_argument("--port", type=int, default=None,
                   help="Override port (highest priority).")
    p.add_argument("--main-root", default=None,
                   help="Override MAIN_ROOT (used by tests).")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.main_root:
        main_root = pathlib.Path(args.main_root).resolve()
    else:
        main_root = resolve_main_root()

    # Ensure .zskills/ exists before any state write
    (main_root / ".zskills").mkdir(parents=True, exist_ok=True)

    # Note: .claude/zskills-config.json is READ-ONLY for the server.
    # The dashboard.work_on_plans_trigger field is added by
    # /update-zskills (schema migration), not bootstrapped here.

    port = resolve_port(main_root, cli_port=args.port)

    server = _bind_or_die(BIND_HOST, port)

    static_dir = pathlib.Path(__file__).resolve().parent / "static"
    started_mono = time.time()
    shutdown_done = threading.Event()
    server.context = {  # type: ignore[attr-defined]
        "main_root": main_root,
        "port": port,
        "started_mono": started_mono,
        "static_dir": static_dir,
        # _handle_health checks this to suppress PID-file self-heal once
        # SIGTERM has fired (otherwise inflight polls re-create the file
        # the shutdown handler just removed).
        "shutting_down": shutdown_done,
    }

    pid_path = write_pid_file(main_root, port)

    def _shutdown(signum, frame):  # noqa: ARG001
        if shutdown_done.is_set():
            return
        shutdown_done.set()
        # server.shutdown() blocks until serve_forever() returns, and
        # MUST be called from a different thread (deadlock otherwise).
        # Use a non-daemon thread so the process keeps running until
        # cleanup completes.
        def _finalize():
            try:
                server.shutdown()
            finally:
                try:
                    server.server_close()
                finally:
                    remove_pid_file(pid_path)
        threading.Thread(target=_finalize, daemon=False).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    sys.stderr.write(
        f"zskills dashboard listening on http://{BIND_HOST}:{port} "
        f"(main_root={main_root}, pid={os.getpid()})\n"
    )
    # Boot-time inspectability for the v1.1→v1.2 hard-cut migration
    # boundary (DA6). Operators diagnosing "v1.2 client + v1.1 server"
    # mismatch grep this line to confirm the server's column tuples and
    # state-file schema version at boot.
    sys.stderr.write(
        f"PLAN_COLUMNS={PLAN_COLUMNS} ISSUE_COLUMNS={ISSUE_COLUMNS} "
        f"state_version=1.2\n"
    )
    sys.stderr.flush()
    try:
        server.serve_forever()
    finally:
        # Belt-and-suspenders cleanup if serve_forever exits without signal
        if not shutdown_done.is_set():
            server.server_close()
            remove_pid_file(pid_path)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
