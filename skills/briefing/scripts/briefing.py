#!/usr/bin/env python3
"""
briefing.py — Data-gathering helper for the /briefing skill.

Standalone Python script. No dependencies beyond the standard library.
Sole runtime as of #289 — the briefing.cjs Node fork was retired (the
portability promise it defended had already been lost to other Python-only
components; Python is required per CLAUDE.md "Python is required").

Usage:
  python3 briefing.py worktrees          — JSON worktree classification
  python3 briefing.py checkboxes         — JSON unchecked items from reports
  python3 briefing.py commits [--since=] — JSON categorized commits
  python3 briefing.py summary            — Formatted terminal output
  python3 briefing.py report [--since=]  — Combined JSON blob
  python3 briefing.py verify             — Verification status
  python3 briefing.py current            — Current session status
  python3 briefing.py worktrees-status   — Detailed worktree cleanup report
  python3 briefing.py dogfooding [--since=] [--no-gh]
                                         — Per-skill successful-usage counts
                                           (.landed source: + labeled gh backfill)
"""

import glob
import json
import math
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime

SELF = os.path.basename(sys.argv[0])

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None


# ---------------------------------------------------------------------------
# Path config (zskills-paths.sh Python mirror)
# ---------------------------------------------------------------------------


def _read_json_dict(path):
    """Load a JSON file expected to hold an object. {} on any failure."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def load_zskills_config(main_path):
    """Config cascade (INSTALL_REDESIGN Phase 5): project > user > built-ins.

    Per-key SHALLOW merge at the top level: built-in defaults loaded from
    the canonical skills/update-zskills/scripts/zskills-defaults.json
    (always LOADED, never a copied dict), overlaid by the user tier
    (~/.claude/zskills-config.json), overlaid by the project tier
    (<main_path>/.claude/zskills-config.json). `execution.*` is
    PROJECT-TIER-ONLY across the whole cascade (safety carve-out — a
    user-level file must not weaken a project's repo discipline), so the
    user tier's `execution` key is dropped before merging. Missing or
    malformed tiers contribute nothing (fail-open), matching the bash
    resolver family.

    SYNC NOTE: intentionally duplicated as `_load_zskills_config` in
    zskills-dashboard/scripts/zskills_monitor/{collect.py,server.py}
    (separate processes, no shared module) — keep the three in sync.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    defaults_path = os.path.join(
        here, '..', '..', 'update-zskills', 'scripts', 'zskills-defaults.json')
    merged = {k: v for k, v in _read_json_dict(defaults_path).items()
              if k != '_comment'}
    user = _read_json_dict(os.path.expanduser(
        os.path.join('~', '.claude', 'zskills-config.json')))
    user.pop('execution', None)
    merged.update(user)
    merged.update(_read_json_dict(
        os.path.join(main_path, '.claude', 'zskills-config.json')))
    return merged


def read_zskills_paths(main_path):
    """Resolve audit/plans/issues dirs through the Phase 5 config cascade.

    Mirrors the bash helper at
    .claude/skills/update-zskills/scripts/zskills-paths.sh.

    Use-as-is is absolute-only: only paths starting with `/` are absolute.
    All other forms (including `..foo`) are joined with main_path. Mirrors
    bash helper semantics (Locked Decision 1).

    No config at either tier -> built-in defaults (docs/plans | docs/issues
    | docs/reports via zskills-defaults.json). The leaf-level `or` literals
    below only fire for a PARTIAL output block surviving the shallow merge
    (or a missing defaults JSON) and match zskills-defaults.json output.*.
    """
    cfg = load_zskills_config(main_path)
    output = (cfg.get('output') if isinstance(cfg, dict) else None) or {}
    if not isinstance(output, dict):
        output = {}
    plans_rel = output.get('plans_dir') or 'docs/plans'
    issues_rel = output.get('issues_dir') or 'docs/issues'
    reports_rel = output.get('reports_dir') or 'docs/reports'

    def _resolve(rel):
        return rel if os.path.isabs(rel) else os.path.join(main_path, rel)

    audit_dir = os.path.join(main_path, '.zskills', 'audit')

    return {
        'plans_dir': _resolve(plans_rel),
        'issues_dir': _resolve(issues_rel),
        'audit_dir': audit_dir,
        'reports_dir': _resolve(reports_rel),
    }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def find_repo_root(start_dir=None):
    """Find the repo root (closest ancestor with .git)."""
    d = start_dir or _SCRIPT_DIR
    for _ in range(20):
        if os.path.exists(os.path.join(d, '.git')) or os.path.exists(os.path.join(d, 'package.json')):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return start_dir or _SCRIPT_DIR


def run(cmd, cwd=None, timeout=60):
    """Run a shell command and return stripped stdout, or '' on error.

    The child is started in its OWN process group (start_new_session=True →
    setsid) so a network-bound command stuck in a read (the 0-CPU-for-9-min
    hang class) can be torn down by process-GROUP kill on timeout — plain
    subprocess.run only kills the immediate child, which can leave helper
    processes alive and the call hung past the bound. On TimeoutExpired (or
    any other error) we return '' exactly as before; callers see no
    behavioral change beyond the bounded teardown.
    """
    try:
        proc = subprocess.Popen(
            cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, cwd=cwd, start_new_session=True,
        )
        try:
            stdout, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError, OSError):
                pass
            try:
                proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError, OSError):
                    pass
                try:
                    proc.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            return ''
        return stdout.strip()
    except Exception:
        return ''


# ---------------------------------------------------------------------------
# parsePeriod
# ---------------------------------------------------------------------------

def parse_period(period):
    """
    Convert shorthand period string to git --since format.
    e.g. '1h' -> '1 hour ago', '24h' -> '24 hours ago', '2d' -> '2 days ago'
    """
    if not period:
        return '24 hours ago'
    m = re.match(r'^(\d+)\s*([hd])$', str(period), re.IGNORECASE)
    if not m:
        return '24 hours ago'
    n = int(m.group(1))
    unit = m.group(2).lower()
    if unit == 'h':
        return '1 hour ago' if n == 1 else f'{n} hours ago'
    if unit == 'd':
        if n == 1:
            return '24 hours ago'
        return f'{n} days ago'
    return '24 hours ago'


# ---------------------------------------------------------------------------
# _marker_path — Phase 8 root-turd consolidation dual-read resolver
# ---------------------------------------------------------------------------

# Old root-turd filename for each consolidated marker. Writers now target
# .zskills/<name>; readers probe the new path FIRST, then fall back to the
# old root path (worktrees created before the move carry it for their whole
# lifetime). THE single dual-read definition in this module — every marker
# read below goes through it.
_MARKER_OLD_NAMES = {
    'landed': '.landed',
    'worktreepurpose': '.worktreepurpose',
    'tracked': '.zskills-tracked',
}


def _marker_path(root, name):
    """Resolve a consolidated worktree marker: <root>/.zskills/<name> when it
    exists, else the legacy root path (e.g. <root>/.landed). New path wins
    when both exist. Returns the new path (which may not exist) when neither
    does, so os.path.exists() checks downstream behave naturally."""
    new_path = os.path.join(root, '.zskills', name)
    if os.path.exists(new_path):
        return new_path
    old_path = os.path.join(root, _MARKER_OLD_NAMES[name])
    if os.path.exists(old_path):
        return old_path
    return new_path


# ---------------------------------------------------------------------------
# parseLanded
# ---------------------------------------------------------------------------

def parse_landed(content):
    """
    Parse a .landed file content. Handles both formats:
      - "full" format: status, date, source, phase, commits (space-separated hashes)
      - "partial" format: status, date, source, landed/skipped lists, reason
    """
    if not content:
        return {'status': 'unknown'}
    lines = content.split('\n')
    result = {'status': 'unknown'}
    current_list = None  # 'landed' | 'skipped'

    for line in lines:
        status_match = re.match(r'^status:\s*(.+)', line)
        if status_match:
            result['status'] = status_match.group(1).strip()
            current_list = None
            continue
        date_match = re.match(r'^date:\s*(.+)', line)
        if date_match:
            result['date'] = date_match.group(1).strip()
            current_list = None
            continue
        # `source:` names the skill that produced the landing (e.g.
        # fix-issues, run-plan, do). Captured for the dogfooding
        # measurement (SKILL_VERIFICATION_SMOKES Phase 4) — the strongest
        # per-skill usage signal.
        source_match = re.match(r'^source:\s*(.+)', line)
        if source_match:
            result['source'] = source_match.group(1).strip()
            current_list = None
            continue
        # `ci:` / `pr_state:` distinguish a SUCCESSFUL land from an attempt
        # in PR-mode markers (used by the dogfooding success filter).
        ci_match = re.match(r'^ci:\s*(.+)', line)
        if ci_match:
            result['ci'] = ci_match.group(1).strip()
            current_list = None
            continue
        pr_state_match = re.match(r'^pr_state:\s*(.+)', line)
        if pr_state_match:
            result['pr_state'] = pr_state_match.group(1).strip()
            current_list = None
            continue
        reason_match = re.match(r'^reason:\s*(.+)', line)
        if reason_match:
            result['reason'] = reason_match.group(1).strip()
            current_list = None
            continue
        commits_match = re.match(r'^commits:\s*(.+)', line)
        if commits_match:
            result['commits'] = commits_match.group(1).strip().split()
            current_list = None
            continue
        pr_match = re.match(r'^pr:\s*(.+)', line)
        if pr_match:
            result['pr'] = pr_match.group(1).strip()
            current_list = None
            continue
        branch_match = re.match(r'^branch:\s*(.+)', line)
        if branch_match:
            result['branch'] = branch_match.group(1).strip()
            current_list = None
            continue
        if re.match(r'^landed:\s*$', line):
            current_list = 'landed'
            if 'landed' not in result:
                result['landed'] = []
            continue
        if re.match(r'^skipped:\s*$', line):
            current_list = 'skipped'
            if 'skipped' not in result:
                result['skipped'] = []
            continue
        # Indented list items
        item_match = re.match(r'^\s+-\s+(.+)', line)
        if item_match and current_list:
            if current_list not in result:
                result[current_list] = []
            result[current_list].append(item_match.group(1).strip())
            continue
        # Non-indented non-empty line ends current list
        if line.strip() and not re.match(r'^\s', line) and current_list:
            current_list = None

    return result


# ---------------------------------------------------------------------------
# Live PR state (issue #476)
# ---------------------------------------------------------------------------

# In-process cache (per-briefing-run). Maps PR number (str) -> dict with
# keys 'state' (str) and 'mergeStateStatus' (str). A miss / gh-failure
# entry is stored as None so we don't retry within the same run.
_PR_STATE_CACHE = {}


def _pr_number_from(pr_url_or_num, branch=None):
    """Extract a PR number (str) from a URL like
    https://github.com/owner/repo/pull/123, a bare "#123" / "123", or a
    branch name (fallback: gh resolves the branch). Returns None if no
    deterministic number can be derived without an extra API round-trip.
    """
    if pr_url_or_num:
        m = re.search(r'/pull/(\d+)\b', str(pr_url_or_num))
        if m:
            return m.group(1)
        m = re.match(r'^#?(\d+)$', str(pr_url_or_num).strip())
        if m:
            return m.group(1)
    if branch:
        # Fall back to the branch name; gh accepts a branch as PR selector
        # in `gh pr view <branch>`. Cache key uses the branch so a re-query
        # for the same branch is deduped.
        return f'branch:{branch}'
    return None


def query_pr_state(pr_url_or_num, branch=None):
    """Query live PR state via `gh pr view`. Returns dict
    {'state': 'OPEN'|'CLOSED'|'MERGED', 'mergeStateStatus': '...'} or
    None if gh failed (offline, rate-limited, no such PR). Cached per
    PR number for the lifetime of the process.

    Non-fatal: any exception → None → caller falls back to .landed
    category. Briefing must keep working without network.
    """
    key = _pr_number_from(pr_url_or_num, branch=branch)
    if key is None:
        return None
    if key in _PR_STATE_CACHE:
        return _PR_STATE_CACHE[key]

    # Selector for gh pr view: prefer the numeric PR, fall back to branch.
    if key.startswith('branch:'):
        selector = key[len('branch:'):]
    else:
        selector = key

    try:
        proc = subprocess.run(
            ['gh', 'pr', 'view', selector, '--json', 'state,mergeStateStatus,number'],
            capture_output=True, text=True, timeout=15,
        )
        if proc.returncode != 0 or not proc.stdout.strip():
            _PR_STATE_CACHE[key] = None
            return None
        data = json.loads(proc.stdout)
        state = data.get('state')
        mss = data.get('mergeStateStatus')
        if not state:
            _PR_STATE_CACHE[key] = None
            return None
        result = {'state': state, 'mergeStateStatus': mss}
        _PR_STATE_CACHE[key] = result
        # Also memoize under the resolved number so a later branch->same-PR
        # lookup hits the cache.
        num = data.get('number')
        if num is not None:
            _PR_STATE_CACHE[str(num)] = result
        return result
    except (subprocess.TimeoutExpired, subprocess.SubprocessError,
            FileNotFoundError, json.JSONDecodeError, OSError):
        _PR_STATE_CACHE[key] = None
        return None


# ---------------------------------------------------------------------------
# classifyWorktrees
# ---------------------------------------------------------------------------

def classify_worktrees(repo_root=None):
    """
    Classify all worktrees into categories.
    Returns list of dicts with path, name, branch, category, isNamed, ahead, behind, etc.
    """
    repo_root = repo_root or find_repo_root()

    # Step 1: Get registered worktrees from git
    porcelain = run('git worktree list --porcelain', cwd=repo_root, timeout=60)
    registered_worktrees = parse_worktree_list(porcelain)

    # Filter out the main worktree
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    worktrees = [
        wt for wt in registered_worktrees
        if wt['path'] != main_path and not wt['bare']
    ]

    # Step 2: Detect orphaned directories
    agent_wt_dir = os.path.join(main_path, '.claude', 'worktrees')
    named_wt_dir = os.path.join(main_path, 'worktrees')
    registered_paths = set(wt['path'] for wt in registered_worktrees)

    orphaned = []
    for d in [agent_wt_dir, named_wt_dir]:
        if not os.path.exists(d):
            continue
        try:
            for entry in os.listdir(d):
                full_path = os.path.join(d, entry)
                if not os.path.isdir(full_path):
                    continue
                if full_path not in registered_paths:
                    orphaned.append({
                        'path': full_path,
                        'name': entry,
                        'branch': '',
                        'category': 'orphaned',
                        'isNamed': not entry.startswith('agent-'),
                        'ahead': 0,
                        'behind': 0,
                    })
        except Exception:
            pass

    # Step 3: Batch commit counts
    branch_refs = ' '.join(
        f'refs/heads/{wt["branch"]}'
        for wt in worktrees if wt['branch']
    )

    commit_counts = {}
    if branch_refs:
        ref_output = run(
            f"git for-each-ref --format='%(refname:short) %(ahead-behind:main)' {branch_refs}",
            cwd=main_path, timeout=30
        )
        commit_counts = parse_for_each_ref(ref_output)

    # Step 4: Classify each worktree
    now = time.time() * 1000  # epoch millis
    TWO_HOURS = 2 * 60 * 60 * 1000

    results = []
    for wt in worktrees:
        name = os.path.basename(wt['path'])
        is_named = not name.startswith('agent-')
        branch = wt['branch'] or ''
        counts = commit_counts.get(branch, {'ahead': 0, 'behind': 0})

        # Named worktrees get their own category
        if is_named:
            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': 'named',
                'isNamed': True,
                'ahead': counts['ahead'],
                'behind': counts['behind'],
            })
            continue

        # Check for the worktreepurpose marker (dual-read)
        purpose = None
        purpose_path = _marker_path(wt['path'], 'worktreepurpose')
        if os.path.exists(purpose_path):
            try:
                with open(purpose_path, 'r') as f:
                    purpose = f.read().strip()
            except Exception:
                pass

        # Check for the landed marker (dual-read)
        landed_path = _marker_path(wt['path'], 'landed')
        landed_data = None
        if os.path.exists(landed_path):
            try:
                with open(landed_path, 'r') as f:
                    content = f.read()
                landed_data = parse_landed(content)
            except Exception:
                pass

        if landed_data and landed_data.get('status') in ('full', 'landed'):
            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': 'landed-full',
                'isNamed': False,
                'ahead': counts['ahead'],
                'behind': counts['behind'],
                'landed': landed_data,
                'purpose': purpose,
            })
            continue

        if landed_data and landed_data.get('status') == 'partial':
            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': 'landed-partial',
                'isNamed': False,
                'ahead': counts['ahead'],
                'behind': counts['behind'],
                'landed': landed_data,
                'purpose': purpose,
            })
            continue

        # PR-mode landed markers: derive a base category from the marker
        # status, then validate against live GitHub state (issue #476).
        # The marker is written once at landing time and never updated;
        # MERGED / CLOSED-unmerged PRs would otherwise show stale.
        marker_pr_status = landed_data.get('status') if landed_data else None
        if marker_pr_status in ('pr-ready', 'pr-ci-failing', 'pr-failed',
                                'conflict', 'pr-state-unknown',
                                'failed', 'direct-push-failed',
                                'direct-verify-failed'):
            if marker_pr_status == 'pr-ready':
                base_category = 'landed-pr-ready'
            else:
                base_category = 'landed-pr-needs-attention'

            # Live-state validation. Falls back to marker-derived category
            # on any gh failure (offline, rate-limited, no PR record).
            live = query_pr_state(landed_data.get('pr'), branch=branch)
            category = base_category
            if live is not None:
                gh_state = live.get('state')
                if gh_state == 'MERGED':
                    # Issue #516: `gh pr view` state=MERGED is sticky after
                    # merge — it never reverts to OPEN even if the local
                    # branch gains post-merge commits. Gate on local
                    # ahead-count so the user is surfaced (not silently
                    # told SAFE TO REMOVE) when the branch has diverged.
                    if counts['ahead'] > 0:
                        category = 'landed-pr-merged-but-diverged'
                    else:
                        category = 'landed-pr-merged'
                elif gh_state == 'CLOSED':
                    category = 'landed-pr-abandoned'
                # OPEN → keep base_category (marker-derived).

            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': category,
                'isNamed': False,
                'ahead': counts['ahead'],
                'behind': counts['behind'],
                'landed': landed_data,
                'purpose': purpose,
                'liveState': live,
            })
            continue

        # No .landed (or unrecognized status) — check mtime
        mtime = get_worktree_mtime(wt['path'], name, main_path)

        if counts['ahead'] == 0:
            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': 'empty',
                'isNamed': False,
                'ahead': 0,
                'behind': counts['behind'],
                'mtime': mtime,
                'purpose': purpose,
            })
            continue

        if mtime and (now - mtime) < TWO_HOURS:
            results.append({
                'path': wt['path'],
                'name': name,
                'branch': branch,
                'category': 'possibly-active',
                'isNamed': False,
                'ahead': counts['ahead'],
                'behind': counts['behind'],
                'mtime': mtime,
                'purpose': purpose,
            })
            continue

        results.append({
            'path': wt['path'],
            'name': name,
            'branch': branch,
            'category': 'done-needs-review',
            'isNamed': False,
            'ahead': counts['ahead'],
            'behind': counts['behind'],
            'purpose': purpose,
            'mtime': mtime,
        })

    return results + orphaned


def parse_worktree_list(output):
    """Parse `git worktree list --porcelain` output."""
    if not output:
        return []
    blocks = output.split('\n\n')
    result = []
    for block in blocks:
        if not block.strip():
            continue
        lines = block.split('\n')
        entry = {'path': '', 'head': '', 'branch': '', 'bare': False}
        for line in lines:
            if line.startswith('worktree '):
                entry['path'] = line[len('worktree '):]
            elif line.startswith('HEAD '):
                entry['head'] = line[len('HEAD '):]
            elif line.startswith('branch '):
                entry['branch'] = line[len('branch '):].replace('refs/heads/', '')
            elif line == 'bare':
                entry['bare'] = True
        result.append(entry)
    return result


def parse_for_each_ref(output):
    """Parse `git for-each-ref` ahead-behind output."""
    if not output:
        return {}
    result = {}
    for line in output.split('\n'):
        if not line.strip():
            continue
        parts = line.strip().split()
        if len(parts) >= 3:
            try:
                result[parts[0]] = {
                    'ahead': int(parts[1]),
                    'behind': int(parts[2]),
                }
            except ValueError:
                result[parts[0]] = {'ahead': 0, 'behind': 0}
    return result


def get_worktree_mtime(wt_path, name, main_path):
    """
    Get the most recent modification time for a worktree.
    Strategy: match agent ID in log filenames, then fallback to .landed, then key files.
    Returns epoch millis or None.
    """
    # Extract 8-char agent ID from worktree name
    id_match = re.search(r'agent-([a-f0-9]{8})', name)
    if id_match:
        agent_id = id_match.group(1)
        logs_dir = os.path.join(main_path, '.claude', 'logs')
        if os.path.exists(logs_dir):
            try:
                log_files = [f for f in os.listdir(logs_dir) if agent_id in f]
                newest = 0
                for f in log_files:
                    try:
                        st = os.stat(os.path.join(logs_dir, f))
                        mtime_ms = st.st_mtime * 1000
                        if mtime_ms > newest:
                            newest = mtime_ms
                    except Exception:
                        pass
                if newest > 0:
                    return newest
            except Exception:
                pass

    # Fallback: check the landed marker's mtime if it exists (dual-read)
    landed_path = _marker_path(wt_path, 'landed')
    try:
        st = os.stat(landed_path)
        mtime_ms = st.st_mtime * 1000
        if mtime_ms > 0:
            return mtime_ms
    except Exception:
        pass

    # Fallback: check a few key files in the worktree root
    for candidate in ['.git', 'package.json']:
        try:
            st = os.stat(os.path.join(wt_path, candidate))
            mtime_ms = st.st_mtime * 1000
            if mtime_ms > 0:
                return mtime_ms
        except Exception:
            pass

    return None


# ---------------------------------------------------------------------------
# scanCheckboxes
# ---------------------------------------------------------------------------

def scan_checkboxes(repo_root=None):
    """Scan report files for unchecked checkboxes, excluding fenced code blocks."""
    repo_root = repo_root or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)

    files = []

    # Collect report files from the audit dir AND the reports dir
    # (resolved via zskills-config). Post-#217: work-trail reports
    # (plan-*, verify-*, SPRINT_REPORT) live under reports_dir; roll-up
    # indexes and briefing-* / FIX_REPORT files stay under audit_dir.
    # Scan both so checkbox tracking covers all report surfaces.
    paths = read_zskills_paths(main_path)
    seen = set()
    for d in (paths['audit_dir'], paths['reports_dir']):
        if not d or d in seen:
            continue
        seen.add(d)
        if os.path.exists(d):
            try:
                for f in os.listdir(d):
                    if f.endswith('.md'):
                        files.append(os.path.join(d, f))
            except Exception:
                pass

    return scan_checkboxes_in_files(files)


def scan_checkboxes_in_files(files):
    """Scan a list of files for unchecked checkboxes, tracking nearest heading."""
    results = []
    checkbox_re = re.compile(r'^\s*-\s*\[ \]\s')

    for file_path in files:
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            lines = content.split('\n')
            in_code_block = False
            last_heading = ''

            for i, line in enumerate(lines):
                if re.match(r'^```', line):
                    in_code_block = not in_code_block
                    continue
                if in_code_block:
                    continue
                # Track nearest heading for context
                heading_match = re.match(r'^#{1,6}\s+(.+)', line)
                if heading_match:
                    last_heading = re.sub(r'[*_`#]', '', heading_match.group(1)).strip()
                if checkbox_re.match(line):
                    text = re.sub(r'^\s*-\s*\[ \]\s*', '', line).strip()
                    results.append({
                        'file': file_path,
                        'line': i + 1,
                        'text': text,
                        'heading': last_heading,
                    })
        except Exception:
            pass

    return results


# ---------------------------------------------------------------------------
# scanPlans
# ---------------------------------------------------------------------------

def scan_plans(repo_root=None):
    """Scan plans/*.md for completion status and missing reports."""
    repo_root = repo_root or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    paths = read_zskills_paths(main_path)
    plans_dir = paths['plans_dir']
    # plan-{slug}.md reports moved from audit_dir to reports_dir (issue #217).
    reports_dir = paths['reports_dir']

    plan_files = sorted(glob.glob(os.path.join(plans_dir, '*.md')))
    results = []

    for plan_file in plan_files:
        try:
            with open(plan_file, 'r') as f:
                content = f.read()
        except Exception:
            continue

        lines = content.split('\n')

        # --- Extract metadata from YAML frontmatter (first 20 lines) ---
        title = ''
        issue = ''
        status = ''
        created = ''
        in_frontmatter = False
        frontmatter_ended = False

        for line in lines[:20]:
            stripped = line.strip()
            if stripped == '---' and not in_frontmatter and not frontmatter_ended:
                in_frontmatter = True
                continue
            if stripped == '---' and in_frontmatter:
                frontmatter_ended = True
                in_frontmatter = False
                continue
            if in_frontmatter:
                m = re.match(r'^(\w+):\s*(.+)', stripped)
                if m:
                    key, val = m.group(1).lower(), m.group(2).strip().strip('"').strip("'")
                    if key == 'issue':
                        issue = val
                    elif key == 'title':
                        title = val
                    elif key == 'status':
                        status = val
                    elif key == 'created':
                        created = val

        # --- Fallback: extract title/issue from first heading ---
        if not title:
            for line in lines[:5]:
                heading_match = re.match(r'^#\s+(.+)', line)
                if heading_match:
                    raw = heading_match.group(1).strip()
                    issue_match = re.search(r'\(#(\d+)\)', raw)
                    if issue_match:
                        if not issue:
                            issue = issue_match.group(1)
                        title = re.sub(r'\s*\(#\d+\)\s*', '', raw).strip()
                    else:
                        title = raw
                    break

        if not title:
            title = os.path.splitext(os.path.basename(plan_file))[0]

        # --- Scan for phase status indicators ---
        phase_statuses = []
        status_re = re.compile(r'\*\*Status:\*\*\s*(.+)', re.IGNORECASE)
        for line in lines:
            sm = status_re.search(line)
            if sm:
                phase_statuses.append(sm.group(1).strip().lower())

        all_phases_done = (
            len(phase_statuses) > 0
            and all(s == 'done' for s in phase_statuses)
        )

        # --- Check for corresponding report ---
        slug = os.path.splitext(os.path.basename(plan_file))[0]
        report_path = os.path.join(reports_dir, f'plan-{slug}.md')
        has_report = os.path.exists(report_path)

        results.append({
            'file': plan_file,
            'title': title,
            'issue': issue,
            'status': status,
            'created': created,
            'all_phases_done': all_phases_done,
            'has_report': has_report,
            'phase_count': len(phase_statuses),
        })

    return results


# ---------------------------------------------------------------------------
# parseCommits
# ---------------------------------------------------------------------------

def parse_commits(since=None, repo_root=None):
    """Parse commits on main within a given period."""
    repo_root = repo_root or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    since = since or '24 hours ago'

    output = run(
        f'git log main --since="{since}" --format="%h|%s|%aI" -n 200',
        cwd=main_path
    )

    if not output:
        return []

    type_re = re.compile(r'^(fix|feat|docs|test|chore|plan|refactor|style|perf|ci|build)(\(.+?\))?:\s*', re.IGNORECASE)

    results = []
    for line in output.split('\n'):
        if not line:
            continue
        parts = line.split('|')
        if len(parts) < 3:
            continue
        hash_val = parts[0]
        subject = '|'.join(parts[1:-1])  # rejoin if subject contains |
        date = parts[-1]

        type_match = type_re.match(subject)
        commit_type = type_match.group(1).lower() if type_match else 'other'

        results.append({
            'hash': hash_val,
            'subject': subject,
            'date': date,
            'type': commit_type,
        })

    return results


# ---------------------------------------------------------------------------
# Helpers — time formatting
# ---------------------------------------------------------------------------

def format_local(date=None):
    """
    Format a timestamp in the configured timezone (env TIMEZONE, default UTC).
    Returns e.g. "2026-03-21 10:15 EDT" or "2026-03-21 14:15 UTC".

    The tz-name suffix is derived from tzinfo.tzname(d) rather than a
    hardcoded label, so it stays truthful when TIMEZONE is reconfigured.
    """
    tz_name = os.environ.get('TIMEZONE', 'UTC')
    d = date or datetime.now()
    try:
        if ZoneInfo is not None:
            tz = ZoneInfo(tz_name)
            if date is None:
                d = datetime.now(tz)
            else:
                # If date is naive, assume UTC and convert
                if d.tzinfo is None:
                    from datetime import timezone
                    d = d.replace(tzinfo=timezone.utc).astimezone(tz)
                else:
                    d = d.astimezone(tz)
            suffix = tz.tzname(d) or tz_name
            return d.strftime('%Y-%m-%d %H:%M') + ' ' + suffix
        else:
            # Fallback: zoneinfo unavailable
            raise ImportError("no zoneinfo")
    except Exception:
        # Fallback if timezone not available
        return d.strftime('%Y-%m-%d %H:%M') + ' UTC'


def format_relative_time(ms):
    """
    Format milliseconds as relative time string.
    e.g. "12m ago", "6h ago", "3d ago"
    """
    if not ms or ms < 0:
        return 'unknown'
    minutes = math.floor(ms / 60000)
    if minutes < 60:
        return f'{minutes}m ago'
    hours = math.floor(minutes / 60)
    if hours < 48:
        return f'{hours}h ago'
    days = math.floor(hours / 24)
    return f'{days}d ago'


def get_latest_commit_subject(branch, main_path):
    """Get the latest commit subject for a worktree branch."""
    if not branch:
        return ''
    return run(f'git log {branch} -1 --format="%s"', cwd=main_path)


def get_uncommitted_counts(main_path):
    """Get uncommitted file counts on main."""
    output = run('git status -s', cwd=main_path)
    if not output:
        return {'modified': 0, 'deleted': 0, 'untracked': 0, 'total': 0}
    lines = [l for l in output.split('\n') if l]
    modified = 0
    deleted = 0
    untracked = 0
    for line in lines:
        code = line[:2]
        if code == '??':
            untracked += 1
        elif 'D' in code:
            deleted += 1
        else:
            modified += 1
    return {'modified': modified, 'deleted': deleted, 'untracked': untracked, 'total': len(lines)}


def get_stash_entries(main_path):
    """Get stash entries."""
    output = run('git stash list', cwd=main_path)
    if not output:
        return []
    return [l for l in output.split('\n') if l]


def get_worktree_commits(branch, main_path, limit=None):
    """Get commit log entries for a worktree branch (ahead of main)."""
    if not branch:
        return []
    n = f'-n {limit}' if limit else ''
    output = run(f'git log main..{branch} {n} --format="%h|%s"', cwd=main_path)
    if not output:
        return []
    results = []
    for line in output.split('\n'):
        if not line:
            continue
        idx = line.index('|') if '|' in line else -1
        if idx >= 0:
            results.append({'hash': line[:idx], 'subject': line[idx + 1:]})
    return results


# ---------------------------------------------------------------------------
# formatSummary — three-bucket triage view
# ---------------------------------------------------------------------------

def _topic_name(file_path):
    """Derive friendly topic name from filename."""
    base = os.path.splitext(os.path.basename(file_path))[0]
    base = re.sub(r'^plan-', '', base)
    base = re.sub(r'^verify-', '', base)
    base = base.replace('-', ' ')
    return re.sub(r'\b\w', lambda m: m.group(0).upper(), base)


def format_summary(worktrees, checkboxes, commits, opts=None):
    """Format the three-bucket triage summary."""
    opts = opts or {}
    lines = []
    now = opts.get('now') or time.time() * 1000
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)

    lines.append(f'BRIEFING — {format_local()}')
    lines.append('')

    # === NEEDS ATTENTION bucket (non-verification items) ===
    needs_attention = []

    # Done-needs-review worktrees
    done_review = [wt for wt in worktrees if wt['category'] == 'done-needs-review']
    for wt in done_review:
        commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
        purpose_note = f' ({wt["purpose"]})' if wt.get('purpose') else ''
        needs_attention.append(f'  ! worktree {wt["name"]} — {wt["ahead"]} {commit_word}, ready for review{purpose_note}')

    # Landed-partial worktrees
    landed_partial = [wt for wt in worktrees if wt['category'] == 'landed-partial']
    for wt in landed_partial:
        skipped_count = len(wt.get('landed', {}).get('skipped', [])) if wt.get('landed') else 0
        skip_word = 'commit' if skipped_count == 1 else 'commits'
        needs_attention.append(f'  ! worktree {wt["name"]} — {skipped_count} skipped {skip_word}')

    # PR-mode needs-attention worktrees
    pr_needs_attention = [wt for wt in worktrees if wt['category'] == 'landed-pr-needs-attention']
    for wt in pr_needs_attention:
        status = wt.get('landed', {}).get('status', 'unknown') if wt.get('landed') else 'unknown'
        pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
        pr_note = f' — PR: {pr_url}' if pr_url else ''
        needs_attention.append(f'  ! worktree {wt["name"]} — status: {status}{pr_note}')

    # PR closed without merge — recover work before removing (issue #476)
    pr_abandoned = [wt for wt in worktrees if wt['category'] == 'landed-pr-abandoned']
    for wt in pr_abandoned:
        pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
        pr_note = f' — PR: {pr_url}' if pr_url else ''
        needs_attention.append(f'  ! worktree {wt["name"]} — PR closed unmerged{pr_note}')

    # PR merged but branch has commits not on main — silent-commit-loss hazard (issue #516)
    pr_merged_but_diverged = [wt for wt in worktrees if wt['category'] == 'landed-pr-merged-but-diverged']
    for wt in pr_merged_but_diverged:
        ahead = wt.get('ahead', 0)
        commit_word = 'commit' if ahead == 1 else 'commits'
        pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
        pr_note = f' — PR: {pr_url}' if pr_url else ''
        needs_attention.append(f'  ! worktree {wt["name"]} — PR merged but {ahead} {commit_word} ahead of main{pr_note}')

    # Uncommitted changes on main
    uncommitted = opts.get('uncommitted')
    if uncommitted is None:
        uncommitted = get_uncommitted_counts(main_path)
    if uncommitted['total'] > 0:
        file_word = 'file' if uncommitted['total'] == 1 else 'files'
        needs_attention.append(f'  ! {uncommitted["total"]} uncommitted {file_word} on main')

    if needs_attention:
        lines.append(f'NEEDS ATTENTION ({len(needs_attention)})')
        lines.extend(needs_attention)
        lines.append('')

    # === VERIFICATION section ===
    # Filter out VERIFICATION_REPORT
    source_checkboxes = [cb for cb in checkboxes if not os.path.basename(cb['file']).startswith('VERIFICATION')]
    if source_checkboxes:
        cb_by_file = {}
        for cb in source_checkboxes:
            rel = os.path.relpath(cb['file'], main_path) if cb['file'].startswith(main_path) else os.path.basename(cb['file'])
            if rel not in cb_by_file:
                cb_by_file[rel] = []
            cb_by_file[rel].append(cb)
        file_count = len(cb_by_file)
        lines.append(f'VERIFICATION ({len(source_checkboxes)} items across {file_count} topics)')
        for file_key, items in cb_by_file.items():
            topic = _topic_name(file_key)
            lines.append(f'  {topic} ({len(items)}) — {file_key}')
            for cb in items:
                is_generic = bool(re.match(r'^\*?\*?Sign off\*?\*?', cb['text'])) or len(cb['text']) < 10
                label = cb['heading'] if (is_generic and cb.get('heading')) else cb['text']
                lines.append(f'    [ ] {label}')
        lines.append('')

    # === LANDED SINCE LAST bucket ===
    if commits:
        since_label = (opts.get('since') or '24h').upper()
        lines.append(f'LANDED SINCE LAST {since_label} ({len(commits)})')
        # Group by type
        by_type = {}
        for c in commits:
            by_type.setdefault(c['type'], []).append(c)
        shown = 0
        MAX_SHOWN = 10
        for type_name, items in by_type.items():
            for c in items:
                if shown < MAX_SHOWN:
                    stripped = re.sub(r'^[a-z]+(\(.+?\))?:\s*', '', c['subject'], flags=re.IGNORECASE)
                    lines.append(f'  {type_name}: {c["hash"]} {stripped}')
                    shown += 1
        if len(commits) > MAX_SHOWN:
            lines.append(f'  ... ({len(commits) - MAX_SHOWN} more)')
        lines.append('')

    # === IN FLIGHT bucket ===
    in_flight = []
    possibly_active = [wt for wt in worktrees if wt['category'] == 'possibly-active']
    for wt in possibly_active:
        commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
        age = format_relative_time(now - wt['mtime']) if wt.get('mtime') else 'unknown'
        in_flight.append(f'  ~ {wt["name"]} — {wt["ahead"]} {commit_word}, modified {age}')

    # Stash entries
    stash_entries = opts.get('stash')
    if stash_entries is None:
        stash_entries = get_stash_entries(main_path)
    if stash_entries:
        entry_word = 'entry' if len(stash_entries) == 1 else 'entries'
        in_flight.append(f'  ~ {len(stash_entries)} stash {entry_word}')

    if in_flight:
        lines.append(f'IN FLIGHT ({len(in_flight)})')
        lines.extend(in_flight)
        lines.append('')

    # === WORKTREES summary ===
    wt_counts = {}
    for wt in worktrees:
        wt_counts[wt['category']] = wt_counts.get(wt['category'], 0) + 1
    total = len(worktrees)
    if total > 0:
        parts = []
        if wt_counts.get('done-needs-review'):
            parts.append(f'{wt_counts["done-needs-review"]} need review')
        if wt_counts.get('possibly-active'):
            parts.append(f'{wt_counts["possibly-active"]} active')
        if wt_counts.get('landed-full'):
            parts.append(f'{wt_counts["landed-full"]} landed')
        if wt_counts.get('landed-pr-ready'):
            parts.append(f'{wt_counts["landed-pr-ready"]} pr-ready')
        if wt_counts.get('landed-pr-needs-attention'):
            parts.append(f'{wt_counts["landed-pr-needs-attention"]} pr-needs-attention')
        if wt_counts.get('landed-pr-merged'):
            parts.append(f'{wt_counts["landed-pr-merged"]} pr-merged')
        if wt_counts.get('landed-pr-merged-but-diverged'):
            parts.append(f'{wt_counts["landed-pr-merged-but-diverged"]} pr-merged-but-diverged')
        if wt_counts.get('landed-pr-abandoned'):
            parts.append(f'{wt_counts["landed-pr-abandoned"]} pr-abandoned')
        if wt_counts.get('landed-partial'):
            parts.append(f'{wt_counts["landed-partial"]} landed-partial')
        if wt_counts.get('empty'):
            parts.append(f'{wt_counts["empty"]} empty')
        if wt_counts.get('named'):
            parts.append(f'{wt_counts["named"]} named')
        if wt_counts.get('orphaned'):
            parts.append(f'{wt_counts["orphaned"]} orphaned')
        lines.append(f'WORKTREES ({total}: {", ".join(parts)})')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# formatReport — write a markdown report file
# ---------------------------------------------------------------------------

def generate_report_path(audit_dir, date=None):
    """Generate a briefing-{date}.md file path, handling duplicates with -N suffix.

    Writes under audit_dir (briefing files stay in audit_dir per issue #217 triage).
    """
    d = date or datetime.now()
    et_str = format_local(d)
    match = re.search(r'(\d{4}-\d{2}-\d{2})\s+(\d{2}):(\d{2})', et_str)
    if match:
        date_str = match.group(1)
        time_str = match.group(2) + match.group(3)
    else:
        date_str = d.strftime('%Y-%m-%d')
        time_str = d.strftime('%H%M')
    base = f'briefing-{date_str}-{time_str}'
    candidate = os.path.join(audit_dir, f'{base}.md')
    if not os.path.exists(candidate):
        return candidate
    for i in range(2, 100):
        candidate = os.path.join(audit_dir, f'{base}-{i}.md')
        if not os.path.exists(candidate):
            return candidate
    return candidate


def format_report(worktrees, checkboxes, commits, opts=None):
    """Format the full markdown report."""
    opts = opts or {}
    lines = []
    et_now = format_local()
    since = opts.get('since') or '24 hours ago'
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)

    lines.append(f'# Briefing Report — {et_now}')
    lines.append(f'Period: {since} -> now')
    lines.append('')

    # Summary counts
    need_review = len([wt for wt in worktrees if wt['category'] == 'done-needs-review'])
    in_flight_count = len([wt for wt in worktrees if wt['category'] == 'possibly-active'])
    landed_count = len([wt for wt in worktrees if wt['category'] in ('landed-full', 'landed-partial', 'landed-pr-ready', 'landed-pr-merged')])
    unchecked_count = len(checkboxes)
    cb_files = set(cb['file'] for cb in checkboxes)

    lines.append('## Summary')
    lines.append(f'- {len(commits)} commits landed on main')
    lines.append(f'- {len(worktrees)} worktrees: {need_review} need review, {in_flight_count} in flight, {landed_count} landed')
    lines.append(f'- {unchecked_count} unchecked sign-off items across {len(cb_files)} reports')
    lines.append('')

    # Needs Attention
    done_review = [wt for wt in worktrees if wt['category'] == 'done-needs-review']
    landed_partial = [wt for wt in worktrees if wt['category'] == 'landed-partial']
    pr_needs_attention = [wt for wt in worktrees if wt['category'] == 'landed-pr-needs-attention']
    # Issue #516: PR=MERGED but branch ahead of main — silent-commit-loss
    # hazard that the section is specifically meant to flag.
    landed_diverged = [wt for wt in worktrees if wt['category'] == 'landed-pr-merged-but-diverged']
    if done_review or landed_partial or pr_needs_attention or landed_diverged or checkboxes:
        lines.append('## Needs Attention')
        lines.append('')

        for wt in done_review:
            commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
            lines.append(f'### [ ] Review: {wt["name"]} ({wt["ahead"]} {commit_word})')
            wt_commits = get_worktree_commits(wt['branch'], main_path, 10)
            if wt_commits:
                lines.append('Commits:')
                for c in wt_commits:
                    lines.append(f'- `{c["hash"]}` {c["subject"]}')
            if wt.get('mtime'):
                lines.append(f'Last modified: {format_relative_time(time.time() * 1000 - wt["mtime"])}')
            lines.append('')

        # Checkbox sign-offs grouped by file
        cb_by_file = {}
        for cb in checkboxes:
            rel = os.path.relpath(cb['file'], main_path) if cb['file'].startswith(main_path) else os.path.basename(cb['file'])
            if rel not in cb_by_file:
                cb_by_file[rel] = []
            cb_by_file[rel].append(cb)
        for file_key, items in cb_by_file.items():
            lines.append(f'### [ ] Sign-off: {file_key} ({len(items)} unchecked items)')
            for cb in items:
                lines.append(f'- [ ] {cb["text"]} (line {cb["line"]})')
            lines.append('')

        # Partial landings
        for wt in landed_partial:
            skipped = wt.get('landed', {}).get('skipped', []) if wt.get('landed') else []
            lines.append(f'### [ ] Partial: {wt["name"]} ({len(skipped)} skipped)')
            for s in skipped:
                lines.append(f'- Skipped: {s}')
            lines.append('')

        # PR-mode needs-attention
        for wt in pr_needs_attention:
            status = wt.get('landed', {}).get('status', 'unknown') if wt.get('landed') else 'unknown'
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f' — PR: {pr_url}' if pr_url else ''
            lines.append(f'### [ ] PR attention: {wt["name"]} (status: {status}{pr_note})')
            lines.append('')

        # PR merged but local branch ahead of main — investigate before
        # removing the worktree (issue #516).
        for wt in landed_diverged:
            ahead = wt.get('ahead', 0)
            commit_word = 'commit' if ahead == 1 else 'commits'
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f' — PR: {pr_url}' if pr_url else ''
            lines.append(f'### [ ] Investigate: {wt["name"]} (PR merged but {ahead} {commit_word} ahead of main{pr_note})')
            lines.append('')

    # Landed on Main
    if commits:
        lines.append('## Landed on Main')
        lines.append('| Type | Hash | Subject | Date |')
        lines.append('|------|------|---------|------|')
        for c in commits:
            lines.append(f'| {c["type"]} | {c["hash"]} | {c["subject"]} | {c["date"]} |')
        lines.append('')

    # Worktree Status
    lines.append('## Worktree Status')
    lines.append('| Worktree | Category | Commits | Last Modified | Notes |')
    lines.append('|----------|----------|---------|---------------|-------|')
    for wt in worktrees:
        age = format_relative_time(time.time() * 1000 - wt['mtime']) if wt.get('mtime') else '-'
        notes = f'status: {wt["landed"]["status"]}' if wt.get('landed') else ''
        lines.append(f'| {wt["name"]} | {wt["category"]} | {wt.get("ahead", 0)} | {age} | {notes} |')
    lines.append('')

    # In Progress
    possibly_active = [wt for wt in worktrees if wt['category'] == 'possibly-active']
    if possibly_active:
        lines.append('## In Progress')
        lines.append('| Worktree | Commits | Last Modified | Summary |')
        lines.append('|----------|---------|---------------|---------|')
        for wt in possibly_active:
            age = format_relative_time(time.time() * 1000 - wt['mtime']) if wt.get('mtime') else '-'
            latest_subject = get_latest_commit_subject(wt['branch'], main_path)
            lines.append(f'| {wt["name"]} | {wt.get("ahead", 0)} | {age} | {latest_subject} |')
        lines.append('')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# formatVerify — aggregate sign-off items
# ---------------------------------------------------------------------------

def format_verify(worktrees, checkboxes, opts=None):
    """Format the verification view."""
    opts = opts or {}
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    lines = []
    has_content = False

    # Unmerged worktrees
    unmerged = [wt for wt in worktrees if wt['category'] == 'done-needs-review']
    if unmerged:
        has_content = True
        lines.append(f'UNMERGED WORKTREES ({len(unmerged)} — review and land)')
        for wt in unmerged:
            commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
            purpose_note = f' — {wt["purpose"]}' if wt.get('purpose') else ''
            lines.append(f'  {wt["name"]} ({wt["ahead"]} {commit_word}){purpose_note}')
            if not opts.get('skipGit'):
                wt_commits = get_worktree_commits(wt['branch'], main_path, 5)
                for c in wt_commits:
                    lines.append(f'    {c["hash"]} {c["subject"]}')
        lines.append('')

    # Report sign-offs — grouped by topic with verification context
    source_checkboxes = [cb for cb in checkboxes if not os.path.basename(cb['file']).startswith('VERIFICATION')]
    if source_checkboxes:
        has_content = True
        cb_by_file = {}
        for cb in source_checkboxes:
            rel = os.path.relpath(cb['file'], main_path) if cb['file'].startswith(main_path) else os.path.basename(cb['file'])
            if rel not in cb_by_file:
                cb_by_file[rel] = []
            cb_by_file[rel].append(cb)

        item_count = len(source_checkboxes)
        file_count = len(cb_by_file)
        lines.append(f'SIGN-OFF NEEDED ({item_count} items across {file_count} topics)')
        lines.append('')

        for file_key, items in cb_by_file.items():
            topic = _topic_name(file_key)

            # Get last commit date for this report file
            commit_date = ''
            if not opts.get('skipGit'):
                log_out = run(f'git log -1 --format="%ar" -- {file_key}', cwd=main_path)
                if log_out:
                    commit_date = f' (updated {log_out})'

            lines.append(f'  {topic}{commit_date}')
            lines.append(f'  {file_key}')
            lines.append('')

            for cb in items:
                is_generic = bool(re.match(r'^\*?\*?Sign off\*?\*?', cb['text'])) or len(cb['text']) < 10
                label = cb['heading'] if (is_generic and cb.get('heading')) else cb['text']
                lines.append(f'    [ ] {label}')
            lines.append('')

    # Partial landings
    partial = [wt for wt in worktrees if wt['category'] == 'landed-partial']
    if partial:
        has_content = True
        lines.append(f'PARTIAL LANDINGS ({len(partial)} — review skipped commits)')
        for wt in partial:
            lines.append(f'  {wt["name"]}')
            skipped = wt.get('landed', {}).get('skipped', []) if wt.get('landed') else []
            for s in skipped:
                lines.append(f'    Skipped: {s}')
        lines.append('')

    # PR-mode needs attention
    pr_attention = [wt for wt in worktrees if wt['category'] == 'landed-pr-needs-attention']
    if pr_attention:
        has_content = True
        lines.append(f'PR NEEDS ATTENTION ({len(pr_attention)} — inspect and resolve)')
        for wt in pr_attention:
            status = wt.get('landed', {}).get('status', 'unknown') if wt.get('landed') else 'unknown'
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f' — {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]} (status: {status}{pr_note})')
        lines.append('')

    # PR closed without merge — recover work before removing (issue #476)
    pr_abandoned = [wt for wt in worktrees if wt['category'] == 'landed-pr-abandoned']
    if pr_abandoned:
        has_content = True
        lines.append(f'PR CLOSED UNMERGED ({len(pr_abandoned)} — recover work before removing)')
        for wt in pr_abandoned:
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f' — {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]}{pr_note}')
        lines.append('')

    if not has_content:
        return 'ALL CLEAR — no pending items.'

    return 'VERIFICATION NEEDED\n\n' + '\n'.join(lines)


# ---------------------------------------------------------------------------
# formatCurrent — show what's in flight right now
# ---------------------------------------------------------------------------

def format_current(worktrees, opts=None):
    """Format the current-in-flight view."""
    opts = opts or {}
    now = opts.get('now') or time.time() * 1000
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    lines = []

    lines.append(f'CURRENTLY IN FLIGHT — {format_local()}')
    lines.append('')

    # Possibly active (modified < 2h ago)
    possibly_active = [wt for wt in worktrees if wt['category'] == 'possibly-active']
    if possibly_active:
        lines.append('POSSIBLY ACTIVE (modified < 2h ago)')
        for wt in possibly_active:
            commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
            age = format_relative_time(now - wt['mtime']) if wt.get('mtime') else 'unknown'
            lines.append(f'  {wt["name"]}  {wt["ahead"]} {commit_word}  {age}')
        lines.append('')

    # Finished, not landed
    finished = [wt for wt in worktrees if wt['category'] == 'done-needs-review']
    if finished:
        lines.append('FINISHED, NOT LANDED (modified > 2h ago)')
        for wt in finished:
            commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
            age = format_relative_time(now - wt['mtime']) if wt.get('mtime') else 'unknown'
            lines.append(f'  {wt["name"]}  {wt["ahead"]} {commit_word}  {age}')
        lines.append('')

    # PR-ready worktrees (worktree safe to remove; open PR)
    pr_ready = [wt for wt in worktrees if wt['category'] == 'landed-pr-ready']
    if pr_ready:
        lines.append(f'PR OPEN — WORKTREE SAFE TO REMOVE ({len(pr_ready)})')
        for wt in pr_ready:
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f'  PR: {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]}{pr_note}')
        lines.append('')

    # PR-mode needs attention
    pr_attention = [wt for wt in worktrees if wt['category'] == 'landed-pr-needs-attention']
    if pr_attention:
        lines.append(f'PR NEEDS ATTENTION ({len(pr_attention)})')
        for wt in pr_attention:
            status = wt.get('landed', {}).get('status', 'unknown') if wt.get('landed') else 'unknown'
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f'  PR: {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]}  status: {status}{pr_note}')
        lines.append('')

    # PR merged (live state confirmed) — safe to remove (issue #476)
    pr_merged = [wt for wt in worktrees if wt['category'] == 'landed-pr-merged']
    if pr_merged:
        lines.append(f'PR MERGED — WORKTREE SAFE TO REMOVE ({len(pr_merged)})')
        for wt in pr_merged:
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f'  PR: {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]}{pr_note}')
        lines.append('')

    # PR abandoned (closed without merge) — recover work before removing (issue #476)
    pr_abandoned = [wt for wt in worktrees if wt['category'] == 'landed-pr-abandoned']
    if pr_abandoned:
        lines.append(f'PR CLOSED UNMERGED — RECOVER WORK BEFORE REMOVING ({len(pr_abandoned)})')
        for wt in pr_abandoned:
            pr_url = wt.get('landed', {}).get('pr', '') if wt.get('landed') else ''
            pr_note = f'  PR: {pr_url}' if pr_url else ''
            lines.append(f'  {wt["name"]}{pr_note}')
        lines.append('')

    # Empty worktrees
    empty = [wt for wt in worktrees if wt['category'] == 'empty']
    if empty:
        names = ', '.join(wt['name'] for wt in empty)
        lines.append(f'EMPTY WORKTREES ({len(empty)} — safe to remove)')
        lines.append(f'  {names}')
        lines.append('')

    # Uncommitted on main
    uncommitted = opts.get('uncommitted')
    if uncommitted is None:
        uncommitted = get_uncommitted_counts(main_path)
    if uncommitted['total'] > 0:
        lines.append('UNCOMMITTED ON MAIN')
        parts = []
        if uncommitted['modified'] > 0:
            parts.append(f'{uncommitted["modified"]} modified')
        if uncommitted['deleted'] > 0:
            parts.append(f'{uncommitted["deleted"]} deleted')
        if uncommitted['untracked'] > 0:
            parts.append(f'{uncommitted["untracked"]} untracked')
        lines.append(f'  {", ".join(parts)}')
        lines.append('')

    # Stash
    stash_entries = opts.get('stash')
    if stash_entries is None:
        stash_entries = get_stash_entries(main_path)
    lines.append('STASH')
    if stash_entries:
        for entry in stash_entries:
            lines.append(f'  {entry}')
    else:
        lines.append('  (empty)')
    lines.append('')

    # Long-running branches (named worktrees)
    named = [wt for wt in worktrees if wt['category'] == 'named' and wt.get('ahead', 0) > 0]
    if named:
        lines.append('LONG-RUNNING BRANCHES')
        for wt in named:
            commit_word = 'commit' if wt['ahead'] == 1 else 'commits'
            lines.append(f'  {wt["name"].ljust(20)} {wt["ahead"]} {commit_word} ahead')
        lines.append('')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Staleness warnings
# ---------------------------------------------------------------------------

def check_staleness(worktrees, opts=None):
    """Check for staleness conditions and return warning strings."""
    opts = opts or {}
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    now = opts.get('now') or time.time() * 1000
    warnings = []
    SEVEN_DAYS = 7 * 24 * 60 * 60 * 1000
    FORTY_EIGHT_HOURS = 48 * 60 * 60 * 1000

    # Check for briefing reports (briefing-*.md files stay in audit_dir
    # per issue #217 triage — they're forensic, not work-trail).
    audit_dir = read_zskills_paths(main_path)['audit_dir']
    latest_briefing = None
    if os.path.exists(audit_dir):
        try:
            files = sorted(
                [f for f in os.listdir(audit_dir) if f.startswith('briefing-') and f.endswith('.md')],
                reverse=True
            )
            if files:
                try:
                    st = os.stat(os.path.join(audit_dir, files[0]))
                    latest_briefing = st.st_mtime * 1000
                except Exception:
                    pass
        except Exception:
            pass

    if latest_briefing is None:
        warnings.append('No briefing report exists yet')
    elif (now - latest_briefing) > FORTY_EIGHT_HOURS:
        age = format_relative_time(now - latest_briefing)
        warnings.append(f'Most recent briefing report is {age} old')

    # Check for stale done-needs-review worktrees
    stale_worktrees = [
        wt for wt in worktrees
        if wt['category'] == 'done-needs-review'
        and wt.get('mtime') and (now - wt['mtime']) > SEVEN_DAYS
    ]
    for wt in stale_worktrees:
        age = format_relative_time(now - wt['mtime'])
        warnings.append(f'Stale: {wt["name"]} needs review ({age} old)')

    return warnings


# ---------------------------------------------------------------------------
# Checkbox preservation
# ---------------------------------------------------------------------------

def preserve_checkboxes(report_content, audit_dir, date=None):
    """Preserve checked checkboxes from a previous same-day briefing report.

    Reads briefing-{date}*.md from audit_dir (briefing files stay in
    audit_dir per issue #217 triage — only plan-*, verify-*, SPRINT_REPORT
    moved to reports_dir).
    """
    d = date or datetime.now()
    et_str = format_local(d)
    date_match = re.search(r'(\d{4}-\d{2}-\d{2})', et_str)
    today_str = date_match.group(1) if date_match else d.strftime('%Y-%m-%d')

    if not os.path.exists(audit_dir):
        return report_content

    # Find previous same-day briefing reports
    previous_content = None
    try:
        files = sorted(
            [f for f in os.listdir(audit_dir) if f.startswith(f'briefing-{today_str}') and f.endswith('.md')],
            reverse=True
        )
        for f in files:
            try:
                with open(os.path.join(audit_dir, f), 'r') as fh:
                    previous_content = fh.read()
                break  # Use most recent
            except Exception:
                pass
    except Exception:
        return report_content

    if not previous_content:
        return report_content

    # Build set of checked items from previous report
    checked_keys = set()
    current_section = ''
    for line in previous_content.split('\n'):
        heading_match = re.match(r'^###\s+\[x\]\s+(.+)', line, re.IGNORECASE)
        if heading_match:
            current_section = heading_match.group(1).strip()
            checked_keys.add(f'heading:{current_section}')
            continue
        heading = re.match(r'^###\s+\[.\]\s+(.+)', line, re.IGNORECASE)
        if heading:
            current_section = heading.group(1).strip()
            continue
        item_match = re.match(r'^\s*-\s*\[x\]\s+(.+)', line, re.IGNORECASE)
        if item_match:
            checked_keys.add(f'item:{current_section}:{item_match.group(1).strip()}')

    if not checked_keys:
        return report_content

    # Apply checked state to new report
    new_lines = report_content.split('\n')
    new_section = ''
    for i, line in enumerate(new_lines):
        heading = re.match(r'^###\s+\[ \]\s+(.+)', line)
        if heading:
            new_section = heading.group(1).strip()
            if f'heading:{new_section}' in checked_keys:
                new_lines[i] = line.replace('### [ ]', '### [x]')
            continue
        heading_any = re.match(r'^###\s+\[.\]\s+(.+)', line)
        if heading_any:
            new_section = heading_any.group(1).strip()
            continue
        item = re.match(r'^(\s*-\s*)\[ \]\s+(.+)', line)
        if item:
            key = f'item:{new_section}:{item.group(2).strip()}'
            if key in checked_keys:
                new_lines[i] = line.replace('[ ]', '[x]', 1)

    return '\n'.join(new_lines)


# ---------------------------------------------------------------------------
# scanCheckboxesRecent
# ---------------------------------------------------------------------------

def scan_checkboxes_recent(repo_root=None, max_age=None, max_briefings=None):
    """Scan checkboxes with recency filter."""
    max_age = max_age or 30 * 24 * 60 * 60 * 1000  # 30 days
    max_briefings = max_briefings or 10
    now = time.time() * 1000
    repo_root = repo_root or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)

    files = []

    # Collect report files with mtime from BOTH the audit dir and the
    # reports dir. Post-#217 triage: briefing-* stay in audit_dir;
    # plan-*/verify-*/SPRINT_REPORT moved to reports_dir. Scan both.
    paths = read_zskills_paths(main_path)
    briefings = []
    others = []
    seen = set()
    for d in (paths['audit_dir'], paths['reports_dir']):
        if not d or d in seen:
            continue
        seen.add(d)
        if not os.path.exists(d):
            continue
        try:
            entries = [f for f in os.listdir(d) if f.endswith('.md')]
            for f in entries:
                file_path = os.path.join(d, f)
                try:
                    st = os.stat(file_path)
                    mtime_ms = st.st_mtime * 1000
                    if f.startswith('briefing-'):
                        briefings.append({'path': file_path, 'mtime': mtime_ms})
                    elif (now - mtime_ms) <= max_age:
                        others.append(file_path)
                except Exception:
                    pass
        except Exception:
            pass
    # Sort briefings by mtime descending, take top N
    briefings.sort(key=lambda b: b['mtime'], reverse=True)
    for b in briefings[:max_briefings]:
        files.append(b['path'])
    files.extend(others)

    return scan_checkboxes_in_files(files)


# ---------------------------------------------------------------------------
# formatWorktreesStatus — detailed cleanup readiness report
# ---------------------------------------------------------------------------

# GitHub squash-merge appends ` (#NNN)` to the subject on main when the PR
# lands. The worktree's pre-merge subject has no such suffix, so literal
# string equality misses every PR-mode landed commit. Strip the suffix on
# the main side before comparison. Worktree side is left literal — its
# subjects don't carry the suffix. Anchor `$` ensures only end-of-subject
# parentheticals are stripped (a middle-of-subject `(#NNN)` reference is
# preserved). See issue #474.
_PR_SUFFIX_RE = re.compile(r'\s*\(#\d+\)\s*$')


def _normalize_main_subject(subject):
    """Strip trailing PR-squash-merge ` (#NNN)` suffix from a main subject."""
    return _PR_SUFFIX_RE.sub('', subject).rstrip()


def partition_commits_by_landing(wt_commits, main_subjects):
    """Check which worktree commits exist on main by subject match.

    `main_subjects` is the set of subjects already harvested from main.
    Callers should pass a set already normalized via
    `_normalize_main_subject` (or build the set via the canonical path in
    `format_worktrees_status`, which normalizes). We also normalize
    defensively here so direct test callers don't need to remember.
    """
    normalized = {_normalize_main_subject(s) for s in main_subjects}
    landed = []
    unlanded = []
    for c in wt_commits:
        if c['subject'] in normalized:
            landed.append(c)
        else:
            unlanded.append(c)
    return {'landed': landed, 'unlanded': unlanded}


def get_unextracted_logs(wt_path):
    """Check if a worktree has unextracted .claude/logs/ files."""
    output = run('git status -s .claude/logs/', cwd=wt_path)
    if not output:
        return []
    return [line.strip() for line in output.split('\n') if line]


def format_worktrees_status(worktrees, opts=None):
    """Format detailed worktree status with cleanup readiness."""
    opts = opts or {}
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
    lines = []

    lines.append(f'WORKTREE STATUS — {format_local()}')
    lines.append('')

    # Get main commit subjects for landing detection. Normalize away the
    # GitHub squash-merge ` (#NNN)` suffix at set-construction time so the
    # downstream literal `in` check works for PR-mode landed commits
    # (issue #474).
    main_subjects = opts.get('mainSubjects')
    if main_subjects is None and not opts.get('skipGit'):
        main_log = run('git log main --format="%s"', cwd=main_path)
        main_subjects = (
            {_normalize_main_subject(s) for s in main_log.split('\n')}
            if main_log else set()
        )
    if main_subjects is None:
        main_subjects = set()
    else:
        main_subjects = {_normalize_main_subject(s) for s in main_subjects}

    # Classify worktrees into cleanup buckets
    safe_to_remove = []
    needs_log_extraction = []
    not_safe = []
    named = []
    orphaned_list = []

    for wt in worktrees:
        if wt['category'] == 'orphaned':
            orphaned_list.append({**wt, 'reason': 'not registered with git'})
            continue
        if wt['category'] == 'named':
            named.append(wt)
            continue

        # Check for unextracted logs
        unextracted_logs = [] if opts.get('skipGit') else get_unextracted_logs(wt['path'])

        if wt['category'] == 'empty':
            if unextracted_logs:
                needs_log_extraction.append({**wt, 'logs': unextracted_logs, 'reason': 'empty but has modified logs'})
            else:
                safe_to_remove.append({**wt, 'reason': '0 commits'})
            continue

        if wt['category'] == 'landed-full':
            if unextracted_logs:
                needs_log_extraction.append({**wt, 'logs': unextracted_logs, 'reason': '.landed: full, but logs not extracted'})
            else:
                safe_to_remove.append({**wt, 'reason': '.landed: full'})
            continue

        # Live PR state confirmed MERGED (issue #476) — same shape as
        # landed-full (PR is on main, worktree can go away).
        if wt['category'] == 'landed-pr-merged':
            if unextracted_logs:
                needs_log_extraction.append({**wt, 'logs': unextracted_logs, 'reason': 'PR merged, but logs not extracted'})
            else:
                safe_to_remove.append({**wt, 'reason': 'PR merged (live gh check)'})
            continue

        # Issue #516: PR=MERGED but local branch has commits not on main.
        # `gh pr view` is sticky after merge, so the live MERGED state
        # is not proof the commits are on main. Surface as NOT SAFE.
        if wt['category'] == 'landed-pr-merged-but-diverged':
            ahead = wt.get('ahead', 0)
            not_safe.append({
                **wt,
                'unlanded': [],
                'landedCount': 0,
                'reason': f'PR merged but branch has {ahead} commits not on main — investigate (issue #516)',
            })
            continue

        # For other categories, check if commits are actually on main
        wt_commits = [] if opts.get('skipGit') else get_worktree_commits(wt['branch'], main_path)
        partition = partition_commits_by_landing(wt_commits, main_subjects)
        landed_commits = partition['landed']
        unlanded_commits = partition['unlanded']

        if len(unlanded_commits) == 0 and len(wt_commits) > 0:
            if unextracted_logs:
                needs_log_extraction.append({**wt, 'logs': unextracted_logs, 'landedCount': len(landed_commits), 'reason': 'all commits on main, but logs not extracted'})
            else:
                safe_to_remove.append({**wt, 'landedCount': len(landed_commits), 'reason': f'all {len(landed_commits)} commits on main'})
        elif len(unlanded_commits) > 0:
            not_safe.append({**wt, 'unlanded': unlanded_commits, 'landedCount': len(landed_commits), 'reason': f'{len(unlanded_commits)} commits not on main'})
        else:
            safe_to_remove.append({**wt, 'reason': 'no commits found'})

    # Render sections
    if safe_to_remove:
        lines.append(f'SAFE TO REMOVE ({len(safe_to_remove)})')
        for wt in safe_to_remove:
            p = f'  [{wt["purpose"]}]' if wt.get('purpose') else ''
            lines.append(f'  {wt["name"]}  {wt.get("ahead", 0)} commits  ({wt["reason"]}){p}')
        lines.append('')
        lines.append('  Commands:')
        for wt in safe_to_remove:
            lines.append(f'    git worktree remove {wt["path"]}')
        lines.append('')

    if needs_log_extraction:
        lines.append(f'NEEDS LOG EXTRACTION FIRST ({len(needs_log_extraction)})')
        for wt in needs_log_extraction:
            p = f'  [{wt["purpose"]}]' if wt.get('purpose') else ''
            lines.append(f'  {wt["name"]}  {wt.get("ahead", 0)} commits  ({wt["reason"]}){p}')
            for log in wt.get('logs', []):
                lines.append(f'    {log}')
        lines.append('')
        lines.append('  Extract logs before removing:')
        lines.append('    cp <worktree>/.claude/logs/* .claude/logs/')
        lines.append('    git add .claude/logs/ && git commit -m "chore: extract logs"')
        lines.append('')

    if not_safe:
        lines.append(f'NOT SAFE — unlanded commits ({len(not_safe)})')
        for wt in not_safe:
            landed_note = f', {wt["landedCount"]} landed' if wt.get('landedCount', 0) > 0 else ''
            p = f'  [{wt["purpose"]}]' if wt.get('purpose') else ''
            unlanded_count = len(wt.get('unlanded', []))
            if unlanded_count == 0 and wt.get('reason'):
                # Issue #516: diverged-after-merge has no enumerated
                # unlanded commits but a meaningful reason — surface it.
                lines.append(f'  {wt["name"]}  ({wt["reason"]}){p}')
            else:
                lines.append(f'  {wt["name"]}  {unlanded_count} unlanded{landed_note}{p}')
            for c in wt.get('unlanded', [])[:5]:
                lines.append(f'    {c["hash"]} {c["subject"]}')
            if unlanded_count > 5:
                lines.append(f'    ... and {unlanded_count - 5} more')
        lines.append('')

    if named:
        lines.append(f'NAMED / LONG-RUNNING ({len(named)}) — never auto-remove')
        for wt in named:
            lines.append(f'  {wt["name"]}  {wt.get("ahead", 0)} commits ahead')
        lines.append('')

    if orphaned_list:
        lines.append(f'ORPHANED ({len(orphaned_list)}) — directory exists but not registered with git')
        for wt in orphaned_list:
            lines.append(f'  {wt["name"]}  {wt["path"]}')
        lines.append('')

    # Summary line
    total = len(worktrees)
    lines.append(f'Total: {total} worktrees — {len(safe_to_remove)} safe, {len(needs_log_extraction)} need logs, {len(not_safe)} not safe, {len(named)} named, {len(orphaned_list)} orphaned')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# dogfooding — Layer-2 per-skill usage measurement
# (SKILL_VERIFICATION_SMOKES Phase 4)
# ---------------------------------------------------------------------------
#
# MEASURE real per-skill usage from durable signals (display-first; NO hard
# CI gate). Two sources, by descending fidelity:
#   1. `.landed` markers across worktrees — the STRONGEST signal: the
#      `source:` field names the producing skill, and `status:`/`ci:`/
#      `pr_state:` distinguish a SUCCESSFUL land from a mere attempt.
#      Gitignored + lives in /tmp worktrees → a rolling on-disk window.
#   2. `gh pr list --state merged` — the durable BACKFILL beyond the on-disk
#      window, but it only names the subsystem touched (via conventional-
#      commit scope prefix), NOT the skill → a WEAKER per-skill attribution.
#      Routed through run() so a PATH-stripped / offline environment yields
#      '' rather than crashing (hermetic-without-gh contract).

# Canonical skill-name map: `source:` field variants → one skill name.
# Variants arise because callers stamp scoped sources (fix-issues-sprint,
# fix-issues-pr-mode-NNN). Exact keys take precedence; prefix rules below
# catch the parameterized variants.
_DOGFOOD_SOURCE_CANON = {
    'fix-issues': 'fix-issues',
    'fix-issues-sprint': 'fix-issues',
    'fix-issues-pr-mode': 'fix-issues',
    'run-plan': 'run-plan',
    'draft-plan': 'draft-plan',
    'do': 'do',
    'commit': 'commit',
    'land-pr': 'land-pr',
    'fix-report': 'fix-report',
}

# Ordered (prefix, canonical) rules for parameterized variants like
# `fix-issues-pr-mode-481` or `run-plan.SOME_PLAN`. Longest prefixes first
# so `fix-issues-pr-mode-*` wins over `fix-issues-*`.
_DOGFOOD_SOURCE_PREFIXES = [
    ('fix-issues-pr-mode', 'fix-issues'),
    ('fix-issues-sprint', 'fix-issues'),
    ('fix-issues', 'fix-issues'),
    ('run-plan', 'run-plan'),
    ('draft-plan', 'draft-plan'),
    ('fix-report', 'fix-report'),
    ('land-pr', 'land-pr'),
    ('commit', 'commit'),
    ('do', 'do'),
]


def canonicalize_source(source):
    """Map a `.landed` `source:` value (or a variant) to a canonical skill
    name. Returns the canonicalized name, or the cleaned raw token when no
    rule matches (so unknown sources still aggregate honestly under their
    own bucket rather than vanishing).
    """
    if not source:
        return None
    s = source.strip()
    if not s:
        return None
    # Strip a trailing dotted/parametric suffix down to its leading token
    # for exact-map lookup (e.g. "run-plan.MY_PLAN" → leading "run-plan").
    lead = re.split(r'[.\s]', s, 1)[0]
    if s in _DOGFOOD_SOURCE_CANON:
        return _DOGFOOD_SOURCE_CANON[s]
    if lead in _DOGFOOD_SOURCE_CANON:
        return _DOGFOOD_SOURCE_CANON[lead]
    for prefix, canon in _DOGFOOD_SOURCE_PREFIXES:
        if s == prefix or s.startswith(prefix + '-') or s.startswith(prefix + '.'):
            return canon
    return lead


def _landed_is_successful(landed):
    """A land counts as SUCCESSFUL when status is landed/full, OR a PR-mode
    marker whose pr_state is MERGED or ci is pass. Attempts (pr-failed,
    conflict, direct-*-failed, etc.) do NOT count.
    """
    if not landed:
        return False
    status = (landed.get('status') or '').strip()
    if status in ('landed', 'full'):
        return True
    pr_state = (landed.get('pr_state') or '').strip().upper()
    ci = (landed.get('ci') or '').strip().lower()
    if pr_state == 'MERGED':
        return True
    if ci == 'pass':
        return True
    return False


def _scan_landed_markers(repo_root=None, search_roots=None):
    """Yield parsed `.landed` dicts. By default, enumerates every registered
    git worktree (`git worktree list --porcelain`, including the main
    worktree and named worktrees) and parses each `<wt>/.landed` directly;
    `search_roots` overrides with an explicit list of directories to scan
    for a `.landed` file (used by the test harness — no git/network).

    Issue #809: the prior default path delegated to `classify_worktrees`,
    which only populates a `landed` key for *agent-* worktrees that land in
    the landed-* categories — named worktrees and the main worktree (which
    classify_worktrees filters out entirely) carry valid `.landed` markers
    that never surfaced, so the strong per-skill `source:` signal counted 0
    in production. Enumerating worktrees and parsing `.landed` directly here
    removes that category-gated bridge. We deliberately do NOT change
    `classify_worktrees` (broad blast radius — other reporting consumes it).
    """
    results = []
    if search_roots is not None:
        roots = search_roots
    else:
        repo_root = repo_root or find_repo_root()
        porcelain = run('git worktree list --porcelain',
                        cwd=repo_root, timeout=60)
        roots = [wt['path'] for wt in parse_worktree_list(porcelain)
                 if wt.get('path') and not wt.get('bare')]
    for root in roots:
        landed_path = _marker_path(root, 'landed')
        if os.path.isfile(landed_path):
            try:
                with open(landed_path, 'r', encoding='utf-8') as f:
                    results.append(parse_landed(f.read()))
            except OSError:
                pass
    return results


# Map a conventional-commit scope prefix (the subsystem the PR touched) to
# the skill most likely responsible. This is the WEAKER gh-backfill signal —
# it attributes by subsystem, not by skill, so it is labeled as such in the
# emitted report and never overrides the .landed `source:` count.
_DOGFOOD_SCOPE_HINTS = {
    'fix-issues': 'fix-issues',
    'run-plan': 'run-plan',
    'draft-plan': 'draft-plan',
    'briefing': 'briefing',
    'commit': 'commit',
    'land-pr': 'land-pr',
    'do': 'do',
}


def _scope_from_subject(subject):
    """Extract the conventional-commit scope from a PR title, e.g.
    'fix(run-plan): ...' → 'run-plan'. Returns None when no scope present.
    """
    m = re.match(r'^[a-z]+\(([^)]+)\):', subject or '', re.IGNORECASE)
    if m:
        return m.group(1).strip().lower()
    return None


def gather_dogfooding(since=None, repo_root=None, search_roots=None,
                      enable_gh_backfill=True):
    """Aggregate per-skill SUCCESSFUL usage from .landed markers (+ labeled
    gh-merged-PR backfill). Returns a dict:
        { 'window': <since>,
          'skills': { <canonical-skill>: {
              'landed_count': int,        # successful .landed lands
              'merged_pr_count': int,     # gh-backfill (subsystem hint)
              'last_seen': <ISO date|None> } },
          'gh_backfill': 'used'|'unavailable'|'disabled' }
    """
    since_git = parse_period(since)
    skills = {}

    def _bucket(name):
        return skills.setdefault(
            name, {'landed_count': 0, 'merged_pr_count': 0, 'last_seen': None})

    # --- Source 1: .landed markers (strong signal) -------------------
    for landed in _scan_landed_markers(repo_root=repo_root,
                                       search_roots=search_roots):
        if not _landed_is_successful(landed):
            continue
        skill = canonicalize_source(landed.get('source'))
        if not skill:
            continue
        b = _bucket(skill)
        b['landed_count'] += 1
        date = landed.get('date')
        if date and (b['last_seen'] is None or date > b['last_seen']):
            b['last_seen'] = date

    # --- Source 2: gh merged-PR backfill (weak, subsystem-level) -----
    gh_backfill = 'disabled'
    if enable_gh_backfill:
        gh_backfill = 'unavailable'
        # Route through run(): catches a missing gh / offline → '' so the
        # measurement stays hermetic in PATH-stripped tests.
        out = run(
            f'gh pr list --state merged --json number,title,mergedAt '
            f'--search "merged:>={_gh_since_date(since_git)}" --limit 200',
            cwd=repo_root)
        if out:
            try:
                prs = json.loads(out)
            except (ValueError, TypeError):
                prs = []
            if prs:
                gh_backfill = 'used'
            for pr in prs:
                scope = _scope_from_subject(pr.get('title'))
                if not scope:
                    continue
                skill = _DOGFOOD_SCOPE_HINTS.get(scope)
                if not skill:
                    continue
                b = _bucket(skill)
                b['merged_pr_count'] += 1

    return {
        'window': since or '24h',
        'skills': skills,
        'gh_backfill': gh_backfill,
    }


def _gh_since_date(since_git):
    """Best-effort YYYY-MM-DD for gh's `merged:>=` search qualifier from a
    git --since string like '7 days ago'. Falls back to a wide-open '*' on
    parse failure (gh treats a bad qualifier leniently)."""
    m = re.match(r'^(\d+)\s+(hour|day)s?\s+ago$', since_git or '')
    if not m:
        # '24 hours ago' default or unparseable → 1 day back.
        days = 1
    else:
        n = int(m.group(1))
        days = max(1, n if m.group(2) == 'day' else (n + 23) // 24)
    try:
        from datetime import timedelta
        d = datetime.now() - timedelta(days=days)
        return d.strftime('%Y-%m-%d')
    except Exception:
        return '1970-01-01'


def format_dogfooding(data):
    """Render the dogfooding aggregation as a terminal section."""
    lines = []
    window = data.get('window', '24h')
    lines.append(f'DOGFOODING — per-skill successful usage ({window})')
    lines.append('')
    skills = data.get('skills', {})
    if not skills:
        lines.append('  (no successful lands recorded in window)')
    else:
        for name in sorted(skills):
            b = skills[name]
            last = b.get('last_seen') or '-'
            advisory = '  ! 0 in window' if b['landed_count'] == 0 else ''
            lines.append(
                f'  {name.ljust(16)} landed={b["landed_count"]}  '
                f'merged_pr={b["merged_pr_count"]}  last_seen={last}{advisory}')
    lines.append('')
    backfill = data.get('gh_backfill', 'disabled')
    lines.append(f'  (gh merged-PR backfill: {backfill} — subsystem-level '
                 f'hint, weaker than .landed source:)')
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    if not args:
        print(f'Usage: python3 {SELF} <worktrees|checkboxes|commits|summary|report|verify|current|worktrees-status|dogfooding> [--since=24h] [--output=path] [--no-gh]', file=sys.stderr)
        sys.exit(1)

    subcommand = args[0]
    rest = args[1:]

    # Parse --since=VALUE and --output=VALUE from args
    since = None
    output_path = None
    for arg in rest:
        since_match = re.match(r'^--since=(.+)', arg)
        if since_match:
            since = since_match.group(1)
        output_match = re.match(r'^--output=(.+)', arg)
        if output_match:
            output_path = output_match.group(1)

    since_git = parse_period(since)

    if subcommand == 'worktrees':
        result = classify_worktrees()
        print(json.dumps(result, indent=2))

    elif subcommand == 'checkboxes':
        result = scan_checkboxes()
        print(json.dumps(result, indent=2))

    elif subcommand == 'commits':
        result = parse_commits(since=since_git)
        print(json.dumps(result, indent=2))

    elif subcommand == 'summary':
        wts = classify_worktrees()
        cbs = scan_checkboxes()
        commits = parse_commits(since=since_git)
        staleness_warnings = check_staleness(wts)
        plan_findings = scan_plans()
        plan_warnings = []
        for pf in plan_findings:
            if pf['all_phases_done']:
                t = pf['title']
                if pf['status'] and pf['status'].lower() == 'active':
                    plan_warnings.append(f"Plan {t} appears complete but status is still 'active'")
                if not pf['has_report']:
                    plan_warnings.append(f'Plan {t} complete but no report in audit dir')
                if pf['issue']:
                    plan_warnings.append(f"Plan {t} complete — issue #{pf['issue']} may need closing (run /briefing verify or check manually)")
        all_warnings = staleness_warnings + plan_warnings
        output = format_summary(wts, cbs, commits, {'since': since or '24h'})
        if all_warnings:
            output += '\n\nWARNINGS\n' + '\n'.join(f'  ! {w}' for w in all_warnings)
        print(output)

    elif subcommand == 'report':
        repo_root = find_repo_root()
        main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
        # briefing-*.md files stay in audit_dir per issue #217 triage.
        audit_dir = read_zskills_paths(main_path)['audit_dir']
        wts = classify_worktrees()
        cbs = scan_checkboxes()
        commits = parse_commits(since=since_git)
        content = format_report(wts, cbs, commits, {'since': since_git})
        content = preserve_checkboxes(content, audit_dir)
        if output_path:
            file_path = output_path
            os.makedirs(os.path.dirname(file_path) or '.', exist_ok=True)
        else:
            os.makedirs(audit_dir, exist_ok=True)
            file_path = generate_report_path(audit_dir)
        with open(file_path, 'w') as f:
            f.write(content)
        print(f'Report written to: {file_path}')

    elif subcommand == 'verify':
        wts = classify_worktrees()
        cbs = scan_checkboxes()
        print(format_verify(wts, cbs))

    elif subcommand == 'current':
        wts = classify_worktrees()
        print(format_current(wts))

    elif subcommand == 'worktrees-status':
        wts = classify_worktrees()
        print(format_worktrees_status(wts))

    elif subcommand == 'dogfooding':
        # `--no-gh` disables the gh-merged-PR backfill (the .landed scan
        # still runs); useful for hermetic / offline runs.
        enable_gh = '--no-gh' not in rest
        data = gather_dogfooding(since=since, enable_gh_backfill=enable_gh)
        print(format_dogfooding(data))

    else:
        print(f'Usage: python3 {SELF} <worktrees|checkboxes|commits|summary|report|verify|current|worktrees-status|dogfooding> [--since=24h] [--output=path] [--no-gh]', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
