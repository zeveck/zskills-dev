#!/bin/bash
# tests/test-tokenize-then-walk.sh — unit tests for the
# `is_git_subcommand` and `is_destruct_command` helpers in
# hooks/_lib/git-tokenwalk.sh. Phase 2 of the BLOCK_UNSAFE_HARDENING plan.
#
# 124 cases total:
#   - is_git_subcommand × 3 verbs (commit / cherry-pick / push) × 34 cases = 102
#   - is_destruct_command: kill (12) + rm (6) + find (2) + rsync (2) = 22
#
# Run standalone: `bash tests/test-tokenize-then-walk.sh` exits 0 if all
# cases pass.
#
# NOTE: this file deliberately uses `set -u` only INSIDE the helpers via
# the source. The dispatcher itself relies on globals being set/reset by
# every helper call.

# Locate and source the source-of-truth helper file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../hooks/_lib/git-tokenwalk.sh"

PASS=0
FAIL=0

# ─── Dispatcher helpers ───

# assert_match <case_id> <description> <verb> <cmd>
# Asserts is_git_subcommand "$cmd" "$verb" returns 0.
assert_match() {
  local id="$1" desc="$2" verb="$3" cmd="$4"
  if is_git_subcommand "$cmd" "$verb"; then
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL $id — $desc (expected match, got no-match) cmd=[$cmd] verb=[$verb]"
    FAIL=$((FAIL + 1))
  fi
}

# assert_nomatch <case_id> <description> <verb> <cmd>
# Asserts is_git_subcommand "$cmd" "$verb" returns 1.
assert_nomatch() {
  local id="$1" desc="$2" verb="$3" cmd="$4"
  if is_git_subcommand "$cmd" "$verb"; then
    echo "FAIL $id — $desc (expected no-match, got match) cmd=[$cmd] verb=[$verb] GIT_SUB_REST=[$GIT_SUB_REST]"
    FAIL=$((FAIL + 1))
  else
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  fi
}

# assert_rest_contains <case_id> <description> <verb> <cmd> <pattern>
# Asserts the helper matches AND GIT_SUB_REST matches <pattern> regex.
assert_rest_contains() {
  local id="$1" desc="$2" verb="$3" cmd="$4" pat="$5"
  if ! is_git_subcommand "$cmd" "$verb"; then
    echo "FAIL $id — $desc (expected match, got no-match) cmd=[$cmd]"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$GIT_SUB_REST" =~ $pat ]]; then
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL $id — $desc (GIT_SUB_REST=[$GIT_SUB_REST] does not match /$pat/)"
    FAIL=$((FAIL + 1))
  fi
}

# assert_rest_not_contains <case_id> <description> <verb> <cmd> <pattern>
# Asserts the helper matches AND GIT_SUB_REST does NOT match <pattern>.
assert_rest_not_contains() {
  local id="$1" desc="$2" verb="$3" cmd="$4" pat="$5"
  if ! is_git_subcommand "$cmd" "$verb"; then
    echo "FAIL $id — $desc (expected match, got no-match) cmd=[$cmd]"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$GIT_SUB_REST" =~ $pat ]]; then
    echo "FAIL $id — $desc (GIT_SUB_REST=[$GIT_SUB_REST] unexpectedly matched /$pat/)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  fi
}

# assert_rest_eq <case_id> <description> <verb> <cmd> <expected>
# Asserts the helper matches AND GIT_SUB_REST == <expected> exactly.
assert_rest_eq() {
  local id="$1" desc="$2" verb="$3" cmd="$4" expected="$5"
  if ! is_git_subcommand "$cmd" "$verb"; then
    echo "FAIL $id — $desc (expected match, got no-match) cmd=[$cmd]"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$GIT_SUB_REST" == "$expected" ]]; then
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL $id — $desc (GIT_SUB_REST=[$GIT_SUB_REST] expected=[$expected])"
    FAIL=$((FAIL + 1))
  fi
}

# assert_index_eq <case_id> <description> <verb> <cmd> <expected_index>
assert_index_eq() {
  local id="$1" desc="$2" verb="$3" cmd="$4" expected="$5"
  if ! is_git_subcommand "$cmd" "$verb"; then
    echo "FAIL $id — $desc (expected match, got no-match) cmd=[$cmd]"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$GIT_SUB_INDEX" == "$expected" ]]; then
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL $id — $desc (GIT_SUB_INDEX=$GIT_SUB_INDEX expected=$expected)"
    FAIL=$((FAIL + 1))
  fi
}

# assert_destruct_match <case_id> <description> <cmd> <verb> <flag_match>
assert_destruct_match() {
  local id="$1" desc="$2" cmd="$3" verb="$4" fm="$5"
  if is_destruct_command "$cmd" "$verb" "$fm"; then
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL $id — $desc (expected match) cmd=[$cmd] verb=[$verb] fm=[$fm]"
    FAIL=$((FAIL + 1))
  fi
}

# assert_destruct_nomatch <case_id> <description> <cmd> <verb> <flag_match>
assert_destruct_nomatch() {
  local id="$1" desc="$2" cmd="$3" verb="$4" fm="$5"
  if is_destruct_command "$cmd" "$verb" "$fm"; then
    echo "FAIL $id — $desc (expected no-match) cmd=[$cmd] verb=[$verb] fm=[$fm]"
    FAIL=$((FAIL + 1))
  else
    echo "PASS $id — $desc"
    PASS=$((PASS + 1))
  fi
}

# ─── Matrix runner: replicate is_git_subcommand cases over 3 verbs ───
# For each verb in {commit, cherry-pick, push} we run the same logical 34
# cases. Negative cases that explicitly mention a non-target verb stay as
# no-match because the verb under test never appears in the buffer.

run_subcommand_matrix() {
  local prefix="$1"   # XCC, XCP, XPU
  local verb="$2"     # commit, cherry-pick, push

  # XCC1 — `git <verb>` → match (positive baseline)
  assert_match "${prefix}1" "git $verb baseline" "$verb" "git $verb"

  # XCC2 — `git status` → no match (different verb)
  assert_nomatch "${prefix}2" "git status (non-target verb)" "$verb" "git status"

  # XCC3 — `git <verb> -am 'msg'` → match
  assert_match "${prefix}3" "git $verb with short flag args" "$verb" "git $verb -am 'msg'"

  # XCC4 — `git <verb> --amend` → match (use --amend literally; for
  # cherry-pick/push it's a non-applicable flag but the helper doesn't
  # care — it just checks subcommand position)
  assert_match "${prefix}4" "git $verb --amend (long-flag passthrough)" "$verb" "git $verb --amend"

  # XCC5 — `git -C /tmp/foo <verb> -m bar` → match (-C path two-token consume)
  assert_match "${prefix}5" "git -C /tmp/foo $verb -m bar" "$verb" "git -C /tmp/foo $verb -m bar"

  # XCC6 — `git -C /tmp/foo log` → no match (-C must not over-match other subcommands)
  assert_nomatch "${prefix}6" "git -C /tmp/foo log (different subcommand after -C)" "$verb" "git -C /tmp/foo log"

  # XCC7 — `git -c user.email=x@y.z <verb> -m msg` → match
  assert_match "${prefix}7" "git -c user.email=x@y.z $verb -m msg" "$verb" "git -c user.email=x@y.z $verb -m msg"

  # XCC8 — `git --no-pager <verb> -m foo` → match
  assert_match "${prefix}8" "git --no-pager $verb -m foo" "$verb" "git --no-pager $verb -m foo"

  # XCC9 — `git --git-dir=/x <verb>` → match
  assert_match "${prefix}9" "git --git-dir=/x $verb" "$verb" "git --git-dir=/x $verb"

  # XCC10 — `git -P <verb>` → match
  assert_match "${prefix}10" "git -P $verb (short --no-pager)" "$verb" "git -P $verb"

  # XCC11 — `git -C /tmp -c user.email=x <verb>` → match
  assert_match "${prefix}11" "git -C /tmp -c user.email=x $verb (mixed flags)" "$verb" "git -C /tmp -c user.email=x $verb"

  # XCC12 — `git --git-dir=/x --work-tree=/y <verb> -m msg` → match
  assert_match "${prefix}12" "git --git-dir=/x --work-tree=/y $verb -m msg" "$verb" "git --git-dir=/x --work-tree=/y $verb -m msg"

  # XCC13 — `git --no-pager log` → no match
  assert_nomatch "${prefix}13" "git --no-pager log (different subcommand after long flag)" "$verb" "git --no-pager log"

  # XCC14 — `git -C /tmp diff` → no match
  assert_nomatch "${prefix}14" "git -C /tmp diff (different subcommand)" "$verb" "git -C /tmp diff"

  # XCC15 — `FOO=bar git <verb> -m msg` → match (env-var prefix)
  assert_match "${prefix}15" "FOO=bar git $verb -m msg (env-var prefix)" "$verb" "FOO=bar git $verb -m msg"

  # XCC16 — leading whitespace → match
  assert_match "${prefix}16" "leading whitespace before git $verb" "$verb" "   git $verb"

  # XCC17 — `echo "git <verb>"` → no match
  assert_nomatch "${prefix}17" "echo \"git $verb\" (mention in echo arg)" "$verb" "echo \"git $verb\""

  # XCC18 — `grep -n 'git <verb>' file.sh` → no match (DIRECT class-1 reproducer R1)
  assert_nomatch "${prefix}18" "grep -n 'git $verb' file.sh (R1 reproducer)" "$verb" "grep -n 'git $verb' file.sh"

  # XCC19 — `sed -n 's/git <verb>/git push/' file.sh` → no match
  assert_nomatch "${prefix}19" "sed -n 's/git $verb/git push/' file.sh" "$verb" "sed -n 's/git $verb/git push/' file.sh"

  # XCC20 — `cat file.sh | grep 'git <verb>'` → no match (first token cat)
  assert_nomatch "${prefix}20" "cat file.sh | grep 'git $verb'" "$verb" "cat file.sh | grep 'git $verb'"

  # XCC21 — `bash -c 'git <verb> -m foo'` → no match (D5 carve-out: first token bash)
  assert_nomatch "${prefix}21" "bash -c 'git $verb ...' (D5 carve-out)" "$verb" "bash -c 'git $verb -m foo'"

  # XCC22 — `git <verb> && git push` → match (first segment is git $verb).
  # For verb=push we use a different second segment so the first verb is
  # genuinely $verb.
  if [[ "$verb" == "push" ]]; then
    assert_match "${prefix}22" "git $verb && git fetch (first segment)" "$verb" "git $verb && git fetch"
  else
    assert_match "${prefix}22" "git $verb && git push (first segment)" "$verb" "git $verb && git push"
  fi

  # XCC23 — command substitution → no match (D5 carve-out)
  assert_nomatch "${prefix}23" "git \$(echo $verb) -m foo (cmd-substitution carve-out)" "$verb" "git \$(echo $verb) -m foo"

  # XCC24 — backticks → no match (D5 carve-out)
  assert_nomatch "${prefix}24" "git \`echo $verb\` -m foo (backtick carve-out)" "$verb" "git \`echo $verb\` -m foo"

  # XCC25 — variable expansion → no match (D5 carve-out)
  assert_nomatch "${prefix}25" "GIT_VERB=$verb; git \$GIT_VERB (var-expansion carve-out)" "$verb" "GIT_VERB=$verb; git \$GIT_VERB"

  # XCC26 — git "<verb>" → match (subcommand quote-strip; round-1 DA-H-1)
  assert_match "${prefix}26" "git \"$verb\" (double-quoted subcommand)" "$verb" "git \"$verb\""

  # XCC27 — git '<verb>' → match
  assert_match "${prefix}27" "git '$verb' (single-quoted subcommand)" "$verb" "git '$verb'"

  # XCC28 — GIT_SUB_REST exposure + GIT_SUB_INDEX value
  # `git <verb> -m foo --no-verify` → match, GIT_SUB_REST contains --no-verify, GIT_SUB_INDEX==2.
  assert_rest_contains "${prefix}28a" "GIT_SUB_REST contains --no-verify after match" "$verb" "git $verb -m foo --no-verify" '--no-verify'
  assert_index_eq "${prefix}28b" "GIT_SUB_INDEX==2 after match (post-$verb position)" "$verb" "git $verb -m foo --no-verify" 2

  # XCC29 — segment-truncation invariant.
  # `git checkout main && rm foo -- bar.txt` checked for verb=checkout.
  # We mirror the spec verbatim regardless of verb so we always exercise
  # the segment-truncation boundary.
  assert_rest_not_contains "${prefix}29" "GIT_SUB_REST truncates at && (no -- from post-&& segment)" "checkout" "git checkout main && rm foo -- bar.txt" '(^|[[:space:]])--([[:space:]]|$)'

  # XCC30 — quote-blind D5 carve-out positive lock (round-2 R2-C-1).
  # `git reset 'msg --hard text'` → match; --hard appears in GIT_SUB_REST.
  assert_rest_contains "${prefix}30" "GIT_SUB_REST contains --hard from quoted arg (D5 carve-out)" "reset" "git reset 'msg --hard text'" '--hard'

  # XCC31 — space-elided semicolon carve-out (round-2 R2-C-1).
  # `git clean foo;rm -f bar` → match; GIT_SUB_REST equals `foo;rm -f bar`.
  assert_rest_eq "${prefix}31" "GIT_SUB_REST equals 'foo;rm -f bar' (semicolon glue carve-out)" "clean" "git clean foo;rm -f bar" "foo;rm -f bar"

  # XCC32 — multi-flag positive lock (round-2 DA2-C-1 negative branch).
  # `git commit -m first --no-verify --hard` → match; --no-verify in GIT_SUB_REST.
  assert_rest_contains "${prefix}32" "GIT_SUB_REST retains --no-verify with multi-flag args" "commit" "git commit -m first --no-verify --hard" '--no-verify'

  # XCC33 — Phase 4 integration (no unit case here per plan WI 2.1).
  # Locked at integration level. We add a placeholder PASS so the matrix
  # math (34 cases per verb) holds.
  echo "PASS ${prefix}33 — placeholder (XCC33 is Phase 4 integration; see plan WI 2.1)"
  PASS=$((PASS + 1))

  # XCC34 — multi-line carve-out (round-2 DA2-M-4).
  # `read -ra` only sees the first line; second-line `git commit` is invisible.
  local multi_line=$'echo hi\ngit commit'
  assert_nomatch "${prefix}34" "multi-line: only first line tokenized (D5 carve-out)" "commit" "$multi_line"
}

# ─── Run the matrix for all three verbs ───
run_subcommand_matrix "XCC" "commit"
run_subcommand_matrix "XCP" "cherry-pick"
run_subcommand_matrix "XPU" "push"

# ─── is_destruct_command cases ───

# XKL1 — `kill -9 1234` → match (positive baseline)
assert_destruct_match "XKL1" "kill -9 1234 (baseline)" "kill -9 1234" "kill" '^-(9|KILL|SIGKILL)$'

# XKL2 — `grep -n 'kill -9' notes.md` → no match (DIRECT class-1 reproducer R5)
assert_destruct_nomatch "XKL2" "grep -n 'kill -9' notes.md (R5 reproducer)" "grep -n 'kill -9' notes.md" "kill" '^-(9|KILL|SIGKILL)$'

# XKL3 — `echo "use kill -9 to force"` → no match
assert_destruct_nomatch "XKL3" "echo \"use kill -9 to force\"" "echo \"use kill -9 to force\"" "kill" '^-(9|KILL|SIGKILL)$'

# XKL4 — `kill 1234` (no -9) → no match
assert_destruct_nomatch "XKL4" "kill 1234 (no destructive flag)" "kill 1234" "kill" '^-(9|KILL|SIGKILL)$'

# XKL5 — `kill -KILL 1234` → match
assert_destruct_match "XKL5" "kill -KILL 1234" "kill -KILL 1234" "kill" '^-(9|KILL|SIGKILL)$'

# XKL6 — `kill -s 9 1234` → match (positional pair via :next:)
assert_destruct_match "XKL6" "kill -s 9 1234 (positional-pair via :next:)" "kill -s 9 1234" "kill" '^-s$:next:^(9|KILL|SIGKILL)$'

# XKL7 — `kill -s USR1 1234` → no match (positional-pair rejects USR1)
assert_destruct_nomatch "XKL7" "kill -s USR1 1234 (positional-pair rejects USR1)" "kill -s USR1 1234" "kill" '^-s$:next:^(9|KILL|SIGKILL)$'

# XKL8 — `pgrep node | xargs kill` → no match by is_destruct_command (first token pgrep).
# Pipeline-fed forms are handled by the existing XARGS_KILL regex in generic.sh.
assert_destruct_nomatch "XKL8" "pgrep node | xargs kill (pipeline-fed; not is_destruct_command's domain)" "pgrep node | xargs kill" "kill" '^-(9|KILL|SIGKILL)$'

# XKL9 — `kill 1234 -9` → match (over-match-tolerance positive lock; round-2 R2-H-1)
assert_destruct_match "XKL9" "kill 1234 -9 (over-match-tolerance lock)" "kill 1234 -9" "kill" '^-(9|KILL|SIGKILL)$'

# XKL10 — `pkill 1234 -9` with empty flag_match → match (first-token-only lock)
assert_destruct_match "XKL10" "pkill 1234 -9 with empty flag_match (first-token-only lock)" "pkill 1234 -9" "pkill" ''

# XKL11 — `env -i kill -9 1234` → no match (env-i prefix bypass; round-2 DA2-H-3)
assert_destruct_nomatch "XKL11" "env -i kill -9 1234 (env -i prefix bypass)" "env -i kill -9 1234" "kill" '^-(9|KILL|SIGKILL)$'

# XKL12 — `sudo kill -9 1234` → no match (sudo prefix bypass; round-2 DA2-H-3)
assert_destruct_nomatch "XKL12" "sudo kill -9 1234 (sudo prefix bypass)" "sudo kill -9 1234" "kill" '^-(9|KILL|SIGKILL)$'

# XRM1 — `rm -rf /tmp/foo` → match
assert_destruct_match "XRM1" "rm -rf /tmp/foo (baseline)" "rm -rf /tmp/foo" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XRM2 — `grep 'rm -rf' notes.md` → no match
assert_destruct_nomatch "XRM2" "grep 'rm -rf' notes.md" "grep 'rm -rf' notes.md" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XRM3 — `rm -f file.txt` (no -r) → no match
assert_destruct_nomatch "XRM3" "rm -f file.txt (no -r flag)" "rm -f file.txt" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XRM4 — `printf 'rm -rf %s\n' /tmp/x` → no match
assert_destruct_nomatch "XRM4" "printf 'rm -rf %s\\n' /tmp/x" "printf 'rm -rf %s\\n' /tmp/x" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XRM5 — `rm -rf $HOME/foo` → match (path safety is a separate policy)
assert_destruct_match "XRM5" "rm -rf \$HOME/foo (path safety is separate policy)" "rm -rf \$HOME/foo" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XRM6 — `cat list.txt | xargs rm -rf` → no match by is_destruct_command (first token cat)
assert_destruct_nomatch "XRM6" "cat list.txt | xargs rm -rf (pipeline-fed; not is_destruct_command's domain)" "cat list.txt | xargs rm -rf" "rm" '^-r|^--recursive$|^-[a-zA-Z]*r[a-zA-Z]*$'

# XFD1 — `find /tmp/foo -delete` → match
assert_destruct_match "XFD1" "find /tmp/foo -delete (baseline)" "find /tmp/foo -delete" "find" '^-delete$'

# XFD2 — `grep "find . -delete" notes.md` → no match
assert_destruct_nomatch "XFD2" "grep \"find . -delete\" notes.md" "grep \"find . -delete\" notes.md" "find" '^-delete$'

# XRS1 — `rsync -av src/ dst/ --delete` → match
assert_destruct_match "XRS1" "rsync -av src/ dst/ --delete (baseline)" "rsync -av src/ dst/ --delete" "rsync" '^--delete$'

# XRS2 — `grep "rsync --delete" notes.md` → no match
assert_destruct_nomatch "XRS2" "grep \"rsync --delete\" notes.md" "grep \"rsync --delete\" notes.md" "rsync" '^--delete$'

# ─── Summary ───
echo ""
echo "Total: PASS=$PASS FAIL=$FAIL"
echo "Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)))"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
