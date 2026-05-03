#!/usr/bin/env bash
# hooks/validate-bash-readonly.sh
#
# PreToolUse hook for the commit-reviewer subagent. Rejects state-mutating
# Bash commands so the reviewer cannot edit reality (no git stash, no rm,
# no commit, etc.). Bash regex only (no jq).
#
# Word-boundary form catches forbidden verbs ANYWHERE in the command —
# including after env-var prefixes (`FOO=bar rm`), &&-chains
# (`git diff && rm foo`), subshells (`(rm foo)`), and pipe tails
# (`echo x | rm foo`). N6 fix: a `^[[:space:]]*` anchor would only catch
# top-level invocations and let any of the above bypass.
#
# The leading `(^|[^a-zA-Z_])` requires the verb begin at the string
# start OR be preceded by a non-identifier character (space, `&`, `;`,
# `(`, `|`, etc.), so `mvbacon` (literal substring `mv` inside identifier
# `mvbacon`) is NOT matched.
#
# Test-runner invocations (`npm test`, `bash tests/run-all.sh`) ALLOW
# because the regex matches only verbs in the FORBIDDEN SET — `npm`,
# `bash`, `git diff`, `grep`, etc. are not state-mutating in this hook's
# enforcement scope. Subprocess introspection is intentionally out of
# scope for a syntactic Bash-tool hook.
set -euo pipefail
INPUT="$(cat)"
# Extract command field. Tolerant of escaped quotes inside the value.
if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"((\\\"|[^\"])*)\" ]]; then
  CMD="${BASH_REMATCH[1]}"
else
  exit 0
fi
# Forbidden git verbs (state-mutating). Word-boundary match.
if [[ "$CMD" =~ git[[:space:]]+(stash|checkout|restore|reset|add|rm|commit|push|merge|rebase|cherry-pick|revert|tag|branch[[:space:]]+-D) ]]; then
  cat <<'JSON'
{ "decision": "block", "reason": "commit-reviewer is read-only. Forbidden: git stash/checkout/restore/reset/add/rm/commit/push/merge/rebase/cherry-pick/revert/tag/branch -D. Use git show <commit>:<file> for pre-fix state." }
JSON
  exit 0
fi
# Forbidden general verbs — word-boundary form catches the verb ANYWHERE in the
# command (not just top-level). N6 fix: env-var prefix (`FOO=bar rm /etc/x`),
# &&-chained commands (`git diff && rm foo`), subshells (`(rm foo)`), and pipe
# tails (`echo x | rm foo`) all bypass a `^[[:space:]]*` anchor.
# The leading `(^|[^a-zA-Z_])` requires the verb begin at the string start OR
# be preceded by a non-identifier character (space, `&`, `;`, `(`, `|`, etc.),
# so `npm test` (verb `test` not in our set, but illustrative) is unaffected
# and `mvbacon` (literal substring 'mv' inside an identifier) is NOT matched.
if [[ "$CMD" =~ (^|[^a-zA-Z_])(rm|mv|cp|tee|chmod|chown|dd|truncate)([[:space:]]|$|\;|\&|\|) ]]; then
  cat <<'JSON'
{ "decision": "block", "reason": "commit-reviewer is read-only. Forbidden: rm, mv, cp, tee, chmod, chown, dd, truncate (anywhere in the command, including after env-var prefix, &&, ;, |, or in subshells). The reviewer cannot edit reality." }
JSON
  exit 0
fi
exit 0
