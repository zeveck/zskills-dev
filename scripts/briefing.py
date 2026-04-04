#!/usr/bin/env python3
"""
briefing.py — Data-gathering helper for the /briefing skill.

Standalone Python script. No dependencies beyond the standard library.
Ported from briefing.cjs (Node.js/CommonJS).

Usage:
  python3 scripts/briefing.py worktrees          — JSON worktree classification
  python3 scripts/briefing.py checkboxes         — JSON unchecked items from reports
  python3 scripts/briefing.py commits [--since=] — JSON categorized commits
  python3 scripts/briefing.py summary            — Formatted terminal output
  python3 scripts/briefing.py report [--since=]  — Combined JSON blob
  python3 scripts/briefing.py verify             — Verification status
  python3 scripts/briefing.py current            — Current session status
  python3 scripts/briefing.py worktrees-status   — Detailed worktree cleanup report
"""

import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None

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
    """Run a shell command and return stripped stdout, or '' on error."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            cwd=cwd, timeout=timeout
        )
        return result.stdout.strip()
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

        # Check for .worktreepurpose file
        purpose = None
        purpose_path = os.path.join(wt['path'], '.worktreepurpose')
        if os.path.exists(purpose_path):
            try:
                with open(purpose_path, 'r') as f:
                    purpose = f.read().strip()
            except Exception:
                pass

        # Check for .landed file
        landed_path = os.path.join(wt['path'], '.landed')
        landed_data = None
        if os.path.exists(landed_path):
            try:
                with open(landed_path, 'r') as f:
                    content = f.read()
                landed_data = parse_landed(content)
            except Exception:
                pass

        if landed_data and landed_data.get('status') == 'full':
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

        # No .landed — check mtime
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

    # Fallback: check .landed file mtime if it exists
    landed_path = os.path.join(wt_path, '.landed')
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

    # Collect report files
    reports_dir = os.path.join(main_path, 'reports')
    if os.path.exists(reports_dir):
        try:
            for f in os.listdir(reports_dir):
                if f.endswith('.md'):
                    files.append(os.path.join(reports_dir, f))
        except Exception:
            pass

    # Root-level *REPORT*.md files (exclude timestamped snapshots)
    try:
        for f in os.listdir(main_path):
            if f.endswith('.md') and re.search(r'REPORT', f, re.IGNORECASE) and not re.search(r'\d{4}-\d{2}-\d{2}', f):
                files.append(os.path.join(main_path, f))
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

def format_et(date=None):
    """
    Format a timestamp as ET timezone string.
    Returns e.g. "2026-03-21 10:15 ET"
    """
    d = date or datetime.now()
    try:
        if ZoneInfo is not None:
            tz = ZoneInfo('America/New_York')
            if date is None:
                d = datetime.now(tz)
            else:
                # If date is naive, assume UTC and convert
                if d.tzinfo is None:
                    from datetime import timezone
                    d = d.replace(tzinfo=timezone.utc).astimezone(tz)
                else:
                    d = d.astimezone(tz)
            return d.strftime('%Y-%m-%d %H:%M') + ' ET'
        else:
            # Fallback: try using dateutil
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

    lines.append(f'BRIEFING — {format_et()}')
    lines.append('')

    # Get port for localhost URLs
    port = '8080'
    try:
        port_script = os.path.join(main_path, 'scripts', 'port.js')
        if os.path.exists(port_script):
            port = run(f'node {port_script}', cwd=main_path) or '8080'
    except Exception:
        pass

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
            viewer_url = f'http://localhost:{port}/viewer/?file={file_key}'
            lines.append(f'  {topic} ({len(items)}) — {viewer_url}')
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

def generate_report_path(reports_dir, date=None):
    """Generate a report file path, handling duplicates with -N suffix."""
    d = date or datetime.now()
    et_str = format_et(d)
    match = re.search(r'(\d{4}-\d{2}-\d{2})\s+(\d{2}):(\d{2})', et_str)
    if match:
        date_str = match.group(1)
        time_str = match.group(2) + match.group(3)
    else:
        date_str = d.strftime('%Y-%m-%d')
        time_str = d.strftime('%H%M')
    base = f'briefing-{date_str}-{time_str}'
    candidate = os.path.join(reports_dir, f'{base}.md')
    if not os.path.exists(candidate):
        return candidate
    for i in range(2, 100):
        candidate = os.path.join(reports_dir, f'{base}-{i}.md')
        if not os.path.exists(candidate):
            return candidate
    return candidate


def format_report(worktrees, checkboxes, commits, opts=None):
    """Format the full markdown report."""
    opts = opts or {}
    lines = []
    et_now = format_et()
    since = opts.get('since') or '24 hours ago'
    repo_root = opts.get('repoRoot') or find_repo_root()
    main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)

    lines.append(f'# Briefing Report — {et_now}')
    lines.append(f'Period: {since} -> now')
    lines.append('')

    # Summary counts
    need_review = len([wt for wt in worktrees if wt['category'] == 'done-needs-review'])
    in_flight_count = len([wt for wt in worktrees if wt['category'] == 'possibly-active'])
    landed_count = len([wt for wt in worktrees if wt['category'] in ('landed-full', 'landed-partial')])
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
    if done_review or landed_partial or checkboxes:
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

        # Get port for localhost URL
        port = '8080'
        try:
            port_script = os.path.join(main_path, 'scripts', 'port.js')
            if os.path.exists(port_script):
                port = run(f'node {port_script}', cwd=main_path) or '8080'
        except Exception:
            pass

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

            viewer_url = f'http://localhost:{port}/viewer/?file={file_key}'
            lines.append(f'  {topic}{commit_date}')
            lines.append(f'  {viewer_url}')
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

    lines.append(f'CURRENTLY IN FLIGHT — {format_et()}')
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

    # Check for briefing reports
    reports_dir = os.path.join(main_path, 'reports')
    latest_briefing = None
    if os.path.exists(reports_dir):
        try:
            files = sorted(
                [f for f in os.listdir(reports_dir) if f.startswith('briefing-') and f.endswith('.md')],
                reverse=True
            )
            if files:
                try:
                    st = os.stat(os.path.join(reports_dir, files[0]))
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

def preserve_checkboxes(report_content, reports_dir, date=None):
    """Preserve checked checkboxes from a previous same-day report."""
    d = date or datetime.now()
    et_str = format_et(d)
    date_match = re.search(r'(\d{4}-\d{2}-\d{2})', et_str)
    today_str = date_match.group(1) if date_match else d.strftime('%Y-%m-%d')

    if not os.path.exists(reports_dir):
        return report_content

    # Find previous same-day briefing reports
    previous_content = None
    try:
        files = sorted(
            [f for f in os.listdir(reports_dir) if f.startswith(f'briefing-{today_str}') and f.endswith('.md')],
            reverse=True
        )
        for f in files:
            try:
                with open(os.path.join(reports_dir, f), 'r') as fh:
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

    # Collect report files with mtime
    reports_dir = os.path.join(main_path, 'reports')
    if os.path.exists(reports_dir):
        try:
            entries = [f for f in os.listdir(reports_dir) if f.endswith('.md')]
            briefings = []
            others = []
            for f in entries:
                file_path = os.path.join(reports_dir, f)
                try:
                    st = os.stat(file_path)
                    mtime_ms = st.st_mtime * 1000
                    if f.startswith('briefing-'):
                        briefings.append({'path': file_path, 'mtime': mtime_ms})
                    elif (now - mtime_ms) <= max_age:
                        others.append(file_path)
                except Exception:
                    pass
            # Sort briefings by mtime descending, take top N
            briefings.sort(key=lambda b: b['mtime'], reverse=True)
            for b in briefings[:max_briefings]:
                files.append(b['path'])
            files.extend(others)
        except Exception:
            pass

    # Root-level *REPORT*.md files
    try:
        for f in os.listdir(main_path):
            if f.endswith('.md') and re.search(r'REPORT', f, re.IGNORECASE) and not re.search(r'\d{4}-\d{2}-\d{2}', f):
                file_path = os.path.join(main_path, f)
                try:
                    st = os.stat(file_path)
                    mtime_ms = st.st_mtime * 1000
                    if (now - mtime_ms) <= max_age:
                        files.append(file_path)
                except Exception:
                    pass
    except Exception:
        pass

    return scan_checkboxes_in_files(files)


# ---------------------------------------------------------------------------
# formatWorktreesStatus — detailed cleanup readiness report
# ---------------------------------------------------------------------------

def partition_commits_by_landing(wt_commits, main_subjects):
    """Check which worktree commits exist on main by subject match."""
    landed = []
    unlanded = []
    for c in wt_commits:
        if c['subject'] in main_subjects:
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

    lines.append(f'WORKTREE STATUS — {format_et()}')
    lines.append('')

    # Get main commit subjects for landing detection
    main_subjects = opts.get('mainSubjects')
    if main_subjects is None and not opts.get('skipGit'):
        main_log = run('git log main --format="%s" -n 500', cwd=main_path)
        main_subjects = set(main_log.split('\n')) if main_log else set()
    if main_subjects is None:
        main_subjects = set()

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
            lines.append(f'  {wt["name"]}  {len(wt["unlanded"])} unlanded{landed_note}{p}')
            for c in wt['unlanded'][:5]:
                lines.append(f'    {c["hash"]} {c["subject"]}')
            if len(wt['unlanded']) > 5:
                lines.append(f'    ... and {len(wt["unlanded"]) - 5} more')
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
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    if not args:
        print('Usage: python3 scripts/briefing.py <worktrees|checkboxes|commits|summary|report|verify|current|worktrees-status> [--since=24h] [--output=path]', file=sys.stderr)
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
        output = format_summary(wts, cbs, commits, {'since': since or '24h'})
        if staleness_warnings:
            output += '\n\nWARNINGS\n' + '\n'.join(f'  ! {w}' for w in staleness_warnings)
        print(output)

    elif subcommand == 'report':
        repo_root = find_repo_root()
        main_path = re.sub(r'/\.claude/worktrees/[^/]+$', '', repo_root)
        reports_dir = os.path.join(main_path, 'reports')
        os.makedirs(reports_dir, exist_ok=True)
        wts = classify_worktrees()
        cbs = scan_checkboxes()
        commits = parse_commits(since=since_git)
        content = format_report(wts, cbs, commits, {'since': since_git})
        content = preserve_checkboxes(content, reports_dir)
        file_path = output_path or generate_report_path(reports_dir)
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

    else:
        print('Usage: python3 scripts/briefing.py <worktrees|checkboxes|commits|summary|report|verify|current|worktrees-status> [--since=24h] [--output=path]', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
