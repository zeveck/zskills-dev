#!/usr/bin/env python3
# scripts/porting/codex-scan.py — Claude-construct discovery/gate scanner
# (CODEX_PORT_PLAN Phase 3, WI 3.1).
#
# Architecture per tests/lib/zsh-fence-scan.py (model, not coupled): a
# data-driven class table, a markdown fence state machine PLUS prose scanning
# (Claude constructs appear in prose, unlike zsh-isms), per-finding output
# lines, and one final machine-readable summary line. The scanner is a PURE
# REPORTER (exit 0 always) — policy lives in the bash caller
# (scripts/porting/codex-scan-gate.sh), mirroring the zsh-scan/tripwire split.
#
# MODES
#   --mode discover <root>   Full report over a Claude tree (the porting
#                            worklist). Every hit is reported; violations=0
#                            (discovery is a worklist, not a judgment).
#   --mode gate <root>       Reporter for a PORTED tree: any hit not covered
#                            by an inline allow-marker (line immediately
#                            above, stacking, same semantics as
#                            allow-hardcoded) counts as a violation. Marker
#                            syntax dispatches on file extension, mirroring
#                            allow-hardcoded:
#                              .md               <!-- codex-port-allow: <class> reason: ... -->
#                              .sh/.py/.toml/...  # codex-port-allow: <class> reason: ...
#                            (an HTML comment is a syntax error in those files)
#   --list-classes           One class id per line (recipe-parity checks key
#                            on this).
#
#   --scope <path>           Repeatable; paths relative to <root>. Restricts
#                            the scan to the named subtrees/files. Defaults to
#                            the porting-relevant set (DEFAULT_SCOPE below).
#
# OUTPUT
#   <file>:<line>: [<class>] <match> → <remedy>       per finding
#   CODEX-SCAN-SUMMARY: files=<n> hits=<n> violations=<n> unknown=<n> per-class=<id>:<n>,…
#
# `hits` counts classified findings (sum of per-class); `unknown` counts
# unknown-construct findings separately; `violations` is the gate-mode count
# of marker-uncovered classified hits (0 in discover mode). Unknown findings
# can NEVER be marker-suppressed — an unknown construct needs a ruling
# appended to the guide AND to this class table (the self-amendment rule,
# Phase 4), not a per-line waiver. Exit code: always 0.

import argparse
import fnmatch
import os
import re
import sys

# ---------------------------------------------------------------------------
# Construct class table v1 — DATA, not code (CODEX_PORT_PLAN "Reference —
# scanner construct classes v1"). Phase 4's self-amendment rule appends new
# classes here (append a dict; nothing else changes). Each class carries:
#   id      — stable class id (--list-classes contract; recipe-parity keys)
#   prose   — regex list applied to prose lines (outside markdown fences)
#   fence   — regex list applied inside markdown exec fences AND to every
#             line of non-markdown files
#   remedy  — remedy string naming the guide recipe id (Phase 4)
#   exclude — optional regex: a line matching it is NOT a hit for this class
#             (e.g. co-author trailer lines are commit metadata, not model
#             dispatch)
# ---------------------------------------------------------------------------
CLASS_TABLE = [
    {
        "id": "cron",
        "prose": [r"\bCronCreate\b", r"\bCronList\b", r"\bCronDelete\b",
                  r"compute-cron-fire"],
        "fence": [r"\bCronCreate\b", r"\bCronList\b", r"\bCronDelete\b",
                  r"compute-cron-fire"],
        "remedy": "recipe:cron-to-runner — the foreground runner replaces "
                  "scheduling (Phase-5c handoff-marker rewrite)",
    },
    {
        "id": "agent-dispatch",
        "prose": [r"\bAgent tool\b", r"\bsubagent_type\b",
                  r'isolation:\s*"worktree"'],
        "fence": [r"\bAgent tool\b", r"\bsubagent_type\b",
                  r'isolation:\s*"worktree"'],
        "remedy": "recipe:agent-dispatch — codex exec child / native "
                  ".codex/agents/*.toml; preserve fresh-context",
    },
    {
        "id": "bg-monitor",
        "prose": [r"\bMonitor\b", r"\bTaskOutput\b", r"\bBashOutput\b",
                  r"\brun_in_background\b"],
        "fence": [r"\bMonitor\b", r"\bTaskOutput\b", r"\bBashOutput\b",
                  r"\brun_in_background\b"],
        "remedy": "recipe:bg-monitor-delete — delete/rewrite; the Layer-0 "
                  "timeout apparatus is Claude-specific",
    },
    {
        "id": "skill-tool",
        "prose": [r"\bSkill tool\b"],
        "fence": [r"\bSkill tool\b"],
        "remedy": "recipe:skill-tool-inline — read-SKILL.md-and-execute-"
                  "inline (the validated cron-fire fallback) + push logic "
                  "into bundled scripts",
    },
    {
        "id": "arguments",
        "prose": [r"\$ARGUMENTS\b"],
        "fence": [r"\$ARGUMENTS\b"],
        "remedy": "recipe:arguments-invocation-text — Codex skill invocation "
                  "text semantics",
    },
    {
        "id": "ask-user",
        "prose": [r"\bAskUserQuestion\b"],
        "fence": [r"\bAskUserQuestion\b"],
        "remedy": "recipe:ask-user-prose — plain-prose questioning "
                  "degradation",
    },
    {
        "id": "plugin-root",
        "prose": [r"CLAUDE_PLUGIN_ROOT"],
        "fence": [r"CLAUDE_PLUGIN_ROOT"],
        "remedy": "recipe:plugin-root-alias — verify alias per assumptions "
                  "manifest, else rewrite",
    },
    {
        "id": "project-dir",
        "prose": [r"CLAUDE_PROJECT_DIR"],
        "fence": [r"CLAUDE_PROJECT_DIR"],
        "remedy": "recipe:project-dir-git-fallback — git-fallback becomes "
                  "primary (already exists in zskills-paths.sh)",
    },
    {
        "id": "frontmatter-flags",
        "prose": [r"\bdisable-model-invocation\b", r"\buser-invocable\b",
                  r"\ballowed-tools\b", r"^hooks:\s*$"],
        "fence": [r"\bdisable-model-invocation\b", r"\buser-invocable\b",
                  r"\ballowed-tools\b", r"^hooks:\s*$"],
        "remedy": "recipe:frontmatter-flags-openai-yaml — openai.yaml "
                  "allow_implicit_invocation / documented degradation",
    },
    {
        # Pinned patterns per the v1 reference: the model-literal forms plus
        # the ordinal-prose forms. Co-author trailer lines
        # (`Claude Opus … <noreply@anthropic.com>`) are EXCLUDED by pattern —
        # they are commit metadata, not dispatch.
        "id": "claude-model-dispatch",
        "prose": [r'model:\s*"opus"', r'model:\s*"sonnet"',
                  r"haiku=1 < sonnet=2 < opus=3",
                  r"[Nn]ever dispatch.*[Hh]aiku"],
        "fence": [r'model:\s*"opus"', r'model:\s*"sonnet"',
                  r"haiku=1 < sonnet=2 < opus=3",
                  r"[Nn]ever dispatch.*[Hh]aiku"],
        "remedy": "recipe:model-dispatch-config — rewrite to Codex "
                  "model/model_reasoning_effort config or delete",
        "exclude": r"<noreply@anthropic\.com>",
    },
]

# Unknown-construct heuristic: a Claude-shaped env token the class table does
# not classify. Reported as `unknown-class` for agent judgment; the ruling is
# appended to the guide AND to CLASS_TABLE (self-amendment). NEVER
# marker-suppressible.
RE_UNKNOWN_ENV = re.compile(r"\bCLAUDE_[A-Z][A-Z0-9_]*\b")
KNOWN_CLAUDE_ENV = {"CLAUDE_PLUGIN_ROOT", "CLAUDE_PROJECT_DIR"}
UNKNOWN_REMEDY = ("unclassified Claude construct — record the ruling in the "
                  "guide and append a class to the scanner's class table "
                  "(self-amendment rule)")

# ---------------------------------------------------------------------------
# Default-skip list — DATA, next to the class table (WI 3.1). Rationale:
#   .git          — object store, not content.
#   docs/plans    — worked examples there legitimately contain Claude-isms
#                   (plans are one-time execution artifacts, never ported).
#   docs/porting  — the porting guide itself names Claude constructs to
#                   explain their remedies (same treatment as WI 4.3's
#                   exemption note).
#   tests         — a Claude construct inside a test suite is the
#                   curated-registry recipe's jurisdiction (keep/drop/split
#                   rulings — a suite ASSERTING on a Claude-lane pin is test
#                   content, not shipped prose), never a scanner violation.
#                   This keeps the scanner gate and the ported-tree suite
#                   triage from contradicting each other.
# Port meta-records, by exact ROOT-relative path (path exclusion, NOT
# allow-markers — mechanical, no per-line marking of freeform prose): these
# files are the record OF the port and MUST name Claude constructs to do
# their job (WI 12.1 REQUIRES DEGRADATIONS.md to contain user-invocable /
# allowed-tools / frontmatter-hooks rows; GAPS.md is freeform gap prose).
# The exclusion matches ONLY at the scanned root (<root>/GAPS.md, not
# skills/*/GAPS.md), so a hedge or construct smuggled into shipped prose
# cannot hide behind the basename.
DEFAULT_SKIP_DIRS = [".git", "docs/plans", "docs/porting", "tests"]
META_RECORD_FILES = ["GAPS.md", "DEGRADATIONS.md", "PORT_MANIFEST.json",
                     "PORTING-NOTES.md"]

# Default scan scope (the porting-relevant set): (subdir, glob) pairs
# relative to <root>. FALLBACK RULE: when NONE of the directory entries
# (skills/agents/hooks/scripts) exists under <root> — e.g. the root IS a
# subtree like `skills/`, or a fixture tree — the whole root is scanned
# recursively (all eligible extensions). This is what makes
# `--mode discover skills/` and fixture-tree gates scan anything at all.
DEFAULT_SCOPE = [
    ("skills", "**/*.md"),
    ("agents", "*.md"),
    ("hooks", "**/*"),
    (".", "*.md"),
    ("scripts", "**/*"),
]

# Only text files a port actually ships are scanned (binaries and images are
# never porting surfaces).
SCAN_EXTENSIONS = {".md", ".sh", ".py", ".toml", ".json", ".yaml", ".yml",
                   ".template"}

# Allow-marker syntax dispatches on file extension (mirrors allow-hardcoded):
RE_MARKER_MD = re.compile(
    r"<!--\s*codex-port-allow:\s*([a-z][a-z0-9-]*)\s+reason:.*-->")
RE_MARKER_HASH = re.compile(
    r"^\s*#\s*codex-port-allow:\s*([a-z][a-z0-9-]*)\s+reason:")

RE_FENCE_OPEN = re.compile(r"^[ \t]*```([a-zA-Z0-9_+-]*)[ \t]*$")
RE_FENCE_BARE_CLOSE = re.compile(r"^[ \t]*```[ \t]*$")
RE_BLOCKQUOTE = re.compile(r"^[ \t]*>[ \t]?(.*)$")

COMPILED = [
    {
        "id": c["id"],
        "prose": [re.compile(p) for p in c["prose"]],
        "fence": [re.compile(p) for p in c["fence"]],
        "remedy": c["remedy"],
        "exclude": re.compile(c["exclude"]) if c.get("exclude") else None,
    }
    for c in CLASS_TABLE
]


def marker_regex_for(path):
    """The allow-marker form for this file, by extension."""
    if path.endswith(".md"):
        return RE_MARKER_MD
    return RE_MARKER_HASH


def match_line(line, context):
    """Return list of (class_id, match_text, remedy) for one line.

    context is "prose" or "fence". One finding per (line, class): the first
    matching pattern's text is reported.
    """
    out = []
    for c in COMPILED:
        if c["exclude"] is not None and c["exclude"].search(line):
            continue
        for rx in c[context]:
            m = rx.search(line)
            if m:
                out.append((c["id"], m.group(0), c["remedy"]))
                break
    return out


def unknown_on_line(line):
    """Return list of unknown-construct tokens on this line."""
    out = []
    for m in RE_UNKNOWN_ENV.finditer(line):
        if m.group(0) not in KNOWN_CLAUDE_ENV:
            out.append(m.group(0))
    return out


def scan_file(path, relpath, gate_mode):
    """Scan one file. Returns (findings, unknown_findings).

    findings:         list of (relpath, lineno, class_id, match, remedy,
                       suppressed)
    unknown_findings: list of (relpath, lineno, token)
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            all_lines = fh.readlines()
    except OSError:
        return [], []

    is_md = path.endswith(".md")
    rx_marker = marker_regex_for(path)

    findings = []
    unknowns = []

    in_fence = False
    pending_markers = set()   # class ids stacked above the next target line
    fence_markers = set()     # markers carried for the whole current fence

    for i, raw in enumerate(all_lines, 1):
        line = raw.rstrip("\n")
        m_bq = RE_BLOCKQUOTE.match(line)
        norm = m_bq.group(1) if m_bq else line

        # marker lines: collect and never scan (a marker names a class in
        # documentation; its reason text is not shipped construct usage).
        mm = rx_marker.search(line)
        if mm and not in_fence:
            pending_markers.add(mm.group(1))
            continue

        if is_md and not in_fence and RE_FENCE_OPEN.match(norm):
            # fence opener: pending markers cover the whole fence (same
            # semantics as allow-hardcoded's fence-scoped marker).
            in_fence = True
            fence_markers = set(pending_markers)
            pending_markers = set()
            continue
        if is_md and in_fence and RE_FENCE_BARE_CLOSE.match(norm):
            in_fence = False
            fence_markers = set()
            continue

        if line.strip() == "":
            # blanks do not reset a marker stack (allow-hardcoded semantics:
            # only a non-blank, non-marker line resets).
            continue

        if is_md:
            context = "fence" if in_fence else "prose"
            active = fence_markers if in_fence else pending_markers
        else:
            # non-markdown files: no fences; every line is scanned with the
            # union context (fence patterns == prose patterns in v1, so
            # "fence" is used as the code-context set).
            context = "fence"
            active = pending_markers

        for class_id, match_text, remedy in match_line(norm, context):
            suppressed = gate_mode and class_id in active
            findings.append((relpath, i, class_id, match_text, remedy,
                             suppressed))
        for token in unknown_on_line(norm):
            unknowns.append((relpath, i, token))

        if not in_fence:
            pending_markers = set()

    return findings, unknowns


def is_skipped(relpath):
    """Default-skip check on a root-relative path (forward slashes)."""
    for d in DEFAULT_SKIP_DIRS:
        if relpath == d or relpath.startswith(d + "/"):
            return True
    if relpath in META_RECORD_FILES:
        return True
    return False


def collect_files(root, scopes):
    """Resolve the file set to scan (sorted, root-relative + absolute)."""
    files = {}

    def add(abspath):
        rel = os.path.relpath(abspath, root).replace(os.sep, "/")
        if is_skipped(rel):
            return
        _, ext = os.path.splitext(abspath)
        if ext not in SCAN_EXTENSIONS:
            return
        files[rel] = abspath

    def walk_tree(top):
        for dirpath, dirs, fns in os.walk(top):
            dirs[:] = [d for d in dirs if d != ".git"]
            # prune skipped subtrees early
            rel_dir = os.path.relpath(dirpath, root).replace(os.sep, "/")
            if rel_dir != "." and is_skipped(rel_dir):
                dirs[:] = []
                continue
            for fn in fns:
                add(os.path.join(dirpath, fn))

    if scopes:
        for scope in scopes:
            target = os.path.join(root, scope)
            if os.path.isfile(target):
                add(target)
            elif os.path.isdir(target):
                walk_tree(target)
        return sorted(files.items())

    # default scope: the porting-relevant set
    scope_dirs = [d for d, _g in DEFAULT_SCOPE if d != "."]
    if not any(os.path.isdir(os.path.join(root, d)) for d in scope_dirs):
        # fallback: the root IS a subtree/fixture — scan it whole
        walk_tree(root)
        return sorted(files.items())

    for subdir, glob_pat in DEFAULT_SCOPE:
        base = root if subdir == "." else os.path.join(root, subdir)
        if not os.path.isdir(base):
            continue
        if subdir == ".":
            for fn in os.listdir(base):
                p = os.path.join(base, fn)
                if os.path.isfile(p) and fnmatch.fnmatch(fn, glob_pat):
                    add(p)
            continue
        if glob_pat == "**/*":
            walk_tree(base)
            continue
        if glob_pat == "**/*.md":
            for dirpath, dirs, fns in os.walk(base):
                dirs[:] = [d for d in dirs if d != ".git"]
                for fn in fns:
                    if fn.endswith(".md"):
                        add(os.path.join(dirpath, fn))
            continue
        # single-level glob (agents/*.md)
        for fn in os.listdir(base):
            p = os.path.join(base, fn)
            if os.path.isfile(p) and fnmatch.fnmatch(fn, glob_pat):
                add(p)
    return sorted(files.items())


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Claude-construct discovery/gate scanner (pure reporter; "
                    "exit 0 always — policy lives in codex-scan-gate.sh).")
    parser.add_argument("root", nargs="?",
                        help="tree to scan (required unless --list-classes)")
    parser.add_argument("--mode", choices=["discover", "gate"],
                        default="discover")
    parser.add_argument("--scope", action="append", default=[],
                        help="restrict the scan to this root-relative "
                             "subtree/file (repeatable)")
    parser.add_argument("--list-classes", action="store_true",
                        help="print one class id per line and exit")
    args = parser.parse_args(argv)

    if args.list_classes:
        for c in CLASS_TABLE:
            print(c["id"])
        return 0

    if not args.root:
        parser.error("root is required unless --list-classes is given")
    if not os.path.isdir(args.root):
        # Still a pure reporter: an absent root is an empty scan the caller's
        # summary parse + anti-vacuous floors surface (fail-closed policy is
        # the bash caller's job).
        print("CODEX-SCAN-SUMMARY: files=0 hits=0 violations=0 unknown=0 "
              "per-class=" + ",".join(c["id"] + ":0" for c in CLASS_TABLE))
        return 0

    gate_mode = args.mode == "gate"
    root = os.path.abspath(args.root)
    file_list = collect_files(root, args.scope)

    per_class = {c["id"]: 0 for c in CLASS_TABLE}
    hits = 0
    violations = 0
    unknown_total = 0
    lines_out = []

    for rel, abspath in file_list:
        findings, unknowns = scan_file(abspath, rel, gate_mode)
        for relpath, lineno, class_id, match_text, remedy, suppressed \
                in findings:
            per_class[class_id] += 1
            hits += 1
            uncovered = gate_mode and not suppressed
            if uncovered:
                violations += 1
            # discover mode reports every hit; gate mode reports only the
            # uncovered ones (covered hits are accepted by their marker).
            if not gate_mode or uncovered:
                lines_out.append("%s:%d: [%s] %s → %s"
                                 % (relpath, lineno, class_id, match_text,
                                    remedy))
        for relpath, lineno, token in unknowns:
            unknown_total += 1
            lines_out.append("%s:%d: [unknown-class] %s → %s"
                             % (relpath, lineno, token, UNKNOWN_REMEDY))

    for line in lines_out:
        print(line)
    print("CODEX-SCAN-SUMMARY: files=%d hits=%d violations=%d unknown=%d "
          "per-class=%s"
          % (len(file_list), hits, violations, unknown_total,
             ",".join("%s:%d" % (c["id"], per_class[c["id"]])
                      for c in CLASS_TABLE)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
