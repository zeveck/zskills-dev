/**
 * briefing.js — Data-gathering helper for the /briefing skill.
 *
 * Standalone CommonJS script. No dependencies beyond Node built-ins.
 * Exports core functions for unit testing; also supports CLI invocation.
 *
 * Usage:
 *   node scripts/briefing.js worktrees          — JSON worktree classification
 *   node scripts/briefing.js checkboxes         — JSON unchecked items from reports
 *   node scripts/briefing.js commits [--since=] — JSON categorized commits
 *   node scripts/briefing.js summary            — Formatted terminal output
 *   node scripts/briefing.js report [--since=]  — Combined JSON blob
 */
'use strict';

const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Find the repo root (closest ancestor with .git). */
function findRepoRoot(startDir) {
  let dir = startDir || __dirname;
  for (let i = 0; i < 20; i++) {
    if (fs.existsSync(path.join(dir, '.git')) || fs.existsSync(path.join(dir, 'package.json'))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return startDir || __dirname;
}

function run(cmd, opts = {}) {
  try {
    return execSync(cmd, { encoding: 'utf8', timeout: 60000, ...opts }).trim();
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// parsePeriod
// ---------------------------------------------------------------------------

/**
 * Convert shorthand period string to git --since format.
 * @param {string} [period] - e.g. '1h', '6h', '24h', '1d', '2d', '7d'
 * @returns {string} e.g. '1 hour ago', '24 hours ago', '7 days ago'
 */
function parsePeriod(period) {
  if (!period) return '24 hours ago';
  const m = String(period).match(/^(\d+)\s*([hd])$/i);
  if (!m) return '24 hours ago';
  const n = parseInt(m[1], 10);
  const unit = m[2].toLowerCase();
  if (unit === 'h') {
    return n === 1 ? '1 hour ago' : `${n} hours ago`;
  }
  if (unit === 'd') {
    if (n === 1) return '24 hours ago';
    return `${n} days ago`;
  }
  return '24 hours ago';
}

// ---------------------------------------------------------------------------
// parseLanded
// ---------------------------------------------------------------------------

/**
 * Parse a .landed file content. Handles both formats:
 *   - "full" format: status, date, source, phase, commits (space-separated hashes)
 *   - "partial" format: status, date, source, landed/skipped lists, reason
 * @param {string} content - file content
 * @returns {{ status: string, date?: string, reason?: string, landed?: string[], skipped?: string[] }}
 */
function parseLanded(content) {
  if (!content) return { status: 'unknown' };
  const lines = content.split('\n');
  const result = { status: 'unknown' };
  let currentList = null; // 'landed' | 'skipped'

  for (const line of lines) {
    const statusMatch = line.match(/^status:\s*(.+)/);
    if (statusMatch) {
      result.status = statusMatch[1].trim();
      currentList = null;
      continue;
    }
    const dateMatch = line.match(/^date:\s*(.+)/);
    if (dateMatch) {
      result.date = dateMatch[1].trim();
      currentList = null;
      continue;
    }
    const reasonMatch = line.match(/^reason:\s*(.+)/);
    if (reasonMatch) {
      result.reason = reasonMatch[1].trim();
      currentList = null;
      continue;
    }
    const commitsMatch = line.match(/^commits:\s*(.+)/);
    if (commitsMatch) {
      result.commits = commitsMatch[1].trim().split(/\s+/);
      currentList = null;
      continue;
    }
    if (/^landed:\s*$/.test(line)) {
      currentList = 'landed';
      result.landed = result.landed || [];
      continue;
    }
    if (/^skipped:\s*$/.test(line)) {
      currentList = 'skipped';
      result.skipped = result.skipped || [];
      continue;
    }
    // Indented list items
    const itemMatch = line.match(/^\s+-\s+(.+)/);
    if (itemMatch && currentList) {
      result[currentList] = result[currentList] || [];
      result[currentList].push(itemMatch[1].trim());
      continue;
    }
    // Non-indented non-empty line ends current list
    if (line.trim() && !line.match(/^\s/) && currentList) {
      currentList = null;
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// classifyWorktrees
// ---------------------------------------------------------------------------

/**
 * Classify all worktrees into categories.
 * @param {{ repoRoot?: string }} [opts]
 * @returns {Array<{ path: string, name: string, branch: string, category: string,
 *                    isNamed: boolean, ahead?: number, behind?: number,
 *                    landed?: object, mtime?: number }>}
 */
function classifyWorktrees(opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();

  // Step 1: Get registered worktrees from git
  const porcelain = run('git worktree list --porcelain', { cwd: repoRoot, timeout: 60000 });
  const registeredWorktrees = parseWorktreeList(porcelain);

  // Filter out the main worktree
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const worktrees = registeredWorktrees.filter(wt => {
    // Skip main worktree (the one without a worktree-* branch or the repo root itself)
    if (wt.path === mainPath) return false;
    // Also skip bare worktrees
    if (wt.bare) return false;
    return true;
  });

  // Step 2: Detect orphaned directories
  const agentWtDir = path.join(mainPath, '.claude', 'worktrees');
  const namedWtDir = path.join(mainPath, 'worktrees');
  const registeredPaths = new Set(registeredWorktrees.map(wt => wt.path));

  const orphaned = [];
  for (const dir of [agentWtDir, namedWtDir]) {
    if (!fs.existsSync(dir)) continue;
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        const fullPath = path.join(dir, entry.name);
        if (!registeredPaths.has(fullPath)) {
          orphaned.push({
            path: fullPath,
            name: entry.name,
            branch: '',
            category: 'orphaned',
            isNamed: !entry.name.startsWith('agent-'),
            ahead: 0,
            behind: 0,
          });
        }
      }
    } catch {
      // directory read failed — skip
    }
  }

  // Step 3: Batch commit counts — only for registered worktree branches
  // Collect all branch refs from registered worktrees (skip main)
  const branchRefs = worktrees
    .filter(wt => wt.branch)
    .map(wt => `refs/heads/${wt.branch}`)
    .join(' ');

  let commitCounts = {};
  if (branchRefs) {
    const refOutput = run(
      `git for-each-ref --format='%(refname:short) %(ahead-behind:main)' ${branchRefs}`,
      { cwd: mainPath, timeout: 30000 }
    );
    commitCounts = parseForEachRef(refOutput);
  }

  // Step 4: Classify each worktree
  const now = Date.now();
  const TWO_HOURS = 2 * 60 * 60 * 1000;

  const results = worktrees.map(wt => {
    const name = path.basename(wt.path);
    const isNamed = !name.startsWith('agent-');
    const branch = wt.branch || '';
    const counts = commitCounts[branch] || { ahead: 0, behind: 0 };

    // Named worktrees get their own category
    if (isNamed) {
      return {
        path: wt.path,
        name,
        branch,
        category: 'named',
        isNamed: true,
        ahead: counts.ahead,
        behind: counts.behind,
      };
    }

    // Check for .worktreepurpose file
    let purpose = null;
    const purposePath = path.join(wt.path, '.worktreepurpose');
    if (fs.existsSync(purposePath)) {
      try {
        purpose = fs.readFileSync(purposePath, 'utf8').trim();
      } catch { /* ignore */ }
    }

    // Check for .landed file
    const landedPath = path.join(wt.path, '.landed');
    let landedData = null;
    if (fs.existsSync(landedPath)) {
      try {
        const content = fs.readFileSync(landedPath, 'utf8');
        landedData = parseLanded(content);
      } catch {
        // ignore read errors
      }
    }

    if (landedData && (landedData.status === 'full' || landedData.status === 'landed')) {
      return {
        path: wt.path,
        name,
        branch,
        category: 'landed-full',
        isNamed: false,
        ahead: counts.ahead,
        behind: counts.behind,
        landed: landedData,
        purpose,
      };
    }

    if (landedData && landedData.status === 'partial') {
      return {
        path: wt.path,
        name,
        branch,
        category: 'landed-partial',
        isNamed: false,
        ahead: counts.ahead,
        behind: counts.behind,
        landed: landedData,
        purpose,
      };
    }

    if (landedData && landedData.status === 'pr-ready') {
      return {
        path: wt.path,
        name,
        branch,
        category: 'landed-pr-ready',
        isNamed: false,
        ahead: counts.ahead,
        behind: counts.behind,
        landed: landedData,
        purpose,
      };
    }

    if (landedData && ['pr-ci-failing', 'pr-failed', 'conflict'].includes(landedData.status)) {
      return {
        path: wt.path,
        name,
        branch,
        category: 'landed-pr-needs-attention',
        isNamed: false,
        ahead: counts.ahead,
        behind: counts.behind,
        landed: landedData,
        purpose,
      };
    }

    // No .landed (or unrecognized status) — check mtime
    const mtime = getWorktreeMtime(wt.path, name, mainPath);

    if (counts.ahead === 0) {
      return {
        path: wt.path,
        name,
        branch,
        category: 'empty',
        isNamed: false,
        ahead: 0,
        behind: counts.behind,
        mtime,
        purpose,
      };
    }

    if (mtime && (now - mtime) < TWO_HOURS) {
      return {
        path: wt.path,
        name,
        branch,
        category: 'possibly-active',
        isNamed: false,
        ahead: counts.ahead,
        behind: counts.behind,
        mtime,
        purpose,
      };
    }

    return {
      path: wt.path,
      name,
      branch,
      category: 'done-needs-review',
      isNamed: false,
      ahead: counts.ahead,
      behind: counts.behind,
      purpose,
      mtime,
    };
  });

  return results.concat(orphaned);
}

/**
 * Parse `git worktree list --porcelain` output.
 * @param {string} output
 * @returns {Array<{ path: string, head: string, branch: string, bare: boolean }>}
 */
function parseWorktreeList(output) {
  if (!output) return [];
  const blocks = output.split('\n\n');
  return blocks.filter(Boolean).map(block => {
    const lines = block.split('\n');
    const entry = { path: '', head: '', branch: '', bare: false };
    for (const line of lines) {
      if (line.startsWith('worktree ')) {
        entry.path = line.slice('worktree '.length);
      } else if (line.startsWith('HEAD ')) {
        entry.head = line.slice('HEAD '.length);
      } else if (line.startsWith('branch ')) {
        // branch refs/heads/worktree-agent-xxx → worktree-agent-xxx
        entry.branch = line.slice('branch '.length).replace('refs/heads/', '');
      } else if (line === 'bare') {
        entry.bare = true;
      }
    }
    return entry;
  });
}

/**
 * Parse `git for-each-ref` ahead-behind output.
 * @param {string} output - lines of "branch ahead behind"
 * @returns {Object.<string, { ahead: number, behind: number }>}
 */
function parseForEachRef(output) {
  if (!output) return {};
  const result = {};
  for (const line of output.split('\n')) {
    if (!line.trim()) continue;
    // Format: branchName ahead behind
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 3) {
      result[parts[0]] = {
        ahead: parseInt(parts[1], 10) || 0,
        behind: parseInt(parts[2], 10) || 0,
      };
    }
  }
  return result;
}

/**
 * Get the most recent modification time for a worktree.
 * Strategy: match agent ID in log filenames, then fallback to find, then HEAD date.
 * @param {string} wtPath - worktree absolute path
 * @param {string} name - worktree basename (e.g. agent-a0494e91)
 * @param {string} mainPath - main repo root
 * @returns {number|null} - epoch millis or null
 */
function getWorktreeMtime(wtPath, name, mainPath) {
  // Extract 8-char agent ID from worktree name
  const idMatch = name.match(/agent-([a-f0-9]{8})/);
  if (idMatch) {
    const agentId = idMatch[1];
    const logsDir = path.join(mainPath, '.claude', 'logs');
    if (fs.existsSync(logsDir)) {
      try {
        const logFiles = fs.readdirSync(logsDir)
          .filter(f => f.includes(agentId));
        let newest = 0;
        for (const f of logFiles) {
          try {
            const stat = fs.statSync(path.join(logsDir, f));
            if (stat.mtimeMs > newest) newest = stat.mtimeMs;
          } catch { /* skip */ }
        }
        if (newest > 0) return newest;
      } catch { /* skip */ }
    }
  }

  // Fallback: check .landed file mtime if it exists
  const landedPath = path.join(wtPath, '.landed');
  try {
    const stat = fs.statSync(landedPath);
    if (stat.mtimeMs > 0) return stat.mtimeMs;
  } catch { /* no .landed */ }

  // Fallback: check a few key files in the worktree root
  for (const candidate of ['.git', 'package.json']) {
    try {
      const stat = fs.statSync(path.join(wtPath, candidate));
      if (stat.mtimeMs > 0) return stat.mtimeMs;
    } catch { /* skip */ }
  }

  return null;
}

// ---------------------------------------------------------------------------
// scanCheckboxes
// ---------------------------------------------------------------------------

/**
 * Scan report files for unchecked checkboxes, excluding fenced code blocks.
 * @param {{ repoRoot?: string }} [opts]
 * @returns {Array<{ file: string, line: number, text: string }>}
 */
function scanCheckboxes(opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');

  const results = [];
  const files = [];

  // Collect report files
  const reportsDir = path.join(mainPath, 'reports');
  if (fs.existsSync(reportsDir)) {
    try {
      for (const f of fs.readdirSync(reportsDir)) {
        if (f.endsWith('.md')) files.push(path.join(reportsDir, f));
      }
    } catch { /* skip */ }
  }

  // Root-level *REPORT*.md files (exclude timestamped snapshots like FIX_REPORT_2026-03-17.md)
  try {
    for (const f of fs.readdirSync(mainPath)) {
      if (f.endsWith('.md') && /REPORT/i.test(f) && !/\d{4}-\d{2}-\d{2}/.test(f)) {
        files.push(path.join(mainPath, f));
      }
    }
  } catch { /* skip */ }

  return scanCheckboxesInFiles(files);
}

/**
 * Scan a list of files for unchecked checkboxes, tracking nearest heading.
 * Shared by scanCheckboxes and scanCheckboxesRecent.
 */
function scanCheckboxesInFiles(files) {
  const results = [];
  const checkboxRe = /^\s*-\s*\[ \]\s/;

  for (const filePath of files) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n');
      let inCodeBlock = false;
      let lastHeading = '';

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.match(/^```/)) {
          inCodeBlock = !inCodeBlock;
          continue;
        }
        if (inCodeBlock) continue;
        // Track nearest heading for context
        const headingMatch = line.match(/^#{1,6}\s+(.+)/);
        if (headingMatch) {
          lastHeading = headingMatch[1].replace(/[*_`#]/g, '').trim();
        }
        if (checkboxRe.test(line)) {
          results.push({
            file: filePath,
            line: i + 1,
            text: line.replace(/^\s*-\s*\[ \]\s*/, '').trim(),
            heading: lastHeading,
          });
        }
      }
    } catch { /* skip unreadable files */ }
  }

  return results;
}

// ---------------------------------------------------------------------------
// parseCommits
// ---------------------------------------------------------------------------

/**
 * Parse commits on main within a given period.
 * @param {{ since?: string, repoRoot?: string }} [opts]
 * @returns {Array<{ hash: string, subject: string, date: string, type: string }>}
 */
function parseCommits(opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const since = opts.since || '24 hours ago';

  const output = run(
    `git log main --since="${since}" --format="%h|%s|%aI" -n 200`,
    { cwd: mainPath }
  );

  if (!output) return [];

  const typeRe = /^(fix|feat|docs|test|chore|plan|refactor|style|perf|ci|build)(\(.+?\))?:\s*/i;

  return output.split('\n').filter(Boolean).map(line => {
    const parts = line.split('|');
    if (parts.length < 3) return null;
    const hash = parts[0];
    const subject = parts.slice(1, -1).join('|'); // rejoin if subject contains |
    const date = parts[parts.length - 1];

    const typeMatch = subject.match(typeRe);
    const type = typeMatch ? typeMatch[1].toLowerCase() : 'other';

    return { hash, subject, date, type };
  }).filter(Boolean);
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Helpers — time formatting
// ---------------------------------------------------------------------------

/**
 * Format a timestamp as ET timezone string.
 * @param {Date} [date] — defaults to now
 * @returns {string} e.g. "2026-03-21 10:15 ET"
 */
function formatET(date) {
  const d = date || new Date();
  try {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false,
    });
    const parts = {};
    for (const p of fmt.formatToParts(d)) parts[p.type] = p.value;
    return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute} ET`;
  } catch {
    // Fallback if Intl not available
    return d.toISOString().slice(0, 16).replace('T', ' ') + ' UTC';
  }
}

/**
 * Format milliseconds as relative time string.
 * @param {number} ms - milliseconds ago
 * @returns {string} e.g. "12m ago", "6h ago", "3d ago"
 */
function formatRelativeTime(ms) {
  if (!ms || ms < 0) return 'unknown';
  const minutes = Math.floor(ms / 60000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

/**
 * Get the latest commit subject for a worktree branch.
 * @param {string} branch
 * @param {string} mainPath
 * @returns {string}
 */
function getLatestCommitSubject(branch, mainPath) {
  if (!branch) return '';
  return run(`git log ${branch} -1 --format="%s"`, { cwd: mainPath });
}

/**
 * Get uncommitted file counts on main.
 * @param {string} mainPath
 * @returns {{ modified: number, deleted: number, untracked: number, total: number }}
 */
function getUncommittedCounts(mainPath) {
  const output = run('git status -s', { cwd: mainPath });
  if (!output) return { modified: 0, deleted: 0, untracked: 0, total: 0 };
  const lines = output.split('\n').filter(Boolean);
  let modified = 0, deleted = 0, untracked = 0;
  for (const line of lines) {
    const code = line.slice(0, 2);
    if (code === '??') untracked++;
    else if (code.includes('D')) deleted++;
    else modified++;
  }
  return { modified, deleted, untracked, total: lines.length };
}

/**
 * Get stash entries.
 * @param {string} mainPath
 * @returns {string[]}
 */
function getStashEntries(mainPath) {
  const output = run('git stash list', { cwd: mainPath });
  if (!output) return [];
  return output.split('\n').filter(Boolean);
}

/**
 * Get commit log entries for a worktree branch (ahead of main).
 * @param {string} branch
 * @param {string} mainPath
 * @param {number} [limit]
 * @returns {Array<{ hash: string, subject: string }>}
 */
function getWorktreeCommits(branch, mainPath, limit) {
  if (!branch) return [];
  const n = limit ? `-n ${limit}` : '';
  const output = run(`git log main..${branch} ${n} --format="%h|%s"`, { cwd: mainPath });
  if (!output) return [];
  return output.split('\n').filter(Boolean).map(line => {
    const idx = line.indexOf('|');
    return { hash: line.slice(0, idx), subject: line.slice(idx + 1) };
  });
}

// ---------------------------------------------------------------------------
// formatSummary — three-bucket triage view
// ---------------------------------------------------------------------------

/**
 * Format the three-bucket triage summary.
 * @param {Array} worktrees - classified worktrees
 * @param {Array} checkboxes - unchecked checkbox items
 * @param {Array} commits - recent commits
 * @param {object} [opts] - options
 * @param {number} [opts.now] - current time in epoch ms
 * @param {string} [opts.repoRoot] - repo root path
 * @param {{ modified: number, deleted: number, untracked: number, total: number }} [opts.uncommitted] - pre-fetched uncommitted counts
 * @param {string[]} [opts.stash] - pre-fetched stash entries
 * @returns {string}
 */
function formatSummary(worktrees, checkboxes, commits, opts = {}) {
  const lines = [];
  const now = opts.now || Date.now();
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');

  lines.push(`BRIEFING — ${formatET()}`);
  lines.push('');

  // Get port for localhost URLs
  let port = '8080';
  try {
    const portScript = path.join(mainPath, 'scripts', 'port.js');
    if (fs.existsSync(portScript)) {
      port = run(`node ${portScript}`, { cwd: mainPath }) || '8080';
    }
  } catch { /* default 8080 */ }

  // === NEEDS ATTENTION bucket (non-verification items) ===
  const needsAttention = [];

  // Done-needs-review worktrees
  const doneReview = worktrees.filter(wt => wt.category === 'done-needs-review');
  for (const wt of doneReview) {
    const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
    const purposeNote = wt.purpose ? ` (${wt.purpose})` : '';
    needsAttention.push(`  ! worktree ${wt.name} — ${wt.ahead} ${commitWord}, ready for review${purposeNote}`);
  }

  // Landed-partial worktrees
  const landedPartial = worktrees.filter(wt => wt.category === 'landed-partial');
  for (const wt of landedPartial) {
    const skippedCount = wt.landed && wt.landed.skipped ? wt.landed.skipped.length : 0;
    const skipWord = skippedCount === 1 ? 'commit' : 'commits';
    needsAttention.push(`  ! worktree ${wt.name} — ${skippedCount} skipped ${skipWord}`);
  }

  // PR-mode needs-attention worktrees
  const prNeedsAttention = worktrees.filter(wt => wt.category === 'landed-pr-needs-attention');
  for (const wt of prNeedsAttention) {
    const status = wt.landed ? wt.landed.status : 'unknown';
    const prUrl = wt.landed ? wt.landed.pr || '' : '';
    const prNote = prUrl ? ` — PR: ${prUrl}` : '';
    needsAttention.push(`  ! worktree ${wt.name} — status: ${status}${prNote}`);
  }

  // Uncommitted changes on main
  const uncommitted = opts.uncommitted !== undefined
    ? opts.uncommitted
    : getUncommittedCounts(mainPath);
  if (uncommitted.total > 0) {
    const fileWord = uncommitted.total === 1 ? 'file' : 'files';
    needsAttention.push(`  ! ${uncommitted.total} uncommitted ${fileWord} on main`);
  }

  if (needsAttention.length > 0) {
    lines.push(`NEEDS ATTENTION (${needsAttention.length})`);
    lines.push(...needsAttention);
    lines.push('');
  }

  // === VERIFICATION section (sign-off checkboxes with viewer links) ===
  // Derive friendly topic name from filename
  const topicName = (file) => {
    const base = path.basename(file, '.md');
    return base
      .replace(/^plan-/, '').replace(/^verify-/, '')
      .replace(/-/g, ' ')
      .replace(/\b\w/g, c => c.toUpperCase());
  };

  // Filter out VERIFICATION_REPORT (index that duplicates source items)
  const sourceCheckboxes = checkboxes.filter(cb =>
    !path.basename(cb.file).startsWith('VERIFICATION')
  );
  if (sourceCheckboxes.length > 0) {
    const cbByFile = {};
    for (const cb of sourceCheckboxes) {
      const rel = path.relative(mainPath, cb.file) || path.basename(cb.file);
      if (!cbByFile[rel]) cbByFile[rel] = [];
      cbByFile[rel].push(cb);
    }
    const fileCount = Object.keys(cbByFile).length;
    lines.push(`VERIFICATION (${sourceCheckboxes.length} items across ${fileCount} topics)`);
    for (const [file, items] of Object.entries(cbByFile)) {
      const topic = topicName(file);
      const viewerUrl = `http://localhost:${port}/viewer/?file=${file}`;
      lines.push(`  ${topic} (${items.length}) — ${viewerUrl}`);
      for (const cb of items) {
        const isGeneric = /^\*?\*?Sign off\*?\*?/.test(cb.text) || cb.text.length < 10;
        const label = (isGeneric && cb.heading) ? cb.heading : cb.text;
        lines.push(`    [ ] ${label}`);
      }
    }
    lines.push('');
  }

  // === LANDED SINCE LAST bucket ===
  if (commits.length > 0) {
    const sinceLabel = (opts.since || '24h').toUpperCase();
    lines.push(`LANDED SINCE LAST ${sinceLabel} (${commits.length})`);
    // Group by type
    const byType = {};
    for (const c of commits) {
      byType[c.type] = byType[c.type] || [];
      byType[c.type].push(c);
    }
    let shown = 0;
    const MAX_SHOWN = 10;
    for (const [type, items] of Object.entries(byType)) {
      for (const c of items) {
        if (shown < MAX_SHOWN) {
          lines.push(`  ${type}: ${c.hash} ${c.subject.replace(/^[a-z]+(\(.+?\))?:\s*/i, '')}`);
          shown++;
        }
      }
    }
    if (commits.length > MAX_SHOWN) {
      lines.push(`  ... (${commits.length - MAX_SHOWN} more)`);
    }
    lines.push('');
  }

  // === IN FLIGHT bucket ===
  const inFlight = [];
  const possiblyActive = worktrees.filter(wt => wt.category === 'possibly-active');
  for (const wt of possiblyActive) {
    const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
    const age = wt.mtime ? formatRelativeTime(now - wt.mtime) : 'unknown';
    inFlight.push(`  ~ ${wt.name} — ${wt.ahead} ${commitWord}, modified ${age}`);
  }

  // Stash entries
  const stashEntries = opts.stash !== undefined ? opts.stash : getStashEntries(mainPath);
  if (stashEntries.length > 0) {
    inFlight.push(`  ~ ${stashEntries.length} stash ${stashEntries.length === 1 ? 'entry' : 'entries'}`);
  }

  if (inFlight.length > 0) {
    lines.push(`IN FLIGHT (${inFlight.length})`);
    lines.push(...inFlight);
    lines.push('');
  }

  // === WORKTREES summary ===
  const wtCounts = {};
  for (const wt of worktrees) {
    wtCounts[wt.category] = (wtCounts[wt.category] || 0) + 1;
  }
  const total = worktrees.length;
  if (total > 0) {
    const parts = [];
    if (wtCounts['done-needs-review']) parts.push(`${wtCounts['done-needs-review']} need review`);
    if (wtCounts['possibly-active']) parts.push(`${wtCounts['possibly-active']} active`);
    if (wtCounts['landed-full']) parts.push(`${wtCounts['landed-full']} landed`);
    if (wtCounts['landed-pr-ready']) parts.push(`${wtCounts['landed-pr-ready']} pr-ready`);
    if (wtCounts['landed-pr-needs-attention']) parts.push(`${wtCounts['landed-pr-needs-attention']} pr-needs-attention`);
    if (wtCounts['empty']) parts.push(`${wtCounts['empty']} empty`);
    if (wtCounts['named']) parts.push(`${wtCounts['named']} named`);
    if (wtCounts['orphaned']) parts.push(`${wtCounts['orphaned']} orphaned`);
    lines.push(`WORKTREES (${total}: ${parts.join(', ')})`);
  }

  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// formatReport — write a markdown report file
// ---------------------------------------------------------------------------

/**
 * Generate a report file path, handling duplicates with -N suffix.
 * @param {string} reportsDir
 * @param {Date} [date]
 * @returns {string}
 */
function generateReportPath(reportsDir, date) {
  const d = date || new Date();
  const etStr = formatET(d);
  // Extract date + time from ET string (e.g. "2026-03-21 10:15 ET")
  const match = etStr.match(/(\d{4}-\d{2}-\d{2})\s+(\d{2}):(\d{2})/);
  const dateStr = match ? match[1] : d.toISOString().slice(0, 10);
  const timeStr = match ? `${match[2]}${match[3]}` : d.toISOString().slice(11, 13) + d.toISOString().slice(14, 16);
  const base = `briefing-${dateStr}-${timeStr}`;
  let candidate = path.join(reportsDir, `${base}.md`);
  if (!fs.existsSync(candidate)) return candidate;
  for (let i = 2; i < 100; i++) {
    candidate = path.join(reportsDir, `${base}-${i}.md`);
    if (!fs.existsSync(candidate)) return candidate;
  }
  return candidate;
}

/**
 * Format the full markdown report.
 * @param {Array} worktrees
 * @param {Array} checkboxes
 * @param {Array} commits
 * @param {object} [opts]
 * @param {string} [opts.since] - git since string (e.g. "24 hours ago")
 * @param {string} [opts.repoRoot]
 * @returns {string}
 */
function formatReport(worktrees, checkboxes, commits, opts = {}) {
  const lines = [];
  const etNow = formatET();
  const since = opts.since || '24 hours ago';
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');

  lines.push(`# Briefing Report — ${etNow}`);
  lines.push(`Period: ${since} -> now`);
  lines.push('');

  // Summary counts
  const needReview = worktrees.filter(wt => wt.category === 'done-needs-review').length;
  const inFlightCount = worktrees.filter(wt => wt.category === 'possibly-active').length;
  const landedCount = worktrees.filter(wt => ['landed-full', 'landed-partial', 'landed-pr-ready'].includes(wt.category)).length;
  const uncheckedCount = checkboxes.length;
  const cbFiles = new Set(checkboxes.map(cb => cb.file));

  lines.push('## Summary');
  lines.push(`- ${commits.length} commits landed on main`);
  lines.push(`- ${worktrees.length} worktrees: ${needReview} need review, ${inFlightCount} in flight, ${landedCount} landed`);
  lines.push(`- ${uncheckedCount} unchecked sign-off items across ${cbFiles.size} reports`);
  lines.push('');

  // Needs Attention
  const doneReview = worktrees.filter(wt => wt.category === 'done-needs-review');
  const landedPartial = worktrees.filter(wt => wt.category === 'landed-partial');
  const prNeedsAttention = worktrees.filter(wt => wt.category === 'landed-pr-needs-attention');
  if (doneReview.length > 0 || landedPartial.length > 0 || prNeedsAttention.length > 0 || checkboxes.length > 0) {
    lines.push('## Needs Attention');
    lines.push('');

    for (const wt of doneReview) {
      const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
      lines.push(`### [ ] Review: ${wt.name} (${wt.ahead} ${commitWord})`);
      const wtCommits = getWorktreeCommits(wt.branch, mainPath, 10);
      if (wtCommits.length > 0) {
        lines.push('Commits:');
        for (const c of wtCommits) {
          lines.push(`- \`${c.hash}\` ${c.subject}`);
        }
      }
      if (wt.mtime) {
        lines.push(`Last modified: ${formatRelativeTime(Date.now() - wt.mtime)}`);
      }
      lines.push('');
    }

    // Checkbox sign-offs grouped by file
    const cbByFile = {};
    for (const cb of checkboxes) {
      const rel = path.relative(mainPath, cb.file) || path.basename(cb.file);
      if (!cbByFile[rel]) cbByFile[rel] = [];
      cbByFile[rel].push(cb);
    }
    for (const [file, items] of Object.entries(cbByFile)) {
      lines.push(`### [ ] Sign-off: ${file} (${items.length} unchecked items)`);
      for (const cb of items) {
        lines.push(`- [ ] ${cb.text} (line ${cb.line})`);
      }
      lines.push('');
    }

    // Partial landings
    for (const wt of landedPartial) {
      const skipped = wt.landed && wt.landed.skipped ? wt.landed.skipped : [];
      lines.push(`### [ ] Partial: ${wt.name} (${skipped.length} skipped)`);
      for (const s of skipped) {
        lines.push(`- Skipped: ${s}`);
      }
      lines.push('');
    }

    // PR-mode needs-attention
    for (const wt of prNeedsAttention) {
      const status = wt.landed ? wt.landed.status : 'unknown';
      const prUrl = wt.landed ? wt.landed.pr || '' : '';
      const prNote = prUrl ? ` — PR: ${prUrl}` : '';
      lines.push(`### [ ] PR attention: ${wt.name} (status: ${status}${prNote})`);
      lines.push('');
    }
  }

  // Landed on Main
  if (commits.length > 0) {
    lines.push('## Landed on Main');
    lines.push('| Type | Hash | Subject | Date |');
    lines.push('|------|------|---------|------|');
    for (const c of commits) {
      lines.push(`| ${c.type} | ${c.hash} | ${c.subject} | ${c.date} |`);
    }
    lines.push('');
  }

  // Worktree Status
  lines.push('## Worktree Status');
  lines.push('| Worktree | Category | Commits | Last Modified | Notes |');
  lines.push('|----------|----------|---------|---------------|-------|');
  for (const wt of worktrees) {
    const age = wt.mtime ? formatRelativeTime(Date.now() - wt.mtime) : '-';
    const notes = wt.landed ? `status: ${wt.landed.status}` : '';
    lines.push(`| ${wt.name} | ${wt.category} | ${wt.ahead || 0} | ${age} | ${notes} |`);
  }
  lines.push('');

  // In Progress
  const possiblyActive = worktrees.filter(wt => wt.category === 'possibly-active');
  if (possiblyActive.length > 0) {
    lines.push('## In Progress');
    lines.push('| Worktree | Commits | Last Modified | Summary |');
    lines.push('|----------|---------|---------------|---------|');
    for (const wt of possiblyActive) {
      const age = wt.mtime ? formatRelativeTime(Date.now() - wt.mtime) : '-';
      const latestSubject = getLatestCommitSubject(wt.branch, mainPath);
      lines.push(`| ${wt.name} | ${wt.ahead || 0} | ${age} | ${latestSubject} |`);
    }
    lines.push('');
  }

  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// formatVerify — aggregate sign-off items
// ---------------------------------------------------------------------------

/**
 * Format the verification view.
 * @param {Array} worktrees
 * @param {Array} checkboxes
 * @param {object} [opts]
 * @param {string} [opts.repoRoot]
 * @returns {string}
 */
function formatVerify(worktrees, checkboxes, opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const lines = [];
  let hasContent = false;

  // Unmerged worktrees
  const unmerged = worktrees.filter(wt => wt.category === 'done-needs-review');
  if (unmerged.length > 0) {
    hasContent = true;
    lines.push(`UNMERGED WORKTREES (${unmerged.length} — review and land)`);
    for (const wt of unmerged) {
      const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
      const purposeNote = wt.purpose ? ` — ${wt.purpose}` : '';
      lines.push(`  ${wt.name} (${wt.ahead} ${commitWord})${purposeNote}`);
      if (!opts.skipGit) {
        const wtCommits = getWorktreeCommits(wt.branch, mainPath, 5);
        for (const c of wtCommits) {
          lines.push(`    ${c.hash} ${c.subject}`);
        }
      }
    }
    lines.push('');
  }

  // Report sign-offs — grouped by topic with verification context
  // Filter out VERIFICATION_REPORT.md (it's an index that duplicates source items)
  const sourceCheckboxes = checkboxes.filter(cb => !path.basename(cb.file).startsWith('VERIFICATION'));
  if (sourceCheckboxes.length > 0) {
    hasContent = true;
    const cbByFile = {};
    for (const cb of sourceCheckboxes) {
      const rel = path.relative(mainPath, cb.file) || path.basename(cb.file);
      if (!cbByFile[rel]) cbByFile[rel] = [];
      cbByFile[rel].push(cb);
    }

    // Derive friendly topic names from filenames
    const topicName = (file) => {
      const base = path.basename(file, '.md');
      return base
        .replace(/^plan-/, '').replace(/^verify-/, '')
        .replace(/-/g, ' ')
        .replace(/\b\w/g, c => c.toUpperCase());
    };

    // Get port for localhost URL
    let port = '8080';
    try {
      const portScript = path.join(mainPath, 'scripts', 'port.js');
      if (fs.existsSync(portScript)) {
        port = run(`node ${portScript}`, { cwd: mainPath }) || '8080';
      }
    } catch { /* default 8080 */ }

    const itemCount = sourceCheckboxes.length;
    const fileCount = Object.keys(cbByFile).length;
    lines.push(`SIGN-OFF NEEDED (${itemCount} items across ${fileCount} topics)`);
    lines.push('');

    for (const [file, items] of Object.entries(cbByFile)) {
      const topic = topicName(file);

      // Get last commit date for this report file
      let commitDate = '';
      if (!opts.skipGit) {
        const logOut = run(`git log -1 --format="%ar" -- ${file}`, { cwd: mainPath });
        if (logOut) commitDate = ` (updated ${logOut})`;
      }

      const viewerUrl = `http://localhost:${port}/viewer/?file=${file}`;
      lines.push(`  ${topic}${commitDate}`);
      lines.push(`  ${viewerUrl}`);
      lines.push('');

      for (const cb of items) {
        const isGeneric = /^\*?\*?Sign off\*?\*?/.test(cb.text) || cb.text.length < 10;
        const label = (isGeneric && cb.heading) ? cb.heading : cb.text;
        lines.push(`    [ ] ${label}`);
      }
      lines.push('');
    }
  }

  // Partial landings
  const partial = worktrees.filter(wt => wt.category === 'landed-partial');
  if (partial.length > 0) {
    hasContent = true;
    lines.push(`PARTIAL LANDINGS (${partial.length} — review skipped commits)`);
    for (const wt of partial) {
      lines.push(`  ${wt.name}`);
      const skipped = wt.landed && wt.landed.skipped ? wt.landed.skipped : [];
      for (const s of skipped) {
        lines.push(`    Skipped: ${s}`);
      }
    }
    lines.push('');
  }

  // PR-mode needs attention
  const prAttention = worktrees.filter(wt => wt.category === 'landed-pr-needs-attention');
  if (prAttention.length > 0) {
    hasContent = true;
    lines.push(`PR NEEDS ATTENTION (${prAttention.length} — inspect and resolve)`);
    for (const wt of prAttention) {
      const status = wt.landed ? wt.landed.status : 'unknown';
      const prUrl = wt.landed ? wt.landed.pr || '' : '';
      const prNote = prUrl ? ` — ${prUrl}` : '';
      lines.push(`  ${wt.name} (status: ${status}${prNote})`);
    }
    lines.push('');
  }

  if (!hasContent) {
    return 'ALL CLEAR — no pending items.';
  }

  return 'VERIFICATION NEEDED\n\n' + lines.join('\n');
}

// ---------------------------------------------------------------------------
// formatCurrent — show what's in flight right now
// ---------------------------------------------------------------------------

/**
 * Format the current-in-flight view.
 * @param {Array} worktrees
 * @param {object} [opts]
 * @param {number} [opts.now]
 * @param {string} [opts.repoRoot]
 * @param {{ modified: number, deleted: number, untracked: number, total: number }} [opts.uncommitted]
 * @param {string[]} [opts.stash]
 * @returns {string}
 */
function formatCurrent(worktrees, opts = {}) {
  const now = opts.now || Date.now();
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const lines = [];

  lines.push(`CURRENTLY IN FLIGHT — ${formatET()}`);
  lines.push('');

  // Possibly active (modified < 2h ago)
  const possiblyActive = worktrees.filter(wt => wt.category === 'possibly-active');
  if (possiblyActive.length > 0) {
    lines.push(`POSSIBLY ACTIVE (modified < 2h ago)`);
    for (const wt of possiblyActive) {
      const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
      const age = wt.mtime ? formatRelativeTime(now - wt.mtime) : 'unknown';
      lines.push(`  ${wt.name}  ${wt.ahead} ${commitWord}  ${age}`);
    }
    lines.push('');
  }

  // Finished, not landed (modified > 2h ago, has commits)
  const finished = worktrees.filter(wt => wt.category === 'done-needs-review');
  if (finished.length > 0) {
    lines.push(`FINISHED, NOT LANDED (modified > 2h ago)`);
    for (const wt of finished) {
      const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
      const age = wt.mtime ? formatRelativeTime(now - wt.mtime) : 'unknown';
      lines.push(`  ${wt.name}  ${wt.ahead} ${commitWord}  ${age}`);
    }
    lines.push('');
  }

  // PR-ready worktrees (worktree safe to remove; open PR)
  const prReady = worktrees.filter(wt => wt.category === 'landed-pr-ready');
  if (prReady.length > 0) {
    lines.push(`PR OPEN — WORKTREE SAFE TO REMOVE (${prReady.length})`);
    for (const wt of prReady) {
      const prUrl = wt.landed ? wt.landed.pr || '' : '';
      const prNote = prUrl ? `  PR: ${prUrl}` : '';
      lines.push(`  ${wt.name}${prNote}`);
    }
    lines.push('');
  }

  // PR-mode needs attention
  const prAttention = worktrees.filter(wt => wt.category === 'landed-pr-needs-attention');
  if (prAttention.length > 0) {
    lines.push(`PR NEEDS ATTENTION (${prAttention.length})`);
    for (const wt of prAttention) {
      const status = wt.landed ? wt.landed.status : 'unknown';
      const prUrl = wt.landed ? wt.landed.pr || '' : '';
      const prNote = prUrl ? `  PR: ${prUrl}` : '';
      lines.push(`  ${wt.name}  status: ${status}${prNote}`);
    }
    lines.push('');
  }

  // Empty worktrees
  const empty = worktrees.filter(wt => wt.category === 'empty');
  if (empty.length > 0) {
    const names = empty.map(wt => wt.name).join(', ');
    lines.push(`EMPTY WORKTREES (${empty.length} — safe to remove)`);
    lines.push(`  ${names}`);
    lines.push('');
  }

  // Uncommitted on main
  const uncommitted = opts.uncommitted !== undefined
    ? opts.uncommitted
    : getUncommittedCounts(mainPath);
  if (uncommitted.total > 0) {
    lines.push('UNCOMMITTED ON MAIN');
    const parts = [];
    if (uncommitted.modified > 0) parts.push(`${uncommitted.modified} modified`);
    if (uncommitted.deleted > 0) parts.push(`${uncommitted.deleted} deleted`);
    if (uncommitted.untracked > 0) parts.push(`${uncommitted.untracked} untracked`);
    lines.push(`  ${parts.join(', ')}`);
    lines.push('');
  }

  // Stash
  const stashEntries = opts.stash !== undefined ? opts.stash : getStashEntries(mainPath);
  lines.push('STASH');
  if (stashEntries.length > 0) {
    for (const entry of stashEntries) {
      lines.push(`  ${entry}`);
    }
  } else {
    lines.push('  (empty)');
  }
  lines.push('');

  // Long-running branches (named worktrees)
  const named = worktrees.filter(wt => wt.category === 'named' && wt.ahead > 0);
  if (named.length > 0) {
    lines.push('LONG-RUNNING BRANCHES');
    for (const wt of named) {
      const commitWord = wt.ahead === 1 ? 'commit' : 'commits';
      lines.push(`  ${wt.name.padEnd(20)} ${wt.ahead} ${commitWord} ahead`);
    }
    lines.push('');
  }

  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// scanPlans — check plans/*.md for completion status and missing reports
// ---------------------------------------------------------------------------

/**
 * Scan plans/*.md for completion status and missing reports.
 * @param {string} [repoRoot]
 * @returns {Array<{file: string, title: string, issue: string, status: string, created: string, all_phases_done: boolean, has_report: boolean, phase_count: number}>}
 */
function scanPlans(repoRoot) {
  repoRoot = repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const plansDir = path.join(mainPath, 'plans');
  const reportsDir = path.join(mainPath, 'reports');

  if (!fs.existsSync(plansDir)) return [];

  let planFiles;
  try {
    planFiles = fs.readdirSync(plansDir)
      .filter(f => f.endsWith('.md'))
      .sort()
      .map(f => path.join(plansDir, f));
  } catch {
    return [];
  }

  const results = [];

  for (const planFile of planFiles) {
    let content;
    try {
      content = fs.readFileSync(planFile, 'utf8');
    } catch {
      continue;
    }

    const lines = content.split('\n');

    // --- Extract metadata from YAML frontmatter (first 20 lines) ---
    let title = '';
    let issue = '';
    let status = '';
    let created = '';
    let inFrontmatter = false;
    let frontmatterEnded = false;

    for (const line of lines.slice(0, 20)) {
      const stripped = line.trim();
      if (stripped === '---' && !inFrontmatter && !frontmatterEnded) {
        inFrontmatter = true;
        continue;
      }
      if (stripped === '---' && inFrontmatter) {
        frontmatterEnded = true;
        inFrontmatter = false;
        continue;
      }
      if (inFrontmatter) {
        const m = stripped.match(/^(\w+):\s*(.+)/);
        if (m) {
          const key = m[1].toLowerCase();
          const val = m[2].trim().replace(/^["']|["']$/g, '');
          if (key === 'issue') issue = val;
          else if (key === 'title') title = val;
          else if (key === 'status') status = val;
          else if (key === 'created') created = val;
        }
      }
    }

    // --- Fallback: extract title/issue from first heading ---
    if (!title) {
      for (const line of lines.slice(0, 5)) {
        const headingMatch = line.match(/^#\s+(.+)/);
        if (headingMatch) {
          const raw = headingMatch[1].trim();
          const issueMatch = raw.match(/\(#(\d+)\)/);
          if (issueMatch) {
            if (!issue) issue = issueMatch[1];
            title = raw.replace(/\s*\(#\d+\)\s*/g, '').trim();
          } else {
            title = raw;
          }
          break;
        }
      }
    }

    if (!title) {
      title = path.basename(planFile, '.md');
    }

    // --- Scan for phase status indicators ---
    const phaseStatuses = [];
    const statusRe = /\*\*Status:\*\*\s*(.+)/i;
    for (const line of lines) {
      const sm = statusRe.exec(line);
      if (sm) {
        phaseStatuses.push(sm[1].trim().toLowerCase());
      }
    }

    const allPhasesDone = (
      phaseStatuses.length > 0 &&
      phaseStatuses.every(s => s === 'done')
    );

    // --- Check for corresponding report ---
    const slug = path.basename(planFile, '.md');
    const reportPath = path.join(reportsDir, `plan-${slug}.md`);
    const hasReport = fs.existsSync(reportPath);

    results.push({
      file: planFile,
      title,
      issue,
      status,
      created,
      all_phases_done: allPhasesDone,
      has_report: hasReport,
      phase_count: phaseStatuses.length,
    });
  }

  return results;
}

// ---------------------------------------------------------------------------
// Staleness warnings (Phase 6)
// ---------------------------------------------------------------------------

/**
 * Check for staleness conditions and return warning strings.
 * @param {Array} worktrees
 * @param {object} [opts]
 * @param {string} [opts.repoRoot]
 * @param {number} [opts.now]
 * @returns {string[]}
 */
function checkStaleness(worktrees, opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const now = opts.now || Date.now();
  const warnings = [];
  const SEVEN_DAYS = 7 * 24 * 60 * 60 * 1000;
  const FORTY_EIGHT_HOURS = 48 * 60 * 60 * 1000;

  // Check for briefing reports
  const reportsDir = path.join(mainPath, 'reports');
  let latestBriefing = null;
  if (fs.existsSync(reportsDir)) {
    try {
      const files = fs.readdirSync(reportsDir)
        .filter(f => f.startsWith('briefing-') && f.endsWith('.md'))
        .sort()
        .reverse();
      if (files.length > 0) {
        try {
          const stat = fs.statSync(path.join(reportsDir, files[0]));
          latestBriefing = stat.mtimeMs;
        } catch { /* skip */ }
      }
    } catch { /* skip */ }
  }

  if (!latestBriefing) {
    warnings.push('No briefing report exists yet');
  } else if ((now - latestBriefing) > FORTY_EIGHT_HOURS) {
    const age = formatRelativeTime(now - latestBriefing);
    warnings.push(`Most recent briefing report is ${age} old`);
  }

  // Check for stale done-needs-review worktrees
  const staleWorktrees = worktrees.filter(wt =>
    wt.category === 'done-needs-review' &&
    wt.mtime && (now - wt.mtime) > SEVEN_DAYS
  );
  for (const wt of staleWorktrees) {
    const age = formatRelativeTime(now - wt.mtime);
    warnings.push(`Stale: ${wt.name} needs review (${age} old)`);
  }

  return warnings;
}

// ---------------------------------------------------------------------------
// Checkbox preservation (Phase 6)
// ---------------------------------------------------------------------------

/**
 * Preserve checked checkboxes from a previous same-day report.
 * @param {string} reportContent - new report markdown content
 * @param {string} reportsDir - reports directory path
 * @param {Date} [date] - current date (for same-day check)
 * @returns {string} - report content with preserved checkboxes
 */
function preserveCheckboxes(reportContent, reportsDir, date) {
  const d = date || new Date();
  const etStr = formatET(d);
  const dateMatch = etStr.match(/(\d{4}-\d{2}-\d{2})/);
  const todayStr = dateMatch ? dateMatch[1] : d.toISOString().slice(0, 10);

  if (!fs.existsSync(reportsDir)) return reportContent;

  // Find previous same-day briefing reports
  let previousContent = null;
  try {
    const files = fs.readdirSync(reportsDir)
      .filter(f => f.startsWith(`briefing-${todayStr}`) && f.endsWith('.md'))
      .sort()
      .reverse();

    for (const f of files) {
      try {
        previousContent = fs.readFileSync(path.join(reportsDir, f), 'utf8');
        break; // Use most recent
      } catch { /* skip */ }
    }
  } catch { return reportContent; }

  if (!previousContent) return reportContent;

  // Build set of checked items from previous report
  // Key format: section heading + item text (stable across regeneration)
  const checkedKeys = new Set();
  let currentSection = '';
  for (const line of previousContent.split('\n')) {
    const headingMatch = line.match(/^###\s+\[x\]\s+(.+)/i);
    if (headingMatch) {
      currentSection = headingMatch[1].trim();
      checkedKeys.add(`heading:${currentSection}`);
      continue;
    }
    const heading = line.match(/^###\s+\[.\]\s+(.+)/i);
    if (heading) {
      currentSection = heading[1].trim();
      continue;
    }
    const itemMatch = line.match(/^\s*-\s*\[x\]\s+(.+)/i);
    if (itemMatch) {
      checkedKeys.add(`item:${currentSection}:${itemMatch[1].trim()}`);
    }
  }

  if (checkedKeys.size === 0) return reportContent;

  // Apply checked state to new report
  const newLines = reportContent.split('\n');
  let newSection = '';
  for (let i = 0; i < newLines.length; i++) {
    const line = newLines[i];
    const heading = line.match(/^###\s+\[ \]\s+(.+)/);
    if (heading) {
      newSection = heading[1].trim();
      if (checkedKeys.has(`heading:${newSection}`)) {
        newLines[i] = line.replace('### [ ]', '### [x]');
      }
      continue;
    }
    const headingAny = line.match(/^###\s+\[.\]\s+(.+)/);
    if (headingAny) {
      newSection = headingAny[1].trim();
      continue;
    }
    const item = line.match(/^(\s*-\s*)\[ \]\s+(.+)/);
    if (item) {
      const key = `item:${newSection}:${item[2].trim()}`;
      if (checkedKeys.has(key)) {
        newLines[i] = line.replace('[ ]', '[x]');
      }
    }
  }

  return newLines.join('\n');
}

/**
 * Scan checkboxes with recency filter — only files modified in last 30 days
 * or top 10 most recent briefing files.
 * @param {{ repoRoot?: string, maxAge?: number, maxBriefings?: number }} [opts]
 * @returns {Array<{ file: string, line: number, text: string }>}
 */
function scanCheckboxesRecent(opts = {}) {
  const maxAge = opts.maxAge || 30 * 24 * 60 * 60 * 1000; // 30 days
  const maxBriefings = opts.maxBriefings || 10;
  const now = Date.now();
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');

  const results = [];
  const files = [];

  // Collect report files with mtime
  const reportsDir = path.join(mainPath, 'reports');
  if (fs.existsSync(reportsDir)) {
    try {
      const entries = fs.readdirSync(reportsDir).filter(f => f.endsWith('.md'));
      const briefings = [];
      const others = [];
      for (const f of entries) {
        const filePath = path.join(reportsDir, f);
        try {
          const stat = fs.statSync(filePath);
          if (f.startsWith('briefing-')) {
            briefings.push({ path: filePath, mtime: stat.mtimeMs });
          } else if ((now - stat.mtimeMs) <= maxAge) {
            others.push(filePath);
          }
        } catch { /* skip */ }
      }
      // Sort briefings by mtime descending, take top N
      briefings.sort((a, b) => b.mtime - a.mtime);
      for (const b of briefings.slice(0, maxBriefings)) {
        files.push(b.path);
      }
      files.push(...others);
    } catch { /* skip */ }
  }

  // Root-level *REPORT*.md files (always included if recent enough, exclude snapshots)
  try {
    for (const f of fs.readdirSync(mainPath)) {
      if (f.endsWith('.md') && /REPORT/i.test(f) && !/\d{4}-\d{2}-\d{2}/.test(f)) {
        const filePath = path.join(mainPath, f);
        try {
          const stat = fs.statSync(filePath);
          if ((now - stat.mtimeMs) <= maxAge) {
            files.push(filePath);
          }
        } catch { /* skip */ }
      }
    }
  } catch { /* skip */ }

  return scanCheckboxesInFiles(files);
}

// ---------------------------------------------------------------------------
// formatWorktreesStatus — detailed cleanup readiness report
// ---------------------------------------------------------------------------

/**
 * Check which worktree commits exist on main by subject match.
 * @param {Array<{ hash: string, subject: string }>} wtCommits
 * @param {Set<string>} mainSubjects - set of commit subjects on main
 * @returns {{ landed: Array, unlanded: Array }}
 */
function partitionCommitsByLanding(wtCommits, mainSubjects) {
  const landed = [];
  const unlanded = [];
  for (const c of wtCommits) {
    if (mainSubjects.has(c.subject)) {
      landed.push(c);
    } else {
      unlanded.push(c);
    }
  }
  return { landed, unlanded };
}

/**
 * Check if a worktree has unextracted .claude/logs/ files.
 * @param {string} wtPath - worktree absolute path
 * @returns {string[]} - list of modified/untracked log file names
 */
function getUnextractedLogs(wtPath) {
  const output = run('git status -s .claude/logs/', { cwd: wtPath });
  if (!output) return [];
  return output.split('\n').filter(Boolean).map(line => line.trim());
}

/**
 * Format detailed worktree status with cleanup readiness.
 * @param {Array} worktrees - classified worktrees
 * @param {object} [opts]
 * @param {Set<string>} [opts.mainSubjects] - pre-fetched main commit subjects
 * @param {boolean} [opts.skipGit] - skip git calls (for testing)
 * @returns {string}
 */
function formatWorktreesStatus(worktrees, opts = {}) {
  const repoRoot = opts.repoRoot || findRepoRoot();
  const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
  const lines = [];

  lines.push(`WORKTREE STATUS — ${formatET()}`);
  lines.push('');

  // Get main commit subjects for landing detection
  let mainSubjects = opts.mainSubjects;
  if (!mainSubjects && !opts.skipGit) {
    const mainLog = run('git log main --format="%s" -n 500', { cwd: mainPath });
    mainSubjects = new Set(mainLog ? mainLog.split('\n').filter(Boolean) : []);
  }
  mainSubjects = mainSubjects || new Set();

  // Classify worktrees into cleanup buckets
  const safeToRemove = [];   // empty or all commits on main, no unextracted logs
  const needsLogExtraction = []; // all commits on main but has unextracted logs
  const notSafe = [];        // has unlanded commits
  const named = [];          // named/long-running branches
  const orphaned = [];       // orphaned directories

  for (const wt of worktrees) {
    if (wt.category === 'orphaned') {
      orphaned.push({ ...wt, reason: 'not registered with git' });
      continue;
    }
    if (wt.category === 'named') {
      named.push(wt);
      continue;
    }

    // Check for unextracted logs
    const unextractedLogs = opts.skipGit ? [] : getUnextractedLogs(wt.path);

    if (wt.category === 'empty') {
      if (unextractedLogs.length > 0) {
        needsLogExtraction.push({ ...wt, logs: unextractedLogs, reason: 'empty but has modified logs' });
      } else {
        safeToRemove.push({ ...wt, reason: '0 commits' });
      }
      continue;
    }

    if (wt.category === 'landed-full') {
      if (unextractedLogs.length > 0) {
        needsLogExtraction.push({ ...wt, logs: unextractedLogs, reason: '.landed: full, but logs not extracted' });
      } else {
        safeToRemove.push({ ...wt, reason: `.landed: full` });
      }
      continue;
    }

    // For other categories, check if commits are actually on main
    const wtCommits = opts.skipGit ? [] : getWorktreeCommits(wt.branch, mainPath);
    const { landed, unlanded } = partitionCommitsByLanding(wtCommits, mainSubjects);

    if (unlanded.length === 0 && wtCommits.length > 0) {
      // All commits on main
      if (unextractedLogs.length > 0) {
        needsLogExtraction.push({ ...wt, logs: unextractedLogs, landedCount: landed.length, reason: 'all commits on main, but logs not extracted' });
      } else {
        safeToRemove.push({ ...wt, landedCount: landed.length, reason: `all ${landed.length} commits on main` });
      }
    } else if (unlanded.length > 0) {
      notSafe.push({ ...wt, unlanded, landedCount: landed.length, reason: `${unlanded.length} commits not on main` });
    } else {
      // No commits found (edge case)
      safeToRemove.push({ ...wt, reason: 'no commits found' });
    }
  }

  // Render sections
  if (safeToRemove.length > 0) {
    lines.push(`SAFE TO REMOVE (${safeToRemove.length})`);
    for (const wt of safeToRemove) {
      const p = wt.purpose ? `  [${wt.purpose}]` : '';
      lines.push(`  ${wt.name}  ${wt.ahead || 0} commits  (${wt.reason})${p}`);
    }
    lines.push('');
    lines.push('  Commands:');
    for (const wt of safeToRemove) {
      lines.push(`    git worktree remove ${wt.path}`);
    }
    lines.push('');
  }

  if (needsLogExtraction.length > 0) {
    lines.push(`NEEDS LOG EXTRACTION FIRST (${needsLogExtraction.length})`);
    for (const wt of needsLogExtraction) {
      const p = wt.purpose ? `  [${wt.purpose}]` : '';
      lines.push(`  ${wt.name}  ${wt.ahead || 0} commits  (${wt.reason})${p}`);
      for (const log of (wt.logs || [])) {
        lines.push(`    ${log}`);
      }
    }
    lines.push('');
    lines.push('  Extract logs before removing:');
    lines.push('    cp <worktree>/.claude/logs/* .claude/logs/');
    lines.push('    git add .claude/logs/ && git commit -m "chore: extract logs"');
    lines.push('');
  }

  if (notSafe.length > 0) {
    lines.push(`NOT SAFE — unlanded commits (${notSafe.length})`);
    for (const wt of notSafe) {
      const landedNote = wt.landedCount > 0 ? `, ${wt.landedCount} landed` : '';
      const p = wt.purpose ? `  [${wt.purpose}]` : '';
      lines.push(`  ${wt.name}  ${wt.unlanded.length} unlanded${landedNote}${p}`);
      for (const c of wt.unlanded.slice(0, 5)) {
        lines.push(`    ${c.hash} ${c.subject}`);
      }
      if (wt.unlanded.length > 5) {
        lines.push(`    ... and ${wt.unlanded.length - 5} more`);
      }
    }
    lines.push('');
  }

  if (named.length > 0) {
    lines.push(`NAMED / LONG-RUNNING (${named.length}) — never auto-remove`);
    for (const wt of named) {
      lines.push(`  ${wt.name}  ${wt.ahead || 0} commits ahead`);
    }
    lines.push('');
  }

  if (orphaned.length > 0) {
    lines.push(`ORPHANED (${orphaned.length}) — directory exists but not registered with git`);
    for (const wt of orphaned) {
      lines.push(`  ${wt.name}  ${wt.path}`);
    }
    lines.push('');
  }

  // Summary line
  const total = worktrees.length;
  lines.push(`Total: ${total} worktrees — ${safeToRemove.length} safe, ${needsLogExtraction.length} need logs, ${notSafe.length} not safe, ${named.length} named, ${orphaned.length} orphaned`);

  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

if (require.main === module) {
  const [,, subcommand, ...args] = process.argv;

  // Parse --since=VALUE and --output=VALUE from args
  let since = null;
  let outputPath = null;
  for (const arg of args) {
    const sinceMatch = arg.match(/^--since=(.+)/);
    if (sinceMatch) since = sinceMatch[1];
    const outputMatch = arg.match(/^--output=(.+)/);
    if (outputMatch) outputPath = outputMatch[1];
  }
  const sinceGit = parsePeriod(since);

  switch (subcommand) {
    case 'worktrees': {
      const result = classifyWorktrees();
      console.log(JSON.stringify(result, null, 2));
      break;
    }
    case 'checkboxes': {
      const result = scanCheckboxes();
      console.log(JSON.stringify(result, null, 2));
      break;
    }
    case 'commits': {
      const result = parseCommits({ since: sinceGit });
      console.log(JSON.stringify(result, null, 2));
      break;
    }
    case 'summary': {
      const worktrees = classifyWorktrees();
      const checkboxes = scanCheckboxes();
      const commits = parseCommits({ since: sinceGit });
      const stalenessWarnings = checkStaleness(worktrees);
      const planFindings = scanPlans();
      const planWarnings = [];
      for (const pf of planFindings) {
        if (pf.all_phases_done) {
          const t = pf.title;
          if (pf.status && pf.status.toLowerCase() === 'active') {
            planWarnings.push(`Plan ${t} appears complete but status is still 'active'`);
          }
          if (!pf.has_report) {
            planWarnings.push(`Plan ${t} complete but no report in reports/`);
          }
          if (pf.issue) {
            planWarnings.push(`Plan ${t} complete — issue #${pf.issue} may need closing (run /briefing verify or check manually)`);
          }
        }
      }
      const allWarnings = [...stalenessWarnings, ...planWarnings];
      let output = formatSummary(worktrees, checkboxes, commits, { since: since || '24h' });
      if (allWarnings.length > 0) {
        output += '\n\nWARNINGS\n' + allWarnings.map(w => `  ! ${w}`).join('\n');
      }
      console.log(output);
      break;
    }
    case 'report': {
      const repoRoot = findRepoRoot();
      const mainPath = repoRoot.replace(/\/.claude\/worktrees\/[^/]+$/, '');
      const reportsDir = path.join(mainPath, 'reports');
      if (!fs.existsSync(reportsDir)) {
        fs.mkdirSync(reportsDir, { recursive: true });
      }
      const worktrees = classifyWorktrees();
      const checkboxes = scanCheckboxes();
      const commits = parseCommits({ since: sinceGit });
      let content = formatReport(worktrees, checkboxes, commits, { since: sinceGit });
      content = preserveCheckboxes(content, reportsDir);
      const filePath = outputPath || generateReportPath(reportsDir);
      fs.writeFileSync(filePath, content, 'utf8');
      console.log(`Report written to: ${filePath}`);
      break;
    }
    case 'verify': {
      const worktrees = classifyWorktrees();
      const checkboxes = scanCheckboxes();
      console.log(formatVerify(worktrees, checkboxes));
      break;
    }
    case 'current': {
      const worktrees = classifyWorktrees();
      console.log(formatCurrent(worktrees));
      break;
    }
    case 'worktrees-status': {
      const worktrees = classifyWorktrees();
      console.log(formatWorktreesStatus(worktrees));
      break;
    }
    default:
      console.error('Usage: node scripts/briefing.cjs <worktrees|checkboxes|commits|summary|report|verify|current|worktrees-status> [--since=24h] [--output=path]');
      process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Exports (for unit testing)
// ---------------------------------------------------------------------------

module.exports = {
  classifyWorktrees,
  scanCheckboxes,
  scanCheckboxesRecent,
  parseCommits,
  parsePeriod,
  formatSummary,
  formatReport,
  formatVerify,
  formatCurrent,
  formatWorktreesStatus,
  partitionCommitsByLanding,
  getUnextractedLogs,
  formatET,
  formatRelativeTime,
  getUncommittedCounts,
  getStashEntries,
  getWorktreeCommits,
  generateReportPath,
  checkStaleness,
  scanPlans,
  preserveCheckboxes,
  // Internal helpers exported for testing
  parseLanded,
  parseWorktreeList,
  parseForEachRef,
};
