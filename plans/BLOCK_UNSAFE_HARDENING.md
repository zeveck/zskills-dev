---
title: Block-Unsafe Hooks Hardening
created: 2026-05-06
status: active
---

# Plan: Block-Unsafe Hooks Hardening

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Both `hooks/block-unsafe-project.sh.template` and `hooks/block-unsafe-generic.sh` classify Bash commands by **bare-substring regex** (`[[ "$COMMAND" =~ git[[:space:]]+commit ]]`, `git[[:space:]]+restore[[:space:]]`, `git[[:space:]]+reset[[:space:]]+--hard`, etc.). The regex matches the literal verb anywhere in the command buffer, including inside `grep` / `sed` / `awk` / `cat` / `echo` / `printf` positional args, `gh` search expressions, and any other read-only invocation that *describes* a destructive command rather than executing one. This shape has tripped the hooks four observed times in the last three days (research §B.1-B.4, including one fired during the prior-art research session itself, and one that fired against THIS plan's drafting session — the drafter's own `grep -nE '(kill -9|killall|pkill|fuser -k|...)'` was BLOCKED on substring match while reading source). PR #73 (Issue #58) and PR #87 (Issue #81) patched this hook for prior over-match incidents — both added regex bandages for the *specific shape* that triggered, not the class. This plan stops the bandage trail.

**Structural fix.** Generalize Plan B's `is_git_commit` tokenize-then-walk pattern (`SKILL_VERSION_PRETOOLUSE_HOOK.md` Phase 2.1, lines 165-200; D&C "Match strategy" lines 292-293) into a verb-parameterized helper `is_git_subcommand "$cmd" "<verb>"` and a sibling `is_destruct_command "$cmd" "<verb>"` for non-git destructive commands (kill family, rm family, find -delete, rsync --delete, xargs ... kill / rm). Replace every bare-substring `git[[:space:]]+verb` and bare-substring destructive-command predicate in both hooks with calls to these helpers. The helpers are inlined in each hook (no shared `hooks/lib/` — matches the existing convention; Plan B inlines `is_git_commit` the same way). The fix LAYERS OVER the existing two-pass redaction (heredoc + flag-scoped quoted-arg) at lines 41-58 of project hook and 65-84 of generic hook — that redaction is **load-bearing for these hard-deny hooks** (unlike Plan B's harmless-soft-fail context) and stays. Tokenize-then-walk runs on `$COMMAND_REDACTED`; redaction strips `git commit -m "…"` bodies and `gh pr create --body "…"` bodies, then tokenize-walk decides whether the *invocation itself* is the target verb.

**Patch trail this plan closes.** The unifying defect class is "regex-based command classification scanning the entire `$COMMAND` buffer rather than a tokenized command structure." Three prior patches — #58/#73 (rules a/b → PUSH_ARGS extraction), #81/#87 (rule c → PUSH_ARGS scope, outer gate `$` anchor), #84 (mirror-regen recipe centralization) — each closed one shape and left the class open. The line-540 cherry-pick site has the identical *structural shape* as the line-404 commit site (`[[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main`) and is unprotected by any of the prior patches (#58/#73/#81/#87/#84 all targeted commit/push, never cherry-pick). Whether it currently fires on `grep "git cherry-pick"` while on main is a **structural hypothesis** that Phase 1's R-trace verification will empirically confirm or refute (per the plan's own per-reproducer empirical discipline; round-1 DA-M-1 + round-2 DA2-H-5). The line-616 push outer gate at `block-unsafe-project.sh.template:616` and 719 still uses bare substring even after PR #87 — PR #87's own body acknowledges *"if any future check is added that tests $COMMAND instead of PUSH_ARGS, it'll regress."* This plan replaces all five bare-substring sites in the project hook plus all six destructive-verb sites in the generic hook (`git restore`, `git clean -f`, `git reset --hard`, `git add . / -A`, `git commit --no-verify`, plus the kill family and rm family) with token-aware classification. Acceptance criteria pin the **bug class**, not specific shapes — this is the discipline the prior patches missed.

**Coordination with Plan B (`SKILL_VERSION_PRETOOLUSE_HOOK.md`, status: active, 5 phases pending).** Plan B Phase 2 implements `is_git_commit` for the new `block-stale-skill-version.sh` hook. The two plans touch disjoint files (Plan B: `hooks/block-stale-skill-version.sh` new; this plan: `hooks/block-unsafe-project.sh.template` + `hooks/block-unsafe-generic.sh` existing). **Earlier drafts asserted "either may land first"; round-1 DA review (DA-C-3) showed both orderings ship duplicated, drifted helper code regardless.** This plan now declares an explicit ordering decision (D6) and a coordination protocol: this plan introduces the source-of-truth helpers in `hooks/_lib/git-tokenwalk.sh`; both this plan's hooks AND Plan B's hook inline from that fixture. Plan B's Phase 2 spec is updated via `/refine-plan` either before this plan lands (if Plan B is still pending) or in this plan's Phase 6 (post-merge consolidation phase). See D6 below.

**Non-goals.**
- Renaming `block-unsafe-project.sh.template` to drop the `.template` suffix (would cascade into `tests/test-hooks.sh:392` `PROJECT_HOOK=` constant; explicitly out of scope per Plan B D1 finding).
- Replacing or restructuring the existing two-pass data-region redaction at lines 41-58 / 65-84. The redaction is load-bearing AND proven (no bug reports against the redaction itself); modifying it is out of scope.
- Hardening `is_main_protected()` (lines 153-165 of project hook). It's pure config-read; the over-match risk is at every call site that ANDs it with a `git[[:space:]]+verb` substring scan. This plan fixes the call sites; the predicate stays.
- Hardening `is_on_main()` (lines 167-188). Already worktree-aware via `extract_cd_target` precedence; not part of the over-match class.
- Hardening `block-agents.sh` or `warn-config-drift.sh`. Those use different matchers/event pairs; out of scope.
- Adding `jq` (zskills convention is bash regex JSON parsing; no `jq` in hooks).
- Skill `metadata.version` bumps for any skill OTHER than `skills/update-zskills/SKILL.md`. Phase 2.6 (round-2 R2-L-2) adds a one-line install-loop comment to `update-zskills/SKILL.md` to document `hooks/_lib/` exclusion; per the skill-versioning rule, that one edit DOES require a `metadata.version` bump. No other skill is touched.

## Decisions (D1-D7)

The 7 design decisions are resolved here verbatim; Phase 1's reference doc snapshots the same rationale for downstream agents (formatted as `### D1` … `### D7` headings, both in this section and in the reference doc, so AC1's grep `^### D[1-7] —` matches).

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

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Reference doc + reproducer trace verifications | ✅ Done | `2c0c4f1` | reference doc landed (232 lines); R1/R4/R5 fire today (empirical traces captured); R2 marked UNTRACED-IN-SYNTHESIS (no destructive substring in the literal command); R3 UNTRACED per DA-C-1; line-540 cherry-pick verification: outcome (b), does NOT fire today — Overview wording stays as hypothesis form |
| 2 — Source-of-truth helpers + harness extension + unit tests | ✅ Done | `57706e9` | helpers + 127 unit cases + harness landed; full suite 2238/2238 (+127 vs baseline 2111); 3 plan-text drift items recorded (AC9 pre-existing jq comment; AC10 XCC8 vs XCC28 typo; AC3 case count 124 vs 127) |
| 3 — Migrate block-unsafe-project.sh — 6 call sites + bypass-canary tests | ✅ Done | `561a73c` | 6 outer gates migrated via new hook-local `is_git_subcommand_in_chain` wrapper (segment-walks `&&`/`||`/`;`/`|`/`\n`); 20 PR1-PR10 cases added; full suite 2258/2258 PASS; pre-existing cd-chain regressions caught and fixed via the wrapper; test-helper JSON-shape latent bug also fixed |
| 4 — Migrate block-unsafe-generic.sh — destructive-verb sites + bypass-canary tests | 🟡 In Progress | — | 7 git-verb sites (round-2 DA2-H-1 reinstated checkout): checkout/restore/clean/reset/add/--no-verify/push; lone-verb destructive sites (kill family). Pipeline-segment-bound rules (XARGS_KILL, RM_RECURSIVE, fuser combined-flag) STAY UNCHANGED — round-1 DA-C-2 |
| 5 — CHANGELOG + class-pinned acceptance canaries + drift gate + finalization | ⏳ Pending | — | 144-case + 192-case matrices; 4 known reproducers; new `tests/test-hook-helper-drift.sh`; PLAN_INDEX update |
| 6 — Plan B consolidation (post-merge) | ⏳ Pending | — | Conditional: refines Plan B's hook to consume `hooks/_lib/git-tokenwalk.sh`. May be no-op if Plan B was `/refine-plan`d before its Phase 2 landed (D6) |

---

## Phase 1 — Reference doc + reproducer trace verifications

### Goal

Lock the 7 decisions (D1-D7 above) in a reference document and catalogue the 4 known reproducers (research §B.1-B.4) plus the live drafter-session reproducer that fired during prior-art research as manual-recipe verifications. This phase produces ONE artifact: `references/block-unsafe-hardening.md`. NO code lands in `hooks/`, `skills/`, `tests/`, or `.claude/` in this phase.

### Work Items

- [ ] 1.1 — Author `references/block-unsafe-hardening.md`. Body sections (in order):
  1. **Decisions D1-D7** copied verbatim from this plan's Decisions section (heading form `### D1 — …` so AC1's grep works; AC1's threshold is now `7` not `5`).
  2. **Known reproducers (manual recipes)** — five subsections, R1-R5. **Each subsection MUST include an empirical deny-envelope trace** (round-1 DA-M-1): run the literal command against the current installed hook, capture the JSON `permissionDecisionReason` text, and quote it in the doc. If the command does NOT currently trip any hook regex, mark the subsection `### R# — UNTRACED (no current regex matches; included as documented historical incident)` and explicitly call out that this reproducer is NOT promoted to a class-pinned AC test.
     - **R1** (research B.1): `grep -n 'git commit\|...' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh` — empirical trace MUST capture which line fires (likely 411).
     - **R2** (research B.2): `sed -n '404,420p' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh` — empirical trace.
     - **R3** (research B.3, **DEMOTED per round-1 DA-C-1; round-2 DA2-H-1 methodological note**): `gh issue list --state open --search 'block-unsafe-project OR git-commit OR over-match OR false-positive in:title,body'`. Round-1 + round-2 empirical re-verification both confirmed this specific shape does not currently trip any hook. **MARK R3 AS UNTRACED.** Do NOT add a PR3 acceptance test (Phase 3.4 update mandatory). **Methodological note (round-2 DA2-H-1):** "synthetic isolation test passes" is necessary but not sufficient evidence of safety — the round-2 DA's own session experienced a real block on a different `grep` shape that did not reproduce in synthesis (likely the COMMAND buffer Claude Code constructs differs from a hand-built `echo '{...}' | bash hook` reproducer). UNTRACED status reflects "no current synthetic reproducer" not "guaranteed safe." A NEW reproducer that surfaces post-merge SHOULD be added as `R6` / `R7` etc. with empirical capture, NOT silently discarded as "couldn't reproduce."
     - **R4** (research B.4): `grep -nE '(commit.*OR|over-match|grep.*git commit|sed.*block-unsafe|...)' /workspaces/zskills/tests/test-hooks.sh` — empirical trace; expect line 411 (project commit transcript site, no `&& main_protected` guard) to fire on the `grep.*git commit` substring.
     - **R5** (drafter-session live): `grep -n -E '(kill -9|killall|pkill|fuser -k|RM_RECURSIVE|find .* -delete|rsync .*--delete|xargs.*kill|xargs.*rm)' /workspaces/zskills/hooks/block-unsafe-generic.sh` — empirically confirmed to BLOCK; rule lives at `block-unsafe-generic.sh:140` (the `kill -9` regex), the deny-string at `:141`. Round-1 refiner verification re-confirmed this fires today. (Round-2 R2-M-3 cosmetic note: rule line = 140, message line = 141; both are correct citations of different artifacts.)
  3. **Patch-trail-this-plan-closes** — the 4-row table from this plan's Overview, verbatim. **Round-2 DA2-H-5 lock:** the Overview's claim about line-540 cherry-pick ("structurally identical and unprotected by prior patches") is a structural hypothesis (NOT a current empirical-block claim — round-2 refiner deliberately rephrased per DA2-H-5). This Phase 1 reference doc MUST add a verification subsection: an empirical run of `printf '%s' '{"tool_name":"Bash","tool_input":{"command":"printf %s git\\ cherry-pick\\ abc"}}' | bash .claude/hooks/block-unsafe-project.sh` on a synthesized-`is_on_main: true` + `main_protected: true` test fixture, capturing whether line 540 fires today on a `printf` of cherry-pick text. Either (a) the trace fires → upgrade Overview wording to "currently fires"; (b) the trace does not fire → Overview wording stays as "structurally identical and unprotected by prior patches" (hypothesis form). Do NOT promote this verification to a PR acceptance test (PR5 already covers the post-migration ALLOW assertion); the empirical capture is for the reference doc only.
  4. **Tokenize-then-walk source-of-truth file** — short subsection (5-10 lines) noting `hooks/_lib/git-tokenwalk.sh` is the canonical body, inlined into both this plan's hooks AND Plan B's hook (post-D6); cite the drift-gate at `tests/test-hook-helper-drift.sh`.
  5. **Plan B coordination** — short subsection summarizing D6: this plan owns the source-of-truth; Plan B refines to consume it. Either via `/refine-plan` (if Plan B is still pending) or via this plan's Phase 6 (post-merge consolidation).

  The reference document is the single source of truth that subsequent phases cite — do NOT scatter D1-D7 rationale across phase prose.

- [ ] 1.2 — Verify the plan is registered in `plans/PLAN_INDEX.md` "Ready to Run". If absent, add a row matching the existing format. Idempotent.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit at end of phase, scope = `references/block-unsafe-hardening.md` + (if needed) `plans/PLAN_INDEX.md` row. Subject: `feat(plans): BLOCK_UNSAFE_HARDENING Phase 1 — reference doc + reproducer catalogue`.
- **No code in `hooks/`, `skills/`, `tests/`, or `.claude/` in this phase.** Verification of the reproducers is recipe-form in the reference doc; Phase 5 turns them into executable test cases.
- **No `--no-verify`.**
- **No skill metadata.version bump** (no SKILL.md edits in this phase or any phase of this plan).

### Acceptance Criteria

- [ ] AC1 — `[ -f references/block-unsafe-hardening.md ]` AND `grep -c '^### D[1-7] —' references/block-unsafe-hardening.md` returns `7`.
- [ ] AC2 — `grep -cE '^### R[1-5]( |$)' references/block-unsafe-hardening.md` returns `5` (one per known reproducer; H3 level so visible in TOC).
- [ ] AC3 — `grep -F 'BLOCK_UNSAFE_HARDENING' plans/PLAN_INDEX.md` returns ≥ 1 match.
- [ ] AC4 — `git diff --stat HEAD~1..HEAD` after the phase commit shows ONLY `references/block-unsafe-hardening.md`, and optionally `plans/PLAN_INDEX.md`. No other paths.
- [ ] AC5 — `grep -F 'is_git_subcommand' references/block-unsafe-hardening.md` returns ≥ 1 AND `grep -F 'is_destruct_command' references/block-unsafe-hardening.md` returns ≥ 1.
- [ ] AC6 — Each reproducer subsection (R1, R2, R4, R5) contains a fenced-code block with the literal `permissionDecisionReason` text captured from running the command against the installed hook. R3 subsection contains the literal text `UNTRACED` (round-1 DA-C-1). Verify: `grep -c 'permissionDecisionReason' references/block-unsafe-hardening.md` returns ≥ 4 AND `grep -c '^### R3 — UNTRACED' references/block-unsafe-hardening.md` returns 1.

### Dependencies

None. Phase 1 is a pure precondition.

---

## Phase 2 — Source-of-truth helpers + harness extension + unit tests

### Goal

Land FOUR artifacts:
1. `hooks/_lib/git-tokenwalk.sh` — the source-of-truth file containing both helper bodies (per D2). NEW directory `hooks/_lib/` introduced.
2. `tests/test-tokenize-then-walk.sh` — standalone unit test file with ~92 cases (88 from round-0 + XCC23/XCC24/XCC25 + the new subcommand-quote-strip XCC26/XCC27 from round-1 DA-H-1).
3. `tests/test-hooks-helpers.sh` — NEW harness extension file holding `setup_project_test_on_main` and supporting helpers (round-1 R-C-1 / R-H-6). Sourced by both `tests/test-hooks.sh` (Phase 3) AND `tests/test-hooks.sh` matrix loops (Phase 5).
4. Single `run_suite` line addition to `tests/run-all.sh` for `test-tokenize-then-walk.sh`.

The unit test file is standalone (Option B from research §C.1) rather than appended to `tests/test-hooks.sh` because (a) the helpers are fresh code with no prior coverage to integrate against, (b) standalone makes cherry-pick / revert clean if Phases 3-4 need to be split, (c) it mirrors Plan B's `tests/test-block-stale-skill-version.sh` convention. Phases 3-4 add migration-specific *integration* tests (bypass-canary cases against the migrated hooks) directly to `tests/test-hooks.sh` because that's where the existing hook coverage lives.

**Helper API change vs. round-0 draft (round-1 R-H-2 / DA-M-6).** The hybrid pattern `is_git_subcommand && [[ "$COMMAND" =~ <flag> ]]` re-introduces $COMMAND-wide false-positive matches (e.g., `git checkout main && grep -- pat` would trip the migrated `git checkout --` rule because `--` exists somewhere in the buffer). To fix this, `is_git_subcommand` is extended to set TWO globals on success:
- `GIT_SUB_INDEX` — the array index immediately AFTER the matched verb token.
- `GIT_SUB_REST` — the post-verb tokens joined by single spaces (a clean buffer for downstream regex checks scoped to the matched git invocation only).

Hybrid migrations in Phase 4.2 then use `[[ "$GIT_SUB_REST" =~ <flag> ]]` instead of `[[ "$COMMAND" =~ <flag> ]]`, restoring segment-bounded discrimination. `GIT_SUB_REST` is reset to `""` on no-match so stale data from a prior call doesn't leak.

**Helper API change vs. round-0 draft (round-1 DA-H-1).** The fixture's `is_git_subcommand` unwraps quotes around the `git` token only; the subcommand token (`commit`, `push`, etc.) is compared literally. This lets `git "commit"` slip past `main_protected`. Fix: apply the same one-layer quote-strip to the subcommand token before comparison. New cases XCC26 (`git "commit"` → match) and XCC27 (`git 'commit'` → match) lock the fix.

### Work Items

- [ ] 2.1 — Author `tests/test-tokenize-then-walk.sh` (test-first; the helpers don't exist yet, so the test fails on first run — that's expected). Sources the helpers from `hooks/_lib/git-tokenwalk.sh` (created in 2.2) so the unit tests run against the exact source-of-truth bodies that Phases 3-4 inline. Cases (mirror Plan B's C1-C11 + C7a-C7j + C10e structure, parameterized over 3 git verbs):

  **`is_git_subcommand` cases (per verb in {commit, cherry-pick, push}; case-id prefix `XCC` for commit, `XCP` for cherry-pick, `XPU` for push):**
  - `XCC1` — `git commit` → match (positive baseline)
  - `XCC2` — `git status` → no match (negative; non-target verb)
  - `XCC3` — `git commit -am 'msg'` → match
  - `XCC4` — `git commit --amend` → match
  - `XCC5` — `git -C /tmp/foo commit -m bar` → match (`-C path` two-token consume)
  - `XCC6` — `git -C /tmp/foo log` → no match (`-C` allowance must not over-match other subcommands)
  - `XCC7` — `git -c user.email=x@y.z commit -m msg` → match (`-c key=val` two-token consume)
  - `XCC8` — `git --no-pager commit -m foo` → match (any `--…` long flag, single-token consume)
  - `XCC9` — `git --git-dir=/x commit` → match (long-flag with embedded `=value`)
  - `XCC10` — `git -P commit` → match (short-form `--no-pager`)
  - `XCC11` — `git -C /tmp -c user.email=x commit` → match (mixed `-C` AND `-c`)
  - `XCC12` — `git --git-dir=/x --work-tree=/y commit -m msg` → match (multiple long flags in series)
  - `XCC13` — `git --no-pager log` → no match (subcommand check after flag-skip is `log`)
  - `XCC14` — `git -C /tmp diff` → no match
  - `XCC15` — `FOO=bar git commit -m msg` → match (env-var prefix)
  - `XCC16` — `   git commit` (leading whitespace) → match
  - `XCC17` — `echo "git commit"` → no match (mention in echo arg; first token is `echo`)
  - `XCC18` — `grep -n 'git commit' file.sh` → no match (mention in grep arg) — **DIRECT class-1 reproducer R1**
  - `XCC19` — `sed -n 's/git commit/git push/' file.sh` → no match (mention in sed arg)
  - `XCC20` — `cat file.sh | grep 'git commit'` → no match (first token is `cat`; piped grep is in a separate segment but tokenize-walk only sees the first token)
  - `XCC21` (negative; documented carve-out per D5) — `bash -c 'git commit -m foo'` → no match (first token is `bash`)
  - `XCC22` — `git commit && git push` → match `git commit` (the chained `git push` is a different segment; `is_git_subcommand "$cmd" "commit"` returns 0 because the first segment is `git commit`)
  - `XCC23` (negative; D5 carve-out — command substitution) — `git $(echo commit) -m foo` → no match (defensive match-failure: tokenizer sees `$(echo` as a non-`-`-prefixed non-flag token, falls out of flag-skip, fails subcommand check)
  - `XCC24` (negative; D5 carve-out — backticks) — `` git `echo commit` -m foo `` → no match (same defensive failure; first post-`git` token starts with `` ` `` not `-`)
  - `XCC25` (negative; D5 carve-out — variable expansion) — `GIT_VERB=commit; git $GIT_VERB` → no match (token after `git` is literal `$GIT_VERB`, not `commit`)
  - `XCC26` (positive; round-1 DA-H-1 fix) — `git "commit"` → match (subcommand token quote-stripped)
  - `XCC27` (positive; round-1 DA-H-1 fix) — `git 'commit'` → match (subcommand token quote-stripped)
  - `XCC28` (positive; GIT_SUB_REST exposure) — after `is_git_subcommand "git commit -m foo --no-verify" commit` returns 0, assert `[[ "$GIT_SUB_REST" =~ --no-verify ]]` is true AND `GIT_SUB_INDEX` equals `2` (post-`commit` index).
  - `XCC29` (negative; GIT_SUB_REST scoping) — after `is_git_subcommand "git checkout main && rm foo -- bar.txt" checkout` returns 0, assert `[[ "$GIT_SUB_REST" =~ [[:space:]]--([[:space:]]|$) ]]` is FALSE (because `--` is in the post-`&&` segment, NOT in the post-`checkout` slice — `GIT_SUB_REST` should contain only `main` and stop at the segment boundary if the helper splits on `&&`/`;`/`||`/`|`; OR contain `main && rm foo -- bar.txt` but the AC requires the helper to truncate at the FIRST shell-segment boundary). **Spec for the helper: `GIT_SUB_REST` is built by joining tokens from `GIT_SUB_INDEX` up to the first token that is `&&`, `||`, `;`, or `|` (exclusive). This restores the segment-scoped semantics the bare-substring regex provided.**
  - `XCC30` (carve-out lock; round-2 R2-C-1 / DA2-C-1) — after `is_git_subcommand "git reset 'msg --hard text'" reset` returns 0, assert `[[ "$GIT_SUB_REST" =~ --hard ]]` is TRUE. **This case PINS the documented quote-blind carve-out (D5).** `read -ra` is whitespace-only-tokenizing and does not honor shell quoting — `--hard` from inside a single-quoted arg appears as its own token and ends up in `GIT_SUB_REST`. The hybrid `clean -f` / `reset --hard` migrations WILL trip on quoted args containing the discriminator literal. Narrower than the bare-substring whole-buffer class the plan closes (which trips on ANY mention anywhere in the buffer; this only trips when the mention is inside a real `git $VERB` invocation's quoted arg) but a real residual carve-out.
  - `XCC31` (carve-out lock; round-2 R2-C-1 / DA2-C-1) — after `is_git_subcommand 'git clean foo;rm -f bar' clean` returns 0, assert `GIT_SUB_REST` equals `foo;rm -f bar`. **This case PINS the space-elided shell-control carve-out (D5).** `;` glues to the neighbor token (`foo;rm`); the segment-truncation `case '&&'\|'\|\|'\|';'\|'\|') break ;;` never sees `;` as its own token, so the `-f` from the post-`;` `rm` segment leaks into `GIT_SUB_REST`. Hybrid `clean -f` migration WILL trip on `git clean foo;rm -f bar` even though the user's `git clean` call has no `-f` flag. Narrower than bare-substring class (`grep "rm -f" notes.md` no longer trips); a real residual carve-out for users who write space-elided multi-statement commands.
  - `XCC32` (carve-out lock; round-2 DA2-C-1 negative-bypass branch) — after `is_git_subcommand "git commit -m first --no-verify --hard" commit` returns 0, assert `[[ "$GIT_SUB_REST" =~ --no-verify ]]` is TRUE. Documents that the helper handles unredacted multi-flag args correctly when no quote-with-shell-control intersects. (The complementary negative-bypass case — `git commit -m 'first && second' --no-verify` *unredacted at the helper level* — is mitigated by the line-56/82 redaction sed which strips `-m '...'` bodies BEFORE the helper runs; XCC32 is the unit-test-level positive lock that the helper's segment-truncation does not falsely truncate when no `&&`/`\|`/`;` appears in the args.)
  - `XCC33` (carve-out lock; round-2 R2-C-1 false-positive branch) — full integration via Phase 4 GR-NEW: `git clean foo;rm -f bar` → `expect_deny`. Documents that the hybrid `clean -f` rule WILL trip on this shape (false-positive on the `-f` from the post-`;` `rm`). Narrower than bare-substring class. CHANGELOG bullet acknowledges. (No XCC33 unit case — it's Phase 4 integration; XCC31 above is the unit-level invariant that drives this Phase 4 deny.)
  - `XCC34` (carve-out lock; round-2 DA2-M-4) — `is_git_subcommand $'echo hi\ngit commit' commit` returns 1 (no match). **This case PINS the multi-line carve-out (D5).** `read -ra TOKENS <<< "$cmd"` reads only the first line up to the newline; `git commit` on the second line is invisible. Documents that newline-separated multi-statement commands bypass the helper entirely. Same property holds for Plan B's `is_git_commit`.

  Then the same matrix replicated for `cherry-pick` (XCP1-XCP34, swap verb in positive cases) and `push` (XPU1-XPU34). Result: 102 cases total for `is_git_subcommand` (34 × 3 verbs).

  **`is_destruct_command` cases (per verb in {kill, rm, find, rsync}; case-id prefix `XKL` for kill, `XRM` for rm, `XFD` for find, `XRS` for rsync):**

  Note: `is_destruct_command` is FIRST-TOKEN-ANCHORED ONLY. Pipeline-fed forms (`pgrep | xargs kill`, `cat foo | xargs rm`) and combined-flag forms (`fuser -mk`) are NOT covered by this helper — they are handled by the EXISTING well-bounded regexes (`XARGS_KILL`, the `fuser -[a-z]*k[a-z]*` combined-flag pattern). Phase 4 leaves those existing regexes UNCHANGED; this helper only replaces the bare-substring rules where the destructive verb genuinely IS the first token of a command. See round-1 DA-C-2 for the canonical analysis.

  - `XKL1` — `kill -9 1234` → match (positive baseline; first-token-anchored)
  - `XKL2` — `grep -n 'kill -9' notes.md` → no match (mention in grep arg) — **DIRECT class-1 reproducer R5**
  - `XKL3` — `echo "use kill -9 to force"` → no match
  - `XKL4` — `kill 1234` (no -9) → no match (helper requires the flag-discriminator)
  - `XKL5` — `kill -KILL 1234` → match
  - `XKL6` (positive; round-1 R-H-5 — positional pair) — `kill -s 9 1234` → match (helper extension: `flag_match` matched on `-s` AND next token matches `^(9|KILL|SIGKILL)$` — see 2.2 helper update)
  - `XKL7` (negative; round-1 R-H-5) — `kill -s USR1 1234` → no match (`-s` followed by non-destructive signal name; positional-pair check rejects)
  - `XKL8` (carve-out; pipeline-fed) — `pgrep node | xargs kill` → no match by `is_destruct_command` (first token `pgrep`). **THIS CASE LIVES IN THE EXISTING `XARGS_KILL` REGEX AT generic.sh:157, WHICH IS UNCHANGED.** This unit case is a NEGATIVE assertion that `is_destruct_command` itself does NOT cover the pipeline shape.
  - `XKL9` (carve-out lock; round-2 R2-H-1 — over-match-tolerance positive) — `is_destruct_command "kill 1234 -9" kill '^-(9|KILL|SIGKILL)$'` returns 0 (match). **PINS the documented over-match.** The helper scans ALL post-first-token tokens for `flag_match`; it does NOT restrict to flag-position. So a stray `-9` arg (here, in PID-position) trips the rule. This is acceptable (the actual destructive forms are conventional), but the test locks it so a future "tighten to flag-position" refactor is a deliberate choice with a failing test.
  - `XKL10` (carve-out lock; round-2 R2-H-1 — first-token-only-with-empty-flag) — `is_destruct_command "pkill 1234 -9" pkill ''` returns 0 (match). **PINS the empty-flag_match semantics.** When `flag_match=""`, the helper matches solely on first-token-equals-verb. So `pkill 1234 -9` matches because first token is `pkill`; the `-9` is irrelevant. Defensive lock against a refactor that adds inadvertent flag-scanning to the empty-flag branch.
  - `XKL11` (carve-out lock; round-2 DA2-H-3) — `is_destruct_command "env -i kill -9 1234" kill '^-(9|KILL|SIGKILL)$'` returns 1 (no match). **PINS the `env -i` prefix bypass (D5).** The helper consumes `env` keyword and `KEY=VAL` env-var prefixes but does NOT consume `env`'s own flags. Tokens after env-skip: `[-i, kill, -9, 1234]`. First token is `-i` (post-env), not `kill`, so `is_destruct_command` returns 1. Documented carve-out.
  - `XKL12` (carve-out lock; round-2 DA2-H-3) — `is_destruct_command "sudo kill -9 1234" kill '^-(9|KILL|SIGKILL)$'` returns 1 (no match). **PINS the `sudo` prefix bypass (D5).** Helper does not interpret `sudo`/`doas`/`su` as transparent prefixes. Documented carve-out — a session using `sudo kill -9` to terminate root-owned processes will silently bypass the destructive-flag rule.
  - `XRM1` — `rm -rf /tmp/foo` → match (positive)
  - `XRM2` — `grep 'rm -rf' notes.md` → no match
  - `XRM3` — `rm -f file.txt` → no match (no `-r` flag — helper's flag_match requires `-r*` or `--recursive`)
  - `XRM4` — `printf 'rm -rf %s\n' /tmp/x` → no match (mention in printf arg)
  - `XRM5` — `rm -rf $HOME/foo` → match (the path-safety check is a *separate* policy at `is_safe_destruct`)
  - `XRM6` (carve-out; pipeline-fed) — `cat list.txt | xargs rm -rf` → no match by `is_destruct_command` (first token `cat`). **PIPELINE FORM HANDLED BY EXISTING `RM_RECURSIVE` REGEX AT generic.sh:217 (whole-buffer scan), WHICH IS UNCHANGED.** Negative-assertion case parallels XKL8.
  - `XFD1` — `find /tmp/foo -delete` → match (first token `find`, flag_match `^-delete$` matches)
  - `XFD2` — `grep "find . -delete" notes.md` → no match
  - `XRS1` — `rsync -av src/ dst/ --delete` → match
  - `XRS2` — `grep "rsync --delete" notes.md` → no match

  Total: 22 cases for `is_destruct_command` (round-2 added XKL9/10/11/12 = 4 new; running total: 8 + 6 + 2 + 2 + 4 = 22).

  **Grand total: 102 (`is_git_subcommand` × 3 verbs = 34 × 3 = 102; round-2 added XCC30/31/32/34 = 4 new per verb) + 22 (`is_destruct_command`) = 124 cases.** AC3 below pins `≥ 124` (round-2 update from `≥ 104`). This is the unit-test surface; Phases 3-4 add integration-test cases against the migrated hooks themselves.

- [ ] 2.2 — Author `hooks/_lib/git-tokenwalk.sh` (NEW directory `hooks/_lib/`, NEW file). Contains both helper function definitions plus a `set -u` guard. **Per D2: this file is the source-of-truth, inlined byte-identical into both hooks in Phases 3-4 (and Plan B's hook in Phase 6 / D6 refinement).** The drift gate at Phase 5.4 enforces byte-equality.

  ```bash
  #!/bin/bash
  # hooks/_lib/git-tokenwalk.sh — source-of-truth helper bodies for
  # is_git_subcommand + is_destruct_command. Inlined verbatim into
  # hooks/block-unsafe-project.sh.template, hooks/block-unsafe-generic.sh,
  # and hooks/block-stale-skill-version.sh (Plan B, post-D6).
  # Maintain HERE only. CI gate: tests/test-hook-helper-drift.sh.
  set -u

  # Returns 0 iff $cmd is a git invocation whose subcommand is $want_sub.
  # On match, also sets:
  #   GIT_SUB_INDEX = array index immediately after the matched subcommand
  #     token (i.e., the first arg position).
  #   GIT_SUB_REST  = post-subcommand args joined by single spaces, TRUNCATED
  #     at the first shell-segment boundary token (`&&`, `||`, `;`, `|`).
  #     Provides a properly scoped buffer for downstream regex checks.
  # On no-match, GIT_SUB_INDEX=-1 and GIT_SUB_REST="" (callers may rely on
  # this reset to avoid stale data leaking from a prior call).
  #
  # Tokenize-then-walk: skip env-var prefixes (KEY=VAL...), optional `env`,
  # find literal `git`, walk past top-level flags (-C/-c consume next token,
  # other -X / --foo / --foo=bar consume single token), check next token == $want_sub.
  # Quoted-`git` ("git"/'git') and quoted-subcommand ("commit"/'commit') are
  # both unwrapped one quote layer to tolerate JSON-wire-format double-quote
  # injection (round-1 DA-H-1 fix).
  is_git_subcommand() {
    local cmd="$1"
    local want_sub="$2"
    GIT_SUB_INDEX=-1
    GIT_SUB_REST=""
    local -a TOKENS
    # shellcheck disable=SC2206
    read -ra TOKENS <<< "$cmd"
    local i=0 n=${#TOKENS[@]}
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    local g="${TOKENS[$i]:-}"
    g="${g%\"}"; g="${g#\"}"
    g="${g%\'}"; g="${g#\'}"
    [[ "$g" != "git" ]] && return 1
    ((i++))
    while [[ $i -lt $n && "${TOKENS[$i]:0:1}" == "-" ]]; do
      case "${TOKENS[$i]}" in
        -C|-c) ((i+=2)) ;;
        *)     ((i+=1)) ;;
      esac
    done
    local sub="${TOKENS[$i]:-}"
    sub="${sub%\"}"; sub="${sub#\"}"
    sub="${sub%\'}"; sub="${sub#\'}"
    [[ "$sub" != "$want_sub" ]] && return 1
    # Match. Set GIT_SUB_INDEX and build GIT_SUB_REST scoped to the
    # current shell segment (truncate at first &&/||/;/|).
    GIT_SUB_INDEX=$((i + 1))
    local j=$GIT_SUB_INDEX
    local rest=""
    while [[ $j -lt $n ]]; do
      case "${TOKENS[$j]}" in
        '&&'|'||'|';'|'|') break ;;
      esac
      rest="$rest ${TOKENS[$j]}"
      ((j++))
    done
    # Strip the leading space introduced by the loop.
    GIT_SUB_REST="${rest# }"
    return 0
  }

  # Returns 0 iff $cmd is a destructive invocation whose FIRST token (after
  # env-var-prefix skip) is $want_first AND (if $flag_match is non-empty)
  # one of the subsequent flag tokens matches the $flag_match regex.
  #
  # FIRST-TOKEN-ANCHORED ONLY. Pipeline-fed forms (e.g., `cat foo | xargs rm`,
  # `pgrep node | xargs kill`) and combined-flag forms (e.g., `fuser -mk`)
  # are NOT covered by this helper — they are handled by the EXISTING
  # well-bounded regexes in block-unsafe-generic.sh (XARGS_KILL at line 157,
  # RM_RECURSIVE at line 217, fuser combined-flag at line 146). Phase 4
  # leaves those existing regexes UNCHANGED. See round-1 DA-C-2.
  #
  # Pass $flag_match="" for "first token == verb" only (e.g., killall,
  # pkill — single-token verbs whose presence at position 0 is itself the
  # destructive signal).
  #
  # Positional-pair semantics for kill -s <SIGNAL>: if $flag_match contains
  # the literal `:next:<regex>` suffix, the helper also requires the NEXT
  # token after the matched flag to satisfy <regex>. Used for `kill -s 9`
  # vs. `kill -s USR1` (round-1 R-H-5). Example: flag_match='^-s$:next:^(9|KILL|SIGKILL)$'.
  is_destruct_command() {
    local cmd="$1"
    local want_first="$2"
    local flag_match="${3:-}"
    local next_match=""
    if [[ "$flag_match" == *":next:"* ]]; then
      next_match="${flag_match##*:next:}"
      flag_match="${flag_match%:next:*}"
    fi
    local -a TOKENS
    # shellcheck disable=SC2206
    read -ra TOKENS <<< "$cmd"
    local i=0 n=${#TOKENS[@]}
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    local first="${TOKENS[$i]:-}"
    first="${first%\"}"; first="${first#\"}"
    first="${first%\'}"; first="${first#\'}"
    [[ "$first" != "$want_first" ]] && return 1
    [[ -z "$flag_match" ]] && return 0
    ((i++))
    while [[ $i -lt $n ]]; do
      if [[ "${TOKENS[$i]}" =~ $flag_match ]]; then
        if [[ -n "$next_match" ]]; then
          local next_tok="${TOKENS[$((i+1))]:-}"
          [[ "$next_tok" =~ $next_match ]] && return 0
        else
          return 0
        fi
      fi
      ((i++))
    done
    return 1
  }
  ```

  **Helper notes:**

  - `is_destruct_command` scans ALL subsequent tokens for `flag_match` rather than restricting to flag-position tokens — this is because forms like `find /tmp -delete` and `rsync -av src/ dst/ --delete` put the destructive flag arbitrarily late in the arg list. The over-match risk (e.g., `kill 1234 -9` where `-9` is a stray arg) is acceptable because the actual destructive-flag forms are conventional. **Round-2 R2-H-1 lock:** the over-match tolerance is now test-pinned via XKL9 (`kill 1234 -9` → match, documents that the carve-out trips by design) and XKL10 (`pkill 1234 -9` → match because `pkill` uses `flag_match=""`, asserts first-token-only behavior). These two cases lock the documented carve-out so it can't drift either direction in future refactors.
  - The `:next:<regex>` suffix encoding for positional-pair flag matching (R-H-5) is intentionally a string-suffix on `flag_match` rather than a fourth helper parameter. This keeps the helper signature stable for callers that don't need positional-pair semantics, and makes the "this rule needs positional discrimination" intent visible at the call site. (Round-2 DA2-L-1 noted the encoding is brittle if a regex literally contains `:next:`; that's exotic and unblocking. If a future call site needs literal `:next:` in flag_match, refactor to a 4th positional parameter — only 3-4 call sites currently.)
  - Globals (`GIT_SUB_INDEX`, `GIT_SUB_REST`) are unprefixed for ergonomic call-site use. They are set on EVERY call (success or failure), so callers do not need to gate access — but they are caller-scope-visible so a hook that calls `is_git_subcommand` from inside a function body should `local GIT_SUB_INDEX GIT_SUB_REST` first if isolation matters. The current hooks call from top-level rule blocks; isolation is moot.
  - **`GIT_SUB_INDEX` is exposed for unit-test introspection (XCC28 asserts the post-`commit` index value).** No production caller in Phases 3-5 reads `GIT_SUB_INDEX` directly — all callers use `GIT_SUB_REST`. The dual-global API documents the helper's internal walk position symmetrically and lets future call sites that need finer-grained slicing (e.g., "extract args 1-3, skip arg 4, then check arg 5") use `GIT_SUB_INDEX` without re-tokenizing. Round-2 DA2-O-1 surfaced this as YAGNI; the rationale here is documentation + introspection. If Phase 6 finds no consumer beyond XCC28 emerges by the time Plan B consolidates, drop `GIT_SUB_INDEX` then.

- [ ] 2.3 — Author `tests/test-hooks-helpers.sh` (NEW). Contains the harness extension `setup_project_test_on_main` (round-1 R-C-1 / R-H-6) plus any other helper sharing between Phase 3 integration tests and Phase 5 matrix loops. Required helpers:

  ```bash
  # setup_project_test_on_main — extends setup_project_test by checking out
  # `main` and writing main_protected: true into the runtime config. The
  # existing run_main_protected_test pattern (tests/test-hooks.sh:950-1023)
  # demonstrates the same shape; this helper shares the harness across the
  # PR1-PR11 (Phase 3.4) and matrix (Phase 5.2) test surfaces.
  setup_project_test_on_main() {
    setup_project_test
    # Switch to main (setup_project_test calls `git init`; default branch
    # may be master or main depending on init.defaultBranch). Force-rename.
    (cd "$TEST_TMPDIR" && \
     CB=$(git branch --show-current) && \
     [[ "$CB" != "main" ]] && git branch -m "$CB" main; \
     true)
    # Patch the config to enable main_protected. Reuses the same JSON file
    # setup_project_test already wrote.
    CFG="$TEST_TMPDIR/.claude/zskills-config.json"
    python3 -c "
import json
with open('$CFG') as f: c = json.load(f)
c.setdefault('execution', {})['main_protected'] = True
with open('$CFG', 'w') as f: json.dump(c, f)
"
  }
  ```

  This file is sourced by `tests/test-hooks.sh` AT THE TOP of the project-hook test section (Phase 3.4 and 5.2 callers depend on it). Sourcing pattern: `source "$(dirname "$0")/test-hooks-helpers.sh"`.

  **Verification within Phase 2:** add a self-test inside `test-hooks-helpers.sh` that calls `setup_project_test_on_main` and asserts (a) `git -C "$TEST_TMPDIR" branch --show-current` returns `main`, (b) the runtime config returns true via the same pattern the hook uses (`grep -F '"main_protected": true' "$TEST_TMPDIR/.claude/zskills-config.json"`).

- [ ] 2.4 — Add `tests/test-tokenize-then-walk.sh` to `tests/run-all.sh` dispatcher. Single line per Phase 1.1 §4 of Plan B's reference-doc dispatcher pattern: `run_suite "test-tokenize-then-walk.sh" "tests/test-tokenize-then-walk.sh"`. Insertion point: after the `test-hooks.sh` line (currently `tests/run-all.sh:38`).

- [ ] 2.5 — Run `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and verify the new test file's cases all pass; total suite case count increases by ≥ 124 vs HEAD~1 (102 git-subcommand + 22 destruct).

- [ ] 2.6 (round-2 R2-L-2 / DA2-M-1) — Add a one-line comment to `skills/update-zskills/SKILL.md` Step C near the hook-install enumeration (lines 818-859 or wherever the hook-list lives at implementation time): `# hooks/_lib/git-tokenwalk.sh is the source-of-truth for hooks/block-unsafe-*.sh* helpers. Inlined into each hook; DO NOT install separately.` This converts the silent-future-bug ("a contributor adds it to the install loop thinking it's missing") into a documented constraint at the install site. **Per the skill-versioning rule (CLAUDE.md §"Skill versioning"): this edit MUST bump `metadata.version` for `skills/update-zskills/SKILL.md`** — recompute via `scripts/skill-content-hash.sh skills/update-zskills/`. Insert the bump in the same commit as 2.6.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/_lib/git-tokenwalk.sh` (new) + `tests/test-tokenize-then-walk.sh` (new) + `tests/test-hooks-helpers.sh` (new) + addition to `tests/run-all.sh` (single `run_suite` line) + `skills/update-zskills/SKILL.md` (one-line install-loop comment, round-2 2.6) + skill `metadata.version` bump (recomputed via `scripts/skill-content-hash.sh`). Subject: `feat(hooks): tokenize-then-walk source-of-truth + unit tests + harness extension`.
- **No hook edits in this phase.** The helpers exist only in `hooks/_lib/git-tokenwalk.sh`; Phases 3-4 inline them into `hooks/block-unsafe-*.sh*`. This separation is deliberate: it lets Phase 2 land green (helpers proven correct in isolation) before any hook behavior changes.
- **NO `jq`** — pure-bash regex per zskills convention.
- **NO `--no-verify`.**
- **NO `2>/dev/null`** on critical operations.
- **Test output capture:** `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"`.
- **Defense against bypass via shell-expansion class** (round-1 R-M-3 / D5): `tokenize-then-walk` reads `$cmd` via `read -ra TOKENS <<< "$cmd"` which splits on `$IFS` (whitespace) BUT does not interpret `$()`, backticks, `$VAR`, or `<()`. Per D5, this is the documented carve-out class. Cases XCC23/XCC24/XCC25 each lock one shell-expansion shape as a NEGATIVE assertion. The carve-out is structural, not a bug.
- **`hooks/_lib/` install behavior:** `hooks/_lib/git-tokenwalk.sh` is NOT installed by `/update-zskills` (the underscore-prefix marker; see Phase 5.4 D&C). Consumers' `.claude/hooks/` directory does NOT carry it. The file exists only in this repo as a maintenance artifact. The hooks themselves carry the inlined function bodies. The drift gate (Phase 5.4) runs ONLY in this repo's CI.
- **Subcommand-quote-strip rationale (round-1 DA-H-1):** `git "commit"` arrives in JSON-wire-format with surrounding double-quotes; an attacker who controls the bash string can use this to bypass `main_protected`. The fixture's helper unwraps one layer of quotes around BOTH the `git` token AND the subcommand token. Cases XCC26/XCC27 lock the fix.
- **`GIT_SUB_REST` segment-truncation rationale (round-1 R-H-2 / DA-M-6):** the round-0 hybrid pattern (`is_git_subcommand && [[ "$COMMAND" =~ <flag> ]]`) re-introduced $COMMAND-wide false-positives. Setting `GIT_SUB_REST` to the post-subcommand tokens TRUNCATED at the first shell-segment boundary token (`&&`, `||`, `;`, `|`) restores the per-segment scoping the original bare regex provided. Phase 4.2 migrations use `[[ "$GIT_SUB_REST" =~ <flag> ]]` exclusively (NEVER `[[ "$COMMAND" =~ <flag> ]]` for hybrid checks).

### Acceptance Criteria

- [ ] AC1 — `[ -f hooks/_lib/git-tokenwalk.sh ]` AND `bash -n hooks/_lib/git-tokenwalk.sh` returns 0 (syntactic validity only — round-2 R2-H-4 weakening note: AC1 is a smoke check; correctness is verified via AC2/AC3 + AC10's GIT_SUB_REST exposure assertion). Additionally assert function definitions are reachable: `bash -c 'source hooks/_lib/git-tokenwalk.sh; type -t is_git_subcommand && type -t is_destruct_command' > /tmp/gtwfns 2>&1; grep -c '^function$' /tmp/gtwfns` returns `2` (both helpers are defined as functions).
- [ ] AC2 — `[ -x tests/test-tokenize-then-walk.sh ]` AND `bash tests/test-tokenize-then-walk.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`.
- [ ] AC3 — All cases pass: `grep -c '^PASS' "$TEST_OUT/.test-results.txt"` returns ≥ `124` (round-2: was `≥ 104`; added XCC30/31/32/34 × 3 verbs = 12 + XKL9/10/11/12 = 4 → 16 new cases, total 124).
- [ ] AC4 — `grep -n 'test-tokenize-then-walk.sh' tests/run-all.sh` returns exactly one match in `run_suite "<name>" "tests/<name>"` shape.
- [ ] AC5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`.
- [ ] AC6 — `grep -cF 'is_git_subcommand' hooks/_lib/git-tokenwalk.sh` returns ≥ 1 (function defined) AND `grep -cF 'is_destruct_command' hooks/_lib/git-tokenwalk.sh` returns ≥ 1.
- [ ] AC7 — Direct-class reproducers as named test cases:
  - `XCC18` (`grep -n 'git commit' file.sh` → no match) PRESENT in test file and PASSING.
  - `XKL2` (`grep -n 'kill -9' notes.md` → no match) PRESENT and PASSING.
- [ ] AC8 — `XCC21`, `XCP21`, `XPU21` (`bash -c`), `XCC23`/`XCC24`/`XCC25` (shell-expansion class), `XCC26`/`XCC27` (subcommand quote-strip) ALL PRESENT and PASSING.
- [ ] AC9 — `grep -rF 'jq' hooks/` returns 0 matches (note: `-r` flag — round-1 R-M-4 fix) AND `grep -F 'jq' hooks/_lib/git-tokenwalk.sh tests/test-tokenize-then-walk.sh` returns 0.
- [ ] AC10 — `XCC8`/`XCC29` (GIT_SUB_REST exposure + segment-truncation invariant) PRESENT and PASSING.
- [ ] AC11 — `XKL6`/`XKL7` (positional-pair `-s 9` discrimination per round-1 R-H-5) PRESENT and PASSING.
- [ ] AC12 — `XKL8`/`XRM6` (pipeline-fed forms documented as NOT covered by `is_destruct_command`; round-1 DA-C-2 negative-assertion locks) PRESENT and PASSING.
- [ ] AC13 — Harness extension self-test: `setup_project_test_on_main` installed in `tests/test-hooks-helpers.sh`, the self-test passes, and `git -C "$TEST_TMPDIR" branch --show-current` returns `main` after invocation.
- [ ] AC14 (round-2 R2-C-1 / DA2-C-1 carve-out lock) — `XCC30` (quote-blind positive; `git reset 'msg --hard text'` → match + `--hard` in `GIT_SUB_REST`) + `XCC31` (space-elided semicolon; `git clean foo;rm -f bar` → match + `GIT_SUB_REST` contains `-f`) + `XCC32` (multi-flag positive; assert `--no-verify` retained) + `XCC34` (multi-line; first line only — no match for second-line `git commit`) ALL PRESENT and PASSING.
- [ ] AC15 (round-2 R2-H-1 over-match-tolerance lock) — `XKL9` (`kill 1234 -9` → match) + `XKL10` (`pkill 1234 -9` empty-flag → match) PRESENT and PASSING.
- [ ] AC16 (round-2 DA2-H-3 prefix-bypass lock) — `XKL11` (`env -i kill -9 1234` → no match) + `XKL12` (`sudo kill -9 1234` → no match) PRESENT and PASSING.

### Dependencies

Phase 1 complete. Reference doc exists with D1-D7.

---

## Phase 3 — Migrate block-unsafe-project.sh — 6 call sites + bypass-canary tests

### Goal

Replace all 6 bare-substring `git[[:space:]]+(commit|cherry-pick|push)` regex sites in `hooks/block-unsafe-project.sh.template` (lines 404, 411, 540, 546, 616, 719 — round-1 DA-M-2 corrected the count from "5" to "6") with calls to `is_git_subcommand "$COMMAND" "<verb>"` (helper inlined verbatim from `hooks/_lib/git-tokenwalk.sh` per D2). Mirror to `.claude/hooks/block-unsafe-project.sh`. Add bypass-canary integration tests for each migrated site to `tests/test-hooks.sh` covering the 4 traced reproducers (R1, R2, R4, R5; R3 is UNTRACED per round-1 DA-C-1 and gets NO PR test) plus a class-pinned canary set per verb. The existing positive cases (#73, #87 regression tests) MUST continue to pass — verified by running the full `tests/test-hooks.sh` suite.

**Out of scope for this phase:** `block-unsafe-project.sh.template:227` (`git[[:space:]]+add[[:space:]]+\.claude/logs/?` — a project-hook-specific log-protection rule). This is a properly-scoped rule (D.1 class — has a `[[:space:]]` boundary on both sides AND a literal path). Migrating it to `is_git_subcommand "$COMMAND" add` would weaken the discriminator (any `git add` form would match the outer gate, then need a path-regex to discriminate). The rule is left in its current bare-regex form. Acceptance criteria reflect this explicit non-migration.

### Work Items

- [ ] 3.1 — Inline `is_git_subcommand` from `hooks/_lib/git-tokenwalk.sh` into `hooks/block-unsafe-project.sh.template`. Insertion point: immediately after the existing `block_with_reason()` definition (`grep -n '^block_with_reason()' hooks/block-unsafe-project.sh.template` to locate; currently at line 61) (so the helper is in scope for all subsequent rule blocks). The inlined function body MUST be byte-identical to the source-of-truth — verify with `diff <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/block-unsafe-project.sh.template) <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/_lib/git-tokenwalk.sh)`. The `set -u` guard and shebang at the top of `hooks/_lib/git-tokenwalk.sh` are NOT inlined — only the function bodies. Phase 5.4 drift gate verifies this scope.

- [ ] 3.2 — Replace the 5 bare-substring sites in `hooks/block-unsafe-project.sh.template`:

  | Line  | Before                                                                          | After                                                                  |
  |-------|---------------------------------------------------------------------------------|------------------------------------------------------------------------|
  | 404   | `if [[ "$COMMAND" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main; then` | `if is_git_subcommand "$COMMAND" commit && is_main_protected && is_on_main; then` |
  | 411   | `if [[ "$COMMAND" =~ git[[:space:]]+commit ]]; then`                            | `if is_git_subcommand "$COMMAND" commit; then`                         |
  | 540   | `if [[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main; then` | `if is_git_subcommand "$COMMAND" cherry-pick && is_main_protected && is_on_main; then` |
  | 546   | `if [[ "$COMMAND" =~ git[[:space:]]+cherry-pick ]]; then`                       | `if is_git_subcommand "$COMMAND" cherry-pick; then`                    |
  | 616   | `if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]|\") ]]; then`              | `if is_git_subcommand "$COMMAND" push; then`                           |
  | 719   | `if [[ "$COMMAND" =~ git[[:space:]]+push([[:space:]]|\"|$) ]] && is_main_protected; then` | `if is_git_subcommand "$COMMAND" push && is_main_protected; then`      |

  **Critical:** the existing PUSH_ARGS extraction loop (lines 720-734) and rule (a)/(b)/(c) checks (lines 738-751) STAY UNCHANGED — they operate on `PUSH_ARGS` (the bounded, segment-walk-extracted positional args), which is the right surface. The replacement is ONLY for the OUTER GATE that decides whether to run the PUSH_ARGS extraction at all.

- [ ] 3.3 — Mirror to `.claude/hooks/block-unsafe-project.sh` via `cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh && chmod +x .claude/hooks/block-unsafe-project.sh && diff -q hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh` (must exit 0). The mirror MUST be in the same commit as the source per the mirror-discipline rule (research §G.cross-cutting note 2 + Plan B Phase 3.3 prose).

- [ ] 3.4 — Add bypass-canary integration tests to `tests/test-hooks.sh` immediately after the existing project-hook test section. New section heading (literal, for grep): `# === BLOCK_UNSAFE_HARDENING bypass canaries — project hook ===`. **Source the harness extension at the top of the section: `source "$(dirname "$0")/test-hooks-helpers.sh"`.** All "while on main" cases call `setup_project_test_on_main` before invoking `expect_project_allow` / `expect_project_deny` (the existing helpers in `tests/test-hooks.sh:449-475` operate on `$TEST_TMPDIR`; the harness extension sets it up correctly).

  Test cases:

  - **PR1** — Reproducer R1 verbatim: `grep -n 'git commit\|...' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh` while on main with main_protected=true → `expect_project_allow`. (Sequence: `setup_project_test_on_main; expect_project_allow "PR1: R1" "<cmd>"; teardown_project_test`.)
  - **PR2** — Reproducer R2 verbatim: `sed -n '404,420p' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh` while on main → `expect_project_allow`.
  - **(PR3 — REMOVED.)** Round-1 DA-C-1 + refiner empirical re-verification confirmed R3 (`gh issue list --search 'OR'` form) does NOT trip any current hook regex. The orchestrator's earlier observation was unreproducible. Promoting it to a class-pinned AC test would be a no-signal test (passes before AND after the migration). PR3 IS DELETED. Phase 1's reference doc carries R3 as `### R3 — UNTRACED` per AC6 there. PR-numbering compresses (PR4 below renamed to PR3, etc.) — final list has PR1-PR10 instead of PR1-PR11.
  - **PR3** (was PR4) — Reproducer R4 verbatim: `grep -nE '(commit.*OR|over-match|grep.*git commit|sed.*block-unsafe|...)' /workspaces/zskills/tests/test-hooks.sh` while on main → `expect_project_allow`. **Phase 1's empirical trace MUST confirm R4 fires today** (likely line 411, project commit transcript site, no `&& main_protected` guard). If the empirical trace shows R4 also doesn't fire, demote PR3 the same way PR3-was-PR3 was demoted; reduce to PR1-PR9.
  - **PR4** (was PR5) — Class-pinned negative (commit): `grep "git commit" file.sh` while on main → `expect_project_allow`.
  - **PR5** (was PR6) — Class-pinned negative (cherry-pick): `grep "git cherry-pick" file.sh` while on main → `expect_project_allow`. (Currently UNCAUGHT — line 540 has no allow test; this case was never covered.)
  - **PR6** (was PR7) — Class-pinned negative (push): `grep "git push" file.sh` while on main → `expect_project_allow`. (Existing test at `tests/test-hooks.sh:1385` covers a similar shape but only for rule (c); this verifies the OUTER GATE doesn't fire.)
  - **PR7** (was PR8) — Positive regression (commit on main): `git commit -m "x"` while on main → `expect_project_deny` (`main_protected`). Asserts the migration doesn't weaken the positive case.
  - **PR8** (was PR9) — Positive regression (cherry-pick on main): `git cherry-pick abc123` while on main → `expect_project_deny`.
  - **PR9** (was PR10) — Positive regression (push to main, naked rule c): `git push` while on main with `PUSH_ARGS=""` → `expect_project_deny` (rule c).
  - **PR10** (was PR11) — Bypass-canary battery for `is_git_subcommand` against the project hook: parameterize over the 10 cases from XCC5-XCC14 (top-level git-flag combinations) — assert `git --no-pager commit -m x` on main DENIES (positive: real commit), `git --no-pager log` on main ALLOWS (negative: not a commit). PLUS one explicit JSON-quote-injection assertion (round-1 DA-H-1): `git "commit" -m "x"` on main → `expect_project_deny` (verifies the subcommand quote-strip works at the hook level too).

- [ ] 3.5 — Run `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` and verify exit 0. The PRE-EXISTING positive cases that exercise lines 404 / 411 / 540 / 546 / 616 / 719 (per `grep -nF 'expect_project_deny' tests/test-hooks.sh | head -50`) MUST all still pass. New bypass canaries pass. Total case count increases by 10 (PR1-PR10) plus 11 per-verb cases inside PR10 (10 from XCC5-XCC14 + 1 quote-injection) = 21 new cases.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/block-unsafe-project.sh.template` + `.claude/hooks/block-unsafe-project.sh` + `tests/test-hooks.sh`. Subject: `feat(hooks): block-unsafe-project — tokenize-then-walk migration (5 sites)`.
- **Mirror MUST be in same commit as source.** Hook source + `.claude/hooks/` mirror are one atomic unit; per-Edit permission storms on `.claude/hooks/` (memory anchor `feedback_claude_skills_permissions`) make `cp` after editing the source the canonical idiom. **Do NOT** edit `.claude/hooks/block-unsafe-project.sh` directly.
- **No skill metadata.version bump** — hooks are not skills.
- **Inline-helper drift check in commit message body:** include the `diff -q` output between the inlined helper and `hooks/_lib/git-tokenwalk.sh` (must show no differences). Phase 5 AC also locks this. (Round-1 fix: source-of-truth path moved from `tests/fixtures/` to `hooks/_lib/`; round-2 verified no remaining stale `tests/fixtures/` references.)
- **Existing PUSH_ARGS extraction is in-scope but unchanged.** The replacement targets ONLY the outer gate predicate. The PUSH_ARGS extraction loop, rule (a)/(b)/(c) regexes, and the `extract_cd_target` precedence in `is_on_main` are all preserved verbatim. Phase 3.4's PR8/PR9/PR10 positive regressions verify behavior preservation.
- **Defense against `$COMMAND` redaction-bypass constructs (process substitution, `$()`):** the helper's `read -ra TOKENS <<< "$cmd"` does NOT interpret these — they're tokenized literally. The behavior is: any verb hidden behind shell expansion is NOT classified as that verb. This is a defensive failure mode — same class as the `bash -c` carve-out (D5) and the `XCC23` defensive-match-failure case. Documented per D2 D&C of Phase 2.
- **NO `--no-verify`.**
- **Tests: capture to file, never pipe.** `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"`.

### Acceptance Criteria

- [ ] AC1 — Bare-substring sites for migrated verbs are gone. Specifically: `grep -nE 'git\[\[:space:\]\]\+(commit|cherry-pick|push)' hooks/block-unsafe-project.sh.template | grep -vE '^56:'` returns 0 lines. (Round-1 R-H-1 fix: line 56 is the project hook's redaction sed for `git commit -m`; intentionally preserved per D3. Round-0 used `^(56|82):` but line 82 belongs to the GENERIC hook — wrong file.) Note `git[[:space:]]+add` at line 227 is OUT OF SCOPE per Goal section, so the verb-set excludes `add`.
- [ ] AC2 — `grep -cF 'is_git_subcommand' hooks/block-unsafe-project.sh.template` returns ≥ `7` (1 function definition + 6 call sites at lines 404, 411, 540, 546, 616, 719). Round-1 R-H-3 corrected: round-0 prose "5 outer gates plus the function declaration line" was self-contradictory; the correct accounting is 1 function + 6 call sites = 7 occurrences.
- [ ] AC3 — `diff -q hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh` exits 0 (mirror in sync).
- [ ] AC4 — `diff <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/block-unsafe-project.sh.template) <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/_lib/git-tokenwalk.sh)` exits 0 (inlined helper byte-identical to source-of-truth).
- [ ] AC5 — `bash tests/test-hooks.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0; PR1-PR10 all PASS in output.
- [ ] AC6 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC7 — Pre-existing positive cases preserved: `grep -cF 'expect_project_deny "main_protected' tests/test-hooks.sh` returns the same count pre/post (no positive case removed). Verify with `git diff HEAD~1..HEAD -- tests/test-hooks.sh | grep -E '^-.*expect_project_deny'` returns 0 lines.
- [ ] AC8 — `git diff --stat HEAD~1..HEAD` shows exactly the three paths: `hooks/block-unsafe-project.sh.template`, `.claude/hooks/block-unsafe-project.sh`, `tests/test-hooks.sh`. No skill files, no settings.json, no other hooks, no scripts/.
- [ ] AC9 — Reproducer R3 is NOT in the test surface (round-1 DA-C-1): `grep -F 'gh issue list --state open --search' tests/test-hooks.sh` returns 0 matches. The reference doc (Phase 1) carries it as `### R3 — UNTRACED` only.
- [ ] AC10 — Subcommand quote-strip exercised at hook level (round-1 DA-H-1): `grep -F 'git "commit"' tests/test-hooks.sh` returns ≥ 1 match (within PR10 expansion).

### Dependencies

Phase 2 complete. `hooks/_lib/git-tokenwalk.sh` exists with the helpers proven correct in isolation. (Round-1 D2 moved source-of-truth from `tests/fixtures/` to `hooks/_lib/`.)

---

## Phase 4 — Migrate block-unsafe-generic.sh — destructive-verb sites + bypass-canary tests

### Goal

Replace bare-substring destructive-verb regex sites in `hooks/block-unsafe-generic.sh` with calls to `is_git_subcommand` (for the git-verb subset) and `is_destruct_command` (for the non-git destructive verbs that genuinely use first-token form). Mirror to `.claude/hooks/block-unsafe-generic.sh`. Add bypass-canary integration tests to `tests/test-hooks.sh`. Same shape as Phase 3 but a different hook file with a different surface mix.

**Round-1 DA-C-2 scope reduction (CRITICAL).** The round-0 draft replaced ALL bare-substring destructive sites with `is_destruct_command`, including pipeline-fed forms (`cat foo | xargs rm`, `pgrep | xargs kill`) and combined-flag forms (`fuser -mk`). DA-C-2 demonstrated this WEAKENS coverage: `is_destruct_command` is first-token-anchored and would silently let pipeline-fed destruction slip past. **Decision (round 1):**

| Existing site | Action | Reason |
|---|---|---|
| `STASH_BOUNDARY` (line 106) | UNCHANGED | Already properly bounded (D.1); shell-separator-anchored |
| `kill -9 / -KILL / -SIGKILL / -s 9` (line 140) | MIGRATE to `is_destruct_command` (with `:next:` positional-pair semantics for `-s`) | Genuine first-token form; helper handles correctly |
| `fuser -k` combined-flag (line 146) | UNCHANGED | The existing regex `fuser[[:space:]]+(.*-[a-z]*k[a-z]*|--kill)` correctly handles `-mk`/`-km`/`-k` variants. `is_destruct_command "$COMMAND" fuser '^-k$'` would lose `-mk` coverage. KEEP THE BARE REGEX. |
| `XARGS_KILL` (line 157) | UNCHANGED | Already properly bounded (D.1); pipeline-segment-anchored |
| `KILL_SUBST` (line 175) | UNCHANGED | Documented `Known gaps` (per source comments); intentional scope |
| `RM_RECURSIVE` (line 217) | UNCHANGED | Bare-substring BUT pipeline-fed `cat foo | xargs rm -rf` is the canonical anti-pattern; first-token-anchoring would weaken coverage. The existing regex is the lesser of two evils. CALL OUT in CHANGELOG that this is a documented tradeoff. |
| `find ... -delete` (line 225) | UNCHANGED | Same logic as RM_RECURSIVE — pipeline forms are real and need whole-buffer scan |
| `rsync ... --delete` (line 232) | UNCHANGED | Same logic |
| `xargs ... rm` (line 239) | UNCHANGED | Pipeline-anchored by definition |
| `git restore` outer gate (line 125) | MIGRATE to `is_git_subcommand` | First-token-anchored is correct (no pipeline form for git verbs) |
| `git checkout --` (line 120) | MIGRATE to `is_git_subcommand` + `[[ "$GIT_SUB_REST" =~ -- ]]` | **Round-2 DA2-H-1 + refiner-session live-block reversal of round-1 DA-M-6.** During round-2 verification, the refiner's own bash session was LIVE-BLOCKED when the COMMAND buffer contained the literal text `git checkout -- foo` (inside an echo-to-file invocation). The existing regex `git[[:space:]]+checkout[[:space:]]+(.*[[:space:]])?--([[:space:]]|$)` matches ANYWHERE in the buffer — including `git checkout --` mentioned in a heredoc, sed-replace argument, or shell-string passed to a child command. Round-1 DA-M-6's "properly bounded" claim was wrong about the bound: it's `[[:space:]]+` between `git` and `checkout` and a within-segment `--` anchor, but it's NOT first-token-anchored — a `printf 'git checkout -- foo' > out.sh` trips it. Migration to `is_git_subcommand "$COMMAND" checkout && [[ "$GIT_SUB_REST" =~ (^\|[[:space:]])--([[:space:]]\|$) ]]` correctly requires `git` to be the first invoked verb AND `--` in the post-`checkout` segment. |
| `git clean -f` (line 130) | MIGRATE to `is_git_subcommand` + `[[ "$GIT_SUB_REST" =~ ... ]]` | Bare-substring class; the `-f` discriminator is properly scoped via `GIT_SUB_REST` |
| `git reset --hard` (line 135) | MIGRATE | Same |
| `git add -A / --all / .` (line 246) | MIGRATE | Same |
| `git commit --no-verify` (line 251) | MIGRATE | Same |
| `git push` outer gate (line 262) | MIGRATE | First-token-anchored; PUSH_ARGS extraction (lines 270-280) and rules (a)/(b)/(c) (lines 282-296) UNCHANGED |

**Net reduction vs. round-0:** the destructive-non-git table in Phase 4.3 collapses from 5 rows (kill, rm, find, rsync, xargs) to 1 row (kill only). RM_RECURSIVE/find/rsync/xargs migrations are removed. This is the correct response to DA-C-2.

### Work Items

- [ ] 4.1 — Inline `is_git_subcommand` AND `is_destruct_command` from `hooks/_lib/git-tokenwalk.sh` into `hooks/block-unsafe-generic.sh`. Insertion point: immediately after the existing `block_with_reason()` definition (`grep -n '^block_with_reason()' hooks/block-unsafe-generic.sh` to locate; currently at line 87). Both functions inlined byte-identical to the source-of-truth (Phase 5.4 drift gate verifies).

- [ ] 4.2 — Replace the in-scope bare-substring git-verb sites in `hooks/block-unsafe-generic.sh`. **Hybrid checks use `[[ "$GIT_SUB_REST" =~ ... ]]` (NOT `[[ "$COMMAND" =~ ... ]]`) per round-1 R-H-2 / DA-M-6 fix.** Line 120 (`git checkout --`) IS migrated per round-2 DA2-H-1 (refiner's session live-blocked on `printf 'git checkout -- foo'`-style buffer; round-1 DA-M-6's "properly bounded" claim was wrong about first-token anchoring).

  | Line  | Verb                        | Before                                                                  | After                                                                                |
  |-------|-----------------------------|-------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
  | 120   | `git checkout --`           | `if [[ "$COMMAND" =~ git[[:space:]]+checkout[[:space:]]+(.*[[:space:]])?--([[:space:]]|$) ]]; then` | `if is_git_subcommand "$COMMAND" checkout && [[ "$GIT_SUB_REST" =~ (^\|[[:space:]])(.*[[:space:]])?--([[:space:]]\|$) ]]; then` |
  | 125   | `git restore`               | `if [[ "$COMMAND" =~ git[[:space:]]+restore[[:space:]] ]]; then`         | `if is_git_subcommand "$COMMAND" restore; then`                                      |
  | 130   | `git clean -f`              | `if [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f ]]; then` | `if is_git_subcommand "$COMMAND" clean && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])-[a-zA-Z]*f([[:space:]]|$) ]]; then` |
  | 135   | `git reset --hard`          | `if [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then`    | `if is_git_subcommand "$COMMAND" reset && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])--hard([[:space:]]|$) ]]; then` |
  | 246   | `git add -A` / `--all` / `.` | `if [[ "$COMMAND" =~ git[[:space:]]+add[[:space:]]+(-A|--all|\.([[:space:]]|\"|\|)) ]] || …` | `if is_git_subcommand "$COMMAND" add && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])(-A|--all|\.)([[:space:]]|$) ]]; then` |
  | 251   | `git commit --no-verify`    | `if [[ "$COMMAND" =~ git[[:space:]]+commit[[:space:]]+.*--no-verify ]]; then` | `if is_git_subcommand "$COMMAND" commit && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])--no-verify([[:space:]]|$) ]]; then` |
  | 262   | `git push` outer gate       | `if [[ "$COMMAND" =~ git[[:space:]]+push ]]; then`                       | `if is_git_subcommand "$COMMAND" push; then`                                          |

  **Round-2 R2-H-3 boundary narrowing — line 246 documented behavior change.** The original line-246 regex's `\.([[:space:]]|\"|\|)` boundary catches `git add .` followed by space, close-quote `"`, or pipe `|`. The migrated regex's `([[:space:]]|$)` boundary drops the close-quote and pipe cases. So `git add .|cat` (pipe-glued, no space) currently TRIPS the bare regex but the migrated regex does NOT. **This is an intentional simplification documented in CHANGELOG bullet 3 (Phase 5.1).** Verify via `grep -F 'add .|' tests/test-hooks.sh` returns 0 (no positive regression test exists for the pipe-glued form); if nonzero, this AC fails and the migration MUST replicate the `\"|\|` cases. Empirically expected: 0 (the form is pathological and unlikely to have a test).

  **Critical:**
  - `GIT_SUB_REST` is set by `is_git_subcommand` to the post-subcommand args TRUNCATED at the first shell-segment boundary (`&&`, `||`, `;`, `|`). This means `git clean foo && rm -f bar.txt` will NOT trip the `clean -f` rule — `GIT_SUB_REST` contains only `foo`, the `-f` is in the post-`&&` `rm` segment. Round-1 R-H-2 / DA-M-6 fix.
  - The line-262 outer gate replacement preserves PUSH_ARGS extraction at lines 270-280 and push rules (a)/(b)/(c) at 282-296 UNCHANGED. The replacement is ONLY for the gate that decides whether to run PUSH_ARGS extraction.
  - `STASH_BOUNDARY` (line 106), `XARGS_KILL` (line 157), `KILL_SUBST` (line 175), `RM_RECURSIVE` (line 217), `find -delete` (line 225), `rsync --delete` (line 232), `xargs ... rm` (line 239), and `fuser -k` combined-flag (line 146) ALL stay UNCHANGED. **Round-2 update: `git checkout --` (line 120) is NO LONGER unchanged — it is migrated per round-2 DA2-H-1.** See Goal section table for per-rule rationale.
  - **PUSH_ARGS pre-existing carve-out (round-2 DA2-O-2).** The line-262 outer-gate replacement uses `is_git_subcommand` (segment-aware) but the existing PUSH_ARGS extraction at lines 270-280 of `block-unsafe-generic.sh` (and the parallel block in `block-unsafe-project.sh.template:720-734`) iterates over `$COMMAND` (segment-blind) — so for `git push && rm -rf foo`, PUSH_ARGS may include tokens from the post-`&&` segment. **This is pre-existing behavior; the migration does not worsen it.** A future refactor should change PUSH_ARGS extraction to iterate `$GIT_SUB_REST` instead of `$COMMAND`. Out of scope for this plan (the bare gate is already replaced; PUSH_ARGS extraction is a separate inner-loop refactor with its own coverage surface). CHANGELOG bullet (Phase 5.1) acknowledges.

- [ ] 4.3 — Replace the destructive-non-git verb sites in `hooks/block-unsafe-generic.sh`. **Round-1 DA-C-2 scope reduction: only kill -9 family migrated; rm/find/rsync/xargs sites are NOT migrated (their bare regex provides pipeline-form coverage that first-token-anchoring would lose).**

  | Line(s)  | Verb                                     | Strategy                                                                                                                                                                |
  |----------|------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
  | 140      | kill -9 / -KILL / -SIGKILL / -s 9 / killall / pkill | Replace bare regex with `is_destruct_command "$COMMAND" kill '^-(9|KILL|SIGKILL)$' \|\| is_destruct_command "$COMMAND" kill '^-s$:next:^(9\|KILL\|SIGKILL)$' \|\| is_destruct_command "$COMMAND" killall '' \|\| is_destruct_command "$COMMAND" pkill ''`. The two-call form for `kill` covers (a) bare `-9`/`-KILL`/`-SIGKILL` flags and (b) positional-pair `-s <SIGNAL>` per round-1 R-H-5 (`:next:` syntax). Empty `flag_match` for killall/pkill means "first token == verb." `fuser -k` line 146 is NOT migrated (DA-C-2; combined-flag `-mk` would lose coverage). |

  **NOT migrated (round-1 DA-C-2):** Lines 217 (`RM_RECURSIVE`), 225 (`find -delete`), 232 (`rsync --delete`), 239 (`xargs ... rm`), 146 (`fuser -k`). Round-0 proposed `is_destruct_command` for each; DA-C-2 demonstrated this would silently weaken coverage of pipeline-fed forms (`cat foo | xargs rm`, `pgrep | xargs kill`) and combined-flag forms (`fuser -mk`). The bare regex's whole-buffer scan correctly catches these forms today; first-token-anchoring would lose them. **Document in Phase 5 CHANGELOG: these rules remain bare-substring; the bug class for them is OPEN; future hardening would need a segment-aware tokenizer that handles pipe semantics correctly.**

- [ ] 4.4 — Mirror to `.claude/hooks/block-unsafe-generic.sh` via `cp hooks/block-unsafe-generic.sh .claude/hooks/block-unsafe-generic.sh && chmod +x .claude/hooks/block-unsafe-generic.sh && diff -q ... .` (must exit 0). Same atomic-commit discipline as Phase 3.3.

- [ ] 4.5 — Add bypass-canary integration tests to `tests/test-hooks.sh` immediately after the existing generic-hook test section. New section heading (literal, for grep): `# === BLOCK_UNSAFE_HARDENING bypass canaries — generic hook ===`.

  **Round-1 reductions:** GR5 (the unsubstantiated "most-cited generic-hook false-positive" `grep "rm -rf foo"` claim per DA-H-3) is DROPPED — DA-H-3 traced no such bug report; it was a hypothetical. GR6/GR7 (`grep "find . -delete"` / `grep "rsync --delete"`) are DROPPED because lines 225/232 are NOT migrated (DA-C-2 scope reduction); the existing bare regex still fires on those `grep` cases. GR8 (`printf 'remember to git reset --hard'`) STAYS — line 135 IS migrated. The migration's coverage shifts from "every bare-regex site" to "the migrated bare-regex sites."

  Test cases (renumbered):

  - **GR1** — Reproducer R5 verbatim (drafter-session live; round-1 refiner re-verified fires): `grep -n -E '(kill -9|killall|pkill|fuser -k|RM_RECURSIVE|find .* -delete|rsync .*--delete|xargs.*kill|xargs.*rm)' /workspaces/zskills/hooks/block-unsafe-generic.sh` → `expect_allow`. **The case that fired against the drafter session.**
  - **GR2** — `grep "git restore" notes.md` → `expect_allow` (currently BLOCKS at line 125; uncovered).
  - **GR3** — `grep "git clean -f" notes.md` → `expect_allow` (currently BLOCKS at line 130; uncovered).
  - **GR4** — `grep "git reset --hard" notes.md` → `expect_allow` (currently BLOCKS at line 135; uncovered).
  - **GR5** — `printf 'remember to git reset --hard\n'` → `expect_allow` (line 135 migrated).
  - **GR6** — `echo "use kill -9 1234 to force"` → `expect_allow` (line 140 migrated).
  - **GR7** — `cat NOTES.md` where path itself contains substring `kill-9` → `expect_allow` (path-substring class; line 140 migrated).
  - **GR8** — `grep "git commit --no-verify" tests/test-hooks.sh` → `expect_allow` (line 251 migrated; uncovered).
  - **GR9** — `grep "git add -A" notes.md` → `expect_allow` (line 246 migrated).
  - **GR10** — `grep "git push" notes.md` → `expect_allow` (line 262 migrated).
  - **GR11** — Segment-truncation invariant (round-1 R-H-2 — confirms `GIT_SUB_REST` properly scopes): `git clean foo && rm -f bar.txt` → `expect_allow` (the post-`&&` `-f` MUST NOT trip the line-130 `clean -f` rule; `GIT_SUB_REST` truncates at `&&`).
  - **GR12** — Segment-truncation invariant: `git reset --soft && grep -- pattern file.sh` → `expect_allow` (post-`&&` `--` must not trip; reset --soft is allowed).
  - **GR12a** (round-2 R2-C-1 / DA2-C-1 carve-out lock — quote-blind positive over-match) — `git reset 'msg --hard text'` → `expect_deny`. **Documents the residual carve-out:** the helper IS quote-blind (D5), so `--hard` from inside the single-quoted arg appears as its own token in `GIT_SUB_REST` and trips the hybrid `reset --hard` rule. Narrower than bare-substring (which would trip on ANY mention anywhere; this only trips when the mention is inside a real `git reset` invocation's quoted arg) but a real residual over-match. This case PINS the carve-out so it can't drift either direction; if a future refactor adds quote-aware tokenization, this case must flip to `expect_allow` consciously.
  - **GR12b** (round-2 R2-C-1 / DA2-C-1 carve-out lock — space-elided shell-control) — `git clean foo;rm -f bar` → `expect_deny`. **Documents the residual carve-out:** `;` glues to neighbor token, segment-truncation never sees it as a boundary, `-f` from post-`;` `rm` leaks into `GIT_SUB_REST`. Same lock semantics as GR12a.
  - **GR12c** (round-2 DA2-H-1 line-120 migration coverage) — `printf 'git checkout -- foo\n' > /tmp/notes.sh` → `expect_allow`. **Asserts the line-120 migration kills the over-match.** Pre-migration, line 120's whole-buffer regex matches `git checkout -- foo` inside the printf string and DENIES; post-migration, `is_git_subcommand "$COMMAND" checkout` returns 1 (first token is `printf`, not `git`) so the rule is correctly skipped. Companion positive: `git checkout -- file.sh` → `expect_deny` (real invocation; line-120 still fires post-migration via the migrated rule).
  - **GR13** — Positive regression: `git restore .` → `expect_deny`. Asserts the migration doesn't weaken.
  - **GR14** — Positive regression: `git clean -f` → `expect_deny`.
  - **GR15** — Positive regression: `git reset --hard` → `expect_deny`.
  - **GR16** — Positive regression: `kill -9 1234` → `expect_deny`.
  - **GR17** — Positive regression: `kill -s 9 1234` → `expect_deny` (round-1 R-H-5 positional-pair: `:next:` matched).
  - **GR18** — Positive non-regression: `kill -s USR1 1234` → `expect_allow` (round-1 R-H-5: `-s USR1` is NOT a destructive signal; helper rejects).
  - **GR19** — Positive regression: `rm -rf /home/foo` → `expect_deny` (line 217 NOT migrated; bare `RM_RECURSIVE` still fires; `is_safe_destruct` rejects path).
  - **GR20** — Positive regression (pipeline form preserved per DA-C-2): `cat list.txt | xargs rm -rf` → `expect_deny` (line 217 unchanged; bare `RM_RECURSIVE` whole-buffer match still fires). **This is the DA-C-2 lock — the most common destructive shape MUST stay caught.**
  - **GR21** — Positive regression (combined-flag preserved per DA-C-2): `fuser -mk 8080` → `expect_deny` (line 146 unchanged; `fuser[[:space:]]+(.*-[a-z]*k[a-z]*|--kill)` still fires on `-mk`).
  - **GR22** — Positive regression: `kill -9 $(lsof -ti :3000)` → `expect_deny` (line 175 `KILL_SUBST` unchanged).
  - **GR23** — Bypass-canary battery: `git --no-pager restore .` → `expect_deny` (the new `is_git_subcommand`-gated `restore` rule catches; parity vs. the old bare regex).
  - **GR24** — Bypass-canary: `git --git-dir=/x clean -f` → `expect_deny` (`GIT_SUB_REST` contains `-f`).
  - **GR25** — Subcommand quote-strip (round-1 DA-H-1): `git "restore" .` → `expect_deny` (subcommand quote-stripped; matches `restore`).

- [ ] 4.6 — Run `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` and verify exit 0. Pre-existing positive cases preserved; GR1-GR25 all pass.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/block-unsafe-generic.sh` + `.claude/hooks/block-unsafe-generic.sh` + `tests/test-hooks.sh`. Subject: `feat(hooks): block-unsafe-generic — tokenize-then-walk migration (destructive verbs)`.
- **Mirror MUST be in same commit.** Same atomic-commit discipline as Phase 3.3.
- **No skill metadata.version bump.**
- **Inline-helper drift check:** both `is_git_subcommand` AND `is_destruct_command` must be byte-identical to the fixture bodies (Phase 5 AC verifies).
- **STASH_BOUNDARY (line 106) and KILL_PID_BACKTICK_REGEX-class rules at line 163-177 stay unchanged** — they are already properly bounded (research D.1) and have explicit `Known gaps` doc-comments justifying their precise scope. Modifying them is out of scope; doing so would risk weakening intentional behavior.
- **The `is_safe_destruct` policy at lines 180-243 stays unchanged.** Issue #84 surfaced its boundary (recursive-rm outside `/tmp/<name>` blocked even for legitimate mirror-regen). The fix landed via `scripts/mirror-skill.sh` centralization, NOT via policy relaxation. This plan does NOT relax `is_safe_destruct`; it only ensures the GATE that decides whether to consult `is_safe_destruct` correctly identifies a real `rm -rf` invocation rather than a `grep` over text that mentions `rm -rf`.
- **NO `--no-verify`. NO `jq`. NO `2>/dev/null` on critical ops.**

### Acceptance Criteria

- [ ] AC1 — Bare-substring regex sites for the MIGRATED verbs are gone. Specifically: `grep -nE 'git\[\[:space:\]\]\+(checkout|restore|clean|reset|add|commit|push)' hooks/block-unsafe-generic.sh | grep -vE '^82:'` returns 0 matches. (Line 82 = redaction sed (D3 — preserved). Round-2 DA2-H-1 reinstated `checkout` to the migration set, so the verb-list now includes it AND line 120 must not appear in the filter.) Line numbers verified empirically by Phase 4.1 implementer; if drift has shifted them, update the AC pin.
- [ ] AC2 — `grep -cF 'is_git_subcommand' hooks/block-unsafe-generic.sh` returns ≥ `8` (1 function definition + 7 call sites: checkout, restore, clean, reset, add, commit-no-verify, push). Round-0 expected ≥ 8 (with checkout); round-1 DA-M-6 dropped checkout (`≥ 7`); round-2 DA2-H-1 reinstated checkout (`≥ 8`).
- [ ] AC3 — `grep -cF 'is_destruct_command' hooks/block-unsafe-generic.sh` returns ≥ `5` (1 function definition + 4 call sites: 2 for kill — bare-flag + `:next:` positional-pair per R-H-5 — plus killall + pkill). Round-0 expected ≥ 6 with rm/find/rsync/xargs; round-1 DA-C-2 dropped those four sites.
- [ ] AC4 — `diff -q hooks/block-unsafe-generic.sh .claude/hooks/block-unsafe-generic.sh` exits 0.
- [ ] AC5 — `diff <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/block-unsafe-generic.sh) <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/_lib/git-tokenwalk.sh)` exits 0 AND same diff for `is_destruct_command` exits 0.
- [ ] AC6 — `bash tests/test-hooks.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0; GR1-GR25 all PASS in output.
- [ ] AC7 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC8 — Pre-existing positive cases preserved: `git diff HEAD~1..HEAD -- tests/test-hooks.sh | grep -E '^-.*expect_deny'` returns 0 lines (no positive case removed).
- [ ] AC9 — `git diff --stat HEAD~1..HEAD` shows exactly the three paths: `hooks/block-unsafe-generic.sh`, `.claude/hooks/block-unsafe-generic.sh`, `tests/test-hooks.sh`. No skill files, no settings.json, no other hooks.
- [ ] AC10 — Reproducer R5 (drafter-session live) → GR1 PRESENT and PASSING.
- [ ] AC11 — DA-C-2 lock (pipeline-form preservation): GR20 (`cat list.txt | xargs rm -rf` → DENY) + GR21 (`fuser -mk 8080` → DENY) BOTH PRESENT and PASSING. These assert the most common destructive pipelines stay caught.
- [ ] AC12 — Segment-truncation invariant (round-1 R-H-2): GR11 (`git clean foo && rm -f bar.txt` → ALLOW) + GR12 PRESENT and PASSING. Asserts `GIT_SUB_REST` does not leak across `&&`.
- [ ] AC13 — Positional-pair discrimination (round-1 R-H-5): GR17 (`kill -s 9` → DENY) + GR18 (`kill -s USR1` → ALLOW) PRESENT and PASSING.
- [ ] AC14 (round-2 R2-C-1 / DA2-C-1 carve-out lock at integration level) — GR12a (`git reset 'msg --hard text'` → DENY) + GR12b (`git clean foo;rm -f bar` → DENY) PRESENT and PASSING. Locks the residual quote-blind / space-elided over-match per D5 carve-out enumeration.
- [ ] AC15 (round-2 DA2-H-1 line-120 migration lock) — GR12c-allow (`printf 'git checkout -- foo'...` → ALLOW) + GR12c-deny (`git checkout -- file.sh` → DENY) BOTH PRESENT and PASSING. Asserts the line-120 migration kills the over-match while preserving the positive case.

### Dependencies

Phase 3 complete. The project hook is migrated and green; the generic hook migration in this phase has no dependency on Phase 3 *behavior* but is sequenced after it for review hygiene (one hook at a time).

---

## Phase 5 — CHANGELOG + class-pinned acceptance canaries + final conformance

### Goal

Land the CHANGELOG entry, the **class-pinned acceptance canary matrices** (the discipline this plan exists to enforce), and the final conformance gate. Per D4, the matrices are 144 negative cases (12 read-only commands × 3 git verbs × 4 quote-shapes) for the project hook surface and 192 negative cases (8 read-only commands × 6 destructive verbs × 4 quote-shapes) for the generic hook surface — generated by a small loop in the test file, NOT enumerated by hand. Plus the 4 known reproducers (R1-R4) and the drafter-session reproducer (R5) as named cases (already added in Phases 3-4 as PR1-PR4 + GR1).

### Work Items

- [ ] 5.1 — Append CHANGELOG entry to `CHANGELOG.md`. Convention per Plan B Phase 5.1 R2-N-2 fix: ONE H3 entry titled `### Added — Hooks: tokenize-then-walk source-of-truth + class-pinned matrices (BLOCK_UNSAFE_HARDENING)` under today's date H2 (round-2 #9 of DA review — explicit ONE-H3 instruction so implementer doesn't accidentally create 6 separate H3 entries). Body bullets (under the single H3):
  - **Added — `hooks/_lib/git-tokenwalk.sh`** — source-of-truth file holding `is_git_subcommand` and `is_destruct_command` (tokenize-then-walk classification helpers). Inlined byte-identical into `hooks/block-unsafe-project.sh.template` (6 call sites: lines 404, 411, 540, 546, 616, 719) and `hooks/block-unsafe-generic.sh` (7 git-verb call sites — round-2 reinstated checkout per DA2-H-1: checkout, restore, clean, reset, add, commit-no-verify, push; plus 4 destructive-verb call sites: kill bare-flag, kill `-s` positional-pair, killall, pkill).
  - **Closes the over-match patch trail** of Issues #58/#73, #81/#87 by killing the bug CLASS (regex-based whole-buffer scan) at the migrated subset, not the specific shape. The class-pinned acceptance matrices (144 project-hook + 192 generic-hook negative cases over the migrated verbs) catch future incidents in NEW shapes that prior shape-pinned tests missed. **Class is partially open for the unmigrated subset** (next bullet).
  - **Removed — bare-substring `[[ "$COMMAND" =~ git[[:space:]]+verb ]]` patterns** at the migrated sites (replaced by `is_git_subcommand "$COMMAND" verb`). NOT removed at line 56 (project) / line 82 (generic) redaction sed (D3 — load-bearing). **Round-2 line-246 boundary narrowing (intentional):** the migrated `git add` regex's `\.` boundary alternatives `[[:space:]]|$` drop the original's `\"` (close-quote) and `\|` (pipe) cases. So `git add .|cat` (pipe-glued, no space) currently TRIPS the bare regex but does NOT trip the migrated regex. Pathological form; no positive regression test exists in `tests/test-hooks.sh`. Documented for forensics.
  - **Documented tradeoff (DA-C-2):** lines 146 (`fuser -k`), 217 (`RM_RECURSIVE`), 225 (`find -delete`), 232 (`rsync --delete`), 239 (`xargs ... rm`) in `block-unsafe-generic.sh` REMAIN bare-substring whole-buffer regex. First-token-anchoring would silently weaken coverage of pipeline-fed destruction (`cat foo | xargs rm`, `pgrep | xargs kill`) and combined-flag forms (`fuser -mk`) — both canonical anti-patterns. Future hardening of THESE sites needs a segment-aware tokenizer that handles pipe semantics; out of scope for this plan.
  - **Documented carve-outs (round-2 D5 expansion):** the helpers are quote-blind (`read -ra` is whitespace-only; flag-discriminator inside quoted args still trips), space-elided shell-control bypasses segment-truncation (`git clean foo;rm -f bar` → `-f` leaks from post-`;` `rm`), `env -i`/`sudo`/`doas`/`su` prefixes bypass first-token-anchoring, and multi-line commands are read up to first newline only. Each is a NEGATIVE assertion in the unit test surface (XCC30-34, XKL11-12) so a future close-the-carve-out pass MUST update the named tests.
  - **Pre-existing carve-out (round-2 DA2-O-2 — not introduced by this plan):** PUSH_ARGS extraction at `block-unsafe-generic.sh:270-280` and the parallel block in project hook iterate over `$COMMAND` (segment-blind), not `$GIT_SUB_REST`. For `git push && rm -rf foo`, PUSH_ARGS may include tokens from the post-`&&` segment. Future refactor should change PUSH_ARGS to iterate `$GIT_SUB_REST`; out of scope for this plan (the bare gate was the over-match site addressed here; PUSH_ARGS is a separate inner-loop refactor).
  - **Test surface — class-pinned matrices** of 144 + 192 negative cases (migrated subset) plus 4 traced reproducer cases (R1, R2, R4, R5; R3 untraced and not promoted to AC) in `tests/test-hooks.sh`. NEW `tests/test-hook-helper-drift.sh` per D7 enforces inlined-helper byte-equality at CI time.
  - **`hooks/_lib/` install boundary (round-2 R2-L-2 / DA2-M-1 — Phase 2.6):** added a one-line comment to `skills/update-zskills/SKILL.md` Step C to document that `hooks/_lib/git-tokenwalk.sh` is the source-of-truth for inlined helpers and MUST NOT be added to the per-name install loop. Skill `metadata.version` bumped accordingly.
  - **Coordination with Plan B** (`SKILL_VERSION_PRETOOLUSE_HOOK.md`) per D6: this plan owns `hooks/_lib/git-tokenwalk.sh` as the source-of-truth. Phase 6 of this plan is the canonical consolidation path (round-2 DA2-C-2: round-1's "/refine-plan it before" branch was aspirational and has been demoted to optional orchestrator action). The drift gate in `tests/test-hook-helper-drift.sh` enforces single-version semantics across all consumers.

- [ ] 5.2 — Add the **class-pinned acceptance canary matrix (migrated-verb subset)** to `tests/test-hooks.sh`. New section heading: `# === BLOCK_UNSAFE_HARDENING class-pinned acceptance matrices (migrated subset) ===`. **Round-2 #8 of DA review labeling fix:** the matrix exercises the MIGRATED verbs only (`commit`/`cherry-pick`/`push` for project; the 5 git-verbs + `kill -9` for generic). Unmigrated verbs (`rm -rf`/`find -delete`/`rsync --delete`/`xargs ... rm`/`fuser -k` per DA-C-2 in 4.3) are NOT in the matrix because their bare regex still fires on `grep` over text mentioning them — a matrix entry would correctly FAIL. CHANGELOG bullet 4 documents the open class for the unmigrated subset.

  **Round-1 R-C-1 fix:** the project-hook matrix MUST call `setup_project_test_on_main` (Phase 2.3) before each batch so the line-404/540 `&& is_main_protected && is_on_main` predicates are semantically active. Without this setup, the matrix passes vacuously regardless of migration correctness. AC2 below also asserts `is_main_protected` returns 0 inside the matrix subshell.

  **Round-1 R-H-4 fix:** the SHAPE generator now ensures every shape contains `git $VERB` (with literal space) so all 4 shapes exercise the bare-substring bug class. Round-0's `unquoted` (path-substring `git-$VERB-notes.md` — NO space) and `flagval` (`--pattern=git-$VERB` — NO space) were vacuously-passing for the bare regex. NEW shape names: `single`, `double`, `unquoted-with-space`, `flag-with-space`. The path-substring and flag-value shapes still appear as ADJACENT-class coverage but in 24 separate `adjacent-class-*` cases (NOT counted toward the 144) so coverage is honest about which class each case exercises.

  **Round-1 DA-H-2 fix:** the cmd list is fixed at exactly 12 commands. The round-0 prose said "12 read-only commands (`grep, sed, …, diff`)" — 13 entries explicitly listed. Decision: drop `diff`. The 12 are: `grep sed awk cat echo printf head tail less more file wc`.

  ```bash
  source "$(dirname "$0")/test-hooks-helpers.sh"

  # Project-hook matrix: 12 commands × 3 verbs × 4 quote-shapes = 144 negative cases.
  # Each shape contains `git $VERB` (with literal space) — exercises the bug class.
  for CMD in grep sed awk cat echo printf head tail less more file wc; do
    for VERB in commit cherry-pick push; do
      for SHAPE in single double unquoted-with-space flag-with-space; do
        case "$SHAPE" in
          single)              ARG="'git $VERB foo'" ;;
          double)              ARG="\"git $VERB foo\"" ;;
          unquoted-with-space) ARG="git $VERB foo bar" ;; # No quotes; the verb appears as a literal arg with surrounding space
          flag-with-space)     ARG="--pattern \"git $VERB\"" ;; # `--pattern` then quoted-arg containing `git $VERB`
        esac
        FULL="$CMD $ARG /tmp/notes.md"
        setup_project_test_on_main
        expect_project_allow "matrix-$CMD-$VERB-$SHAPE" "$FULL"
        teardown_project_test
      done
    done
  done

  # Generic-hook matrix: 8 commands × 6 verbs × 4 quote-shapes = 192 negative cases.
  # 6 verbs: 5 git-verbs (genuinely migrated) + 1 destructive (kill -9).
  # rm -rf / find -delete REMOVED from the verb set per round-1 DA-C-2 — those
  # sites are not migrated and the existing bare regex still catches `grep "rm -rf foo"`,
  # so a matrix entry for them would FAIL (correctly: existing behavior preserved).
  for CMD in grep sed awk cat echo printf head tail; do
    for VERB in "git restore" "git clean -f" "git reset --hard" "git add -A" "git commit --no-verify" "kill -9"; do
      for SHAPE in single double unquoted-with-space flag-with-space; do
        case "$SHAPE" in
          single)              ARG="'$VERB foo'" ;;
          double)              ARG="\"$VERB foo\"" ;;
          unquoted-with-space) ARG="$VERB foo bar" ;;
          flag-with-space)     ARG="--pattern \"$VERB\"" ;;
        esac
        FULL="$CMD $ARG /tmp/notes.md"
        SAFE_VERB="$(echo "$VERB" | tr ' /-' '___')"
        expect_allow "matrix-$CMD-$SAFE_VERB-$SHAPE" "$FULL"
      done
    done
  done

  # Adjacent-class coverage (24 cases): path-substring (`grep git-commit-notes.md`)
  # and flag-value (`grep --pattern=git-commit`) — these do NOT exercise the bare
  # regex bug class (no literal space between `git` and verb), but they DO exercise
  # the path-substring / flag-value adjacent classes. Round-1 R-H-4 split out from
  # the main matrix for honest coverage labeling.
  for CMD in grep sed awk cat echo printf head tail; do
    for VERB in commit cherry-pick push; do
      expect_project_allow "adjacent-class-pathsub-$CMD-$VERB" "$CMD git-$VERB-notes.md"
      expect_project_allow "adjacent-class-flagval-$CMD-$VERB"  "$CMD --pattern=git-$VERB /tmp/notes.md"
    done
  done
  ```

  Each `expect_*` invocation runs the appropriate hook and asserts exit 0 + no deny envelope.

  **Setup/teardown discipline (round-2 R2-H-2 / DA2-H-4 — was "MAY hoist" loophole; now MUST per-iteration).** Calling `setup_project_test_on_main`/`teardown_project_test` 144 times per phase IS slow (~7-15s wall-clock, empirically verified per `tests/test-hooks.sh:395-427` × 144). The round-1 "MAY hoist provided tear-up state is invariant" prose put correctness judgment on the implementer for an invariant the plan never proved holds — the hook MAY write to `$TEST_TMPDIR/.zskills/tracking/`, the test invocations MAY produce side effects, and silent cross-case state contamination would mean case N+1 passes vacuously because case N left state. **Decision: per-iteration setup is MANDATORY for the negative matrix.** The performance cost (~10s) is acceptable given the matrix runs only on hook-touching CI gates.

  An OPTIONAL hoist is permitted ONLY for the adjacent-class block (24 cases at the bottom of 5.2, no main_protected dependency); those use the existing top-level `expect_project_allow` / `expect_allow` (no `_on_main` variant) and don't need per-iteration setup at all. The Phase 5.2 code shown above already enforces this: the matrix loop calls `setup_project_test_on_main; expect_project_allow ...; teardown_project_test` per iteration; the adjacent-class block uses bare `expect_project_allow`.

  **Round-2 DA2-H-4 invariant assertion (defense-in-depth).** Phase 5.2 implementer MUST add a sanity-check immediately AFTER the matrix loop completes: `find "$TEST_TMPDIR" -type f 2>/dev/null | wc -l` returns 0 (the per-iteration teardown should have removed everything). If nonzero, fail the matrix with diagnostic output — this catches a bug in `teardown_project_test` or a hook side-effect that's not being cleaned up.

- [ ] 5.3 — Class-pinned positive matrix: 6 actual destructive-verb invocations × 4 invocation-shape variants = 24 positive cases that MUST DENY. This asserts the migration doesn't weaken the positive surface AT THE CLASS LEVEL, complementing Phases 3.4 and 4.5's per-verb positive regressions.

- [ ] 5.4 — Drift check on inlined helpers. **Per D7: NEW file `tests/test-hook-helper-drift.sh` (NOT added to `tests/test-skill-conformance.sh`).** Round-0 hedged "or new test file"; round-1 R-M-5 / DA-M-4 resolved: hook-helper drift is the wrong scope for skill-conformance; a dedicated file is right.

  ```bash
  #!/bin/bash
  # tests/test-hook-helper-drift.sh — assert inlined helpers in
  # hooks/block-unsafe-*.sh* are byte-identical to hooks/_lib/git-tokenwalk.sh.
  # CI gate per D7. Plan B's hook is added here as an additional consumer
  # in Phase 6 (or via /refine-plan if Plan B is still pending).
  #
  # Round-2 R2-M-2 fix: tests/test-helpers.sh does NOT exist in this repo
  # (verified empirically). Define pass/fail inline mirroring the
  # tests/test-hooks.sh:12-22 pattern. Do NOT add a new repo-level helpers
  # file in this plan — Phase 5.4's commit boundary excludes it.
  set -e
  PASS_COUNT=0
  FAIL_COUNT=0
  pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
  fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
  for HOOK in hooks/block-unsafe-project.sh.template hooks/block-unsafe-generic.sh; do
    for FN in is_git_subcommand is_destruct_command; do
      # is_destruct_command is only inlined in generic hook; skip for project.
      [[ "$FN" == "is_destruct_command" && "$HOOK" == *project* ]] && continue
      if diff <(sed -n "/^$FN()/,/^}$/p" "$HOOK") \
              <(sed -n "/^$FN()/,/^}$/p" hooks/_lib/git-tokenwalk.sh) \
              > /dev/null; then
        pass "drift: $HOOK $FN matches source-of-truth"
      else
        fail "drift: $HOOK $FN drifted from hooks/_lib/git-tokenwalk.sh"
      fi
    done
  done
  exit $FAIL_COUNT
  ```

  Register in `tests/run-all.sh` AFTER `test-tokenize-then-walk.sh`: `run_suite "test-hook-helper-drift.sh" "tests/test-hook-helper-drift.sh"`. Phase 5 commit boundary (D&C below) includes this new file.

  **`hooks/_lib/` install behavior** (per Phase 2 D&C `hooks/_lib/` note): the `_lib/` directory is NOT installed by `/update-zskills`. Verify via `grep -F '_lib' skills/update-zskills/SKILL.md` returns 0 matches (no install step references it). The drift gate runs only in this repo's CI, not in consumer projects.

- [ ] 5.5 — Run `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` and confirm exit 0. Total case count increased in Phase 5 alone by: 144 (project negative matrix) + 192 (generic negative matrix) + 24 (project adjacent-class) + 24 (5.3 positive matrix) = 384. Cumulative-from-baseline Phase 1-5 case increase: 0 (Phase 1 — no tests) + 124 (Phase 2 unit cases — round-2 added 16: XCC30/31/32/34 × 3 verbs = 12 + XKL9/10/11/12 = 4) + 21 (Phase 3 PR1-PR10 with PR10 expansion) + 28 (Phase 4 GR1-GR25 + GR12a/12b/12c — round-2 added 3) + 384 (Phase 5) = 557 new test cases.

- [ ] 5.6 — Update `plans/PLAN_INDEX.md`: move BLOCK_UNSAFE_HARDENING entry from "Ready to Run" to "Completed" or equivalent section per the index's existing convention. Add a one-liner note: "closes patch trail #58/#73 + #81/#87; class-pinned matrix; tokenize-then-walk pattern."

- [ ] 5.7 — **Update the existing PR with the Phase 5 commit and ensure CI is green; do NOT open a new PR.** The PR was opened earlier (per "PR-mode landing. Single PR with all 5 phase commits in order" in D&C below). After pushing the Phase 5 commit, dispatch `/land-pr` via Skill tool to monitor CI and merge when green (do NOT call `gh pr merge --auto` directly — see CLAUDE.md "Never call `gh pr create` or `gh pr merge --auto` directly"). Round-2 DA2-O-3 wording fix: this is "land the existing PR after the final commit," not a fresh `/land-pr` invocation. PR body (already opened) MUST be updated to include the patch-trail-this-plan-closes table from the Overview verbatim AND a bullet noting the future-work refactor cited in 5.1 (PUSH_ARGS, unmigrated subset, line-246 close-quote/pipe narrowing, D5 carve-outs).

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `CHANGELOG.md` + `tests/test-hooks.sh` + `tests/test-hook-helper-drift.sh` (NEW per D7) + addition to `tests/run-all.sh` (single `run_suite` line) + `plans/PLAN_INDEX.md`. Subject: `feat(hooks): BLOCK_UNSAFE_HARDENING Phase 5 — class-pinned matrices + drift gate + finalization`.
- **PR-mode landing.** Single PR with all 5 phase commits in order; rebase on main if needed; `/land-pr` polls CI; auto-merge gated on CI green.
- **No skill metadata.version bump in any phase of this plan.** Hooks ≠ skills.
- **NO `--no-verify`. NO `jq`. NO `2>/dev/null` on critical ops. Capture test output to file, never pipe.**

### Acceptance Criteria

- [ ] AC1 — `grep -F 'BLOCK_UNSAFE_HARDENING' CHANGELOG.md` returns ≥ 1 (entry present). Additionally, exactly ONE H3 entry under today's date H2: `grep -cE '^### Added — Hooks: tokenize-then-walk' CHANGELOG.md` returns 1 (round-2 #9 of DA review labeling lock).
- [ ] AC2 — Class-pinned negative matrix (migrated subset): `bash tests/test-hooks.sh > "$TEST_OUT/.test-results.txt" 2>&1; grep -c '^PASS matrix-' "$TEST_OUT/.test-results.txt"` returns ≥ `336` (144 project + 192 generic over the migrated verbs only). Note: this matrix does NOT exercise the unmigrated subset (`rm -rf`/`find -delete`/`rsync --delete`/`xargs ... rm`/`fuser -k`); CHANGELOG bullet 4 documents that the bug class remains open for those sites.
- [ ] AC2b — Adjacent-class coverage matrix (round-1 R-H-4): `grep -c '^PASS adjacent-class-' "$TEST_OUT/.test-results.txt"` returns ≥ `24` (12 path-substring + 12 flag-value, project hook only).
- [ ] AC3 — Class-pinned positive matrix: `grep -c '^PASS positive-matrix-' "$TEST_OUT/.test-results.txt"` returns ≥ `24`.
- [ ] AC4 — All 4 TRACED reproducers PRESENT and PASSING. Round-1 DA-C-1: R3 is UNTRACED and NOT in the test surface.
  - PR1 (R1), PR2 (R2), PR3 (R4) in project-hook section (Phase 3.4).
  - GR1 (R5) in generic-hook section (Phase 4.5).
- [ ] AC5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC6 — Drift check PASS: `bash tests/test-hook-helper-drift.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0; `grep -c '^FAIL drift' "$TEST_OUT/.test-results.txt"` returns 0.
- [ ] AC7 — `gh pr checks <PR-number>` returns all green (CI is the ground truth per CLAUDE.md "Check CI before recommending merge"; local green is necessary but not sufficient).
- [ ] AC8 — `git log --oneline main..HEAD` shows exactly 5 commits (Phases 1-5), one per phase, in order. Phase 6 (if it lands as substantive work) adds a 6th commit. Per-phase commit boundaries verified by `git diff --stat <phase-N-1-commit>..<phase-N-commit>` matching the Phase N D&C "scope" enumeration.
- [ ] AC9 — Round-1 R-C-2 fix, round-2 reinstated checkout. Per-file enumeration:
  - `grep -nE 'git\[\[:space:\]\]\+(commit|cherry-pick|push|restore|clean|reset|add|checkout)' hooks/block-unsafe-project.sh.template | grep -vE '^(56|227):'` returns 0 lines. (Line 56 = redaction sed (D3). Line 227 = `git add \.claude/logs/?` (out of scope per Phase 3 Goal).)
  - `grep -nE 'git\[\[:space:\]\]\+(commit|cherry-pick|push|restore|clean|reset|add|checkout)' hooks/block-unsafe-generic.sh | grep -vE '^82:'` returns 0 lines. (Line 82 = redaction sed (D3). Round-2: line 120 `git checkout --` IS migrated per DA2-H-1 — drop it from the filter.)
  - `grep -nE 'git\[\[:space:\]\]\+(commit|cherry-pick|push|restore|clean|reset|add|checkout)' hooks/block-unsafe-project.sh | grep -vE '^(56|227):'` returns 0 lines (mirror parity).
  - `grep -nE 'git\[\[:space:\]\]\+(commit|cherry-pick|push|restore|clean|reset|add|checkout)' .claude/hooks/block-unsafe-generic.sh | grep -vE '^82:'` returns 0 lines (`.claude/hooks/` mirror; same line numbers).
  - Implementer MUST verify line numbers empirically post-migration; the D3-preserved redaction sed line may shift if function-body insertion changes the file. Update the AC pin if so.
- [ ] AC10 — `plans/PLAN_INDEX.md` updated: BLOCK_UNSAFE_HARDENING moved to completed section.

### Dependencies

Phases 1-4 complete.

---

## Phase 6 — Plan B consolidation (conditional)

### Goal

Per D6 (Plan B coordination): if Plan B's `block-stale-skill-version.sh` has already landed by the time Phases 1-5 of this plan reach Phase 5 sign-off AND Plan B's hook still inlines its own `is_git_commit` (rather than consuming `hooks/_lib/git-tokenwalk.sh`), this phase migrates Plan B's hook to consume the source-of-truth. If Plan B is still pending Phase 2 OR Plan B was already `/refine-plan`'d to consume `hooks/_lib/git-tokenwalk.sh` BEFORE its Phase 2 landed, this phase is a no-op verification.

**Decision flow at Phase 6 start:**

1. `git log --oneline main -- hooks/block-stale-skill-version.sh` — has Plan B's hook landed?
2. If NO: this phase is no-op. Mark complete with a one-line note in PLAN_INDEX explaining Plan B will inline `hooks/_lib/git-tokenwalk.sh` directly when its Phase 2 lands (per D6). **Round-2 DA2-M-1 mid-execution race note:** if Plan B's hook is being landed CONCURRENTLY (a worktree exists but PR is not yet merged), still no-op this phase — the consolidation can run as a follow-up commit after Plan B lands. Do NOT block Plan B by trying to coordinate mid-flight.
3. If YES: check Plan B status — `awk -F': ' '/^status:/ {print $2; exit}' plans/SKILL_VERSION_PRETOOLUSE_HOOK.md`. Branches into 3a / 3b:
   - **3a — Plan B status is `active`:** proceed with work items 6.1-6.5; 6.4 dispatches `/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` to update Plan B's test surface.
   - **3b — Plan B status is `complete`:** proceed with 6.1-6.5; 6.4 edits `tests/test-block-stale-skill-version.sh` directly (`/refine-plan` is not appropriate for completed plans). The commit message body must include a one-line citation of this plan's Phase 6 as the rationale for the test edit.

### Work Items (conditional — only if Plan B already landed)

- [ ] 6.1 — Verify Plan B's hook currently inlines `is_git_commit` (rather than `is_git_subcommand`): `grep -F 'is_git_commit' hooks/block-stale-skill-version.sh` returns ≥ 1 match. If 0, ALSO check whether the tokenize-walk skeleton is duplicated under a different helper name (round-2 R2-M-1 belt-and-suspenders): `grep -cE '^[[:space:]]*read -ra TOKENS' hooks/block-stale-skill-version.sh` returns 0 AND `diff <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/block-stale-skill-version.sh) <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/_lib/git-tokenwalk.sh)` exits 0 (meaning Plan B already consumes the source-of-truth). If both checks pass, Plan B has ALREADY been consolidated; this phase is no-op. If the tokenize-walk skeleton is present under a third name (neither `is_git_commit` nor `is_git_subcommand`), proceed with consolidation (rename to `is_git_subcommand`).
- [ ] 6.2 — Replace Plan B's inlined `is_git_commit` body with an inlined copy of `is_git_subcommand` from `hooks/_lib/git-tokenwalk.sh`. Replace the call site `is_git_commit "$COMMAND" || exit 0` with `is_git_subcommand "$COMMAND" commit || exit 0`. Mirror to `.claude/hooks/block-stale-skill-version.sh`.
- [ ] 6.3 — Add `hooks/block-stale-skill-version.sh` to the drift-check loop in `tests/test-hook-helper-drift.sh`:
  ```bash
  for HOOK in hooks/block-unsafe-project.sh.template hooks/block-unsafe-generic.sh hooks/block-stale-skill-version.sh; do
    # ... existing check ...
  done
  ```
- [ ] 6.4 — Update Plan B's existing tests (`tests/test-block-stale-skill-version.sh` per Plan B Phase 2) to reflect the helper rename from `is_git_commit "$cmd"` to `is_git_subcommand "$cmd" commit`. **Round-2 DA2-M-2 explicit branch handling (per D6):**
  - **If Plan B status is `active`:** dispatch `/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` (via Skill tool) with guidance: "consume `hooks/_lib/git-tokenwalk.sh` source-of-truth; rename `is_git_commit` to `is_git_subcommand "$cmd" commit`."
  - **If Plan B status is `complete`:** edit `tests/test-block-stale-skill-version.sh` directly (`/refine-plan` is not appropriate for completed plans). Bump signature-related count expectations if applicable. Commit message body MUST include the citation: `Closes Plan B test-rename rationale; per BLOCK_UNSAFE_HARDENING.md Phase 6 / D6 (round-2 DA2-M-2).`
- [ ] 6.5 — Run `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0. Drift gate passes; Plan B's existing test surface passes.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/block-stale-skill-version.sh` + `.claude/hooks/block-stale-skill-version.sh` + `tests/test-hook-helper-drift.sh` + (if needed) `tests/test-block-stale-skill-version.sh`. Subject: `refactor(hooks): block-stale-skill-version — consume hooks/_lib/git-tokenwalk.sh source-of-truth (D6 consolidation)`.
- **Mirror MUST be in same commit.**
- **No skill metadata.version bump.**
- **NO `--no-verify`. NO `jq`. NO `2>/dev/null` on critical ops.**

### Acceptance Criteria

- [ ] AC1 — `grep -F 'is_git_commit' hooks/block-stale-skill-version.sh` returns 0 (helper consolidated).
- [ ] AC2 — `grep -F 'is_git_subcommand' hooks/block-stale-skill-version.sh` returns ≥ 2 (1 inlined function definition + 1 call site).
- [ ] AC3 — `diff <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/block-stale-skill-version.sh) <(sed -n '/^is_git_subcommand()/,/^}$/p' hooks/_lib/git-tokenwalk.sh)` exits 0.
- [ ] AC4 — Drift gate at `tests/test-hook-helper-drift.sh` covers all 3 hooks: `grep -c 'block-stale-skill-version.sh' tests/test-hook-helper-drift.sh` returns ≥ 1.
- [ ] AC5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC6 (no-op branch) — If 6.1 returned 0, mark this phase complete with PLAN_INDEX note and skip AC1-AC5.

### Dependencies

Phases 1-5 complete AND (Plan B's hook has landed OR Plan B has been `/refine-plan`'d to consume the source-of-truth). The decision flow in Goal section discriminates.

---

## Drift Log

Round-1 refinement landed (`/draft-plan` round 1, refiner): structural changes per the round-1 reviewer + DA findings.

| Date | Change | Reason |
|------|--------|--------|
| 2026-05-03 | Added D6 (Plan B coordination ordering decision) | Round-1 DA-C-3: "either may land first" produces guaranteed three-way duplication |
| 2026-05-03 | Added D7 (drift-check vehicle decision: new `tests/test-hook-helper-drift.sh`) | Round-1 R-M-5 / DA-M-4 |
| 2026-05-03 | Moved source-of-truth from `tests/fixtures/` to `hooks/_lib/git-tokenwalk.sh` | Round-1 DA-H-4: tests/fixtures/ as runtime source-of-truth is a maintenance trap |
| 2026-05-03 | Helper API extension: `GIT_SUB_INDEX` + `GIT_SUB_REST` globals (segment-truncated post-verb buffer) | Round-1 R-H-2 / DA-M-6: hybrid pattern over `$COMMAND` re-introduced false-positive class |
| 2026-05-03 | Helper API extension: `:next:<regex>` syntax for positional-pair flag matching (kill -s 9) | Round-1 R-H-5: `^-s$` alone weakens the discriminator |
| 2026-05-03 | Helper API extension: subcommand quote-strip | Round-1 DA-H-1: `git "commit"` JSON-wire-format bypass |
| 2026-05-03 | DEMOTED R3 from named AC test to "UNTRACED reproducer" in reference doc | Round-1 DA-C-1: empirical re-verification confirmed R3 trips no current regex |
| 2026-05-03 | DROPPED migration of generic-hook lines 146 (`fuser -k`), 217 (`RM_RECURSIVE`), 225 (`find -delete`), 232 (`rsync --delete`), 239 (`xargs ... rm`) | Round-1 DA-C-2: first-token-anchoring would silently weaken pipeline-fed coverage; bare regex provides whole-buffer scan that catches `cat foo \| xargs rm`, `pgrep \| xargs kill`, `fuser -mk` |
| 2026-05-03 | DROPPED migration of generic-hook line 120 (`git checkout --`) | Round-1 DA-M-6: existing regex already properly bounded |
| 2026-05-03 | EXPANDED Phase 5.2 SHAPE generator: all 4 shapes contain `git $VERB` (with literal space); split out 24 adjacent-class cases | Round-1 R-H-4: `unquoted` and `flagval` round-0 shapes vacuously passed (no literal `git VERB` substring) |
| 2026-05-03 | Added Phase 2.3 harness extension `setup_project_test_on_main` shared by Phase 3 + Phase 5.2 | Round-1 R-C-1 / R-H-6: matrix needs `is_main_protected=true` + `on main` to exercise line-404/540 predicates |
| 2026-05-03 | FIXED Phase 5 AC9 grep filter — enumerate explicit allowed line numbers per file rather than rely on broken `grep -v 'redaction\|STASH_BOUNDARY\|RM_RECURSIVE'` | Round-1 R-C-2: surviving lines don't contain those literal words inline |
| 2026-05-03 | FIXED Phase 3 AC1 line filter from `^(56|82):` to `^56:` (line 82 belongs to generic hook) | Round-1 R-H-1 |
| 2026-05-03 | FIXED Progress Tracker site count from "5 call sites" to "6 call sites" | Round-1 DA-M-2 / R-H-3 |
| 2026-05-03 | FIXED 12-vs-13 command count drift in D4 prose + Phase 5.2 loop (12 chosen; `diff` dropped) | Round-1 DA-H-2 |
| 2026-05-03 | FIXED Phase 2 AC9 `grep -F 'jq' hooks/` to use `-rF` flag | Round-1 R-M-4 |
| 2026-05-03 | EXPANDED D5 carve-out documentation to enumerate `$()`, backticks, `$VAR` (not just `bash -c`); added cases XCC23/XCC24/XCC25 | Round-1 R-M-3 |
| 2026-05-03 | Added Phase 6 (Plan B consolidation) | Round-1 DA-C-3: "future work" was a fig leaf for an unresolved coordination problem |
| 2026-05-03 | DROPPED GR5 (`grep "rm -rf foo"` claim) — unsubstantiated; no real bug report | Round-1 DA-H-3 |
| 2026-05-03 | RENUMBERED PR3-PR11 → PR3-PR10 after R3 demotion; renumbered GR cases after dropping GR5/GR6/GR7 and adding GR11/GR12 (segment-truncation) + GR17/GR18 (positional-pair) + GR19-GR22 (DA-C-2 lock cases) + GR25 (DA-H-1 quote-strip) | Round-1 cascade from above changes |
| 2026-05-03 | EXPANDED D5 carve-out enumeration from `bash -c`/`$()`/backticks/`$VAR` to ALSO include: quote-blind `read -ra` (positive over-match), space-elided shell-control (positive over-match), `env -i`/`sudo`/`doas`/`su` prefix bypass, multi-line commands. Added unit cases XCC30/31/32/34 + XKL11/12 to lock each. | Round-2 R2-C-1 / DA2-C-1 (quote-blind), DA2-H-3 (env -i / sudo), DA2-M-4 (multi-line) |
| 2026-05-03 | ADDED Phase 4 GR12a (`git reset 'msg --hard text'` → DENY) + GR12b (`git clean foo;rm -f bar` → DENY) — INTEGRATION-level locks for the residual quote-blind / space-elided over-match | Round-2 R2-C-1 / DA2-C-1 |
| 2026-05-03 | REINSTATED line-120 (`git checkout --`) to migration scope (round-1 DA-M-6's "properly bounded" claim was wrong about first-token anchoring; refiner's session live-blocked on `printf 'git checkout -- foo'`-style buffer text). Added GR12c lock (printf-form ALLOW + real-form DENY). | Round-2 DA2-H-1 |
| 2026-05-03 | COLLAPSED D6's "/refine-plan it before" branch — now an OPTIONAL orchestrator action (not a Phase 2 work-item). Phase 6 is the canonical consolidation path regardless of Plan B status. | Round-2 DA2-C-2 (round-1's branch was aspirational; no work-item dispatched it) |
| 2026-05-03 | ADDED Phase 6 explicit branch handling for Plan B status `complete` (edit `tests/test-block-stale-skill-version.sh` directly; `/refine-plan` not appropriate for completed plans) + mid-execution race no-op | Round-2 DA2-M-1 / DA2-M-2 |
| 2026-05-03 | ADDED Phase 2.6 work-item: install-loop comment in `skills/update-zskills/SKILL.md` documenting `hooks/_lib/` exclusion. Triggers `metadata.version` bump for `update-zskills` (Non-goals revised). | Round-2 R2-L-2 / DA2-M-1 |
| 2026-05-03 | TIGHTENED Phase 5.2 setup discipline from "MAY hoist provided invariant" to MANDATORY per-iteration setup with post-loop sanity-check (`find $TEST_TMPDIR -type f \| wc -l` returns 0). Optional hoist permitted only for adjacent-class block (no main_protected dependency). | Round-2 R2-H-2 / DA2-H-4 |
| 2026-05-03 | TIGHTENED Phase 2 AC1 from `bash -n` smoke-check to ALSO assert function definitions are reachable (`type -t is_git_subcommand` + `type -t is_destruct_command` both return `function`) | Round-2 R2-H-4 |
| 2026-05-03 | ADDED Phase 6.1 belt-and-suspenders discriminator: also check `read -ra TOKENS` skeleton + diff vs source-of-truth, in case Plan B refactored to a third helper name | Round-2 R2-M-1 |
| 2026-05-03 | ADDED Phase 1.1 work-item to empirically capture line-540 cherry-pick state (Overview claim re-phrased from "was never patched" claim-of-fact to "structurally identical and unprotected by prior patches" hypothesis form, per the plan's own per-reproducer empirical discipline) | Round-2 DA2-H-5 |
| 2026-05-03 | DOCUMENTED Phase 4.2 line-246 boundary narrowing (close-quote/pipe boundary cases dropped) in CHANGELOG bullet 3; verified no positive regression test exists for the pipe-glued form | Round-2 R2-H-3 |
| 2026-05-03 | DOCUMENTED PUSH_ARGS pre-existing carve-out (extracts from `$COMMAND` not `$GIT_SUB_REST`) in CHANGELOG and Phase 4.2 D&C; out of scope for this plan but explicitly acknowledged | Round-2 DA2-O-2 |
| 2026-05-03 | FIXED Phase 5.4 drift-test skeleton: replaced `source tests/test-helpers.sh` (file does not exist) with inline pass/fail definitions mirroring `tests/test-hooks.sh:12-22` | Round-2 R2-M-2 |
| 2026-05-03 | FIXED Decisions-section prose "5 design decisions" / "D[1-5]" → "7 design decisions" / "D[1-7]" to match AC1 grep | Round-2 R2-M-4 |
| 2026-05-03 | CLARIFIED Phase 5.7 wording: "land the EXISTING PR" not "open a fresh PR via /land-pr"; the PR opens earlier per PR-mode landing | Round-2 DA2-O-3 |
| 2026-05-03 | LOCKED CHANGELOG entry shape: ONE H3 entry titled `### Added — Hooks: tokenize-then-walk source-of-truth + class-pinned matrices (BLOCK_UNSAFE_HARDENING)` under today's H2 (NOT 6 separate H3s) — added AC1 grep | Round-2 #9 of DA review (date convention) |
| 2026-05-03 | UPDATED test counts: Phase 2 unit cases 104 → 124 (XCC30/31/32/34 × 3 + XKL9/10/11/12 = 16 new); Phase 4 GR cases 25 → 28 (GR12a/12b/12c added); Phase 5.5 cumulative 534 → 557 | Round-2 cascade from carve-out lock additions |

## Plan Quality

**Drafting process:** `/draft-plan` with 2 rounds of adversarial review (reviewer + devil's advocate in parallel + refiner with verify-before-fix discipline)
**Convergence:** Converged at round 2 (0 critical, 0 high, 0 medium remaining; 1 cosmetic GR-renumbering preserved for round-1 disposition traceability)
**Remaining concerns:** None blocking. Documented carve-outs (D5 quote-blind tokenization, multi-line shell-control) are explicit design trade-offs locked by negative test cases.

### Round History
| Round | Reviewer Findings | DA Findings | Critical | High | Resolved |
|-------|-------------------|-------------|----------|------|----------|
| 1     | 16 (2C + 6H + 8M/L + 9VP)  | 14 (3C + 4H + 1M + 6VP) | 5 unique | 10 | 25/25 (1 justified cosmetic) |
| 2     | 14 (1C + 4H + ~5M/L + 4VP) | 16 (2C + 5H + 6M/L + ~3VP) | 3 unique | 9 | 20/20 (1 justified cosmetic) |

### Notable empirical findings during refinement
- **5 in-session reproducers** of the bug class hit during the drafting process itself (Plan B's 2 DA reproducers + the orchestrator's `gh issue list --search 'OR'` + the prior-art agent's `grep -nE` + the round-2 reviewer's heredoc-with-`git checkout --` block + the refiner's own block during verification). Confirms the bug class is currently active and bites real workflows, not just review tooling.
- **PR3 demoted to UNTRACED** (round 1) after both DA's empirical re-test and refiner's confirmation that no current regex fires on the orchestrator's exact `gh issue list --search 'OR'` query. The block the orchestrator saw was real but its causative regex could not be reproduced; honest documentation as "untraced reference" beats a false class-pinned AC.
- **Line 120 (`git checkout --`) reinstated** to migration scope (round 2) after refiner's session live-block reproduced the over-match class against `git checkout -- foo` literal text, contradicting initial scope-reduction.
- **Read-ra quote-blindness** (round 2) accepted as documented carve-out (D5) rather than implementing a hand-rolled quote-aware tokenizer that would re-introduce the regex-fragility class the plan exists to kill. Both reviewer and DA recommended this trade-off explicitly.

### Plan B coordination
This plan creates `hooks/_lib/git-tokenwalk.sh` as the source-of-truth for the generalized `is_git_subcommand` helper. Plan B (`SKILL_VERSION_PRETOOLUSE_HOOK.md`) implements its own inlined `is_git_commit` for `block-stale-skill-version.sh`. After both plans land, Phase 6 of THIS plan handles consolidation: if Plan B is `status: active` (not yet executed), dispatch `/refine-plan plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` to migrate Plan B Phase 2 to use the shared helper; if Plan B is `status: complete` (already shipped with its own `is_git_commit`), edit Plan B's hook directly with citation. Either way, ONE source-of-truth ships to consumers.

### Out-of-scope (recorded for follow-up)
- **PUSH_ARGS pre-existing carve-out** — `is_main_protected` push-rule (c) extracts `PUSH_ARGS` from `$COMMAND` via regex, NOT from `$GIT_SUB_REST`. Same scoping bug class round 1 fixed elsewhere; future-work to propagate the fix to PUSH_ARGS extraction (documented in Phase 4.2 D&C + CHANGELOG).
- **Newline-separated command bypass** — `echo hi\ngit commit` slips past the helper because `read -ra <<<` only feeds one line. Same property as Plan B's `is_git_commit`. Documented as carve-out; a future multi-line tokenizer would be a structural rewrite, out of scope here.
