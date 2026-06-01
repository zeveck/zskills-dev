#!/usr/bin/env python3
"""
zskills_monitor.collect — Pure-Python aggregation library for the
zskills dashboard (Phase 4 of ZSKILLS_MONITOR_PLAN).

stdlib-only. No HTTP coupling. Importable + callable from a fresh REPL.

Canonical CLI:
    PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \\
      python3 -m zskills_monitor.collect [--fixture DIR] [--repo-root DIR]

`collect_snapshot(repo_root)` returns the JSON-serializable dict
documented in plans/ZSKILLS_MONITOR_PLAN.md (Phase 4 Design section).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION = "1.0"

# Top-level keys that callers (Phases 5/6/7/9) rely on. Stable contract.
SNAPSHOT_TOP_LEVEL_KEYS = {
    "version",
    "updated_at",
    "state_updated_at",
    "repo_root",
    "repo_url",
    "plans",
    "issues",
    "worktrees",
    "branches",
    "activity",
    "queues",
    "state_file_path",
    "errors",
    "issues_fetch_ok",
    "flags",
}

# Phase heading: `## Phase N <sep> Name` where <sep> is em-dash, en-dash,
# colon, or hyphen. All four are accepted because hand-authored plans use
# them interchangeably; the canonical form documented in /draft-plan and
# /plans is em-dash, but rejecting `:` silently demotes valid plans to
# Reference (issue #183).
PHASE_HEADING_RE = re.compile(r"^##\s+Phase\s+(\S+)\s*[—–:\-]\s*(.+)$", re.MULTILINE)

# Progress-tracker row marker — used to find the table.
TRACKER_HEADER_RE = re.compile(r"^\|\s*Phase\s*\|", re.MULTILINE)

# Status-glyph map (per plan).
STATUS_GLYPHS = {
    "⬚": "todo",
    "⏳": "in-progress",
    "⚙️": "in-progress",
    "✅": "done",
    "🔴": "blocked",
}

# Done glyphs / words that imply phase done in tracker rows.
DONE_TOKENS = {"✅", "Done", "done", "DONE"}

# Tracking-marker basename pattern.
MARKER_BASENAME_RE = re.compile(r"^(requires|fulfilled|step)\.(.+)$")

# Marker `key: value` line.
MARKER_LINE_RE = re.compile(r"^(\w+):\s*(.+)$")

# Meta-plan / sub-plan extraction.
META_SKILL_RE = re.compile(
    r"""Skill\s*:\s*\{\s*skill\s*:\s*["']run-plan["'][^}]*?args\s*:\s*["']([^"']+)["']""",
    re.DOTALL,
)

# Errors[] cap.
ERRORS_CAP = 100

# gh issue cache TTL (seconds).
ISSUE_CACHE_TTL_SECONDS = 60

# Per-subsystem collect_snapshot fan-out TTLs (seconds). Tuned to each
# subsystem's natural change frequency vs the 2Hz client poll cadence.
# See issue #514 for the latency analysis that motivated this.
#
# `time.monotonic()` is the TTL clock — NOT `time.time()` — because wall
# clock can jump on NTP sync. Monotonic guarantees a non-decreasing tick
# regardless of wall-time corrections.
SNAPSHOT_CACHE_TTL_WORKTREES = 5.0       # git worktree list
SNAPSHOT_CACHE_TTL_BRANCHES = 5.0        # git for-each-ref
SNAPSHOT_CACHE_TTL_GIT_HISTORY = 10.0    # git log
SNAPSHOT_CACHE_TTL_PLANS = 3.0           # parse_plan + parse_report + landing-mode
SNAPSHOT_CACHE_TTL_TRACKING = 3.0        # .zskills/tracking/ walk + PR-number scan

# Remote-tracking-ref freshness TTL (seconds). SEPARATE from (and far
# longer than) SNAPSHOT_CACHE_TTL_BRANCHES: the 5s branch cache governs how
# often we re-READ refs, while this governs how often we `git fetch --prune`
# to REFRESH the remote-tracking refs from origin. A network round-trip is
# expensive and origin moves slowly relative to the 2Hz client poll, so the
# default is 120s. Override via `dashboard.branch_fetch_ttl_seconds` in
# `.claude/zskills-config.json`. The fetch is non-fatal — a failure records
# an `errors[]` entry and the last-known remote refs are rendered.
BRANCH_FETCH_TTL = 120.0


# ---------------------------------------------------------------------------
# Module-level cache (per-Python-process; documented limitation per DA-14)
# ---------------------------------------------------------------------------

_ISSUE_CACHE: Dict[str, Any] = {
    "ts": 0.0,
    "issues": [],
    "had_value": False,
}

# Separate cache for the closed-issue fetch (D6 — independent cache key,
# 60s TTL). Keyed by (days, limit) so a config change invalidates the
# cache naturally instead of returning a stale narrower window.
_CLOSED_ISSUE_CACHE: Dict[Tuple[int, int], Dict[str, Any]] = {}

# Throttle clock for `git fetch --prune` (issue: Branches-panel remote
# state). Keyed by main_root_str → last monotonic fetch timestamp. The fetch
# only ever updates remote-tracking refs; it never touches the working tree,
# index, or local branches.
_BRANCH_FETCH_TS: Dict[str, float] = {}

# Per-subsystem snapshot cache: maps (kind, main_root_str) →
# (monotonic_ts, value, errors_from_that_call). On cache hit, the
# captured errors are re-extended onto the new caller's errors list so
# the per-snapshot errors block stays accurate.
_SNAPSHOT_CACHE: Dict[Tuple[str, str], Tuple[float, Any, List[Dict[str, str]]]] = {}


def _reset_issue_cache_for_tests() -> None:
    """Reset the module-level cache (test-only helper)."""
    _ISSUE_CACHE["ts"] = 0.0
    _ISSUE_CACHE["issues"] = []
    _ISSUE_CACHE["had_value"] = False
    _CLOSED_ISSUE_CACHE.clear()


def _reset_snapshot_cache_for_tests() -> None:
    """Reset the per-subsystem snapshot cache (test-only helper)."""
    _SNAPSHOT_CACHE.clear()
    _BRANCH_FETCH_TS.clear()


def _cached_subsystem(
    kind: str,
    main_root: pathlib.Path,
    ttl: float,
    fn: Any,
    errors: List[Dict[str, str]],
    *,
    _now: Optional[float] = None,
) -> Any:
    """Cache the result of `fn(local_errors)` keyed by (kind, main_root).

    `fn` is called with a fresh `local_errors` list so cached error
    records can be replayed without double-counting on cache hits. If
    `fn` raises, the cache is NOT updated — fail-loud, no stale value
    poisoning. The monotonic clock is used (NTP-safe). TTL of 0 disables
    caching entirely (always re-fetch).
    """
    now = _now if _now is not None else time.monotonic()
    key = (kind, str(main_root))
    cached = _SNAPSHOT_CACHE.get(key)
    if cached is not None and ttl > 0 and (now - cached[0]) < ttl:
        _ts, value, cached_errors = cached
        if cached_errors:
            errors.extend(cached_errors)
        return value
    local_errors: List[Dict[str, str]] = []
    value = fn(local_errors)
    _SNAPSHOT_CACHE[key] = (now, value, list(local_errors))
    if local_errors:
        errors.extend(local_errors)
    return value


# ---------------------------------------------------------------------------
# briefing.py path-based import (per plan: spec_from_file_location)
# ---------------------------------------------------------------------------

_BRIEFING_MODULE: Any = None


def _load_briefing(main_root: pathlib.Path) -> Any:
    """Path-import skills/briefing/scripts/briefing.py.

    Per plan: use importlib.util.spec_from_file_location rather than
    `from scripts.briefing import …` (broken post-Phase-B). Cached at
    module level after first successful load.
    """
    global _BRIEFING_MODULE
    if _BRIEFING_MODULE is not None:
        return _BRIEFING_MODULE
    briefing_path = (
        pathlib.Path(main_root)
        / "skills"
        / "briefing"
        / "scripts"
        / "briefing.py"
    )
    spec = importlib.util.spec_from_file_location(
        "_zskills_monitor_briefing", str(briefing_path)
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load briefing module from {briefing_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _BRIEFING_MODULE = module
    return module


# ---------------------------------------------------------------------------
# Slug rule (canonical, single source of truth)
# ---------------------------------------------------------------------------


def slug_of(path: Any) -> str:
    """Canonical slug rule.

    `basename(path, ".md") | tr '[:upper:]_' '[:lower:]-'`.

    Identical to `/run-plan`'s inline `tr` and Phase 1's
    `/work-on-plans` slug→file resolver. Phase 4's exposure of the
    same rule for reuse by Phase 9 + later callers.
    """
    p = pathlib.Path(str(path))
    base = p.name
    if base.endswith(".md"):
        base = base[:-3]
    # tr '[:upper:]_' '[:lower:]-'
    return base.lower().replace("_", "-")


# ---------------------------------------------------------------------------
# repo_root resolution (always main, never cwd-relative)
# ---------------------------------------------------------------------------


def _resolve_main_root(repo_root: Any) -> pathlib.Path:
    """Resolve a worktree-or-main path to the MAIN_ROOT.

    A worktree is identified by `.git` being a *file* (gitlink) rather
    than a *directory*. Use briefing.find_repo_root + .git inspection
    to always return the main worktree root.

    Opt-in override: set ``ZSKILLS_DASHBOARD_ROOT`` to an existing
    directory and this function returns that path immediately, bypassing
    the git-common-dir hop.  This lets agents in worktrees point the
    dashboard at their worktree's filesystem for visual verification.
    """
    override = os.environ.get("ZSKILLS_DASHBOARD_ROOT")
    if override:
        op = pathlib.Path(override)
        if op.is_dir():
            return op.resolve()
    p = pathlib.Path(str(repo_root)).resolve()
    # If invoked from a worktree, hop to the main checkout. The
    # canonical idiom is `git rev-parse --git-common-dir` + parent.
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=str(p),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            common_dir = pathlib.Path(result.stdout.strip())
            if not common_dir.is_absolute():
                common_dir = (p / common_dir).resolve()
            # parent of `.git` (or git-common-dir) is the main checkout
            if common_dir.name == ".git" or common_dir.name == "":
                return common_dir.parent.resolve()
            return common_dir.parent.resolve()
    except Exception:
        pass
    return p


# ---------------------------------------------------------------------------
# Path config (mirrors zskills-paths.sh / briefing helpers)
# ---------------------------------------------------------------------------


def _resolve_paths(main_root: pathlib.Path) -> Dict[str, pathlib.Path]:
    """Resolve audit / plans / issues dirs from zskills-config.json.

    Mirrors the bash zskills-paths.sh helper, briefing.py:read_zskills_paths,
    and server.py:_resolve_paths.

    Use-as-is is absolute-only: only paths starting with `/` are absolute;
    all other forms are joined with main_root (Locked Decision 1).

    LOCKSTEP NOTE: when editing this body, mirror the change in
    server.py:_resolve_paths — they are intentional duplicates per Phase 4
    helper-share decision (separate processes, no shared module).

    Missing/malformed config -> silent empty fallback (legacy `plans`).
    """
    cfg_path = main_root / ".claude" / "zskills-config.json"
    text = _read_text(cfg_path)
    cfg: Any = {}
    if text is not None:
        try:
            cfg = json.loads(text)
        except Exception:
            cfg = {}
    output = cfg.get("output", {}) if isinstance(cfg, dict) else {}
    if not isinstance(output, dict):
        output = {}
    plans_rel = output.get("plans_dir") or "plans"
    issues_rel = output.get("issues_dir") or "plans"
    reports_rel = output.get("reports_dir")  # absent → legacy fallback

    def _resolve(rel: str) -> pathlib.Path:
        p = pathlib.Path(rel)
        return p if p.is_absolute() else main_root / rel

    audit_dir = main_root / ".zskills" / "audit"
    reports_dir = _resolve(reports_rel) if reports_rel else audit_dir

    return {
        "plans_dir": _resolve(plans_rel),
        "issues_dir": _resolve(issues_rel),
        "audit_dir": audit_dir,
        "reports_dir": reports_dir,
    }


# ---------------------------------------------------------------------------
# errors[] helpers (sorting + cap)
# ---------------------------------------------------------------------------


def _finalize_errors(errors: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Sort by (source, message) ascending; soft-cap at ERRORS_CAP.

    Sorted output is byte-deterministic for a given error set.
    """
    sortable = []
    for e in errors:
        src = str(e.get("source", ""))
        msg = str(e.get("message", ""))
        sortable.append({"source": src, "message": msg})
    sortable.sort(key=lambda r: (r["source"], r["message"]))
    if len(sortable) <= ERRORS_CAP:
        return sortable
    n_dropped = len(sortable) - ERRORS_CAP
    head = sortable[:ERRORS_CAP]
    head.append({"source": "errors-cap", "message": f"{n_dropped} errors elided"})
    # Re-sort so the summary entry lands deterministically.
    head.sort(key=lambda r: (r["source"], r["message"]))
    return head


# ---------------------------------------------------------------------------
# Plan parsing
# ---------------------------------------------------------------------------


def _read_text(path: pathlib.Path) -> Optional[str]:
    try:
        return path.read_text(encoding="utf-8")
    except Exception:
        return None


def _parse_frontmatter(content: str) -> Dict[str, str]:
    """Parse top-of-file YAML frontmatter using briefing.py's regex idiom.

    Same shape as `def scan_plans` in skills/briefing/scripts/briefing.py
    (anchor: line ~559–579 at the time of writing). No PyYAML.
    """
    fm: Dict[str, str] = {}
    lines = content.split("\n")[:40]
    in_fm = False
    fm_ended = False
    for line in lines:
        stripped = line.strip()
        if stripped == "---" and not in_fm and not fm_ended:
            in_fm = True
            continue
        if stripped == "---" and in_fm:
            fm_ended = True
            in_fm = False
            continue
        if in_fm:
            m = re.match(r"^(\w+):\s*(.+)", stripped)
            if m:
                key = m.group(1).lower()
                val = m.group(2).strip().strip('"').strip("'")
                fm[key] = val
    return fm


def _extract_overview_blurb(content: str) -> str:
    """First non-empty paragraph after `## Overview`, trimmed to 240 chars."""
    m = re.search(r"^##\s+Overview\s*$", content, re.MULTILINE)
    if not m:
        return ""
    after = content[m.end():]
    # Skip blank lines, then read until next blank-line-or-heading.
    lines = after.split("\n")
    paragraph: List[str] = []
    seen_text = False
    for line in lines:
        if line.strip().startswith("##"):
            break
        if not line.strip():
            if seen_text:
                break
            continue
        seen_text = True
        paragraph.append(line.strip())
    blurb = " ".join(paragraph).strip()
    if len(blurb) > 240:
        blurb = blurb[:240]
    return blurb


def _parse_phase_headings(content: str) -> List[Dict[str, Any]]:
    """Return [{n, name}] from `## Phase <N> <sep> Name`.

    `<sep>` may be em-dash (—), en-dash (–), colon (:), or hyphen (-).
    `n` is the phase token as a string (alphanumeric: '1', '5c', 'A').
    """
    out: List[Dict[str, Any]] = []
    for m in PHASE_HEADING_RE.finditer(content):
        token = m.group(1).strip()
        name = m.group(2).strip()
        out.append({"n": token, "name": name})
    return out


def _parse_progress_tracker(content: str) -> List[Dict[str, Any]]:
    """Locate the progress-tracker table and return per-row records.

    Each row has: `n` (phase token), `name`, `status`, `commit`, `notes`.
    Status is mapped via STATUS_GLYPHS or by literal token matching.
    """
    rows: List[Dict[str, Any]] = []
    m = TRACKER_HEADER_RE.search(content)
    if not m:
        return rows
    after = content[m.start():]
    lines = after.split("\n")
    # Skip the header row + separator row, then consume `|`-rows until
    # we hit a non-pipe line.
    started = False
    for line in lines:
        s = line.strip()
        if s.startswith("|"):
            if not started:
                # First row is the header itself; second is `|---|...`.
                started = True
                continue
            # Skip separator (consists only of `|`, `-`, `:`, spaces)
            if re.fullmatch(r"\|[\s\-:|]+\|", s):
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) < 2:
                continue
            # Phase | Status | Commit | Notes
            phase_cell = cells[0]
            status_cell = cells[1] if len(cells) > 1 else ""
            commit_cell = cells[2] if len(cells) > 2 else ""
            notes_cell = cells[3] if len(cells) > 3 else ""

            # Extract phase number/token from "1 — name" style.
            tok_match = re.match(r"^(\S+)", phase_cell)
            token = tok_match.group(1) if tok_match else phase_cell

            # Map status
            status = "todo"
            for glyph, mapped in STATUS_GLYPHS.items():
                if glyph in status_cell:
                    status = mapped
                    break
            else:
                # Word-based fallback
                low = status_cell.lower()
                if "done" in low:
                    status = "done"
                elif "block" in low:
                    status = "blocked"
                elif "progress" in low:
                    status = "in-progress"

            # Strip backticks from commit
            commit = commit_cell.strip("`").strip()
            if commit in ("", "—", "-"):
                commit = None

            rows.append({
                "n": token,
                "name": phase_cell,
                "status": status,
                "commit": commit,
                "notes": notes_cell,
            })
        else:
            if started:
                break
    return rows


def _categorize_plan(
    file_basename: str,
    content: str,
    fm: Dict[str, str],
    phases: List[Dict[str, Any]],
    tracker_rows: List[Dict[str, Any]],
) -> str:
    """Return category in {canary, issue_tracker, reference, executable}."""
    # canary: filename starts with CANARY (case-sensitive)
    if re.match(r"^CANARY", file_basename):
        return "canary"
    # issue_tracker: ends with _ISSUES.md (case-sensitive on ISSUES)
    if re.search(r"_ISSUES\.md$", file_basename):
        return "issue_tracker"
    # reference: explicit frontmatter, or zero phases AND zero tracker
    if str(fm.get("executable", "")).lower() == "false":
        return "reference"
    if not phases and not tracker_rows:
        return "reference"
    return "executable"


def _detect_meta_plan(content: str) -> Tuple[bool, List[str]]:
    """Returns (meta_plan, sub_plans).

    meta_plan = True if at least one `Skill: { skill: "run-plan" …`
    directive is in the body. sub_plans = the slug(s) extracted from
    each such directive's `args:` field.
    """
    matches = META_SKILL_RE.findall(content)
    if not matches:
        return False, []
    sub_plans: List[str] = []
    for args_str in matches:
        # args is typically `plans/<file>.md auto` etc. Take token 0.
        first = args_str.strip().split()[0] if args_str.strip() else ""
        if not first:
            continue
        slug = slug_of(first)
        if slug and slug not in sub_plans:
            sub_plans.append(slug)
    return True, sub_plans


def parse_plan(path: Any) -> Optional[Dict[str, Any]]:
    """Parse a single `plans/*.md` file. Returns None if unreadable."""
    p = pathlib.Path(str(path))
    content = _read_text(p)
    if content is None:
        return None
    fm = _parse_frontmatter(content)
    blurb = _extract_overview_blurb(content)
    phases = _parse_phase_headings(content)
    tracker = _parse_progress_tracker(content)
    phases_done = sum(1 for r in tracker if r.get("status") == "done")
    category = _categorize_plan(p.name, content, fm, phases, tracker)
    meta_plan, sub_plans = _detect_meta_plan(content)
    title = (fm.get("title") or "").strip()
    if not title:
        # Fallback: first H1
        for line in content.split("\n")[:8]:
            mh = re.match(r"^#\s+(.+)", line)
            if mh:
                title = re.sub(r"\s*\(#\d+\)\s*", "", mh.group(1).strip()).strip()
                break
    if not title:
        title = p.stem

    return {
        "slug": slug_of(p),
        "file": str(p),
        "title": title,
        "status": fm.get("status", "").strip() or "active",
        "created": fm.get("created", "").strip(),
        "completed": fm.get("completed", "").strip(),
        "issue": fm.get("issue") or None,
        "blurb": blurb,
        "phase_count": max(len(phases), len(tracker)),
        "phases_done": phases_done,
        "phases": [
            {
                "n": r["n"],
                "name": r["name"],
                "status": r["status"],
                "commit": r["commit"],
                "notes": r["notes"],
            }
            for r in tracker
        ],
        "category": category,
        "meta_plan": meta_plan,
        "sub_plans": sub_plans,
    }


# ---------------------------------------------------------------------------
# Report parsing — `reports/plan-<slug>.md`
# ---------------------------------------------------------------------------

# Section start: `## Phase 5c — Name` OR `## Phase — 5c Name` OR `## Phase — A`.
REPORT_PHASE_RE = re.compile(
    r"^##\s+Phase(?:\s+([A-Za-z0-9]+))?\s*[—-]\s*(.+)$",
    re.MULTILINE,
)


def parse_report(slug: str, main_root: pathlib.Path) -> Optional[Dict[str, Any]]:
    """Parse `<reports_dir>/plan-<slug>.md`. Returns None if absent.

    Per issue #217: plan-<slug>.md reports moved from audit_dir to reports_dir.
    """
    report_path = _resolve_paths(main_root)["reports_dir"] / f"plan-{slug}.md"
    content = _read_text(report_path)
    if content is None:
        return None

    sections: List[Dict[str, Any]] = []
    matches = list(REPORT_PHASE_RE.finditer(content))
    for i, m in enumerate(matches):
        token_a = m.group(1)  # may be None
        rest = m.group(2).strip()
        # Two shapes:
        #   ## Phase 5c — Name   → token_a = "5c", rest = "Name"
        #   ## Phase — 5c Name   → token_a = None, rest = "5c Name"
        #   ## Phase — A         → token_a = None, rest = "A"
        if token_a:
            phase_token = token_a
            phase_name = rest
        else:
            # Try to split first whitespace-delimited token off `rest`
            parts = rest.split(None, 1)
            if len(parts) == 2 and re.match(r"^[A-Za-z0-9]+$", parts[0]):
                phase_token = parts[0]
                phase_name = parts[1]
            else:
                phase_token = rest
                phase_name = rest
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        body = content[start:end]

        section: Dict[str, Any] = {
            "phase_token": phase_token,
            "phase_name": phase_name,
            "body": body.strip(),
        }
        for body_line in body.split("\n"):
            sm = re.match(r"^\*\*Status:\*\*\s*(.+)$", body_line)
            if sm and "status" not in section:
                section["status"] = sm.group(1).strip()
            wm = re.match(r"^\*\*Worktree:\*\*\s*(.+)$", body_line)
            if wm and "worktree" not in section:
                section["worktree"] = wm.group(1).strip()
            bm = re.match(r"^\*\*Branch:\*\*\s*(.+)$", body_line)
            if bm and "branch" not in section:
                section["branch"] = bm.group(1).strip()
            cm = re.match(r"^\*\*Commits?:\*\*\s*(.+)$", body_line)
            if cm and "commits" not in section:
                commits_raw = cm.group(1).strip()
                section["commits"] = [
                    c.strip().strip("`") for c in commits_raw.split(",") if c.strip()
                ]
        sections.append(section)

    return {
        "path": str(report_path.relative_to(main_root)),
        "phases": sections,
    }


# ---------------------------------------------------------------------------
# Tracking-marker scan
# ---------------------------------------------------------------------------


def _parse_marker_file(path: pathlib.Path) -> Optional[Dict[str, str]]:
    """Parse a tracking marker file's `key: value` lines."""
    text = _read_text(path)
    if text is None:
        return None
    fields: Dict[str, str] = {}
    for line in text.split("\n"):
        m = MARKER_LINE_RE.match(line)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    return fields


def _scan_tracking_markers(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    """Walk both flat top-level `.zskills/tracking/*` and one-level-deep
    `.zskills/tracking/*/` subdirs. Dedup with subdir-wins precedence.
    """
    base = main_root / ".zskills" / "tracking"
    if not base.is_dir():
        return []

    # Collect candidates as (basename, path, location, pipeline)
    flat_candidates: List[Tuple[str, pathlib.Path]] = []
    subdir_candidates: List[Tuple[str, pathlib.Path, str]] = []

    try:
        for entry in sorted(base.iterdir()):
            if entry.is_file() and MARKER_BASENAME_RE.match(entry.name):
                flat_candidates.append((entry.name, entry))
            elif entry.is_dir():
                pipeline = entry.name
                try:
                    for sub in sorted(entry.iterdir()):
                        if sub.is_file() and MARKER_BASENAME_RE.match(sub.name):
                            subdir_candidates.append((sub.name, sub, pipeline))
                except Exception as exc:
                    errors.append({
                        "source": "tracking scan",
                        "message": f"could not list {entry}: {exc}",
                    })
    except Exception as exc:
        errors.append({
            "source": "tracking scan",
            "message": f"could not list {base}: {exc}",
        })
        return []

    # Build subdir basename set for dedup checks.
    subdir_basenames = {bn for bn, _, _ in subdir_candidates}

    # Detect (subdir wins) conflict: a flat-only basename that ALSO exists
    # in any subdir → conflict logged, flat dropped.
    activity: List[Dict[str, Any]] = []

    seen_dedup_logged: set = set()

    for bn, p, pipeline in subdir_candidates:
        fields = _parse_marker_file(p)
        if fields is None:
            continue
        ts = fields.get("date") or fields.get("completed")
        if not ts:
            errors.append({
                "source": "tracking marker",
                "message": f"marker {p} missing date/completed",
            })
            continue
        m = MARKER_BASENAME_RE.match(bn)
        kind = m.group(1) if m else "unknown"
        ident = m.group(2) if m else bn
        record = {
            "timestamp": ts,
            "pipeline": pipeline,
            "kind": kind,
            "id": ident,
            "skill": fields.get("skill", ""),
            "status": fields.get("status", ""),
            "output": fields.get("output", ""),
            "location": "pipeline",
            "parent": fields.get("parent") or None,
        }
        activity.append(record)

    for bn, p in flat_candidates:
        if bn in subdir_basenames:
            # Conflict: subdir wins, flat dropped, log once.
            if bn not in seen_dedup_logged:
                errors.append({
                    "source": "tracking dedup",
                    "message": f"{bn}: subdir copy preferred over flat copy",
                })
                seen_dedup_logged.add(bn)
            continue
        fields = _parse_marker_file(p)
        if fields is None:
            continue
        ts = fields.get("date") or fields.get("completed")
        if not ts:
            errors.append({
                "source": "tracking marker",
                "message": f"marker {p} missing date/completed",
            })
            continue
        m = MARKER_BASENAME_RE.match(bn)
        kind = m.group(1) if m else "unknown"
        ident = m.group(2) if m else bn
        record = {
            "timestamp": ts,
            "pipeline": "",
            "kind": kind,
            "id": ident,
            "skill": fields.get("skill", ""),
            "status": fields.get("status", ""),
            "output": fields.get("output", ""),
            "location": "legacy",
            "parent": fields.get("parent") or None,
        }
        activity.append(record)

    # Sort descending by timestamp (parsed as datetime, then UTC-normalized).
    def _sort_key(rec: Dict[str, Any]):
        ts = rec.get("timestamp", "")
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return -dt.astimezone(timezone.utc).timestamp()
        except Exception:
            return 0.0

    activity.sort(key=_sort_key)
    # Cap at 200 in memory.
    return activity[:200]


# ---------------------------------------------------------------------------
# Repo URL helper (for client-side entry-link construction)
# ---------------------------------------------------------------------------

# Accept both HTTPS and SSH origin forms, produce the canonical https URL
# WITHOUT the trailing .git. Returns "" on any failure — client side
# treats empty as "no links available, fall back to plain text."
_GIT_HTTPS_RE = re.compile(r"^https?://([^/]+)/([^/]+/[^/]+?)(?:\.git)?/?$")
_GIT_SSH_RE = re.compile(r"^git@([^:]+):([^/]+/[^/]+?)(?:\.git)?$")


def _derive_repo_url(main_root: pathlib.Path) -> str:
    if not (main_root / ".git").exists():
        return ""
    try:
        result = subprocess.run(
            ["git", "-C", str(main_root), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    url = result.stdout.strip()
    if not url:
        return ""
    m = _GIT_HTTPS_RE.match(url)
    if m:
        return f"https://{m.group(1)}/{m.group(2)}"
    m = _GIT_SSH_RE.match(url)
    if m:
        return f"https://{m.group(1)}/{m.group(2)}"
    return ""


# ---------------------------------------------------------------------------
# Git-history activity (commits that don't have a tracking marker)
# ---------------------------------------------------------------------------

# Subject patterns we extract: trailing "(#N)" PR ref (squash-merge style)
# and any "#N" issue reference. PR_RE is anchored to end-of-string so
# inline "(#999)" body refs don't trigger.
_PR_TRAILER_RE = re.compile(r"\(#(\d+)\)\s*$")
_ISSUE_HASH_RE = re.compile(r"(?:^|\W)#(\d+)\b")


def _scan_git_history(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
    *,
    since_hours: int = 72,
    max_commits: int = 200,
    fulfilled_pr_numbers: Optional[set] = None,
) -> List[Dict[str, Any]]:
    """Read commits from `git log` and emit activity-row records.

    Each commit becomes a record shaped like a tracking-marker record so
    the existing _sort_key + UI renderer accept it without special-casing.
    Commits whose trailing `(#N)` PR number is in `fulfilled_pr_numbers`
    (built from fulfilled.land-pr.* markers) are skipped — the marker is
    richer.
    """
    if not (main_root / ".git").exists():
        return []
    if fulfilled_pr_numbers is None:
        fulfilled_pr_numbers = set()
    since_arg = f"--since={int(since_hours)} hours ago"
    fmt = "%H%x1f%cI%x1f%s"  # SHA, ISO commit date, subject — unit-separator-joined
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(main_root),
                "log",
                since_arg,
                f"--max-count={int(max_commits)}",
                f"--pretty=format:{fmt}",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        errors.append({
            "source": "git history",
            "message": f"git log failed: {exc}",
        })
        return []
    if result.returncode != 0:
        # Empty repo / no commits in window is not an error here. Recognise
        # the canonical "fatal: your current branch ... does not have any
        # commits yet" message so a brand-new repo doesn't show up as a
        # collection error.
        stderr = result.stderr.strip()
        benign = (not stderr) or ("does not have any commits yet" in stderr)
        if not benign:
            errors.append({
                "source": "git history",
                "message": f"git log rc={result.returncode}: {stderr[:200]}",
            })
        return []

    out: List[Dict[str, Any]] = []
    for line in result.stdout.split("\n"):
        line = line.rstrip()
        if not line:
            continue
        parts = line.split("\x1f", 2)
        if len(parts) != 3:
            continue
        sha, iso_date, subject = parts
        pr_num = ""
        m = _PR_TRAILER_RE.search(subject)
        if m:
            pr_num = m.group(1)
            if pr_num in fulfilled_pr_numbers:
                continue  # dedup'd by richer marker
        issue_num = ""
        m2 = _ISSUE_HASH_RE.search(subject)
        if m2 and m2.group(1) != pr_num:
            issue_num = m2.group(1)
        record: Dict[str, Any] = {
            "timestamp": iso_date,
            "pipeline": "",
            "kind": "commit",
            "id": sha[:7],
            "skill": "",
            "status": "",
            "output": "",
            "location": "git",
            "parent": None,
            "subject": subject,
            "sha": sha,
            "pr": pr_num,
            "issue": issue_num,
        }
        out.append(record)
    return out


def _extract_pr_numbers_from_markers(
    main_root: pathlib.Path,
) -> set:
    """Walk fulfilled.land-pr.* markers to collect PR numbers for dedup.

    Reads markers directly from disk (both flat `.zskills/tracking/` and
    per-pipeline subdirs) rather than from the in-memory activity list,
    because the activity list strips the raw `pr` field — it's flattened
    into the `output` slot and may be elided.
    """
    nums: set = set()
    base = main_root / ".zskills" / "tracking"
    if not base.is_dir():
        return nums
    # Match either flat or per-pipeline subdir; the basename is what carries
    # the marker kind/id, and we only care about fulfilled.land-pr.*.
    pr_url_re = re.compile(r"github\.com/[^/]+/[^/]+/pull/(\d+)")
    try:
        for entry in base.iterdir():
            candidates: List[pathlib.Path] = []
            if entry.is_file() and entry.name.startswith("fulfilled.land-pr."):
                candidates.append(entry)
            elif entry.is_dir():
                try:
                    for sub in entry.iterdir():
                        if sub.is_file() and sub.name.startswith("fulfilled.land-pr."):
                            candidates.append(sub)
                except OSError:
                    continue
            for p in candidates:
                fields = _parse_marker_file(p)
                if fields is None:
                    continue
                pr_field = fields.get("pr", "")
                m = pr_url_re.search(pr_field)
                if m:
                    nums.add(m.group(1))
    except OSError:
        return nums
    return nums


# ---------------------------------------------------------------------------
# Worktree + branch listing (reuse briefing.py helpers)
# ---------------------------------------------------------------------------


def _list_worktrees(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    try:
        briefing = _load_briefing(main_root)
    except Exception as exc:
        errors.append({
            "source": "briefing import",
            "message": f"could not load briefing.py: {exc}",
        })
        return []
    try:
        wts = briefing.classify_worktrees(repo_root=str(main_root))
    except Exception as exc:
        errors.append({
            "source": "git worktree",
            "message": f"classify_worktrees failed: {exc}",
        })
        return []
    out: List[Dict[str, Any]] = []
    for wt in wts:
        landed_path = pathlib.Path(wt.get("path", "")) / ".landed"
        landed: Optional[Dict[str, Any]] = None
        try:
            if landed_path.is_file():
                landed = briefing.parse_landed(landed_path.read_text())
        except Exception:
            landed = None
        # age_seconds derived from mtime (briefing returns ms or None).
        mtime = wt.get("mtime")
        age_seconds: Optional[int]
        if isinstance(mtime, (int, float)) and mtime > 0:
            age_seconds = max(0, int(time.time() - (mtime / 1000.0)))
        else:
            age_seconds = None
        out.append({
            "path": wt.get("path", ""),
            "branch": wt.get("branch", ""),
            "category": wt.get("category", ""),
            "landed": landed,
            "ahead": int(wt.get("ahead", 0) or 0),
            "behind": int(wt.get("behind", 0) or 0),
            "age_seconds": age_seconds,
        })
    return out


def _read_protected_branches(main_root: pathlib.Path) -> set:
    """Read `cleanup.protected_branches` from .claude/zskills-config.json.

    This is the SAME set `/cleanup-merged` honors (exact-name match). Absent
    config / block / non-list → empty set. Never raises.
    """
    cfg_path = main_root / ".claude" / "zskills-config.json"
    text = _read_text(cfg_path)
    if text is None:
        return set()
    try:
        cfg = json.loads(text)
    except Exception:
        return set()
    if not isinstance(cfg, dict):
        return set()
    cleanup = cfg.get("cleanup", {})
    if not isinstance(cleanup, dict):
        return set()
    pats = cleanup.get("protected_branches", []) or []
    if not isinstance(pats, list):
        return set()
    return {str(p) for p in pats if isinstance(p, (str,)) and p}


def _branch_fetch_ttl(main_root: pathlib.Path) -> float:
    """Resolve the git-fetch throttle TTL (seconds).

    Default `BRANCH_FETCH_TTL`; overridable via
    `dashboard.branch_fetch_ttl_seconds` in zskills-config.json. Malformed →
    default.
    """
    cfg_path = main_root / ".claude" / "zskills-config.json"
    text = _read_text(cfg_path)
    if text is None:
        return BRANCH_FETCH_TTL
    try:
        cfg = json.loads(text)
    except Exception:
        return BRANCH_FETCH_TTL
    if not isinstance(cfg, dict):
        return BRANCH_FETCH_TTL
    dash = cfg.get("dashboard", {})
    if not isinstance(dash, dict):
        return BRANCH_FETCH_TTL
    raw = dash.get("branch_fetch_ttl_seconds")
    if isinstance(raw, (int, float)) and raw >= 0:
        return float(raw)
    return BRANCH_FETCH_TTL


def _maybe_fetch_remote(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
    *,
    _now: Optional[float] = None,
    _runner: Optional[Any] = None,
) -> None:
    """Throttled, NON-FATAL `git fetch --prune`.

    Refreshes remote-tracking refs at most once per `_branch_fetch_ttl`
    seconds (monotonic clock). A plain `git fetch --prune` only updates
    `refs/remotes/origin/*`; it never touches the working tree, index, or
    local branches. On failure (network down, no remote, etc.) append a
    descriptive `errors[]` entry and CONTINUE so the last-known
    remote-tracking refs are still rendered. Never raises.

    `_now` / `_runner` are test-only injection seams.
    """
    now = _now if _now is not None else time.monotonic()
    key = str(main_root)
    ttl = _branch_fetch_ttl(main_root)
    last = _BRANCH_FETCH_TS.get(key)
    if last is not None and ttl > 0 and (now - last) < ttl:
        return
    runner = _runner or subprocess.run
    try:
        result = runner(
            ["git", "fetch", "--prune"],
            cwd=str(main_root),
            capture_output=True,
            text=True,
            timeout=60,
        )
        # Record the attempt regardless of outcome so a hard-down remote
        # doesn't get retried on every 2Hz poll.
        _BRANCH_FETCH_TS[key] = now
        if getattr(result, "returncode", 1) != 0:
            errors.append({
                "source": "git fetch",
                "message": (getattr(result, "stderr", "") or "non-zero exit").strip()
                or "git fetch --prune failed; rendering last-known remote refs",
            })
    except Exception as exc:
        _BRANCH_FETCH_TS[key] = now
        errors.append({
            "source": "git fetch",
            "message": f"{exc}; rendering last-known remote refs",
        })


def _list_branches(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
    *,
    _now: Optional[float] = None,
    _fetch_runner: Optional[Any] = None,
) -> List[Dict[str, Any]]:
    """Rich branch list: local + remote-only, with last commit + upstream.

    Reads BOTH `refs/heads/` (local) and `refs/remotes/origin/`
    (remote-tracking), refreshing the latter via a throttled non-fatal
    `git fetch --prune` first. Local and remote entries are merged and
    deduped by branch name — the LOCAL entry wins (keeps its
    worktree/landed-classification data). Each entry carries:
      - `locality`: "local" | "remote-only" | "both"
      - `protected`: bool (from cleanup.protected_branches config)
    """
    protected = _read_protected_branches(main_root)

    def _for_each_ref(ref_glob: str, source: str) -> Optional[List[List[str]]]:
        try:
            result = subprocess.run(
                [
                    "git",
                    "for-each-ref",
                    "--format=%(refname:short)|%(committerdate:iso8601-strict)|%(upstream:short)|%(contents:subject)",
                    ref_glob,
                ],
                cwd=str(main_root),
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                errors.append({
                    "source": source,
                    "message": result.stderr.strip() or "non-zero exit",
                })
                return None
        except Exception as exc:
            errors.append({"source": source, "message": str(exc)})
            return None
        rows: List[List[str]] = []
        for line in result.stdout.split("\n"):
            if not line.strip():
                continue
            parts = line.split("|")
            if len(parts) < 4:
                continue
            rows.append(parts)
        return rows

    # Local branches (refs/heads/). A None return means git itself failed.
    local_rows = _for_each_ref("refs/heads/", "git for-each-ref")
    if local_rows is None:
        return []

    # Refresh + read remote-tracking refs (refs/remotes/origin/). The fetch
    # is throttled + non-fatal; the read is non-fatal too.
    _maybe_fetch_remote(
        main_root, errors, _now=_now, _runner=_fetch_runner
    )
    remote_rows = _for_each_ref("refs/remotes/origin/", "git for-each-ref (remote)")
    if remote_rows is None:
        remote_rows = []

    # Build the merged map, LOCAL first so it wins on collision.
    by_name: Dict[str, Dict[str, Any]] = {}
    for parts in local_rows:
        name = parts[0]
        by_name[name] = {
            "name": name,
            "last_commit_at": parts[1],
            "upstream": parts[2] or None,
            "last_commit_subject": "|".join(parts[3:]),
            "locality": "local",
            "protected": name in protected,
        }
    for parts in remote_rows:
        raw = parts[0]
        # `%(refname:short)` yields e.g. "origin/feat/x" or "origin/HEAD".
        if raw == "origin/HEAD" or not raw.startswith("origin/"):
            continue
        name = raw[len("origin/"):]
        if not name or name == "HEAD":
            continue
        existing = by_name.get(name)
        if existing is not None:
            # Local entry wins; merging just flips locality to "both".
            existing["locality"] = "both"
            continue
        by_name[name] = {
            "name": name,
            "last_commit_at": parts[1],
            "upstream": parts[2] or None,
            "last_commit_subject": "|".join(parts[3:]),
            "locality": "remote-only",
            "protected": name in protected,
        }

    return list(by_name.values())


# ---------------------------------------------------------------------------
# gh issue list (cached, 60s)
# ---------------------------------------------------------------------------


def list_issues(
    errors: List[Dict[str, str]],
    *,
    _now: Optional[float] = None,
    _runner: Optional[Any] = None,
) -> Tuple[List[Dict[str, Any]], bool]:
    """Fetch open issues via `gh issue list`. 60s module-level cache.

    On gh failure: returns last cache (or `[]`) and appends to `errors[]`.
    Never raises.

    Returns `(issues, ok)`. `ok` is True when the current fetch succeeded
    OR was served from the 60s TTL cache (the last fetch was successful);
    False when the current fetch failed (regardless of whether a cached
    fallback was returned). The flag drives the client-side prune-guard
    for issue #336 — `collect_snapshot` surfaces it as
    `snapshot["issues_fetch_ok"]`, and the dashboard client skips queue
    pruning when this is False to prevent monitor-state.json corruption
    on the cold-start failure path.

    `_now` and `_runner` are test-only injection seams.
    """
    now = _now if _now is not None else time.time()
    if _ISSUE_CACHE["had_value"] and (now - _ISSUE_CACHE["ts"]) < ISSUE_CACHE_TTL_SECONDS:
        # Cache hit: the most recent fetch succeeded; ok=True.
        return list(_ISSUE_CACHE["issues"]), True

    try:
        runner = _runner or subprocess.run
        result = runner(
            [
                "gh",
                "issue",
                "list",
                "--state",
                "open",
                "--limit",
                "500",
                "--json",
                "number,title,labels,createdAt,body",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if getattr(result, "returncode", 1) != 0:
            errors.append({
                "source": "gh issue list",
                "message": (getattr(result, "stderr", "") or "non-zero exit").strip(),
            })
            cached = list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
            return cached, False
        try:
            data = json.loads(result.stdout)
        except Exception as exc:
            errors.append({
                "source": "gh issue list",
                "message": f"json parse error: {exc}",
            })
            cached = list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
            return cached, False
        if not isinstance(data, list):
            errors.append({
                "source": "gh issue list",
                "message": "unexpected response shape",
            })
            cached = list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
            return cached, False
        issues: List[Dict[str, Any]] = []
        for entry in data:
            if not isinstance(entry, dict):
                continue
            labels_raw = entry.get("labels") or []
            labels: list = []
            for lab in labels_raw:
                if isinstance(lab, dict):
                    name = lab.get("name")
                    if name:
                        labels.append({"name": str(name), "color": lab.get("color", "")})
                elif isinstance(lab, str):
                    labels.append({"name": lab, "color": ""})
            issues.append({
                "number": entry.get("number"),
                "title": entry.get("title", ""),
                "labels": labels,
                "created_at": entry.get("createdAt", ""),
                "body": entry.get("body", ""),
            })
        _ISSUE_CACHE["ts"] = now
        _ISSUE_CACHE["issues"] = issues
        _ISSUE_CACHE["had_value"] = True
        return list(issues), True
    except FileNotFoundError as exc:
        errors.append({
            "source": "gh issue list",
            "message": f"gh not found: {exc}",
        })
        cached = list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
        return cached, False
    except Exception as exc:
        errors.append({
            "source": "gh issue list",
            "message": str(exc),
        })
        cached = list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
        return cached, False


# ---------------------------------------------------------------------------
# Bounded closed-issue fetch (D6 — separate fetch, separate 60s cache)
# ---------------------------------------------------------------------------


def list_closed_issues_in_window(
    errors: List[Dict[str, str]],
    *,
    days: int,
    limit: int,
    _now: Optional[float] = None,
    _runner: Optional[Any] = None,
) -> Tuple[List[Dict[str, Any]], bool]:
    """Fetch recently-closed issues via `gh issue list --state closed`.

    Per D6, runs a SEPARATE bounded call independent of the open-fetch
    in `list_issues`. Cache is keyed by (days, limit) so a config bump
    invalidates the prior narrower window naturally.

    Returns `(issues, ok)`, mirroring the open-fetch contract. Each issue
    dict carries `closed_at` (UTC ISO-8601 string from `entry.get("closedAt", "")`).

    On gh failure: returns last cached entry for this (days, limit) key
    if any, else `[]`; sets `ok=False`. Never raises.

    `_now` and `_runner` are test-only injection seams.
    """
    now = _now if _now is not None else time.time()
    key = (int(days), int(limit))
    bucket = _CLOSED_ISSUE_CACHE.get(key)
    if bucket and bucket.get("had_value") and (now - bucket["ts"]) < ISSUE_CACHE_TTL_SECONDS:
        # Cache hit: most recent fetch succeeded; ok=True.
        return list(bucket["issues"]), True

    # Date filter: `now_utc - days` as `YYYY-MM-DD`.
    cutoff_dt = datetime.fromtimestamp(now, tz=timezone.utc) - _delta_days(int(days))
    cutoff_str = cutoff_dt.strftime("%Y-%m-%d")

    def _cached_or_empty() -> List[Dict[str, Any]]:
        return list(bucket["issues"]) if (bucket and bucket.get("had_value")) else []

    try:
        runner = _runner or subprocess.run
        result = runner(
            [
                "gh",
                "issue",
                "list",
                "--state",
                "closed",
                "--search",
                f"closed:>={cutoff_str}",
                "--limit",
                str(int(limit)),
                "--json",
                "number,title,labels,createdAt,closedAt,body,stateReason",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if getattr(result, "returncode", 1) != 0:
            errors.append({
                "source": "gh issue list (closed)",
                "message": (getattr(result, "stderr", "") or "non-zero exit").strip(),
            })
            return _cached_or_empty(), False
        try:
            data = json.loads(result.stdout)
        except Exception as exc:
            errors.append({
                "source": "gh issue list (closed)",
                "message": f"json parse error: {exc}",
            })
            return _cached_or_empty(), False
        if not isinstance(data, list):
            errors.append({
                "source": "gh issue list (closed)",
                "message": "unexpected response shape",
            })
            return _cached_or_empty(), False
        issues: List[Dict[str, Any]] = []
        for entry in data:
            if not isinstance(entry, dict):
                continue
            labels_raw = entry.get("labels") or []
            labels: list = []
            for lab in labels_raw:
                if isinstance(lab, dict):
                    name = lab.get("name")
                    if name:
                        labels.append({"name": str(name), "color": lab.get("color", "")})
                elif isinstance(lab, str):
                    labels.append({"name": lab, "color": ""})
            issues.append({
                "number": entry.get("number"),
                "title": entry.get("title", ""),
                "labels": labels,
                "created_at": entry.get("createdAt", ""),
                "closed_at": entry.get("closedAt", ""),
                "body": entry.get("body", ""),
                "state_reason": entry.get("stateReason", ""),
            })
        _CLOSED_ISSUE_CACHE[key] = {
            "ts": now,
            "issues": issues,
            "had_value": True,
        }
        return list(issues), True
    except FileNotFoundError as exc:
        errors.append({
            "source": "gh issue list (closed)",
            "message": f"gh not found: {exc}",
        })
        return _cached_or_empty(), False
    except Exception as exc:
        errors.append({
            "source": "gh issue list (closed)",
            "message": str(exc),
        })
        return _cached_or_empty(), False


def _delta_days(days: int):
    """Return a timedelta(days=days). Helper to keep import surface local."""
    from datetime import timedelta
    return timedelta(days=days)


# ---------------------------------------------------------------------------
# Default-column inference (per plan Shared Schemas table)
# ---------------------------------------------------------------------------


def _parse_iso_utc(value: str) -> Optional[datetime]:
    """Parse an ISO-8601 string into a UTC-aware datetime.

    Tolerates:
      - Trailing `Z` (mapped to `+00:00`).
      - Date-only strings (`YYYY-MM-DD`) — appended `T00:00:00+00:00`.
      - Naive datetimes — treated as UTC.

    Returns None on parse failure or empty input.
    """
    if not value or not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    # Date-only: pad with midnight UTC. `datetime.fromisoformat` accepts
    # the date-only form but yields a naive datetime — pad explicitly so
    # tz-aware comparisons stay safe (DA2.4 legacy-defensive normalization).
    if len(raw) == 10 and raw.count("-") == 2:
        raw = raw + "T00:00:00+00:00"
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _infer_default_column(
    plan: Dict[str, Any],
    *,
    now_utc: datetime,
    window_days: int,
) -> Optional[str]:
    """Per the Shared Schemas inference table.

    Returns column name, or None if hidden.

    For `status in ("complete","landed")`: returns `"completed"` when the
    plan has a parseable `completed:` frontmatter field (any date).
    Returns None (hidden) when the field is absent or unparseable —
    historical completes without a backfilled date stay hidden.

    Issue #676: the server-side window cutoff has been removed. ALL
    completed plans with a valid `completed:` timestamp are included in
    the snapshot; the client-side completed-window dropdown filters them
    per user preference (7d/14d/30d/90d/All).
    """
    status = (plan.get("status") or "").strip().lower()
    phases_done = int(plan.get("phases_done") or 0)
    if status in ("complete", "landed"):
        completed_raw = plan.get("completed") or ""
        completed_dt = _parse_iso_utc(completed_raw) if isinstance(completed_raw, str) else None
        if completed_dt is None:
            return None  # hidden (historical or unbackfilled — no date)
        return "completed"
    if status == "conflict":
        return "reviewed"
    if status == "active":
        return "reviewed" if phases_done >= 1 else "drafted"
    if status == "$landed_status":
        # Treat as active per plan ("re-evaluate against active row").
        return "reviewed" if phases_done >= 1 else "drafted"
    # absent or anything else → drafted
    return "drafted"


def _infer_issue_default_column(
    issue: Dict[str, Any],
    *,
    now_utc: datetime,
    window_days: int,
) -> str:
    """Default-column inference for issues.

    Returns `"completed"` when `closedAt` is set; otherwise `"triage"`.
    Mirrors `_infer_default_column` but for issues, where the fallback
    default is `triage` (not `None`).

    Issue #676: the server-side window cutoff has been removed. ALL
    closed issues are routed to `"completed"` regardless of age; the
    client-side completed-window dropdown filters them per user preference.
    """
    closed_raw = issue.get("closed_at") or ""
    closed_dt = _parse_iso_utc(closed_raw) if isinstance(closed_raw, str) else None
    if closed_dt is not None:
        return "completed"
    return "triage"


# ---------------------------------------------------------------------------
# State-file merge
# ---------------------------------------------------------------------------


def _read_state_file(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> Dict[str, Any]:
    """Read .zskills/monitor-state.json. Tolerate v1.0 / v1.1 / v1.2.

    Returns a dict with keys `version`, `default_mode`, `plans`, `issues`,
    `updated_at`. The plans/issues dicts always include a `backlog` key
    (W1.4); on v1.1 files without `backlog`, an empty list is supplied so
    downstream `_annotate_*_queue` consumers can index uniformly.

    Schema versions:
      - v1.0: flat-string arrays for plan slugs.
      - v1.1: per-plan `{slug, mode}` entry dicts; no `backlog`.
      - v1.2: adds persistent `backlog` arrays. v1.1 fixtures still parse
        cleanly (the generic iteration accepts any column name) — the
        explicit `backlog` default just guarantees the key is always
        present for downstream consumers.

    On parse failure, returns empty queues (with `backlog: []` defaults)
    and appends an error.
    """
    state_path = main_root / ".zskills" / "monitor-state.json"
    text = _read_text(state_path)
    empty: Dict[str, Any] = {
        "default_mode": "phase",
        "plans": {"backlog": []},
        "issues": {"backlog": []},
        "updated_at": "",
    }
    if text is None:
        return empty
    try:
        raw = json.loads(text)
    except Exception as exc:
        errors.append({
            "source": ".zskills/monitor-state.json",
            "message": f"json parse error: {exc}",
        })
        return empty
    if not isinstance(raw, dict):
        errors.append({
            "source": ".zskills/monitor-state.json",
            "message": "top-level value is not an object",
        })
        return empty
    version = str(raw.get("version", "1.0"))
    default_mode = raw.get("default_mode") or "phase"
    plans_raw = raw.get("plans") or {}
    issues_raw = raw.get("issues") or {}

    plans_out: Dict[str, List[Dict[str, Any]]] = {}
    for col, entries in plans_raw.items():
        if not isinstance(entries, list):
            continue
        normalized: List[Dict[str, Any]] = []
        for entry in entries:
            if isinstance(entry, str):
                # v1.0 flat-string array
                normalized.append({"slug": entry, "mode": None})
            elif isinstance(entry, dict):
                normalized.append({
                    "slug": str(entry.get("slug", "")),
                    "mode": entry.get("mode"),
                })
            # else: ignore
        plans_out[col] = normalized

    issues_out: Dict[str, List[Any]] = {}
    for col, entries in issues_raw.items():
        if isinstance(entries, list):
            issues_out[col] = list(entries)

    # W1.4: guarantee `backlog` keys are present for downstream consumers
    # (v1.1 files do not write them; v1.2 does).
    if "backlog" not in plans_out:
        plans_out["backlog"] = []
    if "backlog" not in issues_out:
        issues_out["backlog"] = []

    return {
        "version": version,
        "default_mode": default_mode,
        "plans": plans_out,
        "issues": issues_out,
        "updated_at": raw.get("updated_at", ""),
    }


def _annotate_plans_queue(
    plans: List[Dict[str, Any]],
    state: Dict[str, Any],
    main_root: Optional[pathlib.Path] = None,
    *,
    now_utc: Optional[datetime] = None,
    window_days: int = 14,
) -> None:
    """Add `queue: {column, index, mode}` to each plan in-place.

    When `main_root` is provided, also annotates each plan with a
    `claim` field derived from
    `${main_root}/.zskills/claims/plan-<slug>/claim.json` (run-plan
    in-flight chip). Gated on `main_root is not None` per the symmetric
    contract with `_annotate_issues_queue` (R2.6 fixture branch passes
    no main_root and must skip the filesystem read).

    Precedence (W1.3 / D2 rule (i)): state-file explicit-position WINS
    over inference — a plan present in the state file's `backlog` (or
    `drafted`, etc.) stays there even if inference would route it
    elsewhere. Tested by W1.20.

    Completion override (#853): the ONE exception to rule (i). A plan
    whose frontmatter declares `status: complete|landed` AND carries a
    parseable `completed:` timestamp bypasses any pin and routes to
    `completed` via inference. The Completed column is derived (not a
    drop target, not in PLAN_COLUMNS), so a stale pin would otherwise
    strand a completed card in its old column with no UI affordance to
    unstick it. The plan file is source of truth for completion; once it
    transitions, the dashboard column follows on the next poll. Non-
    complete pinned plans are unaffected — their pin still beats
    inference.

    `now_utc` defaults to current wall-clock UTC. `window_days` controls
    the `completed:` recency window (D1, configurable via
    `execution.dashboard_completed_days`).
    """
    if now_utc is None:
        now_utc = datetime.now(timezone.utc)
    state_plans: Dict[str, List[Dict[str, Any]]] = state.get("plans", {})
    # state-file column iteration — picks up new columns from PLAN_COLUMNS / ISSUE_COLUMNS dynamically; conformance: tests/test-skill-conformance.sh
    # Build slug → (column, index, mode) lookup.
    # Auto-prune orphan slugs (#671): derive the set of known slugs from
    # the `plans` list parameter (parsed plan files). State-file entries
    # whose slug has no corresponding parsed plan are orphans — silently
    # drop them from `pos` so they never render and don't accumulate
    # forever in the snapshot.
    known_slugs: set = {
        p["slug"] for p in plans
        if isinstance(p.get("slug"), str) and p["slug"]
    }
    pos: Dict[str, Tuple[str, int, Optional[str]]] = {}
    for col, entries in state_plans.items():
        for i, e in enumerate(entries):
            slug = e.get("slug", "")
            if not slug or slug not in known_slugs:
                continue  # orphan — plan file does not exist
            mode = e.get("mode") if col == "ready" else None
            if slug not in pos:
                pos[slug] = (col, i, mode)

    # Plan-claim index — parallel to the issue-side `claim_index`. Gated
    # on main_root for the same reason (R2.6 fixture branch).
    plan_claim_index: Dict[str, Dict[str, Any]] = {}
    if main_root is not None:
        plan_claim_index = _read_plan_claims(main_root)

    for plan in plans:
        slug = plan["slug"]
        # Completion override (#853): a plan whose frontmatter declares
        # `status: complete|landed` AND carries a parseable `completed:`
        # timestamp is COMPLETE per the plan-file-is-source-of-truth rule.
        # The Completed column is derived (not a drop target / not in
        # PLAN_COLUMNS), so a stale pin in the state file (manual drag,
        # programmatic write, or initial seeding) would otherwise strand
        # the card in its old column forever. Bypass the pos pin here and
        # route via inference (→ "completed"), auto-healing stuck plans on
        # the next poll. This is a NARROW exception to W1.3/D2 rule (i):
        # non-complete pinned plans still honor their pin below.
        status = (plan.get("status") or "").strip().lower()
        completed_raw = plan.get("completed") or ""
        completed_dt = (
            _parse_iso_utc(completed_raw)
            if isinstance(completed_raw, str) else None
        )
        if status in ("complete", "landed") and completed_dt is not None:
            inferred = _infer_default_column(
                plan, now_utc=now_utc, window_days=window_days,
            )
            plan["queue"] = {"column": inferred, "index": -1, "mode": None}
        elif slug in pos:
            col, i, mode = pos[slug]
            plan["queue"] = {"column": col, "index": i, "mode": mode}
        else:
            inferred = _infer_default_column(
                plan, now_utc=now_utc, window_days=window_days,
            )
            plan["queue"] = {"column": inferred, "index": -1, "mode": None}
        # Claim chip — explicit field allow-list (NOT **claim_dict).
        # NO `worktree_path`, NO `host_pid` — same scope discipline as
        # the issue side (DA8 / DA2.1). `dispatch_mode` (#874) IS on the
        # allow-list because the dashboard mode chip's lock condition
        # reads it; the issue side intentionally does NOT mirror — it's
        # a plan-claim concept.
        if isinstance(slug, str) and slug in plan_claim_index:
            c = plan_claim_index[slug]
            plan["claim"] = {
                "pipeline_id":    c.get("pipeline_id"),
                "started_at":     c.get("started_at"),
                "current_phase":  c.get("current_phase"),
                "age_seconds":    c.get("age_seconds"),
                "pipeline_short": c.get("pipeline_short"),
                "dispatch_mode":  c.get("dispatch_mode"),
                # stale (#912): drives the client's in-UI release
                # affordance for dead-pipeline claims.
                "stale":          bool(c.get("stale")),
            }


def _annotate_issues_queue(
    issues: List[Dict[str, Any]],
    state: Dict[str, Any],
    main_root: Optional[pathlib.Path] = None,
    *,
    now_utc: Optional[datetime] = None,
    window_days: int = 14,
) -> None:
    """Add `queue: {column, index}` to each issue in-place.

    When `main_root` is provided, also annotates each Ready-column issue
    with a `skip_reason` derived from the issues tracker
    (`$ZSKILLS_ISSUES_DIR` joined with the tracker basename — composed
    below; issue #445). Missing tracker file or unparseable section → no
    annotation (or `unresearched` per the rule). Triage-column and
    actionable issues get no `skip_reason` field.
    """
    state_issues: Dict[str, List[Any]] = state.get("issues", {})
    # Auto-prune closed issues (#670): derive the set of closed issue
    # numbers from the `issues` list parameter, then skip them when
    # building the explicit-position `pos` lookup. Closed issues are
    # then routed via `_infer_issue_default_column` to `completed`
    # (in-window) or `triage` (out-of-window, where the caller's
    # open-fetch + closed-window-fetch contract typically also drops
    # them from the list entirely).
    closed_set: set = set()
    for issue in issues:
        num = issue.get("number")
        if isinstance(num, int) and issue.get("closed_at"):
            closed_set.add(num)

    pos: Dict[int, Tuple[str, int]] = {}
    for col, entries in state_issues.items():
        for i, num in enumerate(entries):
            try:
                n = int(num)
            except Exception:
                continue
            if n in closed_set:
                continue  # closed — route via inference to completed/triage
            pos[n] = (col, i)

    # Live monitor-state skip override map (#862). Read from `state` (not
    # the filesystem) so it is available even in the 2-arg fixture branch,
    # and so it is the SAME source `filter-unresearched-candidates.sh`
    # consumes from `monitor-state.json`. The unified precedence
    # (override wins, else blurb) is applied per-issue below via
    # `_resolve_effective_skip_reason`.
    monitor_skipped: Dict[int, Dict[str, str]] = _read_monitor_skipped(state)

    # Build skip-reason index once per snapshot (avoids re-parsing the
    # tracker per Ready issue). Only populated when main_root is given.
    skip_index: Dict[int, Optional[Dict[str, str]]] = {}
    issues_plan_path: Optional[pathlib.Path] = None
    # Claim index — parallel to skip_index; gated on main_root for the
    # same reason (R2.6: fixture branch passes 2-arg, no real filesystem).
    claim_index: Dict[int, Dict[str, Any]] = {}
    if main_root is not None:
        issues_plan_path = (
            # allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto resolved issues_dir (parallels the fix-issues/SKILL.md exemption at line 1050); the literal tail is the canonical tracker filename
            _resolve_paths(main_root)["issues_dir"] / "ISSUES_PLAN.md"
        )
        all_nums: List[int] = []
        for col_entries in state_issues.values():
            for num in (col_entries or []):
                try:
                    all_nums.append(int(num))
                except Exception:
                    continue
        if all_nums:
            skip_index = _build_skip_reason_index(issues_plan_path, all_nums)
        claim_index = _read_claims(main_root)

    if now_utc is None:
        now_utc = datetime.now(timezone.utc)

    # W1.3 dedupe-prefer-closed (DA3.7). The caller passes the merged
    # list with open-fetch entries FIRST and closed-fetch entries SECOND.
    # When the same issue # appears in both (cross-cache race per D6), we
    # keep the LAST occurrence (closed-side) so the snapshot renders the
    # issue once in the `completed` column rather than double-rendering
    # in both `triage` and `completed`. Mutating the caller's list
    # in-place keeps the post-call `issues` consistent with what the
    # snapshot will surface (the merged + annotated view).
    seen: Dict[int, int] = {}
    dedup_indices: List[int] = []
    for idx, issue in enumerate(issues):
        num = issue.get("number")
        if isinstance(num, int):
            if num in seen:
                # Later occurrence wins; mark the prior index for drop.
                dedup_indices.append(seen[num])
            seen[num] = idx
    if dedup_indices:
        drop_set = set(dedup_indices)
        kept = [it for i, it in enumerate(issues) if i not in drop_set]
        issues.clear()
        issues.extend(kept)

    for issue in issues:
        num = issue.get("number")
        if isinstance(num, int) and num in pos:
            col, i = pos[num]
            issue["queue"] = {"column": col, "index": i}
            # Effective skip-reason (#862): live monitor-state override
            # wins over the blurb-derived reason. Identical precedence to
            # filter-unresearched-candidates.sh so the chip and the
            # drop-decision never split-brain.
            reason = _resolve_effective_skip_reason(
                num, monitor_skipped, skip_index,
            )
            if reason is not None:
                issue["skip_reason"] = reason
        else:
            # W1.2b — issue default-column inference. Closed-within-window
            # issues land in `completed`; everything else falls through
            # to `triage` (the prior unconditional default).
            inferred_col = _infer_issue_default_column(
                issue, now_utc=now_utc, window_days=window_days,
            )
            issue["queue"] = {"column": inferred_col, "index": -1}
        # Claim chip — explicit field allow-list (NOT **claim_dict) so
        # future-added claim fields never leak into the HTTP response
        # without a deliberate edit here. NO `host_pid` (removed per
        # DA2.1/DA2.2), NO `worktree_path` (never in claim per DA8).
        if isinstance(num, int) and num in claim_index:
            c = claim_index[num]
            issue["claim"] = {
                "pipeline_id": c.get("pipeline_id"),
                "sprint_id": c.get("sprint_id"),
                "age_seconds": c.get("age_seconds"),
                "started_at": c.get("started_at"),
                "pipeline_short": c.get("pipeline_short"),
            }


# ---------------------------------------------------------------------------
# Issue tracker skip-reason derivation (issue #445)
# ---------------------------------------------------------------------------


# Action-now capture: matches `**Action now:**` (with or without
# surrounding bold). Real tracker entries often place this mid-line after
# a `**Complexity:** ...` clause, so we do NOT anchor to line-start;
# instead we capture everything from the colon up to the next sentence
# break (`. **` next-bold-token, or end-of-line).
_ACTION_NOW_RE = re.compile(
    r"\*{0,2}Action now:\*{0,2}\s*(.+?)(?:\n|$|\s+\*{2})",
    re.IGNORECASE,
)

# Verdict capture (same line-position-agnostic shape).
_VERDICT_RE = re.compile(
    r"\*{0,2}Verdict:\*{0,2}\s*(.+?)(?:\n|$|\s+\*{2})",
    re.IGNORECASE,
)

# Section heading: `### #<N>` at start of line.
_SECTION_RE = re.compile(r"^###\s+#(\d+)\b", re.MULTILINE)


def _parse_action_now(
    issue_number: int,
    tracker_text: str,
) -> Optional[Dict[str, str]]:
    """Derive a `skip_reason` dict for `issue_number` from tracker text.

    Returns `None` when the issue is actionable (no skip needed) — i.e.
    when the `**Action now:**` line names a runnable action like
    `/do pr`, `/quickfix`, `/run-plan`, `fix-agent`, or
    `include in next sprint`.

    Returns `{code, label, source}` when the issue should be skipped:

      - `needs-decision` (pink) — `Action now: none` with "author decision"
        or "decide" in the trailing reason (genuinely needs human input)
      - `deferred` (grey) — `Action now: none` with any OTHER trailing
        reason (agent parked the issue; no human input needed)
      - `plan-scale` (blue) — `Action now: /draft-plan`
      - `bug-unclear-cause` (purple) — `Action now: /investigate` OR
        `Verdict: UNCLEAR`
      - `unresearched` (gray) — `Verdict: NOT YET RESEARCHED` OR
        the issue section is absent entirely (no blurb)

    The mention of both `vague` and `unresearched` in issue #445 was a
    reviewer-noted spec ambiguity; we collapse to `unresearched` since the
    derivation rule treats missing-blurb and not-yet-researched
    identically (issue #445 review note).
    """
    section = _extract_section(issue_number, tracker_text)
    if section is None:
        return {
            "code": "unresearched",
            "label": "not yet researched",
            "source": "(no blurb)",
        }

    # Pull the Action now: line (last one in section wins — defensive
    # against authoring quirks; in practice each section has exactly one).
    action_match = None
    for m in _ACTION_NOW_RE.finditer(section):
        action_match = m
    verdict_match = None
    for m in _VERDICT_RE.finditer(section):
        verdict_match = m

    action_raw = action_match.group(1).strip() if action_match else ""
    verdict_raw = verdict_match.group(1).strip() if verdict_match else ""

    # Reconstruct a verbatim source string (prefer the action-now line as
    # the principal hint; fall back to verdict line; final fallback to
    # "(no blurb)").
    if action_match:
        source = "**Action now:** " + action_raw
    elif verdict_match:
        source = "**Verdict:** " + verdict_raw
    else:
        source = "(no blurb)"

    action_lc = action_raw.lower()
    verdict_lc = verdict_raw.lower()

    # Verdict-level signals first (they describe the issue's research
    # state irrespective of any action-now sentence).
    if "not yet researched" in verdict_lc:
        return {
            "code": "unresearched",
            "label": "not yet researched",
            "source": source,
        }

    # Action-now-level signals: match PREFIX of the action-now value
    # (per the rule "Action now: <kind>"). Mid-sentence mentions of
    # `/draft-plan` etc. in qualified-actionable blurbs (e.g.
    # "Fix #1 + #4 prose roll-in (combined /quickfix S). Fix #2 + #3
    # deferred to /draft-plan when prioritized") must NOT match.
    if action_raw:
        # `none` — split into `needs-decision` (genuinely needs human
        # input: "author decision", "decide between") vs `deferred`
        # (agent parked the issue: "leave open", "waiting", "deferred",
        # or any other reason that isn't asking a human to choose).
        if re.match(r"^none\b", action_lc):
            # Extract the part after `none` (typically after an em-dash).
            after_none = re.sub(r"^none\s*[—-]\s*", "", action_lc).strip()
            is_decision = bool(
                re.search(r"author decision", after_none)
                or re.search(r"\bdecide\b", after_none)
            )
            if is_decision:
                label = _short_label(action_raw, default="author decision needed")
                return {
                    "code": "needs-decision",
                    "label": label,
                    "source": source,
                }
            else:
                label = _short_label(action_raw, default="deferred")
                return {
                    "code": "deferred",
                    "label": label,
                    "source": source,
                }
        if re.match(r"^/draft-plan\b", action_lc) or re.match(
            r"^/run-plan\b", action_lc
        ):
            return {
                "code": "plan-scale",
                "label": "plan-scale",
                "source": source,
            }
        if re.match(r"^/investigate\b", action_lc):
            return {
                "code": "bug-unclear-cause",
                "label": "unclear cause",
                "source": source,
            }

    # Verdict-level fallback for UNCLEAR (after action-now had its turn).
    if "unclear" in verdict_lc:
        return {
            "code": "bug-unclear-cause",
            "label": "unclear cause",
            "source": source,
        }

    # Everything else is actionable (`/do pr`, `/quickfix`, `fix-agent`,
    # `include in next sprint`, etc.) — no chip.
    return None


def _short_label(action_raw: str, *, default: str) -> str:
    """Distill a chip-suitable label (≤60 char) from a verbose Action-now.

    Tracker blurbs frequently append decision branches after the leading
    summary ("none — author decision needed on which option. If author
    picks option 1 or 3, escalate to /draft-plan..."). The chip should
    surface the leading rationale only.
    """
    # Strip the leading bare word (e.g. `none — `) so the label is
    # whatever follows the em-dash.
    em_dash_match = re.search(r"[—-]\s*(.+)$", action_raw)
    raw = em_dash_match.group(1).strip() if em_dash_match else default
    # Truncate at first sentence break.
    cut = re.split(r"(?<=[.])\s|[;:]", raw, maxsplit=1)[0].strip().rstrip(".")
    if not cut:
        return default
    if len(cut) > 60:
        return cut[:57].rstrip() + "..."
    return cut


def _extract_section(issue_number: int, tracker_text: str) -> Optional[str]:
    """Return the text of the `### #<N>` section, or None if absent.

    Section runs from its heading up to the next `### #` heading or EOF.
    """
    target = f"#{issue_number}"
    start: Optional[int] = None
    end: Optional[int] = None
    for m in _SECTION_RE.finditer(tracker_text):
        n = int(m.group(1))
        if n == issue_number and start is None:
            start = m.start()
        elif start is not None and end is None:
            end = m.start()
            break
    if start is None:
        return None
    if end is None:
        end = len(tracker_text)
    return tracker_text[start:end]


def _build_skip_reason_index(
    tracker_path: pathlib.Path,
    issue_numbers: List[int],
) -> Dict[int, Optional[Dict[str, str]]]:
    """Parse the tracker once and return {issue_num: skip_reason_or_None}.

    Issues whose section is missing get the synthetic `unresearched`
    entry (matches `_parse_action_now`'s missing-section behavior).
    Issues that are actionable get `None` (so callers can distinguish
    "parsed and found actionable" from "not in this index").
    """
    out: Dict[int, Optional[Dict[str, str]]] = {}
    text = _read_text(tracker_path)
    if text is None:
        # Tracker missing → every Ready issue is effectively unresearched.
        for num in issue_numbers:
            out[num] = {
                "code": "unresearched",
                "label": "not yet researched",
                "source": "(no blurb)",
            }
        return out
    for num in issue_numbers:
        out[num] = _parse_action_now(num, text)
    return out


# ---------------------------------------------------------------------------
# Effective skip-reason resolution (issue #862)
# ---------------------------------------------------------------------------
#
# Split-brain fix: the dashboard skip chip and the /fix-issues drop-decision
# were sourced from two different, non-unified places — the chip from the
# committed `Action now:` blurb (`_parse_action_now`), the drop from
# `monitor-state.json:issues.skipped` (read by
# `filter-unresearched-candidates.sh`). An orchestrator that re-triaged an
# issue and recorded a new classification moved the FILTER but not the CHIP.
#
# The fix unifies both behind ONE precedence, implemented identically in
# this module (chip path) and in `filter-unresearched-candidates.sh`
# (drop path) — the two languages can't literally share a function, so the
# precedence is mirrored and locked by a cross-path agreement test
# (tests/test-fix-issues-skip-effective-reason.sh):
#
#   1. LIVE OVERRIDE — `monitor-state.json:issues.skipped[N]` wins when
#      present. The value is EITHER a bare code string (legacy / no-reason)
#      OR a dict `{"code": ..., "reason": ...}` (#862 free-text reason).
#   2. BLURB FALLBACK — else the `Action now:` blurb-derived reason
#      (`_parse_action_now` via `_build_skip_reason_index`).
#
# `reconsider <N>` clears `issues.skipped[N]` (the filter's one-shot dual),
# which naturally resets the chip to the blurb baseline — no separate
# clear-path is needed here.

# Canonical dashboard skip-code → chip label map, mirroring
# `_parse_action_now`'s per-code default labels. Used to synthesise a chip
# `skip_reason` dict for a monitor-state override that has no committed
# tracker blurb to source a label from.
_SKIP_CODE_DEFAULT_LABELS: Dict[str, str] = {
    "plan-scale": "plan-scale",
    "bug-unclear-cause": "unclear cause",
    "needs-decision": "author decision needed",
    "deferred": "deferred",
    "unresearched": "not yet researched",
}


def _read_monitor_skipped(state: Dict[str, Any]) -> Dict[int, Dict[str, str]]:
    """Read `state["issues"]["skipped"]` into `{issue_num: {code, reason}}`.

    `state` is the live monitor-state dict (the same dict
    `filter-unresearched-candidates.sh` reads from
    `monitor-state.json`), so this is the SINGLE source the override side
    of the precedence consults — no separate filesystem read, and it works
    in the 2-arg fixture branch too.

    Accepts BOTH persisted shapes per entry (#862):
      - bare code string `"<code>"`  (legacy / no-reason)
      - dict `{"code": ..., "reason": ...}`  (free-text reason recorded)

    Malformed / empty entries are skipped. `reason` is normalised to a
    (possibly empty) string.
    """
    out: Dict[int, Dict[str, str]] = {}
    issues_section = state.get("issues", {})
    if not isinstance(issues_section, dict):
        return out
    skipped = issues_section.get("skipped", {})
    if not isinstance(skipped, dict):
        return out
    for k, v in skipped.items():
        try:
            num = int(k)
        except (TypeError, ValueError):
            continue
        if isinstance(v, dict):
            code = v.get("code")
            reason = v.get("reason") or ""
        else:
            code = v
            reason = ""
        if not isinstance(code, str) or not code:
            continue
        out[num] = {"code": code, "reason": str(reason)}
    return out


def _resolve_effective_skip_reason(
    issue_number: int,
    monitor_skipped: Dict[int, Dict[str, str]],
    blurb_index: Dict[int, Optional[Dict[str, str]]],
) -> Optional[Dict[str, str]]:
    """Return the effective `skip_reason` dict for one issue, or None.

    Implements the unified precedence (#862):
      1. live `monitor-state.json:issues.skipped[N]` override wins;
      2. else the blurb-derived reason.

    On a live override, the chip `skip_reason` carries the override code
    plus a label sourced from the recorded free-text reason when present,
    otherwise the canonical per-code default label. `source` is annotated
    so the chip tooltip discloses the override origin.
    """
    override = monitor_skipped.get(issue_number)
    if override is not None:
        code = override["code"]
        reason = override.get("reason") or ""
        label = reason if reason else _SKIP_CODE_DEFAULT_LABELS.get(code, code)
        source = "monitor-state override" + (f": {reason}" if reason else "")
        return {"code": code, "label": label, "source": source}
    return blurb_index.get(issue_number)


# ---------------------------------------------------------------------------
# Claim-file reader (fix-issues claim chip — plans/fix-issues-claims.md
# Phase 3). Enumerates `${main_root}/.zskills/claims/issue-*/claim.json`
# per snapshot and returns a per-issue claim dict keyed by issue number.
# Read-only; never mutates the claim directory. Tolerant of malformed
# JSON (single stderr line, skip) and of claim dirs missing their
# `claim.json` (surfaces a null-metadata claim so the chip can render a
# generic in-flight indicator — avoids the sweep-while-flush race).
#
# Latency budget: <10ms wall-clock p99 for 50 simulated claims
# (issue #514; T3.3 gating benchmark).
# ---------------------------------------------------------------------------


_CLAIM_DIR_RE = re.compile(r"^issue-(\d+)$")
_PLAN_CLAIM_DIR_RE = re.compile(r"^plan-(.+)$")

# Staleness threshold for plan claims (#912). A `/run-plan` pipeline that
# died mid-flight (kill -9, OOM, container restart) leaves claim.json on
# disk indefinitely, which the dashboard renders as a permanently
# claim-locked card with no in-UI recovery. A claim older than this is
# tagged `stale: true` so the renderer can offer a release affordance
# (it is NOT filtered out — the card must still render so the user sees
# and can dismiss it). 6h is comfortably longer than any healthy phase or
# inter-phase idle gap. Fail toward NOT stale: a claim whose age cannot be
# computed (missing/malformed started_at) is never tagged stale, so a live
# claim is never wrongly offered for release.
PLAN_CLAIM_STALE_SECONDS = 21600  # 6h


def _derive_pipeline_short(pipeline_id: str, maxlen: int = 28) -> str:
    """Derive a short, human-meaningful label from a pipeline id.

    The leading pipeline-type prefix (`run-plan.`, `fix-issues.`, `do.`)
    is dropped first via rsplit on `.`.

    Sprint ids — `"fix-issues.sprint-20260521-010731-foo"` — yield
    `"010731-foo"` (the time+slug tail), NOT the useless `"sprint-2"` an
    8-char prefix slice would give, NOR the garbage an 8-char SUFFIX slice
    gives. The sprint branch is gated on the real sprint shape
    (`sprint-<digits>-<digits>-...`) — NOT a bare `len(parts) >= 4` count,
    which mis-fired on multi-hyphen plan slugs (e.g.
    `dashboard-tabs-and-rename-5a-diagnosis` -> "and-rename").

    Everything else (plan slugs like `plugin-distribution`) shows the WHOLE
    slug, front-truncated with an ellipsis only when it exceeds `maxlen`.
    The old `[-8:]` suffix slice butchered `plugin-distribution` -> "ribution".
    """
    tail = pipeline_id.rsplit(".", 1)[-1]
    parts = tail.split("-")
    is_sprint = (
        len(parts) >= 4
        and parts[0] == "sprint"
        and parts[1].isdigit()
        and parts[2].isdigit()
    )
    short = "-".join(parts[2:4]) if is_sprint else tail
    if len(short) > maxlen:
        short = short[: maxlen - 1] + "…"
    return short


def _read_claims(main_root: pathlib.Path) -> Dict[int, Dict[str, Any]]:
    """Read fix-issues claim files under `${main_root}/.zskills/claims/`.

    Returns `{issue_number: claim_dict}` where each dict carries:
        pipeline_id, sprint_id, age_seconds, started_at, pipeline_short

    Tolerant: malformed JSON emits a single stderr line and skips that
    claim. A claim directory present without `claim.json` surfaces a
    null-metadata entry (all values `None`) so the renderer can show a
    generic in-flight indicator (sweep-while-flush race tolerance).

    `main_root` is REQUIRED, not Optional — the fixture branch in
    `collect_snapshot` skips the call entirely via the gating rule in
    `_annotate_issues_queue` (R2.6). A `None` here would either crash or
    no-op pointlessly, neither of which is the intended contract.
    """
    out: Dict[int, Dict[str, Any]] = {}
    claims_dir = main_root / ".zskills" / "claims"
    if not claims_dir.is_dir():
        return out
    now = datetime.now(timezone.utc)
    try:
        entries = list(claims_dir.iterdir())
    except OSError as e:
        sys.stderr.write(
            "zskills_monitor.collect: _read_claims iterdir failed: %s\n" % e
        )
        return out
    for entry in entries:
        if not entry.is_dir():
            continue
        m = _CLAIM_DIR_RE.match(entry.name)
        if m is None:
            continue
        try:
            issue_number = int(m.group(1))
        except (TypeError, ValueError):
            continue
        claim_path = entry / "claim.json"
        if not claim_path.is_file():
            # Sweep-while-flush race tolerance — directory exists but
            # the writer hasn't dropped claim.json yet (or sweep raced
            # us mid-release). Surface a null-metadata claim so the
            # renderer shows the chip but with `?` for time / id.
            out[issue_number] = {
                "pipeline_id": None,
                "sprint_id": None,
                "age_seconds": None,
                "started_at": None,
                "pipeline_short": None,
            }
            continue
        try:
            with open(claim_path, "r", encoding="utf-8") as fh:
                body = json.load(fh)
        except (OSError, ValueError) as e:
            sys.stderr.write(
                "zskills_monitor.collect: _read_claims skip %s: %s\n"
                % (claim_path, e)
            )
            continue
        if not isinstance(body, dict):
            sys.stderr.write(
                "zskills_monitor.collect: _read_claims skip %s: not a JSON object\n"
                % claim_path
            )
            continue
        pipeline_id = body.get("pipeline_id")
        sprint_id = body.get("sprint_id")
        started_at = body.get("started_at")
        age_seconds: Optional[float] = None
        if isinstance(started_at, str) and started_at:
            try:
                parsed = datetime.fromisoformat(started_at)
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                age_seconds = (now - parsed).total_seconds()
            except ValueError:
                age_seconds = None
        pipeline_short: Optional[str] = None
        if isinstance(pipeline_id, str) and pipeline_id:
            pipeline_short = _derive_pipeline_short(pipeline_id)
        out[issue_number] = {
            "pipeline_id": pipeline_id if isinstance(pipeline_id, str) else None,
            "sprint_id": sprint_id if isinstance(sprint_id, str) else None,
            "age_seconds": age_seconds,
            "started_at": started_at if isinstance(started_at, str) else None,
            "pipeline_short": pipeline_short,
        }
    return out


def _read_plan_claims(main_root: pathlib.Path) -> Dict[str, Dict[str, Any]]:
    """Read run-plan claim files under `${main_root}/.zskills/claims/plan-*/`.

    Returns `{slug: claim_dict}` keyed by string slug. Each dict carries:
        pipeline_id, started_at, current_phase, age_seconds,
        pipeline_short, dispatch_mode, stale

    `stale` (#912) is `True` when `age_seconds` exceeds
    `PLAN_CLAIM_STALE_SECONDS` (6h) — the signal that the owning pipeline
    almost certainly died mid-flight and left an orphaned claim. The
    renderer uses it to offer an in-UI release affordance instead of the
    hard claim-lock. It is computed fail-toward-not-stale: if `age_seconds`
    is `None` (missing/malformed/unparseable `started_at`, or the
    null-metadata sweep-race entry) the claim is NEVER marked stale, so a
    live claim is never wrongly surfaced as releasable.

    Tolerant: malformed JSON emits a single stderr line and skips that
    claim. A claim directory present without `claim.json` surfaces a
    null-metadata entry (all values `None`) so the renderer can show a
    generic in-flight indicator (sweep-while-flush race tolerance —
    mirrors `_read_claims` D2.6 behaviour).

    `age_seconds` is computed from `started_at` (post-#684 cleanup
    removed `last_heartbeat_at` as a duplicate of `started_at`; phase
    progression is now signalled by `current_phase`, not chip age).

    `dispatch_mode` (#874) is the persisted mode under which the plan
    is being driven (`phase`, `finish`, or `None` when absent). The
    field survives the wrapper-lifetime gap that #858 left exposed:
    `/work-on-plans` resets to idle within seconds of dispatching, but
    the `/run-plan` claim it spawned outlives it by hours, so the
    dispatch mode must live on the claim, not on the wrapper state file.
    """
    out: Dict[str, Dict[str, Any]] = {}
    claims_dir = main_root / ".zskills" / "claims"
    if not claims_dir.is_dir():
        return out
    now = datetime.now(timezone.utc)
    try:
        entries = list(claims_dir.iterdir())
    except OSError as e:
        sys.stderr.write(
            "zskills_monitor.collect: _read_plan_claims iterdir failed: %s\n" % e
        )
        return out
    for entry in entries:
        if not entry.is_dir():
            continue
        m = _PLAN_CLAIM_DIR_RE.match(entry.name)
        if m is None:
            continue
        slug = m.group(1)
        if not slug:
            continue
        claim_path = entry / "claim.json"
        if not claim_path.is_file():
            # Sweep-while-flush race tolerance — directory exists but
            # the writer hasn't dropped claim.json yet (or sweep raced
            # us mid-release). Surface a null-metadata claim so the
            # renderer shows the chip but with `?` for time / id.
            out[slug] = {
                "pipeline_id": None,
                "started_at": None,
                "current_phase": None,
                "age_seconds": None,
                "pipeline_short": None,
                "dispatch_mode": None,
                # Null-metadata sweep-race entry has no age → fail toward
                # not-stale (#912).
                "stale": False,
            }
            continue
        try:
            with open(claim_path, "r", encoding="utf-8") as fh:
                body = json.load(fh)
        except (OSError, ValueError) as e:
            sys.stderr.write(
                "zskills_monitor.collect: _read_plan_claims skip %s: %s\n"
                % (claim_path, e)
            )
            continue
        if not isinstance(body, dict):
            sys.stderr.write(
                "zskills_monitor.collect: _read_plan_claims skip %s: not a JSON object\n"
                % claim_path
            )
            continue
        pipeline_id = body.get("pipeline_id")
        started_at = body.get("started_at")
        current_phase = body.get("current_phase")
        # dispatch_mode (#874): persisted by claim-plan.sh acquire
        # --dispatch-mode. Only `phase` / `finish` are valid persisted
        # values; anything else (including absence) surfaces as None and
        # the renderer falls back to the entry/default mode precedence.
        raw_dispatch_mode = body.get("dispatch_mode")
        dispatch_mode: Optional[str]
        if isinstance(raw_dispatch_mode, str) and raw_dispatch_mode in ("phase", "finish"):
            dispatch_mode = raw_dispatch_mode
        else:
            dispatch_mode = None
        # Compute age from started_at (post-#684 cleanup: last_heartbeat_at
        # was a duplicate of started_at and has been removed).
        age_seconds: Optional[float] = None
        started_for_age = started_at if isinstance(started_at, str) and started_at else None
        if started_for_age:
            try:
                parsed = datetime.fromisoformat(started_for_age)
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                age_seconds = (now - parsed).total_seconds()
            except ValueError:
                age_seconds = None
        pipeline_short: Optional[str] = None
        if isinstance(pipeline_id, str) and pipeline_id:
            pipeline_short = _derive_pipeline_short(pipeline_id)
        # Staleness (#912): fail toward NOT stale — only a successfully
        # computed age that exceeds the threshold marks the claim stale.
        # A None age (missing/malformed/unparseable started_at) leaves a
        # live claim hard-locked rather than wrongly offering it for
        # release.
        stale = isinstance(age_seconds, (int, float)) and age_seconds > PLAN_CLAIM_STALE_SECONDS
        out[slug] = {
            "pipeline_id": pipeline_id if isinstance(pipeline_id, str) else None,
            "started_at": started_at if isinstance(started_at, str) else None,
            "current_phase": current_phase if isinstance(current_phase, str) else None,
            "age_seconds": age_seconds,
            "pipeline_short": pipeline_short,
            "dispatch_mode": dispatch_mode,
            "stale": bool(stale),
        }
    return out


# ---------------------------------------------------------------------------
# collect_snapshot — entry point
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


# Defaults (W1.6 / D1 / DA2.1).
DEFAULT_DASHBOARD_COMPLETED_DAYS = 14
DEFAULT_DASHBOARD_COMPLETED_LIMIT = 500


def _read_dashboard_completed_config(main_root: pathlib.Path) -> Tuple[int, int]:
    """Resolve `execution.dashboard_completed_days` and
    `execution.dashboard_completed_limit` from `.claude/zskills-config.json`.

    Returns (days, limit). Missing / malformed / out-of-range values fall
    back to the documented defaults (14 / 500). No third-party JSON
    parser — Python stdlib `json` only.
    """
    days = DEFAULT_DASHBOARD_COMPLETED_DAYS
    limit = DEFAULT_DASHBOARD_COMPLETED_LIMIT
    cfg_path = main_root / ".claude" / "zskills-config.json"
    text = _read_text(cfg_path)
    if text is None:
        return days, limit
    try:
        cfg = json.loads(text)
    except Exception:
        return days, limit
    if not isinstance(cfg, dict):
        return days, limit
    execution = cfg.get("execution") if isinstance(cfg.get("execution"), dict) else {}
    raw_days = execution.get("dashboard_completed_days")
    raw_limit = execution.get("dashboard_completed_limit")
    if isinstance(raw_days, int) and raw_days > 0:
        days = raw_days
    if isinstance(raw_limit, int) and raw_limit > 0:
        limit = raw_limit
    return days, limit


def collect_snapshot(
    repo_root: Any,
    *,
    issue_runner: Optional[Any] = None,
    pre_resolved: bool = False,
) -> Dict[str, Any]:
    """Collect the full dashboard snapshot.

    `repo_root` may be a `Path` or `str`. If it's a worktree, the
    snapshot still references the MAIN_ROOT for `.zskills/`, `plans/`,
    and `reports/` (worktree-portable).

    Issue #281 — asymmetric main_root resolution. Long-running callers
    (the dashboard server) resolve MAIN_ROOT once at startup and store
    it in `ctx['main_root']`; every request handler reads from `ctx`.
    Re-resolving inside `collect_snapshot` on every `/api/state` GET
    is redundant *and* — if the server process's cwd ever shifted —
    could diverge from the value POST handlers commit against.
    Callers that have a vetted MAIN_ROOT pass `pre_resolved=True` to
    skip the redundant resolution; CLI / fresh entry points keep the
    default (False) so worktree → main hop still happens.
    """
    if pre_resolved:
        main_root = pathlib.Path(str(repo_root)).resolve()
    else:
        main_root = _resolve_main_root(repo_root)
    errors: List[Dict[str, str]] = []

    # Plans + reports — TTL-cached per subsystem (#514). The plan files
    # change on /run-plan phase ticks (minutes, not seconds); a 3s TTL
    # absorbs ~7 of every 10 polls without showing stale phase state.
    def _build_plans(local_errors: List[Dict[str, str]]) -> List[Dict[str, Any]]:
        plans_dir = _resolve_paths(main_root)["plans_dir"]
        out: List[Dict[str, Any]] = []
        if not plans_dir.is_dir():
            return out
        try:
            plan_files = sorted(plans_dir.glob("*.md"))
        except Exception as exc:
            plan_files = []
            local_errors.append({
                "source": "plans scan",
                "message": str(exc),
            })
        for plan_file in plan_files:
            parsed = parse_plan(plan_file)
            if parsed is None:
                continue
            # Report enrichment
            report = parse_report(parsed["slug"], main_root)
            parsed["has_report"] = report is not None
            parsed["report_path"] = report["path"] if report else None
            parsed["report"] = report  # full report (None if absent)
            # File path stored as relative-to-main-root for portability
            try:
                rel = pathlib.Path(parsed["file"]).resolve().relative_to(main_root)
                parsed["file"] = str(rel)
            except Exception:
                pass
            out.append(parsed)
        return out

    plans = _cached_subsystem(
        "plans", main_root, SNAPSHOT_CACHE_TTL_PLANS, _build_plans, errors,
    )
    # Defensive shallow copy: caller _annotate_plans_queue mutates each
    # plan dict in place, but those mutations are state-file-derived
    # (queue position, column) and the same state file is read fresh
    # every poll — so re-annotation produces a deterministic result. We
    # copy the OUTER list so re-orderings don't leak, but trust the
    # per-plan dicts to be re-annotated to a consistent state.
    plans = list(plans)

    # Dashboard Completed-window config (W1.6 / D1).
    window_days, closed_limit = _read_dashboard_completed_config(main_root)
    now_utc = datetime.now(timezone.utc)

    # State file merge (drives queue annotations + queues block).
    # Uncached — sub-ms read; staleness here would break the live-source
    # invariant for queue annotations.
    state = _read_state_file(main_root, errors)
    state_updated_at = state.get("updated_at", "")
    _annotate_plans_queue(
        plans, state, main_root, now_utc=now_utc, window_days=window_days,
    )

    # Issues. `issues_fetch_ok` is surfaced to the client (issue #336):
    # when False, the dashboard skips its prune-against-live-issues pass
    # in deepCloneQueues to prevent the cold-start corruption window
    # (process restart + first gh-list failure + user drag → wiped
    # monitor-state.json). Cache-hit within 60s TTL is treated as ok=True.
    open_issues, issues_fetch_ok = list_issues(errors, _runner=issue_runner)
    # W1.1 / D6 — separate bounded fetch for closed issues. Fails
    # independently of the open fetch (cold-start retention semantics).
    closed_issues, closed_fetch_ok = list_closed_issues_in_window(
        errors,
        days=window_days,
        limit=closed_limit,
        _runner=issue_runner,
    )
    # Merge: open first, closed second. W1.3 dedupe-prefer-closed
    # (DA3.7) is implemented inside `_annotate_issues_queue` by
    # iterating in this order so the closed-side annotation overwrites
    # the open-side annotation for any shared keys.
    issues = list(open_issues) + list(closed_issues)
    _annotate_issues_queue(
        issues, state, main_root,
        now_utc=now_utc, window_days=window_days,
    )

    # Truncation signal (W1.6 / DA3.4). When the closed fetch saturated
    # the limit, the banner-side renderer needs the live integer to
    # interpolate the message ("Showing 500 most-recent…").
    closed_truncated = (
        closed_fetch_ok and len(closed_issues) >= closed_limit
    )

    # Worktrees + branches — TTL-cached subsystems (#514). Both run git
    # subprocesses; both change at human-action cadence (worktree create
    # / branch checkout), not 2Hz polls.
    worktrees = _cached_subsystem(
        "worktrees", main_root, SNAPSHOT_CACHE_TTL_WORKTREES,
        lambda e: _list_worktrees(main_root, e), errors,
    )
    branches = _cached_subsystem(
        "branches", main_root, SNAPSHOT_CACHE_TTL_BRANCHES,
        lambda e: _list_branches(main_root, e), errors,
    )

    # Tracking activity + git-history events (commits with no marker).
    # Tracking markers are richer (skill, id, pipeline) so they win on
    # dedup; commits whose trailing `(#N)` matches a fulfilled.land-pr.*
    # marker's PR number are dropped. Tracking markers + their PR-number
    # extraction are grouped under one "tracking" subsystem (#514) —
    # they walk the same `.zskills/tracking/` tree.
    def _build_tracking(
        local_errors: List[Dict[str, str]],
    ) -> Tuple[List[Dict[str, Any]], set]:
        marker_activity = _scan_tracking_markers(main_root, local_errors)
        fulfilled_prs = _extract_pr_numbers_from_markers(main_root)
        return marker_activity, fulfilled_prs

    marker_activity, fulfilled_prs = _cached_subsystem(
        "tracking", main_root, SNAPSHOT_CACHE_TTL_TRACKING,
        _build_tracking, errors,
    )
    git_activity = _cached_subsystem(
        "git_history", main_root, SNAPSHOT_CACHE_TTL_GIT_HISTORY,
        lambda e: _scan_git_history(
            main_root, e, fulfilled_pr_numbers=fulfilled_prs,
        ),
        errors,
    )
    activity = marker_activity + git_activity

    def _activity_sort_key(rec: Dict[str, Any]):
        ts = rec.get("timestamp", "")
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return -dt.astimezone(timezone.utc).timestamp()
        except Exception:
            return 0.0

    activity.sort(key=_activity_sort_key)
    activity = activity[:200]

    # Queues block (state-file-shape mirror, plus default_mode).
    # Filter closed issues and orphan plan slugs so the frontend's
    # fingerprintIssues pos-lookup (app.js:612-618) agrees with the
    # server-side _annotate_*_queue annotations. Without this filter
    # the raw state-file positions override queue.column for rendering.
    closed_nums: set = {
        it.get("number") for it in issues
        if isinstance(it.get("number"), int) and it.get("closed_at")
    }
    raw_issues = state.get("issues", {})
    filtered_issues: Dict[str, Any] = {}
    for col, entries in raw_issues.items():
        if not entries:
            filtered_issues[col] = []
            continue
        kept: list = []
        for n in entries:
            try:
                num = int(n)
            except (TypeError, ValueError):
                kept.append(n)
                continue
            if num not in closed_nums:
                kept.append(n)
        filtered_issues[col] = kept
    queues_block: Dict[str, Any] = {
        "default_mode": state.get("default_mode", "phase"),
        "plans": state.get("plans", {}),
        "issues": filtered_issues,
    }

    snapshot: Dict[str, Any] = {
        "version": VERSION,
        "updated_at": _now_iso(),
        "state_updated_at": state_updated_at,
        "repo_root": str(main_root),
        "repo_url": _derive_repo_url(main_root),
        "plans": plans,
        "issues": issues,
        "worktrees": worktrees,
        "branches": branches,
        "activity": activity,
        "queues": queues_block,
        "state_file_path": ".zskills/monitor-state.json",
        "errors": _finalize_errors(errors),
        "issues_fetch_ok": issues_fetch_ok,
        "flags": {
            "closed_issues_truncated": bool(closed_truncated),
            "closed_issues_limit": int(closed_limit),
        },
        "config": {
            "dashboard_completed_days": int(window_days),
        },
    }
    return snapshot


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python3 -m zskills_monitor.collect",
        description=(
            "Collect a single JSON snapshot of zskills dashboard state "
            "(plans, issues, worktrees, branches, tracking activity, "
            "queues, errors). Emits to stdout."
        ),
    )
    p.add_argument(
        "--fixture",
        metavar="DIR",
        default=None,
        help="Treat DIR as the repo root (used by tests).",
    )
    p.add_argument(
        "--repo-root",
        metavar="DIR",
        default=None,
        help="Explicit repo root (defaults to git-detected main checkout).",
    )
    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    if args.fixture:
        # Fixture mode: do NOT walk to git common-dir; treat the fixture
        # directory as the canonical main-root verbatim.
        main_root = pathlib.Path(args.fixture).resolve()
        errors: List[Dict[str, str]] = []
        plans: List[Dict[str, Any]] = []
        plans_dir = _resolve_paths(main_root)["plans_dir"]
        if plans_dir.is_dir():
            for plan_file in sorted(plans_dir.glob("*.md")):
                parsed = parse_plan(plan_file)
                if parsed is None:
                    continue
                report = parse_report(parsed["slug"], main_root)
                parsed["has_report"] = report is not None
                parsed["report_path"] = report["path"] if report else None
                parsed["report"] = report
                try:
                    rel = pathlib.Path(parsed["file"]).resolve().relative_to(main_root)
                    parsed["file"] = str(rel)
                except Exception:
                    pass
                plans.append(parsed)

        state = _read_state_file(main_root, errors)
        _annotate_plans_queue(plans, state)

        # Fixtures: skip gh + git (they're not in fixture mode), to keep
        # tests deterministic.
        issues: List[Dict[str, Any]] = []
        _annotate_issues_queue(issues, state)
        worktrees: List[Dict[str, Any]] = []
        branches: List[Dict[str, Any]] = []
        activity = _scan_tracking_markers(main_root, errors)

        # Surface synthesized errors[] from the fixture's
        # `__synthesized_errors__` file (one JSON object per line) to
        # exercise the cap/sort behavior in tests.
        synth_path = main_root / "__synthesized_errors__"
        if synth_path.is_file():
            for line in synth_path.read_text().split("\n"):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    if isinstance(obj, dict) and "source" in obj and "message" in obj:
                        errors.append({
                            "source": str(obj["source"]),
                            "message": str(obj["message"]),
                        })
                except Exception:
                    continue

        snapshot = {
            "version": VERSION,
            "updated_at": _now_iso(),
            "state_updated_at": state.get("updated_at", ""),
            "repo_root": str(main_root),
            "repo_url": "",
            "plans": plans,
            "issues": issues,
            "worktrees": worktrees,
            "branches": branches,
            "activity": activity,
            "queues": {
                "default_mode": state.get("default_mode", "phase"),
                "plans": state.get("plans", {}),
                "issues": state.get("issues", {}),
            },
            "state_file_path": ".zskills/monitor-state.json",
            "errors": _finalize_errors(errors),
            # Fixture mode skips the gh fetch entirely; report ok=True so
            # the snapshot's top-level-key contract stays stable (#336).
            "issues_fetch_ok": True,
            "flags": {
                "closed_issues_truncated": False,
                "closed_issues_limit": DEFAULT_DASHBOARD_COMPLETED_LIMIT,
            },
        }
    else:
        repo_root = args.repo_root or os.getcwd()
        snapshot = collect_snapshot(repo_root)

    json.dump(snapshot, sys.stdout, indent=2, sort_keys=False, default=str)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
