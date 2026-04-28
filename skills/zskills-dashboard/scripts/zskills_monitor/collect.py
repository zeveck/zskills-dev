#!/usr/bin/env python3
"""
zskills_monitor.collect — Pure-Python aggregation library for the
zskills monitor dashboard (Phase 4 of ZSKILLS_MONITOR_PLAN).

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
    "repo_root",
    "plans",
    "issues",
    "worktrees",
    "branches",
    "activity",
    "queues",
    "state_file_path",
    "errors",
}

# Landing-mode hint regex (canonical, per plan Shared Schemas).
LANDING_MODE_RE = re.compile(
    r"^\s*>\s*\*{0,2}Landing\s+mode:\s*([A-Za-z_-]+)\s*\*{0,2}",
    re.IGNORECASE | re.MULTILINE,
)

# Phase heading: `## Phase N — Name` (em-dash or hyphen).
PHASE_HEADING_RE = re.compile(r"^##\s+Phase\s+(\S+)\s*[—-]\s*(.+)$", re.MULTILINE)

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


# ---------------------------------------------------------------------------
# Module-level cache (per-Python-process; documented limitation per DA-14)
# ---------------------------------------------------------------------------

_ISSUE_CACHE: Dict[str, Any] = {
    "ts": 0.0,
    "issues": [],
    "had_value": False,
}


def _reset_issue_cache_for_tests() -> None:
    """Reset the module-level cache (test-only helper)."""
    _ISSUE_CACHE["ts"] = 0.0
    _ISSUE_CACHE["issues"] = []
    _ISSUE_CACHE["had_value"] = False


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
    """
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


def _resolve_landing_mode(
    plan_body: str,
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> str:
    """Resolution order: (1) plan-body Landing-mode regex; else
    (2) `.claude/zskills-config.json` `execution.landing`;
    else (3) sentinel `"unknown"`.
    """
    m = LANDING_MODE_RE.search(plan_body)
    if m:
        return m.group(1).lower()
    cfg_path = main_root / ".claude" / "zskills-config.json"
    text = _read_text(cfg_path)
    if text is None:
        errors.append({
            "source": ".claude/zskills-config.json",
            "message": "config file unreadable or missing",
        })
        return "unknown"
    try:
        cfg = json.loads(text)
    except Exception as exc:
        errors.append({
            "source": ".claude/zskills-config.json",
            "message": f"json parse error: {exc}",
        })
        return "unknown"
    landing = (cfg.get("execution") or {}).get("landing")
    if isinstance(landing, str) and landing.strip():
        return landing.strip().lower()
    errors.append({
        "source": ".claude/zskills-config.json",
        "message": "execution.landing not set",
    })
    return "unknown"


def _parse_phase_headings(content: str) -> List[Dict[str, Any]]:
    """Return [{n, name}] from `## Phase <N> — Name` (em-dash or hyphen).

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
        "_content": content,  # consumed by caller for landing-mode + dropped after
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
    """Parse `reports/plan-<slug>.md`. Returns None if absent."""
    report_path = main_root / "reports" / f"plan-{slug}.md"
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


def _list_branches(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    """Per plan: rich branch list with last commit + upstream."""
    try:
        result = subprocess.run(
            [
                "git",
                "for-each-ref",
                "--format=%(refname:short)|%(committerdate:iso8601-strict)|%(upstream:short)|%(contents:subject)",
                "refs/heads/",
            ],
            cwd=str(main_root),
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            errors.append({
                "source": "git for-each-ref",
                "message": result.stderr.strip() or "non-zero exit",
            })
            return []
    except Exception as exc:
        errors.append({
            "source": "git for-each-ref",
            "message": str(exc),
        })
        return []
    out: List[Dict[str, Any]] = []
    for line in result.stdout.split("\n"):
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue
        out.append({
            "name": parts[0],
            "last_commit_at": parts[1],
            "upstream": parts[2] or None,
            "last_commit_subject": "|".join(parts[3:]),
        })
    return out


# ---------------------------------------------------------------------------
# gh issue list (cached, 60s)
# ---------------------------------------------------------------------------


def list_issues(
    errors: List[Dict[str, str]],
    *,
    _now: Optional[float] = None,
    _runner: Optional[Any] = None,
) -> List[Dict[str, Any]]:
    """Fetch open issues via `gh issue list`. 60s module-level cache.

    On gh failure: returns last cache (or `[]`) and appends to `errors[]`.
    Never raises.

    `_now` and `_runner` are test-only injection seams.
    """
    now = _now if _now is not None else time.time()
    if _ISSUE_CACHE["had_value"] and (now - _ISSUE_CACHE["ts"]) < ISSUE_CACHE_TTL_SECONDS:
        return list(_ISSUE_CACHE["issues"])

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
            return list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
        try:
            data = json.loads(result.stdout)
        except Exception as exc:
            errors.append({
                "source": "gh issue list",
                "message": f"json parse error: {exc}",
            })
            return list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
        if not isinstance(data, list):
            errors.append({
                "source": "gh issue list",
                "message": "unexpected response shape",
            })
            return list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
        issues: List[Dict[str, Any]] = []
        for entry in data:
            if not isinstance(entry, dict):
                continue
            labels_raw = entry.get("labels") or []
            labels: List[str] = []
            for lab in labels_raw:
                if isinstance(lab, dict):
                    name = lab.get("name")
                    if name:
                        labels.append(str(name))
                elif isinstance(lab, str):
                    labels.append(lab)
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
        return list(issues)
    except FileNotFoundError as exc:
        errors.append({
            "source": "gh issue list",
            "message": f"gh not found: {exc}",
        })
        return list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []
    except Exception as exc:
        errors.append({
            "source": "gh issue list",
            "message": str(exc),
        })
        return list(_ISSUE_CACHE["issues"]) if _ISSUE_CACHE["had_value"] else []


# ---------------------------------------------------------------------------
# Default-column inference (per plan Shared Schemas table)
# ---------------------------------------------------------------------------


def _infer_default_column(plan: Dict[str, Any]) -> Optional[str]:
    """Per the Shared Schemas inference table.

    Returns column name, or None if hidden.
    """
    status = (plan.get("status") or "").strip().lower()
    phases_done = int(plan.get("phases_done") or 0)
    if status in ("complete", "landed"):
        return None  # hidden
    if status == "conflict":
        return "reviewed"
    if status == "active":
        return "reviewed" if phases_done >= 1 else "drafted"
    if status == "$landed_status":
        # Treat as active per plan ("re-evaluate against active row").
        return "reviewed" if phases_done >= 1 else "drafted"
    # absent or anything else → drafted
    return "drafted"


# ---------------------------------------------------------------------------
# State-file merge
# ---------------------------------------------------------------------------


def _read_state_file(
    main_root: pathlib.Path,
    errors: List[Dict[str, str]],
) -> Dict[str, Any]:
    """Read .zskills/monitor-state.json. Tolerate v1.0 and v1.1.

    Returns a dict with keys `default_mode`, `plans`, `issues`. On
    parse failure, returns empty queues + appends an error.
    """
    state_path = main_root / ".zskills" / "monitor-state.json"
    text = _read_text(state_path)
    empty: Dict[str, Any] = {
        "default_mode": "phase",
        "plans": {},
        "issues": {},
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

    return {
        "version": version,
        "default_mode": default_mode,
        "plans": plans_out,
        "issues": issues_out,
    }


def _annotate_plans_queue(
    plans: List[Dict[str, Any]],
    state: Dict[str, Any],
) -> None:
    """Add `queue: {column, index, mode}` to each plan in-place."""
    state_plans: Dict[str, List[Dict[str, Any]]] = state.get("plans", {})
    # Build slug → (column, index, mode) lookup.
    pos: Dict[str, Tuple[str, int, Optional[str]]] = {}
    for col, entries in state_plans.items():
        for i, e in enumerate(entries):
            slug = e.get("slug", "")
            mode = e.get("mode") if col == "ready" else None
            if slug and slug not in pos:
                pos[slug] = (col, i, mode)
    for plan in plans:
        slug = plan["slug"]
        if slug in pos:
            col, i, mode = pos[slug]
            plan["queue"] = {"column": col, "index": i, "mode": mode}
        else:
            inferred = _infer_default_column(plan)
            plan["queue"] = {"column": inferred, "index": -1, "mode": None}


def _annotate_issues_queue(
    issues: List[Dict[str, Any]],
    state: Dict[str, Any],
) -> None:
    """Add `queue: {column, index}` to each issue in-place."""
    state_issues: Dict[str, List[Any]] = state.get("issues", {})
    pos: Dict[int, Tuple[str, int]] = {}
    for col, entries in state_issues.items():
        for i, num in enumerate(entries):
            try:
                pos[int(num)] = (col, i)
            except Exception:
                continue
    for issue in issues:
        num = issue.get("number")
        if isinstance(num, int) and num in pos:
            col, i = pos[num]
            issue["queue"] = {"column": col, "index": i}
        else:
            issue["queue"] = {"column": "triage", "index": -1}


# ---------------------------------------------------------------------------
# collect_snapshot — entry point
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


def collect_snapshot(
    repo_root: Any,
    *,
    issue_runner: Optional[Any] = None,
) -> Dict[str, Any]:
    """Collect the full dashboard snapshot.

    `repo_root` may be a `Path` or `str`. If it's a worktree, the
    snapshot still references the MAIN_ROOT for `.zskills/`, `plans/`,
    and `reports/` (worktree-portable).
    """
    main_root = _resolve_main_root(repo_root)
    errors: List[Dict[str, str]] = []

    plans_dir = main_root / "plans"
    plans: List[Dict[str, Any]] = []
    if plans_dir.is_dir():
        try:
            plan_files = sorted(plans_dir.glob("*.md"))
        except Exception as exc:
            plan_files = []
            errors.append({
                "source": "plans scan",
                "message": str(exc),
            })
        for plan_file in plan_files:
            parsed = parse_plan(plan_file)
            if parsed is None:
                continue
            content = parsed.pop("_content", "")
            parsed["landing_mode"] = _resolve_landing_mode(content, main_root, errors)
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
            plans.append(parsed)

    # State file merge (drives queue annotations + queues block)
    state = _read_state_file(main_root, errors)
    _annotate_plans_queue(plans, state)

    # Issues
    issues = list_issues(errors, _runner=issue_runner)
    _annotate_issues_queue(issues, state)

    # Worktrees + branches
    worktrees = _list_worktrees(main_root, errors)
    branches = _list_branches(main_root, errors)

    # Tracking activity
    activity = _scan_tracking_markers(main_root, errors)

    # Queues block (raw state-file-shape mirror, plus default_mode)
    queues_block: Dict[str, Any] = {
        "default_mode": state.get("default_mode", "phase"),
        "plans": state.get("plans", {}),
        "issues": state.get("issues", {}),
    }

    snapshot: Dict[str, Any] = {
        "version": VERSION,
        "updated_at": _now_iso(),
        "repo_root": str(main_root),
        "plans": plans,
        "issues": issues,
        "worktrees": worktrees,
        "branches": branches,
        "activity": activity,
        "queues": queues_block,
        "state_file_path": ".zskills/monitor-state.json",
        "errors": _finalize_errors(errors),
    }
    return snapshot


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python3 -m zskills_monitor.collect",
        description=(
            "Collect a single JSON snapshot of zskills monitor state "
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
        plans_dir = main_root / "plans"
        if plans_dir.is_dir():
            for plan_file in sorted(plans_dir.glob("*.md")):
                parsed = parse_plan(plan_file)
                if parsed is None:
                    continue
                content = parsed.pop("_content", "")
                parsed["landing_mode"] = _resolve_landing_mode(
                    content, main_root, errors
                )
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
            "repo_root": str(main_root),
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
        }
    else:
        repo_root = args.repo_root or os.getcwd()
        snapshot = collect_snapshot(repo_root)

    json.dump(snapshot, sys.stdout, indent=2, sort_keys=False, default=str)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
