#!/usr/bin/env python3
"""Tests for run-plan claim-file collector in collect.py (Phase 3 of
plans/plans-claim-chip-parity.md).

`_read_plan_claims` reads `${main_root}/.zskills/claims/plan-<slug>/
claim.json` per snapshot and `_annotate_plans_queue` attaches a `claim`
field to each plan. The schema mirrors the issue-side claim (DA2.6 +
field allow-list) but is keyed on string slug instead of issue number,
includes `current_phase`, and computes `age_seconds` from
`started_at` (post-#684 cleanup removed `last_heartbeat_at` as a
duplicate of `started_at`; phase progression is now signalled by the
`current_phase` field rather than by chip age).

stdlib-only — `unittest`, no pytest. Invoked from the .sh wrapper which
translates the results to the dashboard test format (PASS/FAIL lines +
`Results: X passed, Y failed (of Z)`).
"""

from __future__ import annotations

import json
import pathlib
import shutil
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

# Resolve the collect module from the in-tree skill source. The .sh
# wrapper sets PYTHONPATH; this fallback lets `python3 tests/...py` work
# directly from the repo root for quick local iteration.
HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
PKG_PARENT = REPO_ROOT / "skills" / "zskills-dashboard" / "scripts"
if str(PKG_PARENT) not in sys.path:
    sys.path.insert(0, str(PKG_PARENT))

from zskills_monitor import collect  # noqa: E402


def _write_plan_claim(claims_dir: pathlib.Path, slug: str, body: dict) -> None:
    d = claims_dir / ("plan-%s" % slug)
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "claim.json", "w", encoding="utf-8") as fh:
        json.dump(body, fh, sort_keys=True)


def _mkdir_no_claim(claims_dir: pathlib.Path, slug: str) -> None:
    d = claims_dir / ("plan-%s" % slug)
    d.mkdir(parents=True, exist_ok=True)


class ReadPlanClaimsTests(unittest.TestCase):

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="zskills-plan-claims-"))
        self.claims = self.tmp / ".zskills" / "claims"
        self.claims.mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------------
    # Core enumeration / field allow-list / null-metadata tolerance
    # ------------------------------------------------------------------

    def test_three_plan_claims_populated(self) -> None:
        now = datetime.now(timezone.utc)
        fresh_started = now - timedelta(seconds=20)
        mid_started = now - timedelta(seconds=420)
        _write_plan_claim(self.claims, "foo", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "foo",
            "pipeline_id": "run-plan.foo",
            "started_at": fresh_started.isoformat(timespec="seconds"),
            "current_phase": "Phase 3",
        })
        _write_plan_claim(self.claims, "bar-baz", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "bar-baz",
            "pipeline_id": "run-plan.bar-baz",
            "started_at": mid_started.isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
        })
        # Sweep-while-flush race: directory exists, claim.json absent.
        _mkdir_no_claim(self.claims, "pending-slug")

        out = collect._read_plan_claims(self.tmp)

        self.assertIn("foo", out)
        self.assertIn("bar-baz", out)
        self.assertIn("pending-slug", out)

        # Slug 'foo': full metadata, age from started_at (~20s).
        c1 = out["foo"]
        self.assertEqual(c1["pipeline_id"], "run-plan.foo")
        self.assertEqual(c1["current_phase"], "Phase 3")
        self.assertIsNotNone(c1["started_at"])
        self.assertIsNotNone(c1["age_seconds"])
        self.assertGreaterEqual(c1["age_seconds"], 0)
        self.assertLess(c1["age_seconds"], 300)

        # Slug 'bar-baz': mid-aged started_at (~420s).
        c2 = out["bar-baz"]
        self.assertGreater(c2["age_seconds"], 300)

        # Pending-slug: null-metadata, all None.
        c3 = out["pending-slug"]
        self.assertIsNone(c3["pipeline_id"])
        self.assertIsNone(c3["started_at"])
        self.assertIsNone(c3["current_phase"])
        self.assertIsNone(c3["age_seconds"])
        self.assertIsNone(c3["pipeline_short"])

    def test_field_allow_list_no_leaks(self) -> None:
        # Even if a future writer (or rogue test fixture) embeds extra
        # fields, the collector MUST NOT propagate them. NO worktree_path,
        # NO host_pid, NO schema_version, NO kind in the rendered claim
        # dict — only the 5-field allow-list (post-#684 cleanup dropped
        # last_heartbeat_at).
        _write_plan_claim(self.claims, "leakcheck", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "leakcheck",
            "pipeline_id": "run-plan.leakcheck",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
            "host_pid": 99999,
            "worktree_path": "/tmp/should-not-leak",
            "some_future_field": "should-also-not-leak",
        })
        out = collect._read_plan_claims(self.tmp)
        c = out["leakcheck"]
        self.assertNotIn("host_pid", c)
        self.assertNotIn("worktree_path", c)
        self.assertNotIn("schema_version", c)
        self.assertNotIn("kind", c)
        self.assertNotIn("last_heartbeat_at", c)
        self.assertNotIn("some_future_field", c)
        self.assertEqual(
            set(c.keys()),
            {"pipeline_id", "started_at", "current_phase",
             "age_seconds", "pipeline_short"},
        )

    def test_pipeline_short_derived(self) -> None:
        _write_plan_claim(self.claims, "pidcheck", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "pidcheck",
            "pipeline_id": "run-plan.sprint-20260521-010731-foo",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        # _derive_pipeline_short emits the parts[2:4] join when the tail
        # has ≥4 dash-segments (mirror of issue side).
        self.assertEqual(out["pidcheck"]["pipeline_short"], "010731-foo")

    def test_malformed_json_skipped(self) -> None:
        d = self.claims / "plan-broken"
        d.mkdir()
        with open(d / "claim.json", "w", encoding="utf-8") as fh:
            fh.write("{not valid json")
        out = collect._read_plan_claims(self.tmp)
        self.assertNotIn("broken", out)

    def test_claims_dir_missing(self) -> None:
        # No claims dir → empty.
        shutil.rmtree(self.claims)
        out = collect._read_plan_claims(self.tmp)
        self.assertEqual(out, {})

    def test_non_plan_dir_ignored(self) -> None:
        # Stray non-`plan-*` dirs (issue-*, etc.) must not be enumerated.
        (self.claims / "issue-5").mkdir()
        (self.claims / "stray").mkdir()
        _write_plan_claim(self.claims, "foo", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "foo",
            "pipeline_id": "run-plan.foo",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertIn("foo", out)
        self.assertEqual(set(out.keys()), {"foo"})

    def test_unparseable_started_at_yields_null_age(self) -> None:
        _write_plan_claim(self.claims, "bad-started", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "bad-started",
            "pipeline_id": "run-plan.bad-started",
            "started_at": "garbage-not-iso",
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        # Implementation tolerates unparseable started_at by surfacing
        # age_seconds=None (renderer falls back to '?').
        self.assertIsNone(out["bad-started"]["age_seconds"])


class AnnotatePlansQueueGatingTests(unittest.TestCase):
    """R2.6 mirror — the 2-arg fixture branch MUST NOT call _read_plan_claims."""

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="zskills-plan-anno-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_fixture_branch_does_not_call_read_plan_claims(self) -> None:
        plans = [
            {"slug": "foo", "title": "Plan foo"},
            {"slug": "bar", "title": "Plan bar"},
        ]
        state = {"plans": {"drafted": [], "ready": [{"slug": "foo"}, {"slug": "bar"}],
                           "in-progress": [], "done": []}}
        with mock.patch.object(collect, "_read_plan_claims") as mocked:
            collect._annotate_plans_queue(plans, state)
            self.assertEqual(mocked.call_count, 0)
        for plan in plans:
            self.assertNotIn("claim", plan)

    def test_main_root_branch_calls_read_plan_claims(self) -> None:
        plans = [
            {"slug": "alpha", "title": "Claimed plan"},
            {"slug": "beta", "title": "Unclaimed plan"},
        ]
        state = {"plans": {"drafted": [], "ready": [{"slug": "alpha"}, {"slug": "beta"}],
                           "in-progress": [], "done": []}}
        fake_claim = {
            "pipeline_id": "run-plan.alpha",
            "started_at": "2026-05-21T01:07:31+00:00",
            "current_phase": "Phase 2",
            "age_seconds": 30.0,
            "pipeline_short": "alpha",
        }
        with mock.patch.object(collect, "_read_plan_claims",
                               return_value={"alpha": fake_claim}) as mocked:
            collect._annotate_plans_queue(plans, state, self.tmp)
            self.assertEqual(mocked.call_count, 1)
        c = plans[0].get("claim")
        self.assertIsNotNone(c)
        self.assertEqual(c["pipeline_id"], "run-plan.alpha")
        self.assertEqual(c["current_phase"], "Phase 2")
        self.assertEqual(c["started_at"], "2026-05-21T01:07:31+00:00")
        # Allow-list discipline.
        self.assertNotIn("host_pid", c)
        self.assertNotIn("worktree_path", c)
        self.assertNotIn("kind", c)
        self.assertNotIn("schema_version", c)
        self.assertNotIn("last_heartbeat_at", c)
        self.assertEqual(
            set(c.keys()),
            {"pipeline_id", "started_at", "current_phase",
             "age_seconds", "pipeline_short"},
        )
        # Plan beta has no claim attached.
        self.assertNotIn("claim", plans[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
