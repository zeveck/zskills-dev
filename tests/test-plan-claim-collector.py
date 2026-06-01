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
             "age_seconds", "pipeline_short", "dispatch_mode", "stale"},
        )
        # dispatch_mode (#874) is on the allow-list. Absent in the
        # source claim → surfaces as None.
        self.assertIsNone(c["dispatch_mode"])
        # stale (#912) is on the allow-list. A fresh claim → not stale.
        self.assertFalse(c["stale"])

    def test_dispatch_mode_finish_persists(self) -> None:
        # #874: claim.json carrying dispatch_mode="finish" must surface
        # the field verbatim so the dashboard mode chip can lock.
        _write_plan_claim(self.claims, "dmfinish", {
            "schema_version": 1,
            "kind": "plan",
            "slug": "dmfinish",
            "pipeline_id": "run-plan.dmfinish",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 2",
            "dispatch_mode": "finish",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertEqual(out["dmfinish"]["dispatch_mode"], "finish")

    def test_dispatch_mode_phase_persists(self) -> None:
        _write_plan_claim(self.claims, "dmphase", {
            "schema_version": 1,
            "kind": "plan",
            "slug": "dmphase",
            "pipeline_id": "run-plan.dmphase",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 2",
            "dispatch_mode": "phase",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertEqual(out["dmphase"]["dispatch_mode"], "phase")

    def test_dispatch_mode_unknown_rejected_as_none(self) -> None:
        # An invalid string in claim.json (would only happen if a future
        # writer drifted) must NOT propagate to the dashboard — the
        # collector clamps to None and the chip falls through to its
        # default precedence.
        _write_plan_claim(self.claims, "dmbogus", {
            "schema_version": 1,
            "kind": "plan",
            "slug": "dmbogus",
            "pipeline_id": "run-plan.dmbogus",
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
            "dispatch_mode": "bogus",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertIsNone(out["dmbogus"]["dispatch_mode"])

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

    # ------------------------------------------------------------------
    # Staleness gate (#912) — dead-pipeline claim recovery.
    # ------------------------------------------------------------------

    def test_stale_claim_tagged_when_old(self) -> None:
        # A claim whose owning /run-plan pipeline died mid-flight leaves
        # claim.json on disk indefinitely. age > PLAN_CLAIM_STALE_SECONDS
        # (6h) → stale: True so the renderer offers an in-UI release path
        # instead of the permanent hard-lock. ~24h ago is well past 6h.
        now = datetime.now(timezone.utc)
        old_started = now - timedelta(hours=24)
        _write_plan_claim(self.claims, "dead-pipeline", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "dead-pipeline",
            "pipeline_id": "run-plan.dead-pipeline",
            "started_at": old_started.isoformat(timespec="seconds"),
            "current_phase": "Phase 3",
        })
        out = collect._read_plan_claims(self.tmp)
        c = out["dead-pipeline"]
        self.assertTrue(c["stale"])
        # The card must still render (NOT filtered out) so the user can
        # dismiss it.
        self.assertIsNotNone(c["age_seconds"])
        self.assertGreater(c["age_seconds"], collect.PLAN_CLAIM_STALE_SECONDS)

    def test_fresh_claim_not_stale(self) -> None:
        # A just-started claim (started_at=now) is a LIVE pipeline; it must
        # keep the #884/#904 hard-lock (stale: False).
        now = datetime.now(timezone.utc)
        _write_plan_claim(self.claims, "live-pipeline", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "live-pipeline",
            "pipeline_id": "run-plan.live-pipeline",
            "started_at": now.isoformat(timespec="seconds"),
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertFalse(out["live-pipeline"]["stale"])

    def test_claim_just_under_threshold_not_stale(self) -> None:
        # Boundary: a claim a few minutes under 6h is still live.
        now = datetime.now(timezone.utc)
        started = now - timedelta(
            seconds=collect.PLAN_CLAIM_STALE_SECONDS - 300)
        _write_plan_claim(self.claims, "near-threshold", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "near-threshold",
            "pipeline_id": "run-plan.near-threshold",
            "started_at": started.isoformat(timespec="seconds"),
            "current_phase": "Phase 5",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertFalse(out["near-threshold"]["stale"])

    def test_unparseable_started_at_fails_toward_not_stale(self) -> None:
        # Fail-toward-not-stale: an unparseable started_at yields
        # age_seconds=None, which must NOT be treated as stale — otherwise
        # a live claim with a transiently-malformed timestamp would be
        # wrongly offered for release.
        _write_plan_claim(self.claims, "bad-age", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "bad-age",
            "pipeline_id": "run-plan.bad-age",
            "started_at": "garbage-not-iso",
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertIsNone(out["bad-age"]["age_seconds"])
        self.assertFalse(out["bad-age"]["stale"])

    def test_missing_started_at_fails_toward_not_stale(self) -> None:
        # A claim with no started_at at all → age None → not stale.
        _write_plan_claim(self.claims, "no-started", {
            "schema_version": 1,
            "kind": "run-plan",
            "slug": "no-started",
            "pipeline_id": "run-plan.no-started",
            "current_phase": "Phase 1",
        })
        out = collect._read_plan_claims(self.tmp)
        self.assertIsNone(out["no-started"]["age_seconds"])
        self.assertFalse(out["no-started"]["stale"])

    def test_null_metadata_entry_not_stale(self) -> None:
        # Sweep-while-flush race (dir present, claim.json absent) → null
        # metadata entry with stale: False (no age to judge).
        _mkdir_no_claim(self.claims, "pending")
        out = collect._read_plan_claims(self.tmp)
        self.assertFalse(out["pending"]["stale"])


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
            "dispatch_mode": "finish",
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
        # #874: dispatch_mode threads through the allow-list onto plan["claim"]
        # so the dashboard chip can lock LOCKED finish across the full
        # /run-plan lifetime (outliving the /work-on-plans wrapper that
        # spawned it — sibling to #858's wrapper-lifetime batch_mode).
        self.assertEqual(c["dispatch_mode"], "finish")
        # Allow-list discipline.
        self.assertNotIn("host_pid", c)
        self.assertNotIn("worktree_path", c)
        self.assertNotIn("kind", c)
        self.assertNotIn("schema_version", c)
        self.assertNotIn("last_heartbeat_at", c)
        self.assertEqual(
            set(c.keys()),
            {"pipeline_id", "started_at", "current_phase",
             "age_seconds", "pipeline_short", "dispatch_mode", "stale"},
        )
        # stale (#912) threads through onto plan["claim"] from the collector.
        self.assertIn("stale", c)
        # Plan beta has no claim attached.
        self.assertNotIn("claim", plans[1])


class DerivePipelineShortTests(unittest.TestCase):
    """_derive_pipeline_short: human-meaningful short label from a pipeline id.

    Regression coverage for the bug where `run-plan.plugin-distribution`
    rendered as "ribution" (blind [-8:] suffix slice) and multi-hyphen plan
    slugs were mangled by a bare `len(parts) >= 4` sprint heuristic.
    """

    def test_run_plan_slug_shown_whole(self):
        # Was the bug: "ribution". Now the whole slug.
        self.assertEqual(
            collect._derive_pipeline_short("run-plan.plugin-distribution"),
            "plugin-distribution",
        )

    def test_sprint_id_keeps_time_slug_tail(self):
        # Real sprint shape (sprint-<digits>-<digits>-...) still distinguishes
        # concurrent sprints by the time+slug tail.
        self.assertEqual(
            collect._derive_pipeline_short(
                "fix-issues.sprint-20260521-010731-foo"),
            "010731-foo",
        )

    def test_multi_hyphen_plan_slug_not_mangled(self):
        # Pre-fix this hit the `len(parts) >= 4` branch and returned
        # "and-rename". Now the whole slug (capped — see length test).
        self.assertEqual(
            collect._derive_pipeline_short(
                "run-plan.dashboard-tabs-and-rename-5a"),
            "dashboard-tabs-and-rename-5a",
        )

    def test_short_three_part_slug_whole(self):
        # Pre-fix the `[-8:]` fallback gave "xecution".
        self.assertEqual(
            collect._derive_pipeline_short("run-plan.restore-chunked-execution"),
            "restore-chunked-execution",
        )

    def test_long_slug_front_truncated_with_ellipsis(self):
        out = collect._derive_pipeline_short(
            "run-plan.a-really-long-plan-slug-that-exceeds-the-cap", maxlen=28)
        self.assertEqual(len(out), 28)
        self.assertTrue(out.endswith("…"))
        self.assertTrue(out.startswith("a-really-long-plan-slug-"))

    def test_prefix_dropped(self):
        # The pipeline-type prefix before the last '.' is not part of the label.
        self.assertEqual(collect._derive_pipeline_short("do.x"), "x")

    def test_non_sprint_four_part_not_treated_as_sprint(self):
        # 4 parts but parts[0] != "sprint" and parts[1] not digits → whole slug.
        self.assertEqual(
            collect._derive_pipeline_short("run-plan.alpha-beta-gamma-delta"),
            "alpha-beta-gamma-delta",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
