#!/usr/bin/env python3
"""Z Skills Dashboard — Demo Server.

A standalone demo that serves the real dashboard frontend with simulated
data. 20 sci-fi themed plans and 20 issues arrive staggered over ~10
minutes, progress through columns, and trigger a victory overlay when
all items reach completed.

    python3 demo/demo_server.py [--port PORT]

No external dependencies — Python 3 stdlib only.
"""

import argparse
import json
import os
import pathlib
import random
import sys
import time
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

DEMO_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = DEMO_DIR.parent
STATIC_DIR = REPO_ROOT / "skills" / "zskills-dashboard" / "scripts" / "zskills_monitor" / "static"

# ---------------------------------------------------------------------------
# Sci-fi content
# ---------------------------------------------------------------------------

PLAN_DEFS = [
    ("repair-hyperdrive-coupling", "Repair Hyperdrive Coupling", [
        "Diagnose harmonic resonance drift",
        "Replace flux capacitor array",
        "Calibrate thrust vectoring",
    ]),
    ("tachyon-anomaly-investigation", "Investigate Anomalous Tachyon Readings", [
        "Deploy sensor grid to sectors 7-12",
        "Correlate readings with stellar cartography",
        "Draft containment protocol",
        "Peer review with Science Division",
    ]),
    ("hull-breach-deck-7", "Patch Hull Breach in Deck 7", [
        "Emergency atmospheric seal",
        "Structural integrity field reinforcement",
        "Full hull plate replacement",
    ]),
    ("ai-core-alignment-audit", "AI Core Alignment Audit", [
        "Dump personality matrix logs",
        "Cross-reference with ethics subroutine v4.2",
        "Patch value-drift regression",
        "Run full alignment battery",
    ]),
    ("nebula-navigation-charts", "Update Nebula Navigation Charts", [
        "Scan Helix Nebula boundary shifts",
        "Recalculate safe transit corridors",
        "Distribute updated charts to fleet",
    ]),
    ("shields-harmonics-overhaul", "Shield Harmonics Overhaul", [
        "Benchmark current shield modulation",
        "Install phase-variant emitter array",
        "Stress-test against simulated plasma torpedoes",
    ]),
    ("crew-stasis-pod-maintenance", "Crew Stasis Pod Maintenance Cycle", [
        "Drain and clean bio-gel reservoirs",
        "Recalibrate neural induction coils",
        "Run occupant simulation health checks",
    ]),
    ("quantum-comm-relay-upgrade", "Quantum Comm Relay Upgrade", [
        "Decommission legacy subspace antenna",
        "Install entanglement pair buffers",
        "Validate zero-latency handshake",
        "Cut over from subspace to quantum",
    ]),
    ("asteroid-mining-drone-swarm", "Deploy Asteroid Mining Drone Swarm", [
        "Manufacture drone chassis batch",
        "Program swarm coordination AI",
        "Field test in Kuiper belt analog",
    ]),
    ("holodeck-physics-engine", "Holodeck Physics Engine Rewrite", [
        "Profile existing fluid dynamics module",
        "Implement SPH solver in ship-local coordinates",
        "Validate gravity simulation accuracy",
    ]),
    ("stellar-cartography-3d-map", "Stellar Cartography 3D Map Renderer", [
        "Parse galactic coordinate feeds",
        "Build real-time WebGL star renderer",
        "Add interactive sector overlays",
    ]),
    ("xenolinguistics-translator", "Xenolinguistics Universal Translator Patch", [
        "Integrate Vorta dialect corpus",
        "Fix pronoun-case ambiguity in Klingon module",
        "Regression test against 47 known languages",
    ]),
    ("warp-core-efficiency-tuning", "Warp Core Efficiency Tuning", [
        "Measure dilithium crystal decay rates",
        "Optimize matter/antimatter injection ratios",
        "Validate at sustained Warp 8",
    ]),
    ("cargo-bay-inventory-system", "Cargo Bay Inventory System", [
        "RFID-tag all cargo containers",
        "Build real-time manifest dashboard",
        "Integrate with replicator supply chain",
    ]),
    ("emergency-protocol-omega", "Emergency Protocol Omega Drill", [
        "Review and update evacuation routes",
        "Simulate hull breach on 3 decks simultaneously",
        "Score crew response times",
        "Debrief and publish after-action report",
    ]),
    ("bio-neural-gel-pack-refresh", "Bio-Neural Gel Pack Refresh", [
        "Synthesize replacement gel cultures",
        "Swap packs on decks 4-9",
        "Run diagnostic handshake across all nodes",
    ]),
    ("deflector-dish-realignment", "Deflector Dish Realignment", [
        "Recalibrate primary emitter frequency",
        "Test tachyon burst dispersal pattern",
        "Verify long-range sensor integration",
    ]),
    ("transporter-pattern-buffer", "Transporter Pattern Buffer Expansion", [
        "Install additional pattern storage modules",
        "Migrate legacy patterns to new format",
        "Validate transport fidelity at 99.997%",
    ]),
    ("shuttle-bay-automation", "Shuttle Bay Launch Automation", [
        "Install magnetic rail catapult",
        "Program automated docking sequence",
        "Test with unmanned shuttle sorties",
    ]),
    ("gravity-plating-recalibration", "Gravity Plating Recalibration", [
        "Survey plating variance per deck",
        "Flash-update firmware on all grav-generators",
        "Spot-check with portable accelerometers",
    ]),
]

ISSUE_DEFS = [
    (101, "Plasma conduit leak in main engineering"),
    (102, "Navigation array returns NaN for subspace coordinates"),
    (103, "Turbolift stuck between decks 5 and 6"),
    (104, "Replicator produces Earl Grey at wrong temperature"),
    (105, "Inertial dampeners lag 200ms during course corrections"),
    (106, "Holodeck safety protocols intermittently disabled"),
    (107, "Phaser bank 3 fires 15 degrees off target"),
    (108, "Universal translator garbles Andorian sibilants"),
    (109, "Shuttle bay doors report closed when open"),
    (110, "Crew quarters lighting stuck on red alert spectrum"),
    (111, "Sensor ghost on long-range scanners bearing 047 mark 3"),
    (112, "Warp field geometry asymmetric at speeds above Warp 6"),
    (113, "Jefferies tube hatch 14-C jammed shut"),
    (114, "Medical tricorder firmware crashes on Bolian physiology"),
    (115, "Cargo transporter materializes items 2cm left of target"),
    (116, "Bridge viewscreen flickers during FTL transitions"),
    (117, "Environmental controls set deck 12 to 45°C"),
    (118, "Tactical console touch calibration drifted"),
    (119, "Escape pod 7 reports launch-ready when fuel is empty"),
    (120, "Astrometrics lab star catalog 3 months out of date"),
]


# ---------------------------------------------------------------------------
# Simulation engine
# ---------------------------------------------------------------------------

TOTAL_ARRIVAL_WINDOW = 540  # ~9 minutes for all items to arrive (last min is drain)
ITEM_DWELL_BASE = 55       # base seconds per column transition
ITEM_DWELL_VARIANCE = 35   # +/- random variance per transition

PLAN_COLUMNS = ["drafted", "reviewed", "ready", "completed"]
ISSUE_COLUMNS = ["triage", "ready", "completed"]


class SimItem:
    """Tracks an item's lifecycle through columns."""

    __slots__ = ("kind", "id_key", "arrive_at", "columns", "transitions",
                 "col_idx", "last_transition", "claim_pipeline")

    def __init__(self, kind, id_key, arrive_at, columns, rng):
        self.kind = kind
        self.id_key = id_key
        self.arrive_at = arrive_at
        self.columns = columns
        self.transitions = []
        for i in range(len(columns) - 1):
            dwell = ITEM_DWELL_BASE + rng.randint(-ITEM_DWELL_VARIANCE, ITEM_DWELL_VARIANCE)
            dwell = max(10, dwell)
            self.transitions.append(dwell)
        self.col_idx = -1  # not yet arrived
        self.last_transition = 0.0
        self.claim_pipeline = "demo-pipeline-%04d" % rng.randint(1000, 9999)

    def update(self, elapsed):
        if self.col_idx == len(self.columns) - 1:
            return  # already completed
        if elapsed < self.arrive_at:
            return  # not yet arrived
        if self.col_idx == -1:
            self.col_idx = 0
            self.last_transition = self.arrive_at
        while (self.col_idx < len(self.columns) - 1
               and elapsed - self.last_transition >= self.transitions[self.col_idx]):
            self.last_transition += self.transitions[self.col_idx]
            self.col_idx += 1

    @property
    def column(self):
        if self.col_idx < 0:
            return None
        return self.columns[self.col_idx]

    @property
    def is_completed(self):
        return self.col_idx == len(self.columns) - 1

    @property
    def is_in_flight(self):
        col = self.column
        if self.kind == "plan":
            return col == "ready"
        return col == "ready"


class Simulation:
    """Manages the full simulation state."""

    def __init__(self, seed=None):
        self.start_time = time.monotonic()
        self.rng = random.Random(seed if seed is not None else int(time.time()))
        self.plans = []
        self.issues = []
        self._init_items()

    def _init_items(self):
        # Interleave plan and issue arrivals so both kinds show up early.
        # First few arrive in the first 30s so the dashboard isn't empty.
        n_plans = len(PLAN_DEFS)
        n_issues = len(ISSUE_DEFS)
        plan_arrivals = [5 + i * (TOTAL_ARRIVAL_WINDOW - 5) / n_plans
                         + self.rng.uniform(-10, 10) for i in range(n_plans)]
        plan_arrivals = sorted(max(2, t) for t in plan_arrivals)

        issue_arrivals = [8 + i * (TOTAL_ARRIVAL_WINDOW - 8) / n_issues
                          + self.rng.uniform(-10, 10) for i in range(n_issues)]
        issue_arrivals = sorted(max(3, t) for t in issue_arrivals)

        for i, (slug, title, phases) in enumerate(PLAN_DEFS):
            item = SimItem("plan", slug, plan_arrivals[i], PLAN_COLUMNS, self.rng)
            self.plans.append((item, title, phases))

        for i, (num, title) in enumerate(ISSUE_DEFS):
            item = SimItem("issue", num, issue_arrivals[i], ISSUE_COLUMNS, self.rng)
            self.issues.append((item, title))

    def elapsed(self):
        return time.monotonic() - self.start_time

    def tick(self):
        elapsed = self.elapsed()
        for item, _, _ in self.plans:
            item.update(elapsed)
        for item, _ in self.issues:
            item.update(elapsed)

    def all_completed(self):
        return (all(it.is_completed for it, _, _ in self.plans)
                and all(it.is_completed for it, _ in self.issues))

    def progress(self):
        total = len(self.plans) + len(self.issues)
        done = (sum(1 for it, _, _ in self.plans if it.is_completed)
                + sum(1 for it, _ in self.issues if it.is_completed))
        return done, total

    def build_snapshot(self):
        self.tick()
        now_iso = datetime.now(timezone.utc).isoformat()
        elapsed = self.elapsed()

        plans_list = []
        plan_queues = {c: [] for c in PLAN_COLUMNS}

        for item, title, phase_defs in self.plans:
            if item.column is None:
                continue

            # Build phase detail
            phases_done = 0
            phases = []
            if item.is_completed:
                phases_done = len(phase_defs)
            elif item.column == "ready":
                # In-flight: show partial progress
                progress_frac = min(1.0, (elapsed - item.last_transition) /
                                    max(1, item.transitions[item.col_idx])
                                    if item.col_idx < len(item.transitions) else 1.0)
                phases_done = max(1, int(progress_frac * len(phase_defs)))
            elif item.column == "reviewed":
                phases_done = 0
            elif item.column == "drafted":
                phases_done = 0
            else:
                phases_done = len(phase_defs)

            for pi, pname in enumerate(phase_defs):
                phases.append({
                    "n": str(pi + 1),
                    "name": "%d — %s" % (pi + 1, pname),
                    "status": "done" if pi < phases_done else "pending",
                    "commit": "%07x" % self.rng.randint(0, 0xFFFFFFF) if pi < phases_done else None,
                    "notes": "" if pi >= phases_done else "Completed successfully",
                })

            status = "active"
            completed_dt = None
            if item.is_completed:
                status = "complete"
                completed_dt = (datetime.now(timezone.utc)
                                - timedelta(seconds=max(0, elapsed - item.last_transition))
                                ).isoformat()

            created_dt = (datetime.now(timezone.utc)
                          - timedelta(seconds=max(0, elapsed - item.arrive_at))
                          ).strftime("%Y-%m-%d")

            col = item.column
            idx = len(plan_queues[col])
            plan_queues[col].append({"slug": item.id_key, "mode": None})

            plan_obj = {
                "slug": item.id_key,
                "file": "docs/plans/%s.md" % item.id_key.upper().replace("-", "_"),
                "title": title,
                "status": status,
                "created": created_dt,
                "completed": completed_dt,
                "issue": None,
                "blurb": "Starship maintenance task: %s" % title.lower(),
                "phase_count": len(phase_defs),
                "phases_done": phases_done,
                "phases": phases,
                "category": None,
                "meta_plan": None,
                "sub_plans": None,
                "landing_mode": None,
                "has_report": False,
                "report_path": None,
                "report": None,
                "queue": {"column": col, "index": idx, "mode": None},
            }

            if item.is_in_flight and not item.is_completed:
                plan_obj["claim"] = {
                    "pipeline_id": item.claim_pipeline,
                    "sprint_id": None,
                    "age_seconds": elapsed - item.last_transition,
                    "started_at": (datetime.now(timezone.utc)
                                   - timedelta(seconds=elapsed - item.last_transition)
                                   ).isoformat(),
                    "pipeline_short": item.claim_pipeline[-8:],
                }

            plans_list.append(plan_obj)

        # Issues
        issues_list = []
        issue_queues = {c: [] for c in ISSUE_COLUMNS}

        for item, title in self.issues:
            if item.column is None:
                continue

            col = item.column
            idx = len(issue_queues[col])
            issue_queues[col].append(item.id_key)

            created_dt = (datetime.now(timezone.utc)
                          - timedelta(seconds=max(0, elapsed - item.arrive_at))
                          ).isoformat()

            issue_obj = {
                "number": item.id_key,
                "title": title,
                "labels": [],
                "created_at": created_dt,
                "body": "Reported by Engineering: %s" % title,
                "queue": {"column": col, "index": idx},
            }

            if item.column == "completed":
                issue_obj["closed_at"] = (
                    datetime.now(timezone.utc)
                    - timedelta(seconds=max(0, elapsed - item.last_transition))
                ).isoformat()

            if item.is_in_flight and not item.is_completed:
                issue_obj["claim"] = {
                    "pipeline_id": item.claim_pipeline,
                    "sprint_id": "demo-sprint",
                    "age_seconds": elapsed - item.last_transition,
                    "started_at": (datetime.now(timezone.utc)
                                   - timedelta(seconds=elapsed - item.last_transition)
                                   ).isoformat(),
                    "pipeline_short": item.claim_pipeline[-8:],
                }

            issues_list.append(issue_obj)

        done, total = self.progress()

        return {
            "version": "1.0",
            "updated_at": now_iso,
            "state_updated_at": now_iso,
            "repo_root": "/starship/uss-enterprise",
            "repo_url": "",
            "plans": plans_list,
            "issues": issues_list,
            "worktrees": [],
            "branches": [],
            "activity": [],
            "queues": {
                "default_mode": "phase",
                "plans": {
                    "drafted": plan_queues["drafted"],
                    "reviewed": plan_queues["reviewed"],
                    "ready": plan_queues["ready"],
                    "backlog": [],
                    "discarded": [],
                },
                "issues": {
                    "triage": issue_queues["triage"],
                    "ready": issue_queues["ready"],
                    "backlog": [],
                },
            },
            "state_file_path": "(demo mode)",
            "errors": [],
            "issues_fetch_ok": True,
            "flags": {
                "closed_issues_truncated": False,
                "closed_issues_limit": 500,
            },
            "config": {
                "dashboard_completed_days": 14,
            },
            "demo": {
                "active": True,
                "progress_done": done,
                "progress_total": total,
                "all_completed": self.all_completed(),
                "elapsed_seconds": round(elapsed, 1),
            },
        }


# ---------------------------------------------------------------------------
# Demo overlay HTML (injected into the served index.html)
# ---------------------------------------------------------------------------

DEMO_OVERLAY_JS = r"""
<script>
(function() {
  var victoryShown = false;
  var banner = document.createElement('div');
  banner.id = 'demo-banner';
  banner.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9998;'
    + 'background:linear-gradient(135deg,#1a1a2e,#16213e);color:#e0e0ff;'
    + 'text-align:center;padding:8px 16px;font-size:14px;font-family:monospace;'
    + 'border-bottom:2px solid #0f3460;';
  banner.innerHTML = '<span style="color:#e94560">&#9733;</span> '
    + '<strong>Z Skills Dashboard Demo</strong> &mdash; '
    + '<span id="demo-progress">Loading...</span> '
    + '<span style="color:#e94560">&#9733;</span>';
  document.body.prepend(banner);
  document.body.style.paddingTop = '40px';

  var overlay = document.createElement('div');
  overlay.id = 'demo-victory';
  overlay.style.cssText = 'display:none;position:fixed;inset:0;z-index:9999;'
    + 'background:rgba(10,10,30,0.92);justify-content:center;align-items:center;'
    + 'flex-direction:column;font-family:monospace;color:#e0e0ff;';
  overlay.innerHTML = '<div style="text-align:center;max-width:600px;padding:40px;">'
    + '<div style="font-size:72px;margin-bottom:20px;">&#x1F680;</div>'
    + '<h1 style="font-size:36px;color:#e94560;margin:0 0 16px;">Mission Complete</h1>'
    + '<p style="font-size:18px;line-height:1.6;color:#a0a0d0;">All 40 tasks have been '
    + 'processed through the pipeline. The starship is fully operational.</p>'
    + '<p style="font-size:14px;color:#606080;margin-top:24px;">This was a demo of the '
    + 'Z&nbsp;Skills Dashboard &mdash; an agent workflow monitor that tracks plans and '
    + 'issues as they move through triage, review, execution, and completion.</p>'
    + '<button onclick="document.getElementById(\'demo-victory\').style.display=\'none\'"'
    + ' style="margin-top:24px;padding:10px 32px;font-size:16px;cursor:pointer;'
    + 'background:#e94560;color:white;border:none;border-radius:6px;font-family:monospace;"'
    + '>Dismiss</button></div>';
  document.body.appendChild(overlay);

  var origFetch = window.fetch;
  window.fetch = function(input) {
    var url = (typeof input === 'string') ? input : (input && input.url) || '';
    var isState = url.indexOf('/api/state') !== -1;
    return origFetch.apply(this, arguments).then(function(resp) {
      if (isState) {
        var clone = resp.clone();
        clone.json().then(function(data) {
          if (data.demo) {
            var p = document.getElementById('demo-progress');
            if (p) {
              var mins = Math.floor(data.demo.elapsed_seconds / 60);
              var secs = Math.floor(data.demo.elapsed_seconds % 60);
              p.textContent = data.demo.progress_done + '/' + data.demo.progress_total
                + ' completed — ' + mins + 'm ' + secs + 's elapsed';
            }
            if (data.demo.all_completed && !victoryShown) {
              victoryShown = true;
              var v = document.getElementById('demo-victory');
              if (v) v.style.display = 'flex';
            }
          }
        }).catch(function(){});
      }
      return resp;
    });
  }.bind(window);
})();
</script>
"""


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

class DemoHandler(BaseHTTPRequestHandler):
    server_version = "zskills-demo/1.0"
    sim = None  # set by main()

    def log_message(self, fmt, *args):
        sys.stderr.write("[demo] %s - %s\n" % (
            datetime.now().strftime("%H:%M:%S"), fmt % args))

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _static(self, path, content_type):
        try:
            data = path.read_bytes()
        except FileNotFoundError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_index(self):
        index_path = STATIC_DIR / "index.html"
        try:
            html = index_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            self.send_error(404, "index.html not found in %s" % STATIC_DIR)
            return
        html = html.replace("</body>", DEMO_OVERLAY_JS + "</body>")
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/" or path == "/index.html":
            self._serve_index()
            return

        if path == "/sampler.html":
            self._static(STATIC_DIR / "sampler.html", "text/html; charset=utf-8")
            return

        if path == "/app.js":
            self._static(STATIC_DIR / "app.js", "application/javascript; charset=utf-8")
            return

        if path == "/app.css":
            self._static(STATIC_DIR / "app.css", "text/css; charset=utf-8")
            return

        if path == "/favicon.svg":
            self._static(STATIC_DIR / "favicon.svg", "image/svg+xml")
            return

        if path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return

        if path == "/api/health":
            self._json({"status": "ok"})
            return

        if path == "/api/state":
            self._json(self.sim.build_snapshot())
            return

        if path == "/api/work-state":
            self._json({"status": "idle", "current": None, "history": []})
            return

        if path.startswith("/api/plan/"):
            slug = path[len("/api/plan/"):]
            for item, title, phases in self.sim.plans:
                if item.id_key == slug:
                    self._json({
                        "slug": slug,
                        "title": title,
                        "body": "# %s\n\nStarship maintenance plan." % title,
                    })
                    return
            self.send_error(404)
            return

        if path.startswith("/api/issue/"):
            try:
                num = int(path[len("/api/issue/"):])
            except ValueError:
                self.send_error(400)
                return
            for item, title in self.sim.issues:
                if item.id_key == num:
                    self._json({
                        "number": num,
                        "title": title,
                        "body": "Reported by Engineering: %s" % title,
                        "state": "CLOSED" if item.is_completed else "OPEN",
                    })
                    return
            self.send_error(404)
            return

        self._json({"error": "not found"}, 404)

    def do_POST(self):
        # Accept POSTs to queue/trigger/reset gracefully (no-op in demo)
        content_len = int(self.headers.get("Content-Length", 0))
        if content_len:
            self.rfile.read(content_len)

        path = urlparse(self.path).path

        if path == "/api/queue":
            self._json({"ok": True, "demo": "queue changes are not persisted in demo mode"})
            return

        if path == "/api/trigger":
            self._json({"error": "trigger not available in demo mode"}, 501)
            return

        if path == "/api/work-state/reset":
            self._json({"ok": True})
            return

        self._json({"error": "not found"}, 404)


def main():
    parser = argparse.ArgumentParser(description="Z Skills Dashboard Demo")
    parser.add_argument("--port", type=int, default=9090, help="Port (default 9090)")
    parser.add_argument("--seed", type=int, default=None,
                        help="RNG seed for reproducible simulations")
    args = parser.parse_args()

    if not STATIC_DIR.is_dir():
        print("ERROR: static assets not found at %s" % STATIC_DIR, file=sys.stderr)
        print("Run from the repo root: python3 demo/demo_server.py", file=sys.stderr)
        sys.exit(1)

    sim = Simulation(seed=args.seed)
    DemoHandler.sim = sim

    HTTPServer.allow_reuse_address = True
    server = HTTPServer(("127.0.0.1", args.port), DemoHandler)
    print("Z Skills Dashboard Demo")
    print("  URL:  http://127.0.0.1:%d/" % args.port)
    print("  Seed: %s" % (args.seed if args.seed is not None else "(random)"))
    print("  Sim:  20 plans + 20 issues arriving over ~10 minutes")
    print()
    print("Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDemo server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
