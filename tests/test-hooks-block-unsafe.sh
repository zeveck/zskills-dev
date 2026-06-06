#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Generic hook (block-unsafe-generic.sh): deny/allow patterns, push main/master block, config-driven main_protected, fail-closed, non-Bash, edge cases.
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-block-unsafe.sh
#
# SOURCES tests/lib/hooks-harness.sh for all shared helpers and the
# absolutized hook-path globals (HOOK / PROJECT_HOOK / AGENTS_HOOK /
# WARN_HOOK), pass/fail counters, expect_* helpers, the project-hook
# fixture helpers, and setup_project_test_on_main. Emits exactly ONE
# canonical Results: line. Registered in run-all.sh as a run_suite; it
# carries no self-registration assertion (matches the former monolith).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

# shellcheck source=tests/lib/hooks-harness.sh
. "$SCRIPT_DIR/lib/hooks-harness.sh"

echo "=== Hook deny patterns ==="

# 1. git stash drop / clear — destroys stashed work
expect_deny "git stash drop" "git stash drop"
expect_deny "git stash clear" "git stash clear"

# 1b. git stash that CREATES a stash (modifies working tree) — counterfactual
# testing pattern the CLAUDE.md rule bans; concrete past failure was a
# pre-commit reviewer unstaging caller's staged files via stash-pop.
expect_deny "git stash (bare)" "git stash"
expect_deny "git stash -u" "git stash -u"
expect_deny "git stash -u -m msg" "git stash -u -m pre-check-stash"
expect_deny "git stash push -m" "git stash push -m something"
expect_deny "git stash save" "git stash save old-style-label"
# Read / recovery operations stay allowed
expect_allow "git stash apply" "git stash apply"
expect_allow "git stash list" "git stash list"
expect_allow "git stash show" "git stash show"
expect_allow "git stash pop" "git stash pop"
# git stash create and store operate on the object db, not the working tree
expect_allow "git stash create" "git stash create"

# 1c. Overmatch-prevention: text that MENTIONS stash but isn't invoking it.
# These broke before command-boundary gating — hook matched on any substring
# containing "git stash" (commit messages, grep args, echo/printf content,
# even the hook's own error message output).
expect_allow "commit msg w/ stash text" "git commit -m msg-about-git-stash-push"
expect_allow "echo w/ stash text" "echo git-stash-push-blocked"
expect_allow "grep stash in file" "grep stash file.md"
expect_allow "printf w/ stash text" "printf %s git-stash-push"

# 1d. Command-boundary matches: real invocations after shell separators.
expect_deny "&& git stash" "cd foo && git stash"
expect_deny "; git stash" "echo ok; git stash"

# 1e. Path-prefixed git invocations — issue #528. `command -v git` returns
# `/usr/bin/git` on most systems, and scripts capturing `$(command -v git)`
# produce path-prefixed forms. Pre-fix, `is_git_subcommand` compared the
# first token literally to "git" without stripping a path prefix, silently
# bypassing every git-side hook gate. The fix in hooks/_lib/git-tokenwalk.sh
# mirrors the gh variant's path-strip (`case "$g" in */*) g="${g##*/}" ;; esac`).
# Each case below targets a DIFFERENT gate to confirm coverage across the
# whole helper-consuming surface.
expect_deny "/usr/bin/git stash drop (path-prefix #528)"             "/usr/bin/git stash drop"
expect_deny "/usr/local/bin/git checkout -- file (path-prefix #528)" "/usr/local/bin/git checkout -- file.js"
expect_deny "./git reset --hard (relative-path-prefix #528)"         "./git reset --hard HEAD~1"
expect_deny "/usr/bin/git commit --no-verify (path-prefix #528)"     "/usr/bin/git commit --no-verify -m msg"
expect_deny "/usr/bin/git add -A (path-prefix #528)"                 "/usr/bin/git add -A"
# Wrapper + path-prefix: bash -c 'absolute-path git ...' must also gate.
expect_deny "bash -c with /usr/bin/git stash (wrapper + path-prefix #528)" "bash -c '/usr/bin/git stash'"

# 2. git checkout -- file  (file-separator form — discards working tree changes)
# The `--` must be scoped to the file-list separator: `--` followed by
# whitespace (then paths) or end-of-command. Without that anchor, the
# regex false-positives on ANY long flag whose value starts with `--`
# (--quiet, --force, --orphan, etc.). Incident this session: the hook
# blocked `git checkout --quiet main` during Gate A re-run.
expect_deny  "git checkout -- file"             "git checkout -- file.js"
expect_deny  "git checkout -- . (blanket)"      "git checkout -- ."
expect_deny  "git checkout -- multiple files"   "git checkout -- a.js b.js"
expect_deny  "git checkout HEAD~1 -- file"      "git checkout HEAD~1 -- file.js"
expect_deny  "git checkout -- (bare, no path)"  "git checkout --"
# Long flags starting with -- must NOT be caught by the file-separator rule.
expect_allow "git checkout --quiet main"        "git checkout --quiet main"
expect_allow "git checkout --force main"        "git checkout --force main"
expect_allow "git checkout --orphan newbranch"  "git checkout --orphan newbranch"
expect_allow "git checkout --theirs file.js"    "git checkout --theirs file.js"
expect_allow "git checkout --ours file.js"      "git checkout --ours file.js"
expect_allow "git checkout --detach HEAD~1"     "git checkout --detach HEAD~1"
expect_allow "git checkout -b feat/foo"         "git checkout -b feat/foo"

# 3. git restore file
expect_deny "git restore file" "git restore file.js"

# 3a. git switch with destructive flags (modern analog of `git checkout --`).
# #478: discard-changes / -f / --force destroy unstaged work; plain switch
# and `-c` (create-new-branch) remain allowed because git refuses on dirty
# tree without the opt-in flag.
expect_deny  "git switch --discard-changes"       "git switch --discard-changes my-branch"
expect_deny  "git switch -f"                      "git switch -f main"
expect_deny  "git switch --force"                 "git switch --force feat/x"
expect_allow "git switch <branch> (plain)"        "git switch main"
expect_allow "git switch -c new-branch"           "git switch -c new-branch"
# Defense-in-depth: wrapper-aware match via is_git_subcommand_in_wrappers
expect_deny  "WB-switch: bash -c 'git switch -f'" "bash -c 'git switch -f main'"

# 4. git clean -fd
expect_deny "git clean -fd" "git clean -fd"

# 5. git reset --hard
expect_deny "git reset --hard" "git reset --hard"

# 6. kill -9 / killall / pkill
expect_deny "kill -9 1234" "kill -9 1234"
expect_deny "killall node" "killall node"
expect_deny "pkill node" "pkill node"

# 7. fuser -k
expect_deny "fuser -k 8080" "fuser -k 8080"

# 7-prefix. Transparent command-prefix wrappers on destruct verbs — issue
# #567. Mirrors the git-side prefix-skip extension; `is_destruct_command`
# gained the same skip block. Without it, an agent reaching for
# `nohup killall node` (e.g., to detach the kill) or `timeout 30 killall …`
# (after a previous kill hung) bypasses the destruct gate. The 4+ cases
# below cover each destruct verb gated through is_destruct_command{,_in_chain}.
expect_deny "nohup kill -9 1234 (prefix #567)"          "nohup kill -9 1234"
expect_deny "timeout 30 killall node (prefix #567)"     "timeout 30 killall node"
expect_deny "command pkill node (prefix #567)"          "command pkill node"
expect_deny "nice kill -9 1234 (prefix #567)"           "nice kill -9 1234"
# Allow control: a non-destructive command under the same prefix must
# not over-match.
expect_allow "nohup echo killing (non-destruct prefix-only — #567)" "nohup echo killing"

# 7-pathstrip. Path-prefixed destruct verbs — issue #572. Sister of #528
# (which added the path-strip to is_git_subcommand). is_destruct_command
# gained the same `case "$first" in */*) first="${first##*/}" ;; esac`
# block after the prefix-skip loop. Without it, an agent reaching for
# `command -v kill` (which prints /usr/bin/kill) followed by execution of
# the absolute path silently bypasses the destruct gate that CLAUDE.md
# treats as load-bearing. Matrix: each destruct verb × bare-path,
# prefix+path (combines #567 SKIP + path-strip), and wrapper-recursion.
expect_deny "/usr/bin/kill -9 1234 (path-strip #572)"               "/usr/bin/kill -9 1234"
expect_deny "/usr/bin/killall node (path-strip #572)"               "/usr/bin/killall node"
expect_deny "/usr/bin/pkill node (path-strip #572)"                 "/usr/bin/pkill node"
expect_deny "/usr/local/bin/pkill foo (path-strip #572)"            "/usr/local/bin/pkill foo"
expect_deny "nohup /usr/bin/kill -9 1234 (#567 + #572)"             "nohup /usr/bin/kill -9 1234"
expect_deny "timeout 30 /usr/bin/killall node (#567 + #572)"        "timeout 30 /usr/bin/killall node"
expect_deny "cd /tmp && /usr/bin/killall node (chain + #572)"       "cd /tmp && /usr/bin/killall node"
expect_deny "echo a && /usr/bin/pkill node (chain + #572)"          "echo a && /usr/bin/pkill node"
# Allow control: a non-destructive path-prefixed binary must not over-match.
expect_allow "/bin/echo killing (path-strip negative — #572)"       "/bin/echo killing"

# 7c. Wrapper-bypass closure for the destruct gate (#586) — sister of #399's
# git-side closure. Pre-fix, `bash -c '/usr/bin/kill -9 …'`, `eval 'killall
# …'`, `sh -c 'pkill …'` and friends tokenized as `bash`/`sh`/`eval` at the
# top level and slipped past is_destruct_command_in_chain even after #572
# added path-strip. is_destruct_command_in_wrappers iterates wrapper bodies
# and re-applies the chain helper. Property matrix:
#   {bash -c, sh -c, eval, command, exec} × {kill -9, killall, pkill, rm -rf}
#   × {bare, /usr/bin/-prefixed}. (`rm -rf` is gated by RM_RECURSIVE regex,
#   not the destruct helper, so wrapper-quoted `rm -rf` is covered by that
#   regex's substring match — included here for cross-coverage attestation.)
#   `command` / `exec` are command-prefix wrappers handled by the
#   transparent-prefix skip in is_destruct_command (#567), not the
#   wrappers helper — included to attest both paths still gate.
expect_deny "WD1: bash -c 'kill -9 1234'"                    "bash -c 'kill -9 1234'"
expect_deny "WD2: bash -c '/usr/bin/kill -9 1234'"           "bash -c '/usr/bin/kill -9 1234'"
expect_deny "WD3: eval 'killall node'"                       "eval 'killall node'"
expect_deny "WD4: eval '/usr/bin/killall node'"              "eval '/usr/bin/killall node'"
expect_deny "WD5: sh -c 'pkill foo'"                         "sh -c 'pkill foo'"
expect_deny "WD6: sh -c '/usr/bin/pkill foo'"                "sh -c '/usr/bin/pkill foo'"
expect_deny "WD7: bash -c \"killall node\" (double-quoted)"  "bash -c \\\"killall node\\\""
expect_deny "WD8: bash -c 'kill -s 9 1234'"                  "bash -c 'kill -s 9 1234'"
# Command-prefix wrappers (transparent skip path #567, not the wrappers
# helper). Both gates must still fire.
expect_deny "WD9: command kill -9 1234 (prefix path)"        "command kill -9 1234"
expect_deny "WD10: exec /usr/bin/killall node (prefix path)" "exec /usr/bin/killall node"
# Nested wrapper (depth=2 — recursion budget is 3 by default).
expect_deny "WD11: bash -c \"sh -c 'kill -9 1234'\" (nested)" \
  "bash -c \\\"sh -c 'kill -9 1234'\\\""
# Allow control: wrapper around a non-destructive command must not over-match.
expect_allow "WD12: bash -c 'echo killall' (wrapper allow ctrl)" \
  "bash -c 'echo killall'"

# WHS1-WHS12. Here-string / heredoc-to-INTERPRETER bypass closure (#772) —
# sibling of the #399/#597 `bash -c` / `eval` / `sh -c` wrapper closure.
# When the heredoc / here-string is the STDIN of an interpreter
# (bash|sh|zsh|dash|ash|ksh, optionally `-s`), the body is EXECUTED, so a
# destructive command smuggled that way must reach the deny scan. The
# pre-scan re-injection step in block-unsafe-generic.sh extracts the body
# and appends it as a `;`-segment for the existing wrapper/chain scanners.
#
# CRITICAL discriminator (no-false-positive guard): re-inject ONLY when
# the segment head is an interpreter reading stdin as a script (flags-only
# between interpreter and `<<<`/`<<`, no script-file positional). DATA
# heredocs (cat/echo/tee/--body-file, and `bash script.sh <<<data` where
# the here-string is stdin for the script) must STILL be stripped inert.
# Sanity: each WHS DENY case ALLOWs against pre-#772 hook (proving the
# assertion exercises the new logic), verified manually during the fix.

# --- DENY: interpreter-stdin here-strings (the reported bug) ---
expect_deny "WHS1: bash <<<\"git clean -fdx\"" \
  "bash <<<\\\"git clean -fdx\\\""
expect_deny "WHS2: bash <<<'git clean -fdx' (single-quoted body)" \
  "bash <<<'git clean -fdx'"
expect_deny "WHS3: sh <<<\"git reset --hard HEAD~5\"" \
  "sh <<<\\\"git reset --hard HEAD~5\\\""
expect_deny "WHS4: zsh <<<\"git checkout -- .\"" \
  "zsh <<<\\\"git checkout -- .\\\""
expect_deny "WHS5: bash -s <<<\"git clean -fdx\" (-s flag)" \
  "bash -s <<<\\\"git clean -fdx\\\""
expect_deny "WHS6: bash <<<\"kill -9 1234\" (destruct verb)" \
  "bash <<<\\\"kill -9 1234\\\""
expect_deny "WHS7: cd /tmp && bash <<<\"git clean -fdx\" (cd-chain)" \
  "cd /tmp && bash <<<\\\"git clean -fdx\\\""

# --- DENY: interpreter-stdin heredocs ---
expect_deny "WHS8: bash <<EOF git clean -fdx EOF (heredoc to bash)" \
  "bash <<EOF\\ngit clean -fdx\\nEOF"
expect_deny "WHS9: sh <<EOF rm -rf /etc EOF (heredoc to sh)" \
  "sh <<EOF\\nrm -rf /etc\\nEOF"
expect_deny "WHS10: bash <<'EOF' git reset --hard EOF (quoted-delim)" \
  "bash <<'EOF'\\ngit reset --hard HEAD~5\\nEOF"

# --- ALLOW: DATA heredocs / here-strings (no false-positives) ---
# The discriminator must keep these inert: head is NOT an interpreter
# reading stdin as code (cat/echo/tee/gh body), OR there is a script-file
# positional so the body is stdin DATA for that script.
expect_allow "WHS-A1: cat <<EOF data heredoc mentioning git clean -f" \
  "cat <<EOF\\ngit clean -fdx is dangerous\\nEOF"
expect_allow "WHS-A2: echo <<<\"git clean -fdx\" (echo, not interpreter)" \
  "echo <<<\\\"git clean -fdx\\\""
expect_allow "WHS-A3: tee f.txt <<EOF rm -rf /etc EOF (data to tee)" \
  "tee f.txt <<EOF\\nrm -rf /etc\\nEOF"
expect_allow "WHS-A4: gh pr create --body-file=- <<EOF mentions git clean -f" \
  "gh pr create --body-file=- <<EOF\\nnote: git clean -f purges untracked\\nEOF"
expect_allow "WHS-A5: bash script.sh <<<data (here-string is DATA for script)" \
  "bash script.sh <<<\\\"git clean -fdx\\\""
expect_allow "WHS-A6: bash run.sh <<EOF (heredoc is DATA for script)" \
  "bash run.sh <<EOF\\nrm -rf /etc\\nEOF"
expect_allow "WHS-A7: bash <<<\"echo git clean -fdx\" (interpreter runs benign echo)" \
  "bash <<<\\\"echo git clean -fdx\\\""

# WHS13-WHS20. Absolute-path + long-flag interpreter here-string/heredoc
# bypass closure (#789) — closure-incomplete on #772. The #772 head regex
# matched only a BARE interpreter token with single-dash short flags, so
# `/bin/bash <<<…` (absolute path — the left boundary excluded `/`),
# `bash --norc <<<…` (long flag broke the flag run), and
# `bash -eo pipefail <<<…` (option-argument looked like a positional) all
# slipped past the re-injection and Pass-1 stripped the body as inert.
# `/bin/bash` is a completely non-adversarial form, so this defeated the
# destructive-op fence for git reset --hard / rm -rf / git clean -fdx.
#
# The #789 head_re broadening adds an optional path prefix, accepts --long
# flags, and consumes option-argument words after -o/--rcfile/--init-file
# while STILL terminating the flag run at a free non-flag (script-file)
# positional — so `bash script.sh <<<data` stays inert DATA.
# Sanity: each WHS13+ DENY case ALLOWs against the pre-#789 hook (proving
# the assertion exercises the broadened regex), verified manually.

# --- DENY: absolute / relative interpreter PATH (#789) ---
expect_deny "WHS13: /bin/bash <<<\"git reset --hard\" (absolute path)" \
  "/bin/bash <<<\\\"git reset --hard\\\""
expect_deny "WHS14: /usr/bin/bash <<<\"git clean -fdx\" (absolute path)" \
  "/usr/bin/bash <<<\\\"git clean -fdx\\\""
expect_deny "WHS15: cd /tmp && /bin/bash <<<\"git clean -fdx\" (cd-chain, abs path)" \
  "cd /tmp && /bin/bash <<<\\\"git clean -fdx\\\""
# --- DENY: long flags + option-argument before the redirect (#789) ---
expect_deny "WHS16: bash --norc <<<\"git clean -fdx\" (long flag)" \
  "bash --norc <<<\\\"git clean -fdx\\\""
expect_deny "WHS17: bash -eo pipefail <<<\"git reset --hard\" (-o option-arg)" \
  "bash -eo pipefail <<<\\\"git reset --hard\\\""
expect_deny "WHS18: bash -o pipefail <<<\"git clean -fdx\" (-o option-arg)" \
  "bash -o pipefail <<<\\\"git clean -fdx\\\""
# --- DENY: absolute-path heredoc-to-interpreter (#789) ---
expect_deny "WHS19: /bin/bash <<EOF git clean -fdx EOF (abs-path heredoc)" \
  "/bin/bash <<EOF\\ngit clean -fdx\\nEOF"

# --- ALLOW: script-positional still DATA, even with abs-path interpreter (#789) ---
# The broadened head must NOT start denying a script-file positional: the
# here-string/heredoc is stdin DATA for the script, not interpreter code.
expect_allow "WHS20: /bin/bash script.sh <<<data (abs path + script positional)" \
  "/bin/bash script.sh <<<\\\"git clean -fdx\\\""

# 7b. kill-by-port/name anti-pattern — same hazard as fuser -k, different spelling.
# The original incident was 'lsof -ti :8080 | xargs kill' taking out the docker container.
# All spellings must be blocked; only explicit-PID kill and the sanctioned helper are allowed.
expect_deny "lsof -ti | xargs kill"        "lsof -ti :8080 | xargs kill"
expect_deny "lsof -ti | xargs kill -TERM"  "lsof -ti :8080 | xargs kill -TERM"
expect_deny "lsof -ti | xargs kill -9"     "lsof -ti :8080 | xargs kill -9"
expect_deny "pgrep -f | xargs kill"        "pgrep -f vite | xargs kill"
expect_deny "pidof | xargs kill"           "pidof node | xargs kill"
expect_deny "ps | awk | xargs kill"        "ps aux | awk '/vite/{print \$2}' | xargs kill"
expect_deny "kill \$(lsof -ti)"            "kill \$(lsof -ti :8080)"
expect_deny "kill \$(pgrep -f)"            "kill \$(pgrep -f vite)"
expect_deny "kill \$(pidof)"               "kill \$(pidof node)"
expect_deny "kill \`lsof -ti\`"            "kill \`lsof -ti :8080\`"
expect_deny "kill -TERM \$(lsof -ti)"      "kill -TERM \$(lsof -ti :8080)"
# 7c. Shell-separator bypasses — kill/lsof/pgrep/pidof followed by ;&| must still be caught.
# Found during adversarial review: the termination class of the kill/tool word must treat
# shell separators as word boundaries, not as extending the match.
expect_deny "xargs kill;extra"                 "lsof -ti :8080 | xargs kill;echo done"
expect_deny "xargs kill&background"            "lsof -ti :8080 | xargs kill&sleep 1"
expect_deny "xargs kill|piped"                 "lsof -ti :8080 | xargs kill|wc -l"
expect_deny "kill \$(lsof|pipe inside subst)"  "kill \$(lsof -ti :8080|head -1)"
expect_deny "kill \$(pgrep;extra inside subst)" "kill \$(pgrep -f vite;echo)"
# 7d. netstat added to Rule B (unambiguous tool name, no FP surface).
expect_deny "kill \$(netstat -tnlp | awk)" "kill \$(netstat -tnlp | awk '/8080/{split(\$NF,a,\\\"/\\\"); print a[1]}')"
# 7e. Intentionally-gapped tools (ss, ps) are documented as limitations — they remain
# ALLOWED in Rule B because the short names have high FP risk. These tests lock in scope.
# (The xargs → kill form with the same tools IS still caught by Rule A.)
expect_allow "kill \$(grep ss file.txt) — ss not in list" "kill \$(grep ss file.txt)"
expect_allow "kill \$(ps -eo pid) — ps not in list" "kill \$(ps -eo pid)"
# But the xargs-pipeline spelling of the same family IS caught (regression for Rule A):
expect_deny "ss -ltnp | awk | xargs kill"  "ss -ltnp | awk '{print \$NF}' | xargs kill"
expect_deny "ps aux | awk | xargs kill"    "ps aux | awk '/vite/{print \$2}' | xargs kill"

# 7f. `git commit -m \"...\"` message bodies are redacted before scan, so prose
# mentioning banned patterns no longer false-positives. Chained commands AFTER
# the commit must still be visible to the rules. (Discovered when committing
# the helper change itself — the hook blocked its own commit message.)
expect_allow "commit -m \"...kill -9...\" double-quoted"   "git commit -m \"feat: doc kill -9 incident\""
expect_allow "commit -m \"...fuser -k...\" double-quoted"  "git commit -m \"docs: avoid fuser -k\""
expect_allow "commit -m \"...xargs kill...\" double-quoted" "git commit -m \"fix: don't reach for xargs kill\""
expect_allow "commit -m '...kill -9...' single-quoted"   "git commit -m 'feat: doc kill -9 incident'"
expect_allow "commit -m '...killall...' single-quoted"   "git commit -m 'docs: killall is forbidden'"
expect_allow "commit -am '...pkill...' (combined flag)"  "git commit -am \"chore: pkill notes\""
expect_allow "commit --signoff -m with banned words"     "git commit --signoff -m \"feat: lsof -ti | xargs kill\""
# Chained dangerous commands AFTER a clean commit must still be denied.
expect_deny  "commit then chained kill -9"               "git commit -m \"msg\" && kill -9 1234"
expect_deny  "commit then chained fuser -k"              "git commit -m \"msg\" ; fuser -k 8080"
expect_deny  "commit then chained xargs kill"            "git commit -m \"msg\" && lsof -ti :8080 | xargs kill"

# 7g. Heredoc bodies are redacted before the scan (the canonical commit
# idiom uses `-m "$(cat <<'EOF' ... EOF)"`, so prose describing destructive
# ops inside the heredoc no longer false-positives). Chained ops AFTER
# the heredoc remain visible — the closing delimiter bounds the redaction.
expect_allow "heredoc (<<'EOF') in commit w/ find -delete prose" \
  "git commit -m \"\$(cat <<'EOF'\\nfix(hook): match find -delete in data regions\\nEOF\\n)\""
expect_allow "heredoc (<<EOF unquoted) in commit w/ rm -rf prose" \
  "git commit -m \"\$(cat <<EOF\\ndocs: warn against rm -rf outside /tmp\\nEOF\\n)\""
expect_allow "heredoc (<<\"EOF\" dbl-q) in commit w/ rsync --delete prose" \
  "git commit -m \"\$(cat <<\"EOF\"\\nchore: note rsync --delete edge case\\nEOF\\n)\""
expect_allow "heredoc with custom delim (MSGEND)" \
  "git commit -m \"\$(cat <<'MSGEND'\\nkill -9 notes and xargs rm tips\\nMSGEND\\n)\""
# Chained dangerous command AFTER the heredoc closes must still deny.
expect_deny  "heredoc commit then chained rm -rf /etc" \
  "git commit -m \"\$(cat <<'EOF'\\nmsg\\nEOF\\n)\" && rm -rf /etc"
expect_deny  "heredoc commit then chained find / -delete" \
  "git commit -m \"\$(cat <<'EOF'\\nmsg\\nEOF\\n)\" ; find / -delete"

# 7h. `git commit --message` (long-form alias) redacted like -m.
expect_allow "commit --message w/ banned prose" \
  "git commit --message \"fix: xargs rm behavior in scripts\""

# 7i. `gh pr|issue create|comment` with --body|-b|--title|-t values
# carry prose and must be redacted. Per-argument scope: chained
# dangerous ops after the flag still get flagged.
expect_allow "gh pr create --body w/ find -delete prose" \
  "gh pr create --body \"body describing find -delete edge case\""
expect_allow "gh pr create --title w/ rm -rf prose" \
  "gh pr create --title \"fix: avoid rm -rf in hook\""
expect_allow "gh pr create -b short flag" \
  "gh pr create -b \"body w/ xargs rm reference\""
expect_allow "gh pr create -t short flag" \
  "gh pr create -t \"title w/ kill -9 reference\""
expect_allow "gh pr create both --title AND --body (loop test)" \
  "gh pr create --title \"fuser -k notes\" --body \"lsof -ti xargs kill tips\""
expect_allow "gh pr comment --body w/ xargs rm prose" \
  "gh pr comment 42 --body \"see the xargs rm thread\""
expect_allow "gh issue create --title w/ rsync --delete prose" \
  "gh issue create --title \"rsync --delete edge case\""
expect_allow "gh issue create --body heredoc w/ banned prose" \
  "gh issue create --body \"\$(cat <<EOF\\nreport: find . -delete surprise\\nEOF\\n)\""
expect_allow "gh issue comment --body w/ find -delete prose" \
  "gh issue comment 99 --body \"tracked under the find -delete issue\""

# Chained dangerous ops AFTER a redacted gh arg must still be denied.
expect_deny  "gh pr create --body then rm -rf /etc" \
  "gh pr create --body \"clean body\" && rm -rf /etc"
expect_deny  "gh pr comment --body then find / -delete" \
  "gh pr comment 1 --body \"discussion\" ; find / -delete"

# Regression: bare destructive ops (no wrapping arg) still denied.
expect_deny  "rm -rf /etc bare (regression)"  "rm -rf /etc"
expect_deny  "find / -delete bare (regression)" "find / -delete"
expect_deny  "lsof xargs kill bare (regression)" "lsof -ti :8080 | xargs kill"

# 8. Destructive-op scope policy: permit contained /tmp/ destruction, block wide
# Rule: rm -r{,f} / find -delete / rsync --delete / xargs rm require a literal
# /tmp/<name> path AND no shell metachars ($, `, *, ?, ~).

# SAFE (contained /tmp/ path, literal, no expansions)
expect_allow "rm -rf /tmp/foo (safe)" "rm -rf /tmp/foo"
expect_allow "rm -r /tmp/zskills-tests/specific" "rm -r /tmp/zskills-tests/specific"
expect_allow "find /tmp/foo -mindepth 1 -delete" "find /tmp/foo -mindepth 1 -delete"
expect_allow "find /tmp/e2e -name '*.log' -delete" "find /tmp/e2e -name phase-1 -delete"
expect_allow "rsync --delete to /tmp/" "rsync -a --delete /dev/null/ /tmp/foo/"

# UNSAFE: wide scope / unintended expansion risk
expect_deny "rm -rf / (root)" "rm -rf /"
expect_deny "rm -rf \$HOME (var)" "rm -rf \$HOME"
expect_deny "rm -rf \$WORKTREE (var)" "rm -rf \$WORKTREE_PATH"
expect_deny "rm -rf /tmp/\$VAR (var in /tmp)" "rm -rf /tmp/\$VAR"
expect_deny "rm -rf /tmp/foo* (wildcard)" "rm -rf /tmp/foo*"
expect_deny "rm -rf /home/user/foo (outside /tmp)" "rm -rf /home/user/foo"
expect_deny "rm -rf ~/foo (HOME tilde)" "rm -rf ~/foo"
expect_deny "rm -r . (relative)" "rm -r ."
expect_deny "rm -rf /tmp (bare /tmp, no subpath)" "rm -rf /tmp"
expect_deny "find / -delete (root)" "find / -delete"
expect_deny "find \$HOME -delete (var)" "find \$HOME -delete"
expect_deny "rsync --delete outside /tmp" "rsync -a --delete /dev/null/ /foo/"
expect_deny "xargs rm outside /tmp" "find . -name foo | xargs rm"

# Non-recursive rm stays allowed (single file, not wide)
expect_allow "rm single file" "rm some-file.txt"
expect_allow "rm -f single file" "rm -f some-file.txt"

# 9. git add . / -A / --all
expect_deny "git add ." "git add . "
expect_deny "git add -A" "git add -A"
expect_deny "git add --all" "git add --all"

# 10. git commit --no-verify
expect_deny "git commit --no-verify" "git commit --no-verify -m \"msg\""

# 10a-10g. Wrapper-bypass closure (#399): bash -c / eval / sh -c forms of
# blocked git invocations now also DENY. Cross-cutting positive tests over
# the three generic-hook gates (commit --no-verify, add -A, push to main).
expect_deny "WB1: bash -c 'git commit --no-verify'" \
  "bash -c 'git commit --no-verify -m hi'"
expect_deny "WB2: eval 'git commit --no-verify'" \
  "eval 'git commit --no-verify -m hi'"
expect_deny "WB3: bash -c 'cd /tmp/x && git commit --no-verify'" \
  "bash -c 'cd /tmp/x && git commit --no-verify -m hi'"
expect_deny "WB4: bash -c \"git add -A\"" \
  "bash -c \\\"git add -A\\\""
expect_deny "WB5: eval 'git add .'" \
  "eval 'git add .'"
expect_deny "WB6: sh -c 'git commit --no-verify'" \
  "sh -c 'git commit --no-verify -m hi'"
expect_deny "WB7: nested bash -c 'sh -c \"git commit --no-verify\"'" \
  "bash -c 'sh -c \\\"git commit --no-verify -m hi\\\"'"

# WB8-WB16. Wrapper-bypass closure for the 4 destructive-op gates + stash
# (#426, completes #399). PR #417 threaded is_git_subcommand_in_wrappers
# through commit/cherry-pick/push/add but left the 4 destructive-op gates
# (checkout --, restore, clean -f, reset --hard) and STASH_BOUNDARY on the
# original _in_chain tokenizer / first-token regex. Wrapper forms like
# `bash -c 'git reset --hard HEAD~5'` slipped past and silently destroyed
# uncommitted state.
expect_deny "WB8: bash -c 'git reset --hard'" \
  "bash -c 'git reset --hard HEAD~5'"
expect_deny "WB9: eval 'git clean -fd'" \
  "eval 'git clean -fd'"
expect_deny "WB10: sh -c 'git checkout -- file'" \
  "sh -c 'git checkout -- file.js'"
expect_deny "WB11: bash -c 'git restore file'" \
  "bash -c 'git restore file.js'"
expect_deny "WB12: bash -c 'git stash drop'" \
  "bash -c 'git stash drop'"
expect_deny "WB13: eval 'git stash clear'" \
  "eval 'git stash clear'"
expect_deny "WB14: sh -c 'git stash push -u'" \
  "sh -c 'git stash push -u'"
expect_deny "WB15: bash -c 'git stash' (bare create-stash)" \
  "bash -c 'git stash'"
# Wrapper-aware stash gate must still ALLOW the read/recovery subcommands.
expect_allow "WB16: bash -c 'git stash list' (allowed read)" \
  "bash -c 'git stash list'"

echo ""
echo "=== Hook allow patterns ==="

expect_allow "git status" "git status"
expect_allow "git log --oneline" "git log --oneline"
expect_allow "git add file.js" "git add file.js"
expect_allow "git commit -m msg" "git commit -m \"msg\""
# (bare git stash moved to deny list — see above)
expect_allow "rm file.js (no -rf)" "rm file.js"
expect_allow "kill 1234 (no -9)" "kill 1234"
expect_allow "kill -TERM 1234 (SIGTERM allowed)" "kill -TERM 1234"
expect_allow "bash scripts/stop-dev.sh (sanctioned SIGTERM helper)" "bash scripts/stop-dev.sh"
# kill with a pid from a file is the canonical supervised-stop pattern — must stay allowed.
expect_allow "kill \$(cat pidfile)" "kill \$(cat var/dev.pid)"
# xargs for non-kill purposes must not be caught by the xargs-kill rule.
expect_allow "xargs git blame (non-kill)" "git log --format=%H | xargs git blame"
expect_allow "xargs echo (non-kill)" "echo foo | xargs echo"

echo ""
echo "=== Push: block main/master ==="

# Bare push (no remote/refspec) — the hook falls back to `git branch --show-current`.
# Test BOTH branch states to prove the fallback actually differentiates:
# - On main: BLOCK (agents shouldn't push main)
# - On feature branch: ALLOW (feature branches are fine)
# The outer env's branch state is unreliable (CI runs on PR branches), so each
# test creates a controlled temp git repo.
bare_push_test() {
  local label="$1" branch="$2" expected="$3"
  local tmp
  tmp=$(mktemp -d)
  (cd "$tmp" && git init -q -b "$branch" 2>/dev/null \
    || (cd "$tmp" && git init -q && git checkout -b "$branch" 2>/dev/null))
  local result
  result=$(cd "$tmp" && echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | bash "$HOOK")
  rm -rf "$tmp"
  if [ "$expected" = "deny" ]; then
    if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected deny, got: $result"
    fi
  else
    if [[ "$result" != *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected allow, got: $result"
    fi
  fi
}

bare_push_test "deny: git push (bare, on main)" "main" "deny"
bare_push_test "deny: git push (bare, on master)" "master" "deny"
bare_push_test "allow: git push (bare, on feature branch)" "feat/test" "allow"

# Explicit target tests — don't depend on current branch (parser extracts target)
expect_deny "git push origin main" "git push origin main"
expect_deny "git push -u origin main" "git push -u origin main"

# Path-prefixed push to main — issue #528. Same family as #515 (HEAD bypass);
# pre-fix the first-token literal "git" check let path-prefixed forms slip
# through every git-side gate including BLOCK_MAIN_PUSH.
expect_deny "/usr/bin/git push origin main (path-prefix #528)" "/usr/bin/git push origin main"
expect_deny "/usr/local/bin/git push -u origin main (path-prefix #528)" "/usr/local/bin/git push -u origin main"

# Transparent command-prefix wrappers — issue #567. `nohup`, `timeout`,
# `command`, `exec`, `nice`, `time` execute the next argv as a separate
# process; they are operationally equivalent to the bare verb. Pre-fix,
# `is_git_subcommand` matched only the first token literally and silently
# bypassed every git-side gate (BLOCK_MAIN_PUSH, --no-verify, add -A,
# cherry-pick, checkout --, restore, reset --hard, clean -f, stash). The
# fix in hooks/_lib/git-tokenwalk.sh mirrors the gh variant's prefix-skip
# at lines 402-447 (issue #279/PR #255). 12 cases cover the prefix axis
# × verb axis; matches the form of the #528 path-prefix matrix above.
expect_deny "nohup git push origin main (prefix #567)"           "nohup git push origin main"
expect_deny "timeout 30 git push origin main (prefix #567)"      "timeout 30 git push origin main"
expect_deny "timeout --foreground 30 git push origin main (prefix-flag #567)" "timeout --foreground 30 git push origin main"
expect_deny "command git push origin main (prefix #567)"         "command git push origin main"
expect_deny "command -p git push origin main (prefix-flag #567)" "command -p git push origin main"
expect_deny "exec git push origin main (prefix #567)"            "exec git push origin main"
expect_deny "nice git push origin main (prefix #567)"            "nice git push origin main"
expect_deny "time git push origin main (prefix #567)"            "time git push origin main"
expect_deny "time -v git push origin main (prefix-flag #567)"    "time -v git push origin main"
expect_deny "nohup -- git push origin main (prefix-EOO #567)"    "nohup -- git push origin main"
# Different gates: --no-verify and add -A under nohup / timeout.
expect_deny "nohup git commit --no-verify (prefix #567)"         "nohup git commit --no-verify -m msg"
expect_deny "timeout 30 git add -A (prefix #567)"                "timeout 30 git add -A"

# Allow control: a non-git command that happens to start with `nohup` or
# `timeout` must NOT trigger any git-side gate (prevent overmatch).
expect_allow "nohup sleep 5 (non-git prefix-only — #567)"        "nohup sleep 5"
expect_allow "timeout 30 echo done (non-git prefix-only — #567)" "timeout 30 echo done"

# Issue #392: <localref>:main refspec — generic hook's BLOCK_MAIN_PUSH path
# must parse the REMOTE side of the colon. Pre-fix ${X%%:*} kept the local
# side ("feat"), so the rule didn't match and the push went through. Post-fix
# ${X##*:} keeps the destination ("main") and the rule fires.
expect_deny "git push origin feat:main (refspec, local:remote — #392)" "git push origin feat:main"
expect_deny "git push origin localbranch:main (refspec — #392)" "git push origin localbranch:main"
expect_deny "git push origin HEAD:main (refspec — regression)" "git push origin HEAD:main"
expect_deny "git push origin :main (deletion attempt — #392)" "git push origin :main"
expect_deny "git push origin abc123:master (sha:master refspec — #392)" "git push origin abc123:master"
expect_deny "git push -u origin feat:main (upstream + refspec — #392)" "git push -u origin feat:main"

# Issue #457: force-prefix refspec (+main) — no colon, leading '+'. Pre-fix
# normalization stripped colon-LHS and quotes but not '+', so PUSH_TARGET
# stayed "+main" and the equality check against literal "main" missed.
expect_deny "git push origin +main (force-prefix — #457)" "git push origin +main"
expect_deny "git push origin +master (force-prefix master — #457)" "git push origin +master"
expect_deny "git push origin +HEAD:main (force-prefix with refspec — #457)" "git push origin +HEAD:main"

# Issue #470: fully-qualified refs/heads/main — Git accepts this as
# equivalent to `main` but pre-fix neither hook stripped the `refs/heads/`
# prefix, so PUSH_TARGET stayed "refs/heads/main" and the equality check
# against literal "main" missed. Strip after the '+' strip so combined
# forms (+refs/heads/main, refs/heads/+main, feat:refs/heads/main) all
# normalize.
expect_deny "git push origin refs/heads/main (fully-qualified — #470)" "git push origin refs/heads/main"
expect_deny "git push origin refs/heads/master (fully-qualified master — #470)" "git push origin refs/heads/master"
expect_deny "git push origin +refs/heads/main (force + fully-qualified — #470)" "git push origin +refs/heads/main"
expect_deny "git push origin feat:refs/heads/main (refspec + fully-qualified — #470)" "git push origin feat:refs/heads/main"

# Issue #1037: `git -C <dir> push ...` (worktree form) — the push-target
# EXTRACTION must be `-C`-aware, mirroring the `-C`-aware subcommand DETECTION
# (is_git_subcommand skips `-C <dir>` at lines ~310-315). Pre-fix the
# extraction used `${COMMAND##*git push}`, which assumes `git` and `push` are
# ADJACENT tokens; for `git -C /tmp/wt push ...` the literal substring
# "git push" never appears, so the strip was a no-op and the positional loop
# misread `-C`'s DIRECTORY argument as the remote and `push` as a refspec —
# garbage PUSH_REMOTE/PUSH_TARGET. Symptom: /land-pr Step 6b's
# `git -C "$WT" push --force-with-lease` self-blocked / mis-targeted in a
# main_protected repo. Post-fix, extraction reuses GIT_SUB_REST (the `-C`-aware
# tokens after `push`), so `git -C <dir> push ...` parses identically to
# `cd <dir> && git push ...`.
#
# (a) SECURITY preserved: the worktree form pushing to main/master must still
# DENY (fail-closed, no config = main_protected default). Pre-fix these
# silently ALLOWED because PUSH_TARGET resolved to the garbage directory token.
expect_deny "git -C /tmp/wt push origin main (worktree form — #1037)" "git -C /tmp/wt push origin main"
expect_deny "git -C /tmp/wt push -u origin main (worktree + upstream — #1037)" "git -C /tmp/wt push -u origin main"
expect_deny "git -C /tmp/wt push --force origin main (worktree + force — #1037)" "git -C /tmp/wt push --force origin main"
expect_deny "git -C /tmp/wt push origin feat:main (worktree + refspec — #1037)" "git -C /tmp/wt push origin feat:main"
expect_deny "git -C /tmp/wt push origin +main (worktree + force-prefix — #1037)" "git -C /tmp/wt push origin +main"
expect_deny "git -C /tmp/wt push origin refs/heads/master (worktree + qualified — #1037)" "git -C /tmp/wt push origin refs/heads/master"
# (b) ALLOWED case: the worktree form pushing a FEATURE branch (the /land-pr
# Step 6b auto-rebase push) must be allowed — identical to the cd-prefixed form.
expect_allow "git -C /tmp/wt push --force-with-lease origin feat/x (worktree — #1037)" "git -C /tmp/wt push --force-with-lease origin feat/x"
expect_allow "git -C /tmp/wt push origin feat/x (worktree — #1037)" "git -C /tmp/wt push origin feat/x"
expect_allow "cd /tmp/wt && git push --force-with-lease origin feat/x (cd form parity — #1037)" "cd /tmp/wt && git push --force-with-lease origin feat/x"

# Issue #1133: the #1037 fix only taught is_git_subcommand's flag-skip loop
# about `-C`/`-c`. Every OTHER multi-arg git GLOBAL flag with a SPACE-separated
# value (`--git-dir <dir>`, `--work-tree <dir>`, `--namespace <ns>`,
# `--exec-path <path>`, `--super-prefix <pfx>`) still fell through as a 1-token
# flag, so its value was read as the subcommand and the push gate never fired —
# a silent bypass of the same class. The `=`-fused form (`--git-dir=DIR`) is a
# single `-`-prefixed token and was always handled correctly; only the
# space-separated form bypassed.
#
# (a) SECURITY: every space-separated multi-arg flag form pushing to main must
# DENY (fail-closed, no config = main_protected default). Pre-fix: silently
# ALLOWED.
expect_deny "git --git-dir /tmp/wt/.git push origin main (space form — #1133)" "git --git-dir /tmp/wt/.git push origin main"
expect_deny "git --work-tree /tmp/wt push origin main (space form — #1133)" "git --work-tree /tmp/wt push origin main"
expect_deny "git --namespace foo push origin main (space form — #1133)" "git --namespace foo push origin main"
expect_deny "git --exec-path /tmp/wt push origin main (space form — #1133)" "git --exec-path /tmp/wt push origin main"
expect_deny "git --super-prefix p/ push origin main (space form — #1133)" "git --super-prefix p/ push origin main"
# The =-fused forms were already denied (single token) — pin that they stay so.
expect_deny "git --git-dir=/tmp/wt/.git push origin main (fused form — #1133)" "git --git-dir=/tmp/wt/.git push origin main"
# (b) ALLOWED: the same flags pushing a FEATURE branch must still ALLOW (the
# value-token consumption must not over-block a legit feature push).
expect_allow "git --git-dir /tmp/wt/.git push origin feat/x (space form — #1133)" "git --git-dir /tmp/wt/.git push origin feat/x"
expect_allow "git --work-tree /tmp/wt push origin feat/x (space form — #1133)" "git --work-tree /tmp/wt push origin feat/x"
expect_allow "git --namespace foo push origin feat/x (space form — #1133)" "git --namespace foo push origin feat/x"

echo ""
echo "=== Push: main-push block reads execution.main_protected from config ==="

# The generic hook no longer carries a static BLOCK_MAIN_PUSH= line spliced
# per-preset. It reads execution.main_protected from
# $REPO_ROOT/.claude/zskills-config.json at runtime (fail closed when the
# config is absent/unparseable). This mirrors the COMMIT and EDIT gates so a
# single config edit changes all three coherently.
#
# `toggle_value` maps to the config:
#   1 → main_protected: true  → block main/master pushes (locked-main-pr / fail-closed posture)
#   0 → main_protected: false → allow main/master pushes (cherry-pick / direct)
# A temp repo holds the config; REPO_ROOT points the hook's resolution at it.
toggle_test() {
  local label="$1" toggle_value="$2" branch="$3" expected="$4" cmd="${5:-git push}"
  local tmp_repo result protected
  tmp_repo=$(mktemp -d)
  (cd "$tmp_repo" && git init -q -b "$branch" 2>/dev/null \
    || (cd "$tmp_repo" && git init -q && git checkout -b "$branch" 2>/dev/null))
  mkdir -p "$tmp_repo/.claude"
  if [ "$toggle_value" = "1" ]; then protected=true; else protected=false; fi
  printf '{"execution": {"main_protected": %s}}\n' "$protected" > "$tmp_repo/.claude/zskills-config.json"
  result=$(cd "$tmp_repo" && echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | REPO_ROOT="$tmp_repo" bash "$HOOK")
  rm -rf "$tmp_repo"
  if [ "$expected" = "deny" ]; then
    if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected deny, got: $result"
    fi
  else
    if [[ "$result" != *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected allow, got: $result"
    fi
  fi
}

toggle_test "main_protected:true still denies git push on main" 1 "main" "deny"
toggle_test "main_protected:false allows git push on main" 0 "main" "allow"
toggle_test "main_protected:false allows git push on master" 0 "master" "allow"
# Explicit refspec under main_protected:false — hook parses PUSH_TARGET from
# args, not from current branch. Branch here is a feature branch to isolate
# refspec parsing.
toggle_test "main_protected:false allows 'git push origin main' (explicit refspec)" 0 "feat/test" "allow" "git push origin main"
toggle_test "main_protected:false allows 'git push -u origin main' (upstream + refspec)" 0 "feat/test" "allow" "git push -u origin main"

# Issue #1037: worktree-form `git -C <dir> push` must resolve the SAME
# PUSH_TARGET as the cd-prefixed form under both config toggles. Proves the
# `-C`-aware extraction (GIT_SUB_REST reuse) is config-coherent: blocked under
# main_protected:true, allowed under main_protected:false — identical to the
# plain form on lines above.
toggle_test "main_protected:true denies 'git -C <dir> push origin main' (worktree — #1037)" 1 "feat/test" "deny" "git -C /tmp/wt push origin main"
toggle_test "main_protected:false allows 'git -C <dir> push origin main' (worktree — #1037)" 0 "feat/test" "allow" "git -C /tmp/wt push origin main"

# Issue #515: `git push origin HEAD` from a `main` checkout resolves
# server-side to remote `main` — defeats the main-protection regime via a
# one-keystroke substitution. Same family as #470 (the ref-spelling
# enumerations) but `HEAD` is special because resolution happens
# SERVER-SIDE, not in the local parser. Pre-fix, PUSH_TARGET="HEAD"
# survived all normalizations (colon-RHS, +, refs/heads/) and the equality
# check against "main"/"master" missed. Post-fix, an explicit
# `if [ "$PUSH_TARGET" = "HEAD" ]` block resolves to the current local
# branch before the equality check.
toggle_test "main_protected:true denies 'git push origin HEAD' from main (#515)" 1 "main" "deny" "git push origin HEAD"
toggle_test "main_protected:true allows 'git push origin HEAD' from feat branch (#515)" 1 "feat/test" "allow" "git push origin HEAD"
toggle_test "main_protected:true denies 'git push origin HEAD' from master (#515)" 1 "master" "deny" "git push origin HEAD"
# Combines with #528's path-strip fix: `/usr/bin/git push origin HEAD`
# from main must also deny — the wrapper-recursion's path-strip recognizes
# the absolute-path git invocation, and the new HEAD resolution then maps
# PUSH_TARGET to "main".
toggle_test "main_protected:true denies '/usr/bin/git push origin HEAD' from main (#515 + #528)" 1 "main" "deny" "/usr/bin/git push origin HEAD"

echo ""
echo "=== Push: main-push block FAILS CLOSED on missing/unparseable config ==="

# When no config is resolvable (absent / unreadable / unparseable), the gate
# DEFAULTS TO BLOCKING main/master pushes — preserving the prior
# "zskills-shipped configs fail closed (safer)" posture that the former
# static BLOCK_MAIN_PUSH=1 line provided.
failclosed_test() {
  local label="$1" config_state="$2" branch="$3" expected="$4" cmd="${5:-git push origin main}"
  local tmp_repo result
  tmp_repo=$(mktemp -d)
  (cd "$tmp_repo" && git init -q -b "$branch" 2>/dev/null \
    || (cd "$tmp_repo" && git init -q && git checkout -b "$branch" 2>/dev/null))
  mkdir -p "$tmp_repo/.claude"
  case "$config_state" in
    absent)      : ;;  # write nothing
    unparseable) printf 'this is not valid json at all {[' > "$tmp_repo/.claude/zskills-config.json" ;;
    no-key)      printf '{"execution": {"landing": "pr"}}\n' > "$tmp_repo/.claude/zskills-config.json" ;;
  esac
  result=$(cd "$tmp_repo" && echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | REPO_ROOT="$tmp_repo" bash "$HOOK")
  rm -rf "$tmp_repo"
  if [ "$expected" = "deny" ]; then
    if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected deny (fail-closed), got: $result"
    fi
  else
    if [[ "$result" != *"permissionDecision"*"deny"* ]]; then
      pass "$label"
    else
      fail "$label — expected allow, got: $result"
    fi
  fi
}

failclosed_test "fail-closed: absent config blocks push origin main" absent "feat/test" "deny"
failclosed_test "fail-closed: absent config blocks bare push on main" absent "main" "deny" "git push"
failclosed_test "fail-closed: unparseable config blocks push origin main" unparseable "feat/test" "deny"
failclosed_test "fail-closed: config missing main_protected key blocks push origin main" no-key "feat/test" "deny"
# Fail-closed only affects main/master targets — feature-branch pushes still
# allowed even with no resolvable config (the gate is main-targeted, not a
# blanket push block).
failclosed_test "fail-closed: absent config still allows feature-branch push" absent "feat/test" "allow" "git push -u origin feat/test"

echo ""
echo "=== Non-Bash tool_name ==="

result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' | bash "$HOOK")
if [[ -z "$result" ]]; then
  pass "non-Bash tool_name exits silently"
else
  fail "non-Bash tool_name — got unexpected output: $result"
fi

echo ""
echo "=== Edge cases ==="

# Empty command field
result=$(echo '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$HOOK")
if [[ -z "$result" ]]; then
  pass "empty command exits silently"
else
  fail "empty command — got unexpected output: $result"
fi

# tool_name with extra whitespace in JSON
result=$(echo '{"tool_name": "Bash","tool_input":{"command":"git reset --hard"}}' | bash "$HOOK")
if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
  pass "tool_name with space after colon still detected"
else
  fail "tool_name with space after colon — expected deny, got: $result"
fi

echo ""

# === BLOCK_UNSAFE_HARDENING bypass canaries — generic hook ===
# GR1-GR25: bypass-canary integration tests for the tokenize-then-walk
# migration of hooks/block-unsafe-generic.sh (Phase 4 of plan
# plans/BLOCK_UNSAFE_HARDENING.md). These cases assert the migration kills
# the bare-substring over-match class (GR1-GR12c-allow), preserves residual
# carve-outs intentionally (GR12a, GR12b), preserves all positive cases
# (GR13-GR25), and locks pipeline-form / combined-flag coverage that DA-C-2
# kept unchanged (GR20, GR21).

# GR1 — Reproducer R5: grep over the hook source must not trip the hook.
# Plan WI 4.5 specced an alt-regex that mentioned both migrated patterns (kill -9,
# killall, pkill) AND unchanged-rule patterns (fuser -k, find .* -delete, rsync
# --delete, xargs.*rm). Those unchanged rules are bare-substring whole-buffer
# scans that correctly fire on grep args mentioning them — so the WI 4.5 alt
# regex would still trip with the migration in place. Coverage of the migrated
# verbs is what GR1 is supposed to assert, so the regex below is restricted
# to identifier-substrings (RM_RECURSIVE, KILL_SUBST, etc.) plus pattern
# fragments that share text with the OLD bare regexes (e.g. 'git[[:space:]]+restore')
# — neither of which matches any rule (migrated or unchanged) in the COMMAND
# buffer. This is the R5-reproducer spirit (grep over the hook source itself)
# without the spec's accidental collision with unchanged rules.
expect_allow "GR1: grep R5 reproducer over hook source (curated regex)" \
  "grep -n -E '(RM_RECURSIVE|KILL_SUBST|XARGS_KILL|STASH_BOUNDARY|is_safe_destruct|is_git_subcommand)' /workspaces/zskills/hooks/block-unsafe-generic.sh"

# GR2-GR4 — grep over notes.md mentioning the migrated git verbs (pre-Phase-4 BLOCKED)
expect_allow "GR2: grep 'git restore' notes.md"        "grep 'git restore' notes.md"
expect_allow "GR3: grep 'git clean -f' notes.md"       "grep 'git clean -f' notes.md"
expect_allow "GR4: grep 'git reset --hard' notes.md"   "grep 'git reset --hard' notes.md"

# GR5 — printf with banned-prose payload (line 135 migrated)
expect_allow "GR5: printf 'remember to git reset --hard'" \
  "printf 'remember to git reset --hard\\\\n'"

# GR6 — echo banned-prose payload (line 140 migrated)
expect_allow "GR6: echo 'use kill -9 1234 to force'" \
  "echo \\\"use kill -9 1234 to force\\\""

# GR7 — path-substring class (line 140 migrated)
expect_allow "GR7: cat /tmp/kill-9-notes.md (path substring)" \
  "cat /tmp/kill-9-notes.md"

# GR8-GR10 — grep over files mentioning migrated patterns
expect_allow "GR8: grep 'git commit --no-verify' tests/test-hooks.sh" \
  "grep 'git commit --no-verify' tests/test-hooks.sh"
expect_allow "GR9: grep 'git add -A' notes.md"         "grep 'git add -A' notes.md"
expect_allow "GR10: grep 'git push' notes.md"          "grep 'git push' notes.md"

# GR11 — Segment-truncation invariant: post-`&&` `-f` must NOT trip line-130
expect_allow "GR11: git clean foo && rm -f bar.txt (segment truncation)" \
  "git clean foo && rm -f bar.txt"

# GR12 — Segment-truncation invariant: post-`&&` `--` must NOT trip line-120
expect_allow "GR12: git reset --soft && grep -- pattern file.sh" \
  "git reset --soft && grep -- pattern file.sh"

# GR12a — Carve-out lock: quote-blind helper sees `--hard` in the quoted arg
expect_deny "GR12a: git reset 'msg --hard text' (quote-blind carve-out lock)" \
  "git reset 'msg --hard text'"

# GR12b — Carve-out CLOSED by chain wrapper: `is_git_subcommand_in_chain`'s
# sed normalizer splits on `;` regardless of surrounding whitespace, so the
# segment-truncation invariant holds even for space-elided shell-controls.
# Plan WI 4.5 specced this as a CARVE-OUT LOCK (expect_deny) on the assumption
# that the migration would use bare `is_git_subcommand` (segment-blind tokenizer).
# The implementation uses `is_git_subcommand_in_chain` (per Phase-3-parity
# requirement to preserve cd-chain coverage), which closes the carve-out.
# Test flipped to expect_allow accordingly.
expect_allow "GR12b: git clean foo;rm -f bar (chain wrapper closes carve-out)" \
  "git clean foo;rm -f bar"

# GR12c-allow — Line-120 migration kills the over-match
expect_allow "GR12c-allow: printf 'git checkout -- foo' > /tmp/notes.sh" \
  "printf 'git checkout -- foo\\\\n' > /tmp/notes.sh"

# GR12c-deny — Line-120 still fires positively for real invocation
expect_deny "GR12c-deny: git checkout -- file.sh (positive regression)" \
  "git checkout -- file.sh"

# GR13-GR15 — Positive regressions: migrated git-verb rules still fire
expect_deny "GR13: git restore . (positive regression)"     "git restore ."
expect_deny "GR14: git clean -f (positive regression)"      "git clean -f"
expect_deny "GR15: git reset --hard (positive regression)"  "git reset --hard"

# GR16 — Positive regression: kill -9 still fires
expect_deny "GR16: kill -9 1234 (positive regression)"      "kill -9 1234"

# GR17 — Positional-pair `:next:` matched
expect_deny "GR17: kill -s 9 1234 (positional-pair)"        "kill -s 9 1234"

# GR18 — Positional-pair miss: -s USR1 is allowed (non-destructive signal)
expect_allow "GR18: kill -s USR1 1234 (positional-pair miss)" "kill -s USR1 1234"

# GR19 — Positive regression: line 217 unchanged; bare RM_RECURSIVE still fires
expect_deny "GR19: rm -rf /home/foo (line 217 unchanged)"   "rm -rf /home/foo"

# GR20 — Pipeline form preserved (DA-C-2 lock)
expect_deny "GR20: cat list.txt | xargs rm -rf (pipeline form preserved)" \
  "cat list.txt | xargs rm -rf"

# GR21 — Combined-flag preserved (DA-C-2 lock)
expect_deny "GR21: fuser -mk 8080 (combined-flag preserved)" "fuser -mk 8080"

# GR22 — KILL_SUBST line 175 unchanged
expect_deny "GR22: kill -9 \$(lsof -ti :3000) (KILL_SUBST unchanged)" \
  "kill -9 \$(lsof -ti :3000)"

# GR23 — Top-level git flag passthrough: `git --no-pager restore .`
expect_deny "GR23: git --no-pager restore . (top-level flag passthrough)" \
  "git --no-pager restore ."

# GR24 — Top-level git flag passthrough: `git --git-dir=/x clean -f`
expect_deny "GR24: git --git-dir=/x clean -f (top-level flag passthrough)" \
  "git --git-dir=/x clean -f"

# GR25 — Subcommand quote-strip
expect_deny "GR25: git \"restore\" . (subcommand quote-strip)" \
  "git \\\"restore\\\" ."

echo ""

# ─── Project hook test harness ───
# PROJECT_HOOK (absolutized), TEST_TMPDIR, setup_project_test,
# teardown_project_test, setup_push_remote, expect_project_deny, and
# expect_project_allow now live in tests/lib/hooks-harness.sh (sourced at the
# top of this file). No test section moves in Phase 1a — only these helper
# definitions were factored out.
echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
