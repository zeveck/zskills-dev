#!/usr/bin/env python3
"""Render PLAN_INDEX.md from a zskills_monitor.collect snapshot.

Stdin: JSON snapshot (output of `python3 -m zskills_monitor.collect`).
Stdout: markdown for `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md`.

Args:
    --rebuilt-at <STRING>  Timestamp string to embed in the "Last rebuilt"
                           line. The caller computes this (typically via
                           `TZ="${TIMEZONE:-UTC}" date '+%Y-%m-%d %H:%M %Z'`).

Section precedence (fixed; never relax):
    1. category=="canary"                 → Canaries        (NEVER promote)
    2. category in {reference,
                    issue_tracker}        → Reference
    3. status in {complete, landed}       → Complete
    4. category=="executable" AND
       status=="conflict"                 → Needs Review
    5. category=="executable" AND
       status=="active" AND
       1 <= phases_done < phase_count     → In Progress
    6. category=="executable" AND
       status=="active" AND
       phases_done==0 AND
       queue.column != "ready"            → Ready to Run
       (queue.column == "ready" also lands here regardless of phase progress)

Pure stdlib. No pip deps.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
from typing import Any, Dict, Iterable, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Section classifier
# ---------------------------------------------------------------------------

SECTION_CANARIES = "Canaries"
SECTION_REFERENCE = "Reference"
SECTION_COMPLETE = "Complete"
SECTION_NEEDS_REVIEW = "Needs Review"
SECTION_IN_PROGRESS = "In Progress"
SECTION_READY = "Ready to Run"


def section_for(plan: Dict[str, Any]) -> str:
    """Bucket one plan into a section name. Pure function on plan dict."""
    cat = plan.get("category") or ""
    status = plan.get("status") or ""
    phase_count = int(plan.get("phase_count") or 0)
    phases_done = int(plan.get("phases_done") or 0)
    queue = plan.get("queue") or {}
    queue_col = queue.get("column")

    # 1) Canary precedence — NEVER promote.
    if cat == "canary":
        return SECTION_CANARIES
    # 2) Reference categories.
    if cat in ("reference", "issue_tracker"):
        return SECTION_REFERENCE
    # 3) Explicit queue.column=="ready" wins regardless of phase progress
    #    (per SKILL.md: "any plan explicitly placed in the ready column
    #    wins regardless of phase progress"). This MUST precede the
    #    Complete / In Progress / Needs Review checks so a user
    #    drag-and-dropped plan stays on the Ready board.
    if queue_col == "ready":
        return SECTION_READY
    # 4) Completed plans.
    if status in ("complete", "landed"):
        return SECTION_COMPLETE
    # 5) Conflict.
    if cat == "executable" and status == "conflict":
        return SECTION_NEEDS_REVIEW
    # 6) In progress: at least one phase done, but not all.
    if (
        cat == "executable"
        and status == "active"
        and phases_done >= 1
        and phases_done < phase_count
    ):
        return SECTION_IN_PROGRESS
    # 7) Ready: executable+active+no-progress, default column.
    if (
        cat == "executable"
        and status == "active"
        and phases_done == 0
    ):
        return SECTION_READY
    # Anything else (e.g. status="deferred", "proposal", non-executable
    # active plans) — bucket as Needs Review so it surfaces for triage
    # rather than disappearing.
    return SECTION_NEEDS_REVIEW


# ---------------------------------------------------------------------------
# Sorting + priority labelling
# ---------------------------------------------------------------------------


def _parse_created(plan: Dict[str, Any]) -> Optional[datetime.date]:
    """Return frontmatter `created` as a date, or None if missing/invalid."""
    raw = (plan.get("created") or "").strip()
    if not raw:
        return None
    # Accept "YYYY-MM-DD" or full ISO; we only care about the date.
    try:
        return datetime.date.fromisoformat(raw[:10])
    except Exception:
        return None


def _priority(plan: Dict[str, Any], today: datetime.date) -> str:
    """High / Medium / Low per the documented rule.

    High   — issue field present (referenced by a tracked issue or skip).
    Medium — created within 14 days OR no created date.
    Low    — older than 14 days.
    """
    if plan.get("issue"):
        return "High"
    created = _parse_created(plan)
    if created is None:
        return "Medium"
    if (today - created).days <= 14:
        return "Medium"
    return "Low"


def _sort_ready(plans: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Ready ordering: queue.column=="ready" first (by queue.index),
    then default-column entries by creation recency (newest first),
    tiebreaking alphabetically by slug.
    """
    explicit: List[Dict[str, Any]] = []
    default: List[Dict[str, Any]] = []
    for p in plans:
        qcol = (p.get("queue") or {}).get("column")
        if qcol == "ready":
            explicit.append(p)
        else:
            default.append(p)
    explicit.sort(
        key=lambda p: (int((p.get("queue") or {}).get("index", -1)), p["slug"])
    )

    def _recency_key(p: Dict[str, Any]) -> Tuple[int, str]:
        created = _parse_created(p)
        # Newest first: negate ordinal so ascending sort yields newest first.
        ord_ = -(created.toordinal()) if created is not None else 0
        return (ord_, p["slug"])

    default.sort(key=_recency_key)
    return explicit + default


def _sort_alpha(plans: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return sorted(plans, key=lambda p: p["slug"])


# ---------------------------------------------------------------------------
# Meta-plan expansion
# ---------------------------------------------------------------------------


def _expand_meta_plans(
    plans_in_section: List[Dict[str, Any]],
    all_plans: List[Dict[str, Any]],
) -> List[Tuple[Dict[str, Any], List[Dict[str, Any]]]]:
    """Group meta-plans with their sub-plans.

    Returns a list of (plan, sub_plans) tuples in the same order as
    `plans_in_section`, but with sub-plans referenced by any meta-plan
    in the same section REMOVED from top-level (they appear only as
    children of their parent).
    """
    by_slug: Dict[str, Dict[str, Any]] = {p["slug"]: p for p in all_plans}
    consumed: set[str] = set()
    for p in plans_in_section:
        if p.get("meta_plan"):
            for sub_slug in p.get("sub_plans") or []:
                consumed.add(sub_slug)
    out: List[Tuple[Dict[str, Any], List[Dict[str, Any]]]] = []
    for p in plans_in_section:
        if p["slug"] in consumed:
            continue  # listed under its parent only
        if p.get("meta_plan"):
            children: List[Dict[str, Any]] = []
            for sub_slug in p.get("sub_plans") or []:
                child = by_slug.get(sub_slug)
                if child is not None:
                    children.append(child)
            out.append((p, children))
        else:
            out.append((p, []))
    return out


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------


def _basename(plan: Dict[str, Any]) -> str:
    """Filename used as the table link target. Falls back to slug-derived
    upper-case .md if `file` is missing."""
    f = plan.get("file") or ""
    if f:
        return os.path.basename(f)
    return plan["slug"].upper().replace("-", "_") + ".md"


def _md_link(plan: Dict[str, Any]) -> str:
    base = _basename(plan)
    return "[{name}]({name})".format(name=base)


def _next_phase_label(plan: Dict[str, Any]) -> str:
    """First entry in phases[] whose status != "done"; fall back to
    "Phase 1" if no tracker rows are present."""
    phases = plan.get("phases") or []
    for row in phases:
        if (row.get("status") or "") != "done":
            n = row.get("n") or "?"
            name = (row.get("name") or "").strip()
            if name:
                return f"{n} -- {name}"
            return f"{n}"
    if plan.get("phase_count"):
        return "1"
    return "—"


def _current_phase_label(plan: Dict[str, Any]) -> str:
    """Last entry in phases[] with status=="done"."""
    phases = plan.get("phases") or []
    last_done = None
    for row in phases:
        if (row.get("status") or "") == "done":
            last_done = row
    if last_done is None:
        return "—"
    n = last_done.get("n") or "?"
    name = (last_done.get("name") or "").strip()
    if name:
        return f"{n} -- {name}"
    return f"{n}"


def _canary_tracker_status(plan: Dict[str, Any]) -> str:
    """Derive per-canary tracker state from phases[]. Per SKILL.md."""
    phases = plan.get("phases") or []
    if not phases:
        return "Manual — no tracker"
    total = len(phases)
    done = sum(1 for r in phases if (r.get("status") or "") == "done")
    if done == 0:
        return "Ready"
    if done == total:
        return "Complete"
    return "In Progress"


def _escape_pipe(s: str) -> str:
    """Markdown tables use `|` as a delimiter — escape any in cell text."""
    return (s or "").replace("|", "\\|")


def _short_note(plan: Dict[str, Any]) -> str:
    """One-line note. Defaults to the first line of blurb, trimmed."""
    blurb = (plan.get("blurb") or "").strip()
    if not blurb:
        return ""
    first = blurb.splitlines()[0].strip()
    if len(first) > 120:
        first = first[:117] + "..."
    return _escape_pipe(first)


# ---------------------------------------------------------------------------
# Section table renderers
# ---------------------------------------------------------------------------


def _row(*cells: str) -> str:
    return "| " + " | ".join(cells) + " |"


def _empty_row(columns: int) -> str:
    cells = ["(none)"] + [""] * (columns - 1)
    return _row(*cells)


def _render_ready(
    plans: List[Dict[str, Any]],
    all_plans: List[Dict[str, Any]],
    today: datetime.date,
) -> List[str]:
    out = ["## Ready to Run", ""]
    out.append("| Plan | Phases | Next Phase | Priority | Notes |")
    out.append("|------|--------|------------|----------|-------|")
    if not plans:
        out.append(_empty_row(5))
        out.append("")
        return out
    sorted_plans = _sort_ready(plans)
    expanded = _expand_meta_plans(sorted_plans, all_plans)
    for plan, children in expanded:
        out.append(_row(
            _md_link(plan),
            str(plan.get("phase_count") or 0),
            _escape_pipe(_next_phase_label(plan)),
            _priority(plan, today),
            _short_note(plan),
        ))
        for child in children:
            out.append(_row(
                "  ↳ " + _md_link(child),
                str(child.get("phase_count") or 0),
                _escape_pipe(_next_phase_label(child)),
                _priority(child, today),
                "Sub-plan of " + plan["slug"],
            ))
    out.append("")
    return out


def _render_in_progress(
    plans: List[Dict[str, Any]],
    all_plans: List[Dict[str, Any]],
) -> List[str]:
    out = ["## In Progress", ""]
    out.append("| Plan | Phases | Current Phase | Next Phase | Notes |")
    out.append("|------|--------|---------------|------------|-------|")
    if not plans:
        out.append(_empty_row(5))
        out.append("")
        return out
    sorted_plans = _sort_alpha(plans)
    expanded = _expand_meta_plans(sorted_plans, all_plans)
    for plan, children in expanded:
        out.append(_row(
            _md_link(plan),
            "{}/{}".format(
                int(plan.get("phases_done") or 0),
                int(plan.get("phase_count") or 0),
            ),
            _escape_pipe(_current_phase_label(plan)),
            _escape_pipe(_next_phase_label(plan)),
            _short_note(plan),
        ))
        for child in children:
            out.append(_row(
                "  ↳ " + _md_link(child),
                "{}/{}".format(
                    int(child.get("phases_done") or 0),
                    int(child.get("phase_count") or 0),
                ),
                _escape_pipe(_current_phase_label(child)),
                _escape_pipe(_next_phase_label(child)),
                "Sub-plan of " + plan["slug"],
            ))
    out.append("")
    return out


def _render_needs_review(
    plans: List[Dict[str, Any]],
    all_plans: List[Dict[str, Any]],
) -> List[str]:
    out = ["## Needs Review", ""]
    out.append(
        "Old-format plans without progress trackers, plans with "
        "`status: conflict`, or plans with an unrecognised status "
        "(`deferred`, `proposal`, etc.). Triage these once: mark as "
        "Complete, move to Ready, or rewrite with `/draft-plan`."
    )
    out.append("")
    out.append("| Plan | Phases | Issue | Notes |")
    out.append("|------|--------|-------|-------|")
    if not plans:
        out.append(_empty_row(4))
        out.append("")
        return out
    sorted_plans = _sort_alpha(plans)
    expanded = _expand_meta_plans(sorted_plans, all_plans)
    for plan, children in expanded:
        out.append(_row(
            _md_link(plan),
            str(plan.get("phase_count") or 0),
            _escape_pipe(plan.get("status") or ""),
            _short_note(plan),
        ))
        for child in children:
            out.append(_row(
                "  ↳ " + _md_link(child),
                str(child.get("phase_count") or 0),
                _escape_pipe(child.get("status") or ""),
                "Sub-plan of " + plan["slug"],
            ))
    out.append("")
    return out


def _render_complete(
    plans: List[Dict[str, Any]],
    all_plans: List[Dict[str, Any]],
) -> List[str]:
    out = ["## Complete", ""]
    out.append("| Plan | Phases | Notes |")
    out.append("|------|--------|-------|")
    if not plans:
        out.append(_empty_row(3))
        out.append("")
        return out
    sorted_plans = _sort_alpha(plans)
    expanded = _expand_meta_plans(sorted_plans, all_plans)
    for plan, children in expanded:
        note = "All phases done"
        if plan.get("meta_plan"):
            note = "Meta-plan — all sub-plans done"
        out.append(_row(
            _md_link(plan),
            str(plan.get("phase_count") or 0),
            note,
        ))
        for child in children:
            out.append(_row(
                "  ↳ " + _md_link(child),
                str(child.get("phase_count") or 0),
                "Sub-plan of " + plan["slug"],
            ))
    out.append("")
    return out


def _render_canaries(plans: List[Dict[str, Any]]) -> List[str]:
    out = ["## Canaries", ""]
    out.append(
        "Canaries are re-runnable test fixtures; their tracker state "
        "may not reflect actual run history. To check whether a canary "
        "has run, examine git history for its output file or a PR with "
        "its name."
    )
    out.append("")
    out.append("| Canary | Tracker Status | Phases | Notes |")
    out.append("|--------|----------------|--------|-------|")
    if not plans:
        out.append(_empty_row(4))
        out.append("")
        return out
    for plan in _sort_alpha(plans):
        tracker_status = _canary_tracker_status(plan)
        phases_cell = (
            "n/a" if tracker_status == "Manual — no tracker"
            else str(plan.get("phase_count") or 0)
        )
        out.append(_row(
            _md_link(plan),
            tracker_status,
            phases_cell,
            _short_note(plan),
        ))
    out.append("")
    return out


def _render_reference(plans: List[Dict[str, Any]]) -> List[str]:
    out = ["## Reference (not executable)", ""]
    out.append("| File | Type | Description |")
    out.append("|------|------|-------------|")
    if not plans:
        out.append(_empty_row(3))
        out.append("")
        return out
    for plan in _sort_alpha(plans):
        kind = (
            "Issue Tracker"
            if plan.get("category") == "issue_tracker"
            else "Reference"
        )
        out.append(_row(
            _md_link(plan),
            kind,
            _short_note(plan),
        ))
    out.append("")
    return out


# ---------------------------------------------------------------------------
# Top-level render
# ---------------------------------------------------------------------------


def render(snapshot: Dict[str, Any], rebuilt_at: str) -> str:
    plans = list(snapshot.get("plans") or [])
    today = datetime.date.today()

    # Bucket every plan by section.
    buckets: Dict[str, List[Dict[str, Any]]] = {
        SECTION_READY: [],
        SECTION_IN_PROGRESS: [],
        SECTION_NEEDS_REVIEW: [],
        SECTION_COMPLETE: [],
        SECTION_CANARIES: [],
        SECTION_REFERENCE: [],
    }
    for p in plans:
        sec = section_for(p)
        buckets[sec].append(p)

    # Totals line — counts top-level entries (sub-plans are still counted
    # once at their canonical section, so this matches plan-file count
    # exactly).
    totals_line = (
        "Totals: {N} plans — {R} ready, {I} in progress, {C} complete, "
        "{K} canaries, {F} reference."
    ).format(
        N=len(plans),
        R=len(buckets[SECTION_READY]),
        I=len(buckets[SECTION_IN_PROGRESS]),
        C=len(buckets[SECTION_COMPLETE]),
        K=len(buckets[SECTION_CANARIES]),
        F=len(buckets[SECTION_REFERENCE]),
    )

    lines: List[str] = [
        "# Plan Index",
        "",
        "Auto-generated by `/plans rebuild`. Last rebuilt: {}.".format(rebuilt_at),
        "",
        totals_line,
        "",
    ]
    lines.extend(_render_ready(buckets[SECTION_READY], plans, today))
    lines.extend(_render_in_progress(buckets[SECTION_IN_PROGRESS], plans))
    lines.extend(_render_needs_review(buckets[SECTION_NEEDS_REVIEW], plans))
    lines.extend(_render_complete(buckets[SECTION_COMPLETE], plans))
    lines.extend(_render_canaries(buckets[SECTION_CANARIES]))
    lines.extend(_render_reference(buckets[SECTION_REFERENCE]))
    # Trim any trailing blank lines and end on exactly one newline.
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _load_snapshot(stream) -> Dict[str, Any]:
    raw = stream.read()
    if not raw.strip():
        raise ValueError("empty stdin — expected JSON snapshot")
    snap = json.loads(raw)
    if not isinstance(snap, dict):
        raise ValueError("snapshot root must be a JSON object")
    if "plans" not in snap:
        raise ValueError("snapshot missing 'plans' field")
    if not isinstance(snap.get("plans"), list):
        raise ValueError("snapshot 'plans' must be a list")
    return snap


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="render-index.py",
        description=(
            "Render PLAN_INDEX.md from a zskills_monitor.collect snapshot. "
            "Reads JSON on stdin, writes markdown on stdout."
        ),
    )
    parser.add_argument(
        "--rebuilt-at",
        required=True,
        help=(
            "Timestamp string for the 'Last rebuilt' line "
            "(typically: TZ=\"${TIMEZONE:-UTC}\" date '+%%Y-%%m-%%d %%H:%%M %%Z')."
        ),
    )
    args = parser.parse_args(argv)

    try:
        snapshot = _load_snapshot(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(
            "ERROR: render-index.py could not parse snapshot from stdin: {}".format(exc),
            file=sys.stderr,
        )
        return 2

    out = render(snapshot, args.rebuilt_at)
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
