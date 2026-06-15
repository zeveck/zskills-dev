#!/usr/bin/env python3
# tests/lib/zsh-fence-scan.py — zsh fence-portability scanner (#1155).
#
# Clones the WI-5.2 fence state machine from tests/test-skill-conformance.sh
# in Python (repo convention permits Python for unwieldy line-state scanners;
# no jq). Walks the skills/**/*.md SOURCE tree (the .claude/skills mirror is
# byte-identical by the parity suite and is NOT double-scanned), runs a
# per-fence state machine, and emits one line per finding plus a final
# machine-readable summary line.
#
# Environment:
#   ZS_SCAN_ROOT     — directory to scan recursively for *.md (required)
#   ZS_PENDING_FILE  — path to the pending-list fixture (optional; absent →
#                      unconditional enforcement)
#
# Output lines (stdout):
#   ZSH-FENCE: <file>:<open_line> — <check>: <construct> — <remedy>
#       a violation in an UNLISTED file (FAIL) — or any violation when no
#       pending fixture is given.
#   ZSH-FENCE-PENDING: <n> violations in <file>
#       per-file count for a LISTED file with >0 violations (report-only WARN).
#   ZSH-FENCE-STALE: <file> — listed but clean/missing; drop the entry (the
#       list must be EMPTY by Phase 5)
#       a listed file with ZERO violations or that no longer exists (WARN).
#   ZSH-FENCE-FIXTURE-MALFORMED: <reason>
#       the pending fixture is malformed (duplicate / non-skills/ / unsorted).
#   ZSH-FENCE-SUMMARY: exec_fences=<N> check_b_fences=<N> guard_expected_fences=<N> wrapped_fences=<N> unlisted_violations=<N> fixture_malformed=<0|1>
#
# Exit code: always 0 (the bash caller interprets the summary + line classes;
# this keeps the scanner a pure reporter, matching the WI-5.2 precedent).

import os
import re
import sys

scan_root = os.environ["ZS_SCAN_ROOT"]
pending_file = os.environ.get("ZS_PENDING_FILE", "")

GUARD_LINE = ("if [ -n \"${ZSH_VERSION:-}\" ]; then setopt KSH_ARRAYS "
              "BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi")
WRAP_OPENER = "bash <<'ZSKILLS_BASH_FENCE'"

# ── construct regexes (bash ERE semantics, exact per the plan) ────────────
# (a) setopt-unfixable constructs
RE_A_MAPFILE = re.compile(r'(^|[^A-Za-z0-9_])(mapfile|readarray|compgen)([^A-Za-z0-9_]|$)')
RE_A_READA = re.compile(r'(^|[^A-Za-z0-9_])read[ \t]+(-[A-Za-z]+[ \t]+)*-[A-Za-z]*a([ \t]|$)')
RE_A_INDIRECT = re.compile(r'\$\{![A-Za-z_]')
RE_A_CASEMOD = re.compile(r'\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)[^}]*\}')
# (b) regex construct
RE_B_REGEX = re.compile(r'(\[\[[^]]*=~|BASH_REMATCH)')
# (b2) word-split reliance
RE_B2_WORDSPLIT = re.compile(
    r'for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+(\$[A-Za-z_]|\$\{[A-Za-z_][A-Za-z0-9_:%#-]*\})')
# (c) quoted assoc subscript — variable OR literal
RE_C_VAR = re.compile(r'[A-Za-z0-9_]\["\$')
RE_C_LITERAL = re.compile(r'[A-Za-z0-9_]\["[A-Za-z0-9_]+"\]')
# (d) zsh special-parameter assignment
RE_D_SPECIAL = re.compile(r'^[ \t]*(path|status|LINES|COLUMNS|argv|fpath|cdpath)=')

RE_GUARD = re.compile(r'setopt[ \t][^#]*KSH_ARRAYS[^#]*BASH_REMATCH')
RE_GUARD_WORDSPLIT = re.compile(r'SH_WORD_SPLIT')
RE_SKILL_INVOKE = re.compile(r'Skill:[ \t]*\{')
RE_HEREDOC = re.compile(r'<<-?[ \t]*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?')
RE_FENCE_OPEN = re.compile(r'^[ \t]*```([a-zA-Z0-9_+-]*)[ \t]*$')
RE_FENCE_BARE_CLOSE = re.compile(r'^[ \t]*```[ \t]*$')
RE_BLOCKQUOTE = re.compile(r'^[ \t]*>[ \t]?(.*)$')
RE_COMMENT = re.compile(r'^[ \t]*#')
RE_MARKER = re.compile(r'<!--[ \t]*allow-zsh-unwrapped:[ \t]*(.+?)[ \t]+reason:.*-->')

EXEC_LANGS = {"", "bash", "sh", "shell"}

# scan_root is the skills/ dir (or a fixture subtree). Compute repo-relative
# paths against scan_root's PARENT so a scan_root ending in "skills" yields
# "skills/..." (matching the pending-list fixture's repo-relative format).
scan_parent = os.path.dirname(os.path.abspath(scan_root))


def repo_rel(path):
    return os.path.relpath(os.path.abspath(path), scan_parent)


# ── pending-list load + format validation ────────────────────────────────
pending = None          # None == fixture absent (unconditional mode)
fixture_malformed = 0
malformed_lines = []
if pending_file and os.path.isfile(pending_file):
    with open(pending_file, encoding="utf-8") as fh:
        raw = fh.read()
    lines = raw.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]          # tolerate the single LF terminator
    seen = set()
    pending = []
    for ln in lines:
        if ln.strip() == "":
            malformed_lines.append("blank line")
            continue
        if ln.lstrip().startswith("#"):
            malformed_lines.append("comment line: %r" % ln)
            continue
        if not ln.startswith("skills/"):
            malformed_lines.append("non-skills/-prefixed line: %r" % ln)
        if ln in seen:
            malformed_lines.append("duplicate line: %r" % ln)
        seen.add(ln)
        pending.append(ln)
    if pending != sorted(pending):   # default str sort == LC_ALL=C codepoint
        malformed_lines.append("not LC_ALL=C sorted")
    if malformed_lines:
        fixture_malformed = 1

pending_set = set(pending) if pending is not None else set()


def scan_file(path):
    """Return (violations:list[str], census) for one .md file.

    census is a dict with per-file counters that aggregate into the summary:
      exec_fences, check_b_fences, guard_expected_fences, wrapped_fences
    """
    relpath = repo_rel(path)
    with open(path, encoding="utf-8") as fh:
        all_lines = fh.readlines()

    violations = []
    census = dict(exec_fences=0, check_b_fences=0,
                  guard_expected_fences=0, wrapped_fences=0)

    in_fence = False
    fence_type = ""
    fence_open_line = 0
    pending_markers = set()       # markers stacked above the next opener

    # per-fence accumulators
    st = {}

    def reset_fence(open_line, ftype, markers):
        st.clear()
        st.update(dict(
            open_line=open_line, ftype=ftype, markers=set(markers),
            has_a=False, has_b=False, has_b2=False, has_c=False, has_d=False,
            a_token="", d_seen="",
            is_skill_invoke=False, has_guard=False, has_guard_wordsplit=False,
            is_wrapped=False, saw_first_body=False,
            in_heredoc=False, heredoc_delim="",
        ))

    def close_fence():
        if st.get("ftype") != "exec":
            return
        census["exec_fences"] += 1
        if st["is_wrapped"]:
            census["wrapped_fences"] += 1
        if st["has_b"]:
            census["check_b_fences"] += 1
        flagged = st["has_a"] or st["has_b"] or st["has_b2"] or st["has_c"] or st["has_d"]
        if flagged and not st["has_a"] and (st["has_b"] or st["has_b2"] or st["has_c"]):
            census["guard_expected_fences"] += 1

        markers = st["markers"]

        def viol(check, construct, remedy):
            violations.append("ZSH-FENCE: %s:%d — %s: %s — %s"
                              % (relpath, st["open_line"], check, construct, remedy))

        # (a)
        if st["has_a"] and not st["is_wrapped"] and st["a_token"] not in markers:
            if st["is_skill_invoke"]:
                remedy = "rewrite (Track R); wrap unavailable in SKILL-INVOKE fences"
            else:
                remedy = ("wrap the fence (first body line exactly `%s`) or "
                          "rewrite via Track R" % WRAP_OPENER)
            viol("(a) setopt-unfixable", st["a_token"], remedy)
        # (b)
        if st["has_b"] and not st["is_wrapped"] and not st["has_guard"] \
                and "BASH_REMATCH" not in markers and "regex" not in markers:
            viol("(b) regex", "BASH_REMATCH",
                 "wrap, or add the v2 guard as the first executable line: %s" % GUARD_LINE)
        # (b2)
        if st["has_b2"] and not st["is_wrapped"] \
                and not (st["has_guard"] and st["has_guard_wordsplit"]) \
                and "for-in-scalar" not in markers:
            viol("(b2) word-split", "for-in-scalar",
                 "wrap, or add the v2 guard (must include SH_WORD_SPLIT): %s" % GUARD_LINE)
        # (c)
        if st["has_c"] and "quoted-subscript" not in markers:
            viol("(c) quoted assoc subscript", "quoted-subscript",
                 "unquote the subscript — zsh addresses quoted and unquoted "
                 "keys differently; see caller-loop-pattern.md")
        # (d)
        if st["has_d"] and st["d_seen"] not in markers:
            viol("(d) zsh special-param", st["d_seen"],
                 "collides with a zsh tied/read-only special parameter — rename")

    for i, raw in enumerate(all_lines, 1):
        line = raw.rstrip("\n")
        m_bq = RE_BLOCKQUOTE.match(line)
        norm = m_bq.group(1) if m_bq else line

        if not in_fence:
            mo = RE_FENCE_OPEN.match(norm)
            if mo:
                in_fence = True
                lang = mo.group(1)
                reset_fence(i, "exec" if lang in EXEC_LANGS else "other", pending_markers)
                pending_markers = set()
                continue
            mm = RE_MARKER.search(line)
            if mm:
                pending_markers.add(mm.group(1).strip())
                continue
            if line.strip() != "":
                pending_markers = set()
            continue

        # inside a fence
        if RE_FENCE_BARE_CLOSE.match(norm):
            close_fence()
            in_fence = False
            fence_type = ""
            continue

        if st.get("ftype") != "exec":
            continue

        # heredoc-body skip
        if st["in_heredoc"]:
            if norm.strip() == st["heredoc_delim"]:
                st["in_heredoc"] = False
                st["heredoc_delim"] = ""
            continue

        body = norm.strip()
        is_comment = bool(RE_COMMENT.match(norm))

        # wrap-opener detection: first non-comment, non-blank body line.
        if not st["saw_first_body"] and body != "" and not is_comment:
            st["saw_first_body"] = True
            if body == WRAP_OPENER:
                st["is_wrapped"] = True
                st["in_heredoc"] = True
                st["heredoc_delim"] = "ZSKILLS_BASH_FENCE"
                continue

        if is_comment:
            continue

        # heredoc opener (non-comment) → skip body until delimiter (but the
        # opener line itself is still code: evaluate constructs before <<DELIM).
        mh = RE_HEREDOC.search(norm)

        if RE_GUARD.search(norm):
            st["has_guard"] = True
            if RE_GUARD_WORDSPLIT.search(norm):
                st["has_guard_wordsplit"] = True
        if RE_SKILL_INVOKE.search(norm):
            st["is_skill_invoke"] = True

        ma = RE_A_MAPFILE.search(norm)
        if ma:
            st["has_a"] = True
            st["a_token"] = ma.group(2)
        if RE_A_READA.search(norm):
            st["has_a"] = True
            if not st["a_token"]:
                st["a_token"] = "read-a"
        if RE_A_INDIRECT.search(norm):
            st["has_a"] = True
            if not st["a_token"]:
                st["a_token"] = "indirect"
        if RE_A_CASEMOD.search(norm):
            st["has_a"] = True
            if not st["a_token"]:
                st["a_token"] = "case-modification"
        if RE_B_REGEX.search(norm):
            st["has_b"] = True
        if RE_B2_WORDSPLIT.search(norm):
            st["has_b2"] = True
        if RE_C_VAR.search(norm) or RE_C_LITERAL.search(norm):
            st["has_c"] = True
        md = RE_D_SPECIAL.search(norm)
        if md:
            st["has_d"] = True
            st["d_seen"] = md.group(1)

        if mh:
            st["in_heredoc"] = True
            st["heredoc_delim"] = mh.group(1)

    if in_fence and st.get("ftype") == "exec":
        close_fence()

    return violations, census


files = []
for dirpath, _dirs, fns in os.walk(scan_root):
    for fn in fns:
        if fn.endswith(".md"):
            files.append(os.path.join(dirpath, fn))

agg = dict(exec_fences=0, check_b_fences=0,
           guard_expected_fences=0, wrapped_fences=0)
per_file_violations = {}

for f in sorted(files):
    viols, census = scan_file(f)
    for k in agg:
        agg[k] += census[k]
    if viols:
        per_file_violations[repo_rel(f)] = viols

# ── emit fixture-malformed lines ──────────────────────────────────────────
for r in malformed_lines:
    print("ZSH-FENCE-FIXTURE-MALFORMED: %s" % r)

# ── classify per-file violations against the pending list ─────────────────
unlisted_violations = 0
for relpath in sorted(per_file_violations):
    viols = per_file_violations[relpath]
    if pending is not None and relpath in pending_set:
        print("ZSH-FENCE-PENDING: %d violations in %s" % (len(viols), relpath))
    else:
        for v in viols:
            print(v)
        unlisted_violations += len(viols)

# ── stale-entry detection (listed but clean/missing) ──────────────────────
if pending is not None:
    for entry in pending:
        abs_entry = os.path.join(scan_parent, entry)
        if (not os.path.isfile(abs_entry)) or (entry not in per_file_violations):
            print("ZSH-FENCE-STALE: %s — listed but clean/missing; drop the "
                  "entry (the list must be EMPTY by Phase 5)" % entry)

print("ZSH-FENCE-SUMMARY: exec_fences=%d check_b_fences=%d "
      "guard_expected_fences=%d wrapped_fences=%d unlisted_violations=%d "
      "fixture_malformed=%d"
      % (agg["exec_fences"], agg["check_b_fences"],
         agg["guard_expected_fences"], agg["wrapped_fences"],
         unlisted_violations, fixture_malformed))
sys.exit(0)
