#!/usr/bin/env python3
"""Tests for fix-issues claim-file collector in collect.py.

Issue #514 — the claim chip lights up on the dashboard when /fix-issues
is mid-flight. The collector reads `${main_root}/.zskills/claims/issue-*/
claim.json` per snapshot and attaches a `claim` field to each issue.
Latency budget is <10ms p99 for 50 simulated claims (T3.3).

stdlib-only — `unittest`, no pytest. Invoked from the .sh wrapper which
translates the results to the dashboard test format (PASS/FAIL lines +
`Results: X passed, Y failed (of Z)`).
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import sys
import tempfile
import time
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


def _write_claim(claims_dir: pathlib.Path, num: int, body: dict) -> None:
    d = claims_dir / ("issue-%d" % num)
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "claim.json", "w", encoding="utf-8") as fh:
        json.dump(body, fh, sort_keys=True)


def _mkdir_no_claim(claims_dir: pathlib.Path, num: int) -> None:
    d = claims_dir / ("issue-%d" % num)
    d.mkdir(parents=True, exist_ok=True)


class ReadClaimsTests(unittest.TestCase):

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="zskills-claims-"))
        self.claims = self.tmp / ".zskills" / "claims"
        self.claims.mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------------
    # Core enumeration / field allow-list / null-metadata tolerance
    # ------------------------------------------------------------------

    def test_three_claims_populated(self) -> None:
        # Fresh + mid-age claims with full metadata.
        now = datetime.now(timezone.utc)
        fresh = now - timedelta(seconds=30)
        mid = now - timedelta(seconds=600)
        _write_claim(self.claims, 1, {
            "schema_version": 1,
            "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
            "sprint_id": "sprint-20260521-010731-foo",
            "issue": 1,
            "started_at": fresh.isoformat(timespec="seconds"),
        })
        _write_claim(self.claims, 2, {
            "schema_version": 1,
            "pipeline_id": "fix-issues.sprint-20260521-120000-bar",
            "sprint_id": "sprint-20260521-120000-bar",
            "issue": 2,
            "started_at": mid.isoformat(timespec="seconds"),
        })
        # Issue 3: directory exists, claim.json absent — sweep-while-flush
        # race. Must surface a null-metadata in-flight chip.
        _mkdir_no_claim(self.claims, 3)

        out = collect._read_claims(self.tmp)

        self.assertIn(1, out)
        self.assertIn(2, out)
        self.assertIn(3, out)

        # Issue 1: full metadata, age_seconds >= 0
        c1 = out[1]
        self.assertEqual(c1["pipeline_id"], "fix-issues.sprint-20260521-010731-foo")
        self.assertEqual(c1["sprint_id"], "sprint-20260521-010731-foo")
        self.assertIsNotNone(c1["started_at"])
        self.assertIsNotNone(c1["age_seconds"])
        self.assertGreaterEqual(c1["age_seconds"], 0)
        self.assertLess(c1["age_seconds"], 300)  # fresh

        # Issue 2: mid-age
        c2 = out[2]
        self.assertGreater(c2["age_seconds"], 300)

        # Issue 3: null-metadata
        c3 = out[3]
        self.assertIsNone(c3["pipeline_id"])
        self.assertIsNone(c3["sprint_id"])
        self.assertIsNone(c3["started_at"])
        self.assertIsNone(c3["age_seconds"])
        self.assertIsNone(c3["pipeline_short"])

    def test_pipeline_short_explicit_lock(self) -> None:
        # DA4 explicit-example lock — locks the algorithm choice
        # (rsplit/split, parts[2:4]) against future drift to a naive
        # 8-char prefix slice that would yield "sprint-2" for every
        # concurrent sprint.
        _write_claim(self.claims, 10, {
            "schema_version": 1,
            "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
            "sprint_id": "sprint-20260521-010731-foo",
            "issue": 10,
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        })
        out = collect._read_claims(self.tmp)
        self.assertEqual(out[10]["pipeline_short"], "010731-foo")

    def test_pipeline_short_short_tail_fallback(self) -> None:
        # parts < 4 -> sprint_id_tail[-8:] fallback. Tail "shortid"
        # (7 chars) -> "shortid"; tail "abcdefghij" -> "cdefghij".
        _write_claim(self.claims, 11, {
            "schema_version": 1,
            "pipeline_id": "kind.shortid",
            "sprint_id": "shortid",
            "issue": 11,
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        })
        out = collect._read_claims(self.tmp)
        self.assertEqual(out[11]["pipeline_short"], "shortid")

    def test_no_host_pid_no_worktree_path(self) -> None:
        # Field allow-list discipline — even if a future writer (or a
        # rogue test fixture) embeds these fields, the collector MUST
        # NOT propagate them. Per DA2.1/DA2.2 host_pid is removed from
        # the schema; per DA8 worktree_path was never in it.
        _write_claim(self.claims, 12, {
            "schema_version": 1,
            "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
            "sprint_id": "sprint-20260521-010731-foo",
            "issue": 12,
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "host_pid": 99999,
            "worktree_path": "/tmp/should-not-leak",
            "some_future_field": "should-also-not-leak",
        })
        out = collect._read_claims(self.tmp)
        c = out[12]
        self.assertNotIn("host_pid", c)
        self.assertNotIn("worktree_path", c)
        self.assertNotIn("some_future_field", c)
        # Allow-list keys exact set:
        self.assertEqual(
            set(c.keys()),
            {"pipeline_id", "sprint_id", "age_seconds", "started_at", "pipeline_short"},
        )

    def test_malformed_json_skipped(self) -> None:
        # Malformed JSON -> single stderr line, claim skipped (not
        # crash, not partial parse).
        d = self.claims / "issue-20"
        d.mkdir()
        with open(d / "claim.json", "w", encoding="utf-8") as fh:
            fh.write("{not valid json")
        out = collect._read_claims(self.tmp)
        self.assertNotIn(20, out)

    def test_claims_dir_missing(self) -> None:
        # If `.zskills/claims/` doesn't exist, return empty (no claims
        # held). This is the steady-state on a fresh repo.
        shutil.rmtree(self.claims)
        out = collect._read_claims(self.tmp)
        self.assertEqual(out, {})

    def test_non_issue_dir_ignored(self) -> None:
        # Stray non-`issue-*` directories under .zskills/claims/ must
        # not break enumeration (defensive).
        (self.claims / "stray").mkdir()
        (self.claims / "issue-not-a-number").mkdir()
        _write_claim(self.claims, 5, {
            "schema_version": 1,
            "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
            "sprint_id": "sprint-20260521-010731-foo",
            "issue": 5,
            "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        })
        out = collect._read_claims(self.tmp)
        self.assertIn(5, out)
        self.assertEqual(set(out.keys()), {5})


class AnnotateIssuesQueueGatingTests(unittest.TestCase):
    """R2.6 — the 2-arg fixture branch MUST NOT call _read_claims."""

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="zskills-claims-anno-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_fixture_branch_does_not_call_read_claims(self) -> None:
        # Mock _read_claims; call _annotate_issues_queue(issues, state)
        # WITHOUT main_root. Assert _read_claims called 0 times.
        issues = [
            {"number": 1, "title": "issue one"},
            {"number": 2, "title": "issue two"},
        ]
        state = {"issues": {"triage": [], "ready": [1, 2], "in-progress": [], "done": []}}
        with mock.patch.object(collect, "_read_claims") as mocked:
            collect._annotate_issues_queue(issues, state)
            self.assertEqual(mocked.call_count, 0)
        # And no `claim` field was attached.
        for issue in issues:
            self.assertNotIn("claim", issue)

    def test_main_root_branch_calls_read_claims(self) -> None:
        # Positive control — the 3-arg branch DOES call _read_claims
        # once (per snapshot) and the returned dict drives the
        # `issue["claim"]` annotation.
        (self.tmp / ".claude").mkdir()
        (self.tmp / ".claude" / "zskills-config.json").write_text("{}", encoding="utf-8")
        issues = [
            {"number": 7, "title": "claimed"},
            {"number": 8, "title": "unclaimed"},
        ]
        state = {"issues": {"triage": [], "ready": [7, 8], "in-progress": [], "done": []}}
        fake_claim = {
            "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
            "sprint_id": "sprint-20260521-010731-foo",
            "age_seconds": 42.0,
            "started_at": "2026-05-21T01:07:31+00:00",
            "pipeline_short": "010731-foo",
        }
        with mock.patch.object(collect, "_read_claims", return_value={7: fake_claim}) as mocked:
            collect._annotate_issues_queue(issues, state, self.tmp)
            self.assertEqual(mocked.call_count, 1)
        # Issue 7 carries the claim dict; issue 8 does not.
        c = issues[0].get("claim")
        self.assertIsNotNone(c)
        self.assertEqual(c["pipeline_short"], "010731-foo")
        self.assertEqual(c["pipeline_id"], "fix-issues.sprint-20260521-010731-foo")
        # Allow-list discipline — no host_pid / worktree_path even when
        # _read_claims would (hypothetically) return them.
        self.assertNotIn("host_pid", c)
        self.assertNotIn("worktree_path", c)
        self.assertNotIn("claim", issues[1])


class ReadClaimsLatencyBenchmark(unittest.TestCase):
    """T3.3 — issue #514 latency budget. <10ms wall-clock p99 for 50
    simulated claims. NOT skip-not-fail. If this regresses, memoize
    per-snapshot identically to issues_fetch_ok.
    """

    def setUp(self) -> None:
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="zskills-claims-bench-"))
        self.claims = self.tmp / ".zskills" / "claims"
        self.claims.mkdir(parents=True)
        # 50 simulated claims.
        now_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
        for n in range(1, 51):
            _write_claim(self.claims, n, {
                "schema_version": 1,
                "pipeline_id": "fix-issues.sprint-20260521-%06d-bench" % n,
                "sprint_id": "sprint-20260521-%06d-bench" % n,
                "issue": n,
                "started_at": now_iso,
            })

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_p99_under_budget(self) -> None:
        N = 100
        BUDGET_MS = 10.0
        samples = []
        for _ in range(N):
            t0 = time.perf_counter()
            out = collect._read_claims(self.tmp)
            t1 = time.perf_counter()
            self.assertEqual(len(out), 50)
            samples.append((t1 - t0) * 1000.0)
        samples.sort()
        # p99 of 100 samples is index 98 (0-indexed).
        p99 = samples[98]
        self.assertLess(
            p99, BUDGET_MS,
            "p99=%.3fms exceeds %.1fms budget (issue #514). "
            "Memoize _read_claims per-snapshot if this regresses." % (p99, BUDGET_MS),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
