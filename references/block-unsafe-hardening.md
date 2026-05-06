# Block-Unsafe Hooks Hardening — Reference

> Source-of-truth doc cited by every phase of `plans/BLOCK_UNSAFE_HARDENING.md`.
> All decisions, reproducers, and coordination notes live here verbatim so
> downstream phases do not scatter rationale across phase prose.

---

## 1. Decisions D1-D7

The seven design decisions are the same wording as the plan's `Decisions (D1-D7)` section. Verbatim copy follows.

### D1 — Tokenize-then-walk over generalized regex

The regex form `[[ "$COMMAND" =~ ^([A-Z_][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)*(env[[:space:]]+([A-Z_]…)*)?git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--?[A-Za-z][A-Za-z0-9_-]*(=[^[:space:]]*)?))*[[:space:]]+commit ]]` is combinatorially fragile, hard to read, and was empirically demonstrated to be bypassable in Plan B's Round 2 N1 (e.g., the narrow `(-C …|-c …)?` alternation form let `git --no-pager commit` slip through). Tokenize-then-walk is **simpler to reason about** (split on whitespace; skip env-var prefixes; find literal `git`; walk past `-…` flags; check next token is the verb), more robust against future git top-level flag additions, and matches Plan B's chosen approach for the same problem class. Adopting it here unifies the codebase pattern.

The `is_git_subcommand` helper this plan introduces is Plan B's `is_git_commit` parameterized on the verb token. The `is_destruct_command` helper extends the same pattern to non-git first-tokens (`kill`, `rm`, `find`, `rsync`, `xargs`) — same tokenize-skip-flags-walk shape, but the matched verb IS the first token (no `git` prefix), and flag-skipping rules differ slightly (`find`'s `-delete` is an arg not a flag; `rm`'s `-rf` is conventional short-flag form).

### D2 — Inline-from-source-of-truth (`hooks/_lib/git-tokenwalk.sh`)

The two helper bodies (`is_git_subcommand`, `is_destruct_command`) are stored once in `hooks/_lib/git-tokenwalk.sh` (a NEW file landed by Phase 2; the underscore-prefix marks it as a non-installed library, parallel to `_internal/` conventions in other zskills paths). The hooks STILL inline the function bodies (no `source` at runtime — same load-order avoidance as the original draft). What changes vs. the round-0 draft is the **path of the source-of-truth**: round-0 placed it in `tests/fixtures/` (DA-H-4 maintenance trap); this revision moves it to `hooks/_lib/` so the path itself signals "this is hook source, not test data."

**Why inline-not-source remains right.** Sourcing introduces a load-order dependency: every consumer of `/update-zskills` would need the lib file installed before either hook runs, AND the install loop in `skills/update-zskills/SKILL.md` would need a new copy step. Inline keeps each hook self-contained (`bash -n` lints independently, no source-failure fail-open ambiguity). Cost: ~40 lines of duplicated body across two (or, post-Plan-B, three) hooks. Phase 5.4's drift gate (`tests/test-hook-helper-drift.sh`, see D7) makes drift a CI failure, not a maintenance gamble.

**Why a single source-of-truth file.** Round-1 DA-C-3 demonstrated that "let each plan inline its own copy" + "future refactor as YAGNI" + Plan B's parallel `is_git_commit` produces guaranteed three-way drift. With one file at `hooks/_lib/git-tokenwalk.sh`, the drift check enforces single-version semantics across all consumers — including Plan B post-D6 refinement.

### D3 — Redaction stays; helpers run AFTER redaction

The two-pass data-region redaction at `block-unsafe-project.sh.template` lines 41-58 (heredoc bodies + flag-scoped quoted-arg values for `git commit -m` / `gh pr create -b`) and `block-unsafe-generic.sh` lines 65-84 (same passes, byte-identical) is **load-bearing for these hard-deny hooks**. Both hooks deny without script callout; a false-positive match has no veto path. Redaction is the false-positive defense (strips data-bearing args BEFORE classification); tokenize-then-walk is the over-match-on-real-invocations defense (rejects classification when the invocation is `grep` not `git`). They compose cleanly; both are needed.

This contrasts with Plan B's `block-stale-skill-version.sh`, which deliberately omits redaction because that hook delegates to a filesystem-state-driven script that exits 0 on a clean stage — even a hypothetical false-positive harmlessly invokes the script. Plan B D&C lines 292-293 explicitly justify omitting redaction in that hook for that reason. **The inverse logic justifies keeping it here.**

Helpers operate on `$COMMAND_REDACTED` (the post-redaction buffer used by all existing rules in both hooks today; e.g., `block-unsafe-project.sh.template:404` already reads `$COMMAND` AFTER the redaction passes at lines 41-58). No re-architecture needed; helpers slot in where the bare regex used to be.

### D4 — Class-pinned acceptance criteria, not shape-pinned

Per prior-art research §F: every prior patch (#73, #87) added regression cases for the *literal command shape* that triggered the incident. Each shape becomes a single test case; the next over-match in a different shape ships unblocked because the test surface enumerates shapes, not the class. **This plan's Phase 5 ACs MUST pin the class.**

Concretely, Phase 5 generates a **synthetic 144-case negative matrix**: 12 read-only commands (`grep`, `sed`, `awk`, `cat`, `echo`, `printf`, `head`, `tail`, `less`, `more`, `file`, `wc`, `diff`) × 3 git verbs (`commit`, `cherry-pick`, `push`) × 4 quote-shapes (single-quoted arg, double-quoted arg, unquoted positional, `-pattern` flag-value). All 144 must NOT trip either hook on `main`. The 4 known reproducers (B.1-B.4 from research) appear as named test cases in addition to the matrix. A separate positive matrix asserts that ACTUAL destructive invocations (the cases #73 and #87 added) STILL trip — the hook must not weaken.

A second class is pinned for the destructive-verb generic-hook rules (D.2 in research): 8 read-only commands × 6 destructive verbs (`git restore`, `git clean -f`, `git reset --hard`, `git add -A`, `kill -9`, `rm -rf`) × 4 quote-shapes = 192 negative cases. Same shape, different verb set.

### D5 — Documented carve-outs: shell-expansion, quote-blind tokenization, prefix-bypass, multi-line

The tokenize-then-walk helper uses `read -ra TOKENS <<< "$cmd"` — bash's whitespace-split-only tokenization. It does NOT interpret shell quoting, expansion, or multi-statement constructs. Round-2 R2-C-1/DA2-C-1, DA2-H-3, DA2-M-4 enumerated the full bypass class. All of the following are accepted as **documented carve-outs** with locked test cases — each is a NEGATIVE assertion in the unit test surface, so a future hardening pass that wants to close any one MUST update the named test:

| Class | Example | Why bypassed | Lock |
|---|---|---|---|
| Shell expansion: `bash -c` / `sh -c` / `eval` | `bash -c 'git commit -m foo'` | First token is `bash`/`sh`/`eval`, not `git`; helper does not recurse into `-c` arg | XCC21/XCP21/XPU21 |
| Shell expansion: command substitution `$(...)` | `git $(echo commit) -m foo` | Tokens `[git, $(echo, commit), -m, foo]` — flag-skip terminates at `$(echo` (not `-`-prefixed), then sees `commit` ≠ flag, then sees `-m` — fails subcommand check | XCC23 |
| Shell expansion: backticks | `` git `echo commit` -m foo `` | Same as `$()`; the `` ` `` token is not a `-` flag, so flag-skip stops, subcommand check fails | XCC24 |
| Shell expansion: variable | `GIT_VERB=commit; git $GIT_VERB` | Two-statement form; first is env-assignment-only, second tokenizes to `[git, $GIT_VERB]` — `$GIT_VERB` is not literal `commit` | XCC25 |
| Shell expansion: aliased binary | `GIT='git'; $GIT commit` | First token is `$GIT`, fails `git` literal check | (covered by XCC25 family) |
| **Quote-blind tokenization (positive bypass)** — flag-discriminator inside quoted arg | `git reset 'msg --hard text'` | `read -ra` splits on whitespace regardless of quotes — yields `[git, reset, 'msg, --hard, text']`. `is_git_subcommand "$cmd" reset` matches; `GIT_SUB_REST="'msg --hard text'"`. Hybrid `[[ "$GIT_SUB_REST" =~ --hard ]]` MATCHES on the `--hard` *inside the quoted path arg*. **DENIES on a benign single-quoted path argument that happens to contain `--hard` text.** Same defect for `git clean 'foo -f bar'`, `git commit "msg --no-verify text"`, etc. **Strictly narrower than the bare-substring class the plan closes** (which trips on ANY mention anywhere in the buffer; this only trips when the mention is inside an arg of a real `git $VERB` invocation), but a real residual carve-out. | XCC30/XCC31 (negative-acknowledge: helper IS quote-blind) + Phase 4 GR-NEW (`git reset 'msg --hard text'` → expect_deny WITH a CHANGELOG note that this is a documented over-match, not a regression) |
| **Quote-blind tokenization (negative bypass)** — shell-control inside quoted arg | `git commit -m 'first && second' --no-verify` *unredacted* | `read -ra` yields `[git, commit, -m, 'first, &&, second', --no-verify]`. The segment-truncation logic at `&&` would TRUNCATE `GIT_SUB_REST` to `-m 'first` — losing the `--no-verify` discriminator, false-NEGATIVE on a real `--no-verify` invocation. **Mitigated for `commit --no-verify` specifically** because the existing redaction sed at line 56/82 strips `-m '...'` bodies BEFORE the helper runs (verified DA2-C-1 mid-finding). Other hybrid checks (`clean -f`, `reset --hard`, `add -A`) have no comparable redaction; the false-negative bypass is real for arbitrary args containing literal `&&`/`\|`/`;` that arrive unredacted. | XCC32 (assert documented behavior) |
| **Space-elided shell-control** | `git clean foo;rm -f bar` | `;` glues to neighbor token; `read -ra` yields `[git, clean, foo;rm, -f, bar]`. The segment-truncation `case '&&'\|'\|\|'\|';'\|'\|') break ;;` never sees `;` as its own token, so `GIT_SUB_REST` becomes `foo;rm -f bar`. Hybrid `[[ "$GIT_SUB_REST" =~ -f ]]` MATCHES on the `-f` from the *post-`;` `rm`* segment. False-positive trip on `git clean foo` (no `-f` flag). Same for `cmd1\|cmd2`, `cmd1\|\|cmd2`, `cmd1&&cmd2`. | XCC33 (positive-acknowledge: helper trips, by design, narrower than bare-substring whole-buffer class) |
| **Prefix bypass (env -i)** | `env -i kill -9 1234` | Helper consumes `env` keyword (one token) and env-var assignments (`KEY=VAL`), but does NOT consume `env`'s own flags. Tokens after env-skip: `[-i, kill, -9, 1234]`. First token is `-i`, not `kill`; `is_destruct_command` returns 1. | XKL11 (negative-acknowledge) |
| **Prefix bypass (sudo / doas / su)** | `sudo kill -9 1234` | First token is `sudo`, not `kill`. Helper does not interpret prefix-binaries. | XKL12 (negative-acknowledge) |
| **Multi-line command** | `echo hi\ngit commit -m foo` | `read -ra TOKENS <<< "$cmd"` reads only ONE line (up to first newline). Subsequent lines are invisible to the helper. Same property holds for Plan B's `is_git_commit`. | XCC34 (negative-acknowledge) |

**We accept ALL of these as known bypasses / over-matches for the project hook AND the generic hook.** Same justification as Plan B: each carve-out is a minor local-development hole or a narrower-than-baseline over-match, not a structural defeat. CI's branch-protection rules are the backstop for project hook; `is_safe_destruct` policy is unchanged for generic hook. Recursing into shell-expansion or implementing a quote-aware tokenizer in pure bash would re-introduce exactly the regex-fragility class we're killing — the inner string would need a hand-rolled state machine, OR `eval` (unsafe).

**The quote-blind row is the most consequential.** It means the segment-truncation hybrid fix (Phase 2 helper API) does NOT close R-H-2 unconditionally — it closes the *bare-substring whole-buffer* class but leaves the *quoted-arg-inside-real-`git $VERB`-invocation* sub-class. The plan's class-pinned matrix (Phase 5.2) does NOT include cases of this sub-class because the matrix shape `<read-only-cmd> <quoted-arg-mentioning-git-verb>` always has the FIRST token be `grep`/`sed`/etc., not `git` — `is_git_subcommand` returns 1, the hybrid never runs. So the matrix's 144 cases all pass after migration AND the quote-blind sub-class remains open. **This is structurally correct (the matrix exercises the migrated class; the residual sub-class is in D5)**, not a hidden regression — but the carve-out enumeration here is the only thing locking that boundary.

Future hardening could add shell-expansion recursion / quote-aware tokenization / multi-line splitting as a separate plan (it would need a hand-rolled state machine — heavy work); out of scope here.

### D6 — Plan B coordination: this plan owns the source-of-truth; Phase 6 is the canonical consolidation path

Round-1 DA-C-3 demonstrated that "either may land first" produces guaranteed three-way duplication: Plan B's `is_git_commit`, this plan's `is_git_subcommand` in project hook, AND this plan's `is_git_subcommand` in generic hook all carry near-identical bodies that drift independently.

**Decision: this plan introduces `hooks/_lib/git-tokenwalk.sh` as the single source-of-truth, and this plan's Phase 6 is the CANONICAL consolidation path** (regardless of Plan B's current status). Phase 6's first work-item is a `git log` decision that branches: if Plan B has not yet landed its hook, Phase 6 is no-op (Plan B will pick up `hooks/_lib/` when its own Phase 2 implementer reads this plan's reference doc); if Plan B has landed, Phase 6 migrates Plan B's hook to consume the source-of-truth (one-commit refactor, same Phase 3.x discipline as this plan's other hook migrations).

**Why Phase 6 is canonical, not "/refine-plan it before."** Round-2 DA2-C-2 showed that the round-1 "/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md before this plan starts Phase 2" branch was aspirational: no Phase 2 work-item dispatched it, so an implementer working through Phase 2 would never trigger it. Either path was valid; choosing Phase 6 as canonical removes the branch and the silent-no-fire risk.

**Optional orchestrator action (not a work-item).** A human orchestrator working in parallel on both plans MAY proactively dispatch `/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` to update Plan B's Phase 2 spec before Plan B's Phase 2 lands. If they do, Plan B's hook arrives already consuming `hooks/_lib/git-tokenwalk.sh` and this plan's Phase 6 is no-op. This is a coordination convenience, not a plan invariant — Phase 6 handles both paths symmetrically.

**Plan B already-completed handling (round-2 DA2-M-2).** If Plan B status is `complete` at Phase 6 start, `/refine-plan` is NOT appropriate (it operates only on active plans). Phase 6.4 D&C explicitly handles this: edit `tests/test-block-stale-skill-version.sh` directly to call `is_git_subcommand "$cmd" commit` instead of `is_git_commit "$cmd"`, with an explanatory commit-message line citing this plan's Phase 6.

This plan's Phase 6 (see below) handles ALL post-merge consolidation cases (not-landed / mid-execution / landed-active / landed-complete) explicitly with named acceptance criteria.

### D7 — Drift-check delivery: new `tests/test-hook-helper-drift.sh`

Round-1 R-M-5 / DA-M-4 flagged that `tests/test-skill-conformance.sh` is for SKILL files, not hook helpers. The two scopes don't compose cleanly. **Decision: a new test file, `tests/test-hook-helper-drift.sh`, is added in Phase 5.4** with one job: assert that every consumer of `hooks/_lib/git-tokenwalk.sh` (this plan's two hooks + Plan B's hook post-D6) carries a byte-identical inlined function body. Registered in `tests/run-all.sh` per the existing `run_suite` pattern.

---

## 2. Known reproducers (manual recipes)

Five reproducers (R1-R5) cataloguing previously-observed over-match incidents. For each, this section quotes the empirical deny-envelope trace produced by piping a synthesized PreToolUse JSON envelope into the installed hook (`.claude/hooks/block-unsafe-project.sh` or `.claude/hooks/block-unsafe-generic.sh`). Where the literal reproducer command does NOT trip any current hook regex when run in synthesis, the subsection is marked `UNTRACED` per work-item 1.1's discipline.

All traces below were run in this Phase 1 worktree against the installed hooks at `/tmp/zskills-pr-block-unsafe-hardening/.claude/hooks/`. The `is_on_main` precondition was synthesized via `REPO_ROOT=/workspaces/zskills` (the main repo — currently on `main`); `main_protected: true` is the live config value. The bash invocation pattern was:

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"<COMMAND>"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

### R1 — research B.1: grep-OR over-match on commit transcript site

Original incident shape: agent reading the hook source with `grep -n 'git commit\|...' .claude/hooks/block-unsafe-project.sh` was BLOCKED because the bare `git[[:space:]]+commit` regex matched the literal `git commit` substring inside the `grep` pattern arg.

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -n '"'"'git commit\\|...'"'"' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

**Result: FIRES.** Captured `permissionDecisionReason`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"}}
```

**Hook + line that fired:** `.claude/hooks/block-unsafe-project.sh:404` (the `main_protected: block git commit on main` rule — `[[ "$COMMAND" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main`). The rule scans the entire `$COMMAND` buffer for the literal substring `git commit` and finds it inside the `grep` pattern's quoted arg. This is the canonical bare-substring over-match the plan closes via `is_git_subcommand`.

### R2 — research B.2: sed-range read of hook source

Original incident shape: agent inspecting the commit-rule region with `sed -n '404,420p' .claude/hooks/block-unsafe-project.sh` was historically reported as BLOCKED. The current installed hook does NOT match this command shape via any regex (the `sed -n '404,420p' <file>` command contains no `git commit` / `git cherry-pick` / `git push` / destructive-verb substring).

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"sed -n '"'"'404,420p'"'"' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

**Result: does NOT fire.** No `permissionDecisionReason` was emitted (hook exits 0 with empty stdout). Re-run against `block-unsafe-generic.sh` likewise produced no output.

**Status: UNTRACED-IN-SYNTHESIS.** No current regex matches this exact synthesized command. Per work-item 1.1, this reproducer is NOT promoted to a class-pinned AC test on the basis of the literal R2 shape; the over-match class it represents (read-only file inspection of the hook source code) is fully covered by the 144-case negative matrix in Phase 5. Per round-2 DA2-H-1: synthetic-no-fire is necessary but not sufficient evidence of safety — the live COMMAND buffer Claude Code constructs may differ from a hand-built `printf '{...}' | bash hook` reproducer (different escaping, ambient env, transcript context). If a NEW R2-class incident surfaces post-merge it should be added as `R6` / `R7` etc. with a fresh empirical capture, NOT silently discarded.

### R3 — UNTRACED (no current regex matches; included as documented historical incident)

Original incident shape: searching open issues with `gh issue list --state open --search 'block-unsafe-project OR git-commit OR over-match OR false-positive in:title,body'`. **DEMOTED per round-1 DA-C-1.** Both round-1 and round-2 empirical re-verification confirmed this specific shape does not currently trip any hook.

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh issue list --state open --search '"'"'block-unsafe-project OR git-commit OR over-match OR false-positive in:title,body'"'"'"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

**Result: UNTRACED.** No `permissionDecisionReason` was emitted. No PR3 acceptance test will be added (Phase 3.4 update mandatory).

**Methodological note (round-2 DA2-H-1):** "synthetic isolation test passes" is necessary but not sufficient evidence of safety — the round-2 DA's own session experienced a real block on a different `grep` shape that did not reproduce in synthesis (likely the COMMAND buffer Claude Code constructs differs from a hand-built `echo '{...}' | bash hook` reproducer). UNTRACED status reflects "no current synthetic reproducer" not "guaranteed safe." A NEW reproducer that surfaces post-merge SHOULD be added as `R6` / `R7` etc. with empirical capture, NOT silently discarded as "couldn't reproduce."

### R4 — research B.4: grep-OR over-match against test-hooks.sh

Original incident shape: agent reading `tests/test-hooks.sh` with `grep -nE '(commit.*OR|over-match|grep.*git commit|sed.*block-unsafe|...)' tests/test-hooks.sh` was BLOCKED because the bare `git[[:space:]]+commit` regex matched the literal `git commit` substring in the grep pattern (specifically the `grep.*git commit` alternative).

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -nE '"'"'(commit.*OR|over-match|grep.*git commit|sed.*block-unsafe|...)'"'"' /workspaces/zskills/tests/test-hooks.sh"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

**Result: FIRES.** Captured `permissionDecisionReason`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"}}
```

**Hook + line that fired:** `.claude/hooks/block-unsafe-project.sh:404` (same bare-substring rule as R1). The plan's R4 prose anticipated line 411 (the transcript-verification site, no `&& main_protected` guard) firing on the `grep.*git commit` substring; in this synthesis line 404 fires *first* because the `is_main_protected && is_on_main` precondition is satisfied via the `REPO_ROOT=/workspaces/zskills` override. Both lines 404 and 411 share the same `[[ "$COMMAND" =~ git[[:space:]]+commit ]]` over-match defect — the plan's Phase 3 migration replaces both call sites with `is_git_subcommand "$cmd" commit`.

### R5 — drafter-session live: kill-9 substring in destructive-verb regex

Original incident shape: drafter agent reading `block-unsafe-generic.sh` source with a `grep -nE '(kill -9|killall|pkill|fuser -k|RM_RECURSIVE|find .* -delete|rsync .*--delete|xargs.*kill|xargs.*rm)' hooks/block-unsafe-generic.sh` was BLOCKED because the bare-substring `kill -9` regex matched the literal `kill -9` substring inside the grep pattern.

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -n -E '"'"'(kill -9|killall|pkill|fuser -k|RM_RECURSIVE|find .* -delete|rsync .*--delete|xargs.*kill|xargs.*rm)'"'"' /workspaces/zskills/hooks/block-unsafe-generic.sh"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-generic.sh
```

**Result: FIRES.** Captured `permissionDecisionReason`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: kill -9/killall/pkill can kill container-critical processes. Ask the user to stop the process manually."}}
```

**Hook + line that fired:** `.claude/hooks/block-unsafe-generic.sh` — the kill-family rule. Per round-2 R2-M-3 cosmetic: rule line = 140 (the regex), deny-message line = 141; both are correct citations of different artifacts within the same rule. Round-1 refiner verification re-confirmed this fires today. The plan's Phase 4 migration replaces the bare-substring `kill -9` regex with `is_destruct_command "$cmd" kill`, which token-walks the command and rejects classification when the first non-env token is `grep` rather than `kill`.

---

## 3. Patch-trail-this-plan-closes

The unifying defect class is "regex-based command classification scanning the entire `$COMMAND` buffer rather than a tokenized command structure." Three prior patches each closed one shape and left the class open. The fourth row is the line-540 cherry-pick site, which has the identical *structural shape* as the line-404 commit site but is unprotected by any of the prior patches.

| # | Prior issue / PR | Site closed | What stayed open |
|---|---|---|---|
| 1 | Issue #58 / PR #73 | `git push` / `git restore` / `git reset --hard` rules a/b → moved to PUSH_ARGS extraction | Fix was for `push`-flavor rules only; commit/cherry-pick sites left bare-substring; class never named |
| 2 | Issue #81 / PR #87 | rule c → PUSH_ARGS scope, outer gate `$` anchor on push | PR body itself acknowledges *"if any future check is added that tests $COMMAND instead of PUSH_ARGS, it'll regress"*; commit/cherry-pick sites still bare-substring |
| 3 | PR #84 | mirror-regen recipe centralization (process fix, not regex fix) | Did not touch any over-match site; class untouched |
| 4 | (pending — this plan) | line-540 cherry-pick site `[[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main` (structurally identical to line-404 commit site) and unprotected by any of the prior patches (#58/#73/#81/#87/#84 all targeted commit/push, never cherry-pick) | (this plan closes the class via `is_git_subcommand` / `is_destruct_command`) |

The line-616 push outer gate at `block-unsafe-project.sh.template:616` and 719 still uses bare substring even after PR #87. This plan replaces all five bare-substring sites in the project hook plus all six destructive-verb sites in the generic hook (`git restore`, `git clean -f`, `git reset --hard`, `git add . / -A`, `git commit --no-verify`, plus the kill family and rm family) with token-aware classification. Acceptance criteria pin the **bug class**, not specific shapes — this is the discipline the prior patches missed.

### 3.1 Verification: line-540 cherry-pick site against `printf` reproducer (round-2 DA2-H-5)

The Overview's claim about line-540 cherry-pick ("structurally identical and unprotected by prior patches") is a structural hypothesis (NOT a current empirical-block claim — round-2 refiner deliberately rephrased per DA2-H-5). This Phase 1 reference doc empirically tests whether `block-unsafe-project.sh` line 540 currently fires on a `printf` of `git cherry-pick` text using a synthesized fixture where `is_on_main: true` and `main_protected: true`.

**Trace command:**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"printf %s git\\ cherry-pick\\ abc"}}' \
  | REPO_ROOT=/workspaces/zskills bash .claude/hooks/block-unsafe-project.sh
```

**Result: does NOT fire.** No `permissionDecisionReason` was emitted; the hook exits 0 with empty stdout. The bash regex `git[[:space:]]+cherry-pick` requires literal whitespace between `git` and `cherry-pick`; the synthesized command `printf %s git\ cherry-pick\ abc` arrives over the JSON wire as `printf %s git\\ cherry-pick\\ abc` (backslash-escaped space, not a literal space character), so the regex does not match. `bash -x` trace confirmed this resolution.

**Implication (per DA2-H-5):** trace = (b). Overview wording stays as "structurally identical and unprotected by prior patches" (hypothesis form). NOT promoted to a PR acceptance test — PR5 already covers the post-migration ALLOW assertion; this empirical capture is for the reference doc only. The structural defect remains: a real-world invocation that DOES contain a literal `git ` + `cherry-pick` substring (e.g., `grep 'git cherry-pick' file`) on main IS expected to trip the line-540 rule, and the migration to `is_git_subcommand "$cmd" cherry-pick` closes that path along with the line-404 commit-site closure.

---

## 4. Tokenize-then-walk source-of-truth file

`hooks/_lib/git-tokenwalk.sh` is the canonical body of the two helpers — `is_git_subcommand` and `is_destruct_command` — introduced by Phase 2 of this plan. Both `block-unsafe-project.sh.template` and `block-unsafe-generic.sh` inline the function bodies verbatim from this file (no runtime `source`; see D2 for rationale). Plan B's `block-stale-skill-version.sh` will inline from the same file post-D6 consolidation (Phase 6).

A drift gate at `tests/test-hook-helper-drift.sh` (Phase 5.4, see D7) asserts that every consumer of `hooks/_lib/git-tokenwalk.sh` carries a byte-identical inlined function body. CI failure on drift, not a maintenance gamble.

---

## 5. Plan B coordination

Per D6: this plan owns the source-of-truth at `hooks/_lib/git-tokenwalk.sh`; Plan B (`SKILL_VERSION_PRETOOLUSE_HOOK.md`) refines to consume it. Two paths are valid and Phase 6 of this plan handles both symmetrically:

- **Path A (optional, before this plan's Phase 6):** a human orchestrator dispatches `/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` BEFORE Plan B's Phase 2 lands, so Plan B's hook arrives already consuming `hooks/_lib/git-tokenwalk.sh`. This plan's Phase 6 then becomes a no-op verification.
- **Path B (canonical, default):** Plan B lands its own copy of `is_git_commit`, then this plan's Phase 6 (post-merge) migrates Plan B's hook to consume the source-of-truth. One-commit refactor with the same Phase 3.x discipline as this plan's other hook migrations.

If Plan B status is `complete` at Phase 6 start, `/refine-plan` is NOT appropriate (it operates only on active plans); Phase 6.4 D&C edits `tests/test-block-stale-skill-version.sh` directly to call `is_git_subcommand "$cmd" commit` instead of `is_git_commit "$cmd"`, with an explanatory commit-message line citing this plan's Phase 6.
