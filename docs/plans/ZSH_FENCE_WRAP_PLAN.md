---
issue: 1155
title: zsh/macOS portability of skill-file bash fences — three-track remediation + conformance tripwire
created: 2026-06-12
status: active
---

# Plan: zsh Fence Portability — Three-Track Remediation + Conformance Tripwire (#1155 remainder)

## Overview

On stock macOS, Claude Code snapshots the user's login shell (zsh) and skill-file
bash fences execute under **zsh 5.9**, not bash. Issue #1155 catalogued the
breakage; PR #1169 shipped the P0 subset — fence-local
`setopt KSH_ARRAYS BASH_REMATCH` guards on the four worst regex fences
(`run-plan/SKILL.md` ≈L101 + ≈L212, `do/SKILL.md` ≈L292, `land-pr/SKILL.md`
≈L69). PR #1168 separately fixed the sourceable `.sh` helpers (LOCAL_OPTIONS
setopt form) — out of scope here. This plan finishes #1155 for the remaining
~67 bash-ism fences across 15 skills and lands the durable half: a conformance
tripwire so new fences can never silently regress.

**The original "#1155 sketch" said "wrap ~25 fences in the quoted-heredoc
idiom". The fence inventory PROVES that is wrong as a uniform mechanism**:
~49 of the 70 executed bash-ism fences cannot be wrapped (9+ SKILL-INVOKE
fences dispatch the Skill tool mid-fence; ~40 fences participate in
cross-fence variable flow that a child-`bash` wrap would sever, since the
child only inherits *exported* vars and its assignments die with it).
Drafting-time re-verification went further: **every Track-W candidate
spot-checked so far demotes under the binding classification protocol**
(run-plan ≈L1119, do ≈L978, add-remove ≈L115 — see "Inventory
corrections"). The honest policy is therefore **mechanism-per-fence, not
wrap-first**: the per-fence classification protocol below is the authority,
and the plan's value rests on Track G (guard v2), Track R (rewrites), the
subscript normalization, and the conformance tripwire.

- **Track G (guard)** — the fence-local setopt guard (extended canonical
  form, see below) for cross-fence/SKILL-INVOKE fences whose bash-isms are
  setopt-fixable: `[[ =~ ]]`/`BASH_REMATCH`, 0-based indexed-array access,
  and word-split reliance (`for tok in $SCALAR`). This is the workhorse
  track (~45+ fences).
- **Track R (rewrite)** — source-level, behavior-identical-under-both-shells
  rewrites for setopt-UNFIXABLE constructs sitting in unwrappable fences:
  `mapfile` (6 exec sites), `read -r -a` (13 sites), `${var,,}` (2 sites),
  `${!var}` (1 site), `compgen -G` (1 site — missed by prior research).
- **Track W (wrap)** — `bash <<'ZSKILLS_BASH_FENCE' … ZSKILLS_BASH_FENCE`.
  **OPPORTUNISTIC, not a deliverable**: it is the documented fix-of-choice
  for any GENUINELY self-contained bash-ism fence, but no inventoried fence
  has yet survived the classification protocol's self-containment checks —
  the final wrap count may be ZERO, and zero is an acceptable outcome. The
  idiom and rc contract stay specced verbatim below: they are the right
  tool for future self-contained fences, and the tripwire's wrap-detection
  needs their exact shape.
- **declare -A decision** — 20 associative-array declarations (19
  `declare -A` + 1 `local -A`, across 12 files; incl. the 11 caller-loop
  `LP`-family clones). Resolved by a committed probe; the pre-drafting
  probe run (validated 2026-06-12, recorded on #1155) shows the as-written
  pattern is NOT byte-identical under zsh — but a one-line-per-site
  **subscript-quoting normalization** is, so neither blanket verified-accept
  nor a flat-var rewrite is the expected branch. See "The declare -A
  decision".

The durable half is a new section in `tests/test-skill-conformance.sh`
cloning the WI-5.2 fence state machine: every exec fence containing a
zsh-divergent construct must be wrapped, guarded, rewritten away, or carry
an inspectable `<!-- allow-zsh-unwrapped: … -->` marker. It lands in Phase 1
**scoped by a pending-list fixture** so it cannot block concurrent sibling
PRs, ratchets per phase, and goes fully unconditional in Phase 5.

**Falsifiable end state:**

1. `bash tests/test-skill-conformance.sh` includes the zsh-fence tripwire
   running UNSCOPED (the pending-list fixture
   `tests/fixtures/zsh-fence-pending.txt` no longer exists) and passes.
2. `grep -rnE '(^|[^A-Za-z0-9_#])(mapfile|readarray|compgen)([^A-Za-z0-9_]|$)' skills/ --include='*.md' | grep -vE '^\S+:[0-9]+:\s*#' | grep -v 'allow-zsh-unwrapped'`
   finds only prose/comment mentions, zero executable sites (Phase-AC greps
   below are per-construct and stricter).
3. `bash tests/test-zsh-fence-semantics.sh` (new durable probe suite) passes
   — byte-identical bash-vs-zsh output for every idiom this plan relies on.
   In CI the suite REQUIRES zsh (the workflow gains an install step, WI 1.6,
   and the suite hard-FAILs when `${CI:-}` is set and zsh is absent);
   locally it SKIPs with a loud WARN when zsh is missing.
4. `bash tests/run-all.sh` passes clean.
5. Issue #1155 is closable: every fence in the appendix inventory is
   dispositioned (wrapped / guarded / rewritten / normalized / markered) and
   the tripwire enforces the policy for all future fences. Two
   known-residual divergence classes are accepted and RECORDED, not fixed:
   (a) argument-position word-split (`cmd $FLAGS`) in construct-free fences
   — not regex-detectable without unbounded false positives; fences that
   carry a v2 guard are incidentally fixed (SH_WORD_SPLIT is fence-global);
   (b) glob-in-var expansion (`v="*.md"; ls $v`) — the v2 guard does not
   set GLOB_SUBST (reproduced divergent 2026-06-12; zero current users —
   the one glob-existence site is R5-rewritten to a quoted `find -name`).
   Both are pinned in the probe suite (s12) and named in the authoring
   note (WI 1.4) so "guarded = full bash semantics" is never assumed.

## Settled decisions (do not relitigate)

1. **Mechanism-per-fence policy, not uniform wrap — and Track W is
   opportunistic, not a deliverable.** The "wrap ~25 fences" framing from
   the original #1155 sketch is dead — the inventory proves ~49 of 70
   fences are structurally unwrappable, and every spot-checked "wrappable"
   candidate has so far demoted under the classification protocol
   (Inventory correction 1). No phase carries a minimum-wrap acceptance
   criterion; **zero wraps is an acceptable end state**. Every wrap that
   DOES land must carry the protocol's step-2/step-3 grep evidence in the
   phase report.
2. **#1169 guards stay** as the Track-G mechanism. They are upgraded in
   place to the extended canonical guard string (adds `SH_WORD_SPLIT` — a
   strict increase in bash-parity; bash always word-splits unquoted
   expansions, zsh only with this option). Strict increase is NOT full
   parity — glob-in-var remains divergent (no `GLOB_SUBST`; see the
   recorded residual in the Track G section). "Keep as shipped" means keep
   the approach; the string is normalized to ONE canonical form.
3. **Quoted heredoc delimiter is mandatory** for Track W
   (`<<'ZSKILLS_BASH_FENCE'`, never unquoted). Validated 2026-06-12 under
   zsh 5.9 (recorded on #1155): nested heredocs (`PY`/`MARK`/`BODY`) and rc
   propagation are byte-identical; the delimiter string appears nowhere in
   `skills/**/*.md` today (verified: 0 hits).
4. **declare -A is resolved by probe, not by assumption** — and the
   pre-drafting probe already falsified blanket verified-accept (see "The
   declare -A decision"). The expected branch is subscript normalization
   (Branch B). Branch A (accept as-written) and Branch C (flat-var rewrite)
   remain specced; Phase 1's committed probe run selects and records.
5. **Tripwire lands first, scoped; enforcement ratchets — without trapping
   sibling PRs.** Phase 1 lands the full scanner gated by a pending-list
   fixture seeded with every currently-violating file. The protective half
   is strict: violations in UNLISTED files FAIL immediately (new/edited
   files are born compliant). The drainage half is owned by THIS plan, not
   by CI: a listed file with zero violations (or a listed file that no
   longer exists) emits a `ZSH-FENCE-STALE` WARN, never a FAIL — so a
   sibling PR that incidentally cleans or deletes a listed file is never
   forced to edit this plan's fixture. Phases 2–4 drain the list in the
   same commits that fix each file (enforced by each phase's
   `grep -cE … pending.txt # 0` AC, and by Phase 4's empty-list AC);
   Phase 5 deletes the fixture (scanner goes unconditional) and pins
   anti-vacuous floors computed from the Phase-1 census.
6. **SKILL-INVOKE fences are exempt from the WRAP remedy, not from the
   construct rules.** Detection: fence body contains a `Skill:` dispatch
   line (e.g. `# Skill: { skill: "land-pr", args: "$LAND_ARGS" }`,
   `caller-loop-pattern.md` ≈L74). A setopt-unfixable construct inside a
   SKILL-INVOKE fence is still a FAIL — the remedy message says "rewrite
   (Track R); wrap unavailable in SKILL-INVOKE fences" instead of "wrap".
   Rationale: a blanket exemption would let a future `mapfile` land in a
   structurally-unwrappable fence unnoticed; after this plan, no
   SKILL-INVOKE fence carries any (a)-class construct, so both readings are
   green today and the stricter one is the safer ratchet.
7. **Display-only fences get a marker, not a scanner special case.** The one
   known display-only fence (`skills/draft-tests/references/design-constraints.md`
   ≈L58, a 3-line BASH_REMATCH idiom illustration) receives an
   `allow-zsh-unwrapped` marker in Phase 3 (it lives under the draft-tests
   skill dir → version bump applies; the research's "draft-tests drops off"
   note is corrected — it stays in scope).
8. **Out of scope:** sourceable `.sh` helpers (#1168, done); session-level
   shell pinning (REJECTED design — fences must be portable, not the
   session bent to bash); #1156-P1; anything under `hooks/` (hook scripts
   run via explicit `bash` invocation per their registrations);
   `scripts/*.sh`; the `.claude/skills/` mirror (regenerated by
   `scripts/mirror-skill.sh`, never hand-edited).

## Inventory corrections (drafting-time re-verification, worktree @ main 17339d9a)

These findings amend the consolidated research and are load-bearing for the
phase specs. All line refs are ≈L — **verify by content, not blind line
number**.

1. **The "self-contained ~12" Track-W candidate list over-counts.** Spot
   checks demoted at least five entries to Track G:
   - `fix-issues/SKILL.md` ≈L121/≈L134 set `AUTO_FLAG`/`LANDING_MODE`,
     consumed by later fences (`modes/sprint.md` ≈L821/≈L1023 test
     `"$AUTO_FLAG"` inside fences). ≈L221/≈L249/≈L282 set/read routing flags
     (`ADD_MODE`, `BARE_MODE`, `DASHBOARD_MODE`) across fences. All five are
     cross-fence → Track G (they are regex-only).
   - `commit/SKILL.md` ≈L69 reads `$FIRST_TOKEN` (set ≈L36) and re-assigns
     it ≈L130 for downstream branches → Track G.
   - `update-zskills/SKILL.md` ≈L447 populates the whole config-var family
     (`PROJECT_NAME`, `UNIT_CMD`, `FULL_CMD`, …) read downstream → Track G.
   - `zskills-dashboard/SKILL.md` ≈L175 defines the function
     `verify_monitor_identity()` called by later fences (functions die with
     a wrap child) → Track G.
   - `land-pr/SKILL.md` ≈L155 defines `validate_result_value()` used by
     later result-file writes → Track G.
   **Adversarial-review re-verification (2026-06-12) demoted three MORE,
   including the draft's one "verified" wrap — the candidate list is now
   presumed-G until proven otherwise:**
   - `run-plan/SKILL.md` ≈L1119 (the tracking-marker fence, L1119–L1195)
     was WRONGLY called self-contained. Its R-5-1 fence-top comment
     re-derives only `BRANCH_PREFIX` and `PLAN_SLUG` — and the `PLAN_SLUG`
     re-derive itself reads the cross-fence `$PLAN_FILE`
     (`PLAN_SLUG=$(basename "$PLAN_FILE" …)`, ≈L1140; no `PLAN_FILE=`
     assignment exists anywhere in run-plan/SKILL.md — it is model-assigned
     earlier in the session). The fence also reads `$LANDING_MODE`
     (≈L1146/1185), `$PR_WORKTREE_PATH` (≈L1146–1147), `$TRACKING_ID`
     (≈L1157/1162/1171/1188; set ≈L441, an earlier fence), and `$PHASE`
     (≈L1194) with no in-fence derivation. Wrapping would silently write
     tracking markers with EMPTY id/plan/phase fields, fall back
     `BOOKKEEPING_ROOT` to `$CLAUDE_PROJECT_DIR` in PR mode (the PR-mode
     bookkeeping bug class), and SKIP the `requires.land-pr` write
     (re-opening the PR #211 hole) — no error raised. → **Track G.**
   - `do/SKILL.md` ≈L978 reads `$REMAINING` (set by the pre-flight
     pre-parse, cross-fence) and writes `FORCE`/`ROUNDS`, read downstream
     (`do/SKILL.md` ≈L846/849/850 in a later fence, plus routing prose at
     ≈L600/614/722/747/751). Fails protocol steps 2 AND 3. → **Track G.**
   - `fix-issues/subcommands/add-remove.md` ≈L115 reads `$REMOVE_MODE` /
     `$REMOVE_ISSUE_NUM`, set in `fix-issues/SKILL.md` ≈L223/230 (cross-
     FILE, even). → **Track G.**
   Track W membership is decided per-fence at execution time by the
   classification protocol below. After eight of eight inspected
   candidates demoted, the expected final count is **0–6, plausibly
   ZERO** — and zero is acceptable (Settled decision 1). The remaining
   unverified candidates (do/modes/pr ≈L18, draft-tests ≈L175,
   add-rank-remove ≈L415, update-zskills ≈L1433, zskills-dashboard ≈L670,
   research-and-plan ≈L142) are presumed Track G until the protocol's
   step-2/step-3 greps prove otherwise.
2. **`compgen -G` at `skills/run-plan/SKILL.md` ≈L463** — a bash builtin
   absent in zsh, setopt-unfixable, missing from the research construct
   table. Track R (find-based replacement, idiom below).
3. **Construct counts corrected:** `read -r -a` is **13** sites (all
   `fix-issues/modes/sprint.md`: ≈L782, 817, 818, 844, 845, 897, 1019,
   1020, 1039, 1040, 1084, 1909, 2203), not 6. Executable `mapfile` is **6**
   (`work-on-plans/modes/execute.md` ≈L190/214/277;
   `fix-issues/modes/sprint.md` ≈L359/708/1833) plus one prose mention
   (sprint.md ≈L346, not in a fence). `${var,,}` is at `cleanup-merged/SKILL.md`
   ≈L480/≈L793 (drifted from the researched ≈L372/727). Associative-array
   declarations total **20 across 12 files** — 19 `declare -A` PLUS one
   `local -A LP_DASH` (`fix-issues/modes/sprint.md` ≈L672, mixed-quoted
   assignment `LP_DASH["$KEY"]` ≈L679, bare-literal read
   `${LP_DASH[STATUS]:-}` ≈L684, inside the dashboard-empty sync-land
   SKILL-INVOKE fence). An earlier draft "corrected" the research's 20
   down to 19 because its census grep was `declare -A`-only and could not
   see `local -A`; the research was right. **Any census grep for this
   class MUST be `grep -rnE '(declare|local|typeset) -A' skills/
   --include='*.md'`.** The `LP`-family clone count is **11 + canonical**
   (run-plan/modes/pr ≈L425, do/modes/pr ≈L526, commit/modes/pr ≈L167,
   fix-issues/modes/pr ≈L165, fix-issues/modes/sync ≈L348, sprint
   `LP_NOACT` ≈L1438 / `LP_SPRINT` ≈L2865 / `LP_DASH` ≈L672,
   draft-tests/modes/land ≈L204, draft-plan/SKILL.md ≈L965,
   refine-plan/SKILL.md ≈L785 — all named `LP*` on disk; an earlier draft
   called the fix-issues/pr and draft-plan clones "`P`", which was
   fiction).
4. **Word-split reliance is a real, previously-unmodelled class:** ~11
   `for tok in $ARGUMENTS` sites (refine-plan ≈L86/173/189,
   run-plan/subcommands/stop-next-status.md ≈L21, draft-tests/SKILL.md
   ≈L90, update-zskills/SKILL.md ≈L386, research-and-plan/SKILL.md ≈L366,
   verify-changes/SKILL.md ≈L198, draft-plan/SKILL.md ≈L76/230,
   fix-issues/modes/sprint.md ≈L1692 blockquoted) silently degrade under
   zsh (loop runs once with the whole string). Note zsh DOES word-split
   unquoted command substitutions (`for f in $(…)` is safe; 3 sites) — only
   parameter expansion is affected. Fixed by `SH_WORD_SPLIT` in the
   extended guard (Track G), validated byte-identical 2026-06-12.
   `run-plan/subcommands/stop-next-status.md` was absent from the research
   per-skill totals — the Phase-1 scanner report is ground truth for the
   final file census, and the appendix is advisory.
   **Path-dependence caveat (`$ARGUMENTS`):** on the slash/Skill-tool path,
   `$ARGUMENTS` is textually substituted into the skill body at load time —
   the fence the model executes already contains literal tokens, and
   `for tok in $ARGUMENTS` does NOT degrade there under either shell. The
   degradation is real on the **cron-fire path** (managed.md's cron rule
   has the model Read SKILL.md and execute inline with `$ARGUMENTS` set as
   a shell variable) and for any other model-assigned scalar matching the
   same shape. Do not try to reproduce the degradation on the primary
   path — it only manifests when the value arrives as a runtime variable.
   `SH_WORD_SPLIT` is the correct, harmless remedy on every path.
   **Known-residual sibling class (out of detectable scope):**
   argument-position word-split reliance (`cmd $FLAGS`) degrades
   identically under zsh but is NOT inventoried or tripwired — regexing
   "unquoted expansion in argument position" has unbounded false
   positives. Fences that receive a v2 guard are incidentally fixed
   (SH_WORD_SPLIT is fence-global); construct-free fences are not. This is
   an accepted, recorded residual (see end-state item 5), named in the
   WI 1.4 authoring note.
5. **zsh special-parameter collisions** (`LINES`, `COLUMNS`, `path`,
   `status`, `argv`, `fpath`, `cdpath` are tied/read-only in zsh; e.g.
   `LINES=()` errors with "attempt to assign array value to non-array"):
   grep over `skills/**/*.md` found **zero** existing collisions
   (validated 2026-06-12), but the tripwire gains a cheap check (d) so none
   ever lands.
6. **Quoted-LITERAL assoc subscripts misroute too** (reproduced
   2026-06-12: `L3["STATUS"]="success"` then `${L3[STATUS]:-EMPTY}` →
   `EMPTY` under zsh, `success` under bash — zsh stores the key WITH the
   literal quote characters; setopt-irrelevant, same misroute class as the
   mixed quoted-variable case). The tree today has **zero** bash
   quoted-literal subscripts — every hit of the exact check-(c) literal
   regex `[A-Za-z0-9_]\["[A-Za-z0-9_]+"\]` in `skills/**/*.md` (**11
   lines**, e.g. `doc["updated_at"]`, verified 2026-06-12) is Python
   inside a `<<'PY'` heredoc body, not shell. (Looser greps see more —
   bare `\["[A-Za-z]` → 14, word-char-prefixed `[A-Za-z0-9_]\["[A-Za-z]`
   → 12 — but the 3 extras never match check (c): cleanup-merged ≈L77 is
   a JSON config example and add-rank-remove ≈L318 `{})["ready"]` lack a
   preceding word char; update-zskills ≈L1509 prose `scripts["test:all"]`
   has `:` in the key. Do not stall reconciling those counts.) The gap is
   forward-looking: the Branch-B
   normalization rule covers fixed-token keys explicitly, and tripwire
   check (c) is extended to catch the quoted-literal spelling (with a
   heredoc-body skip so the Python lines cannot false-positive — see the
   tripwire section).

## Validated mechanisms — idioms VERBATIM

Everything below was probe-validated byte-identical between bash and
zsh 5.9 on 2026-06-12 (recorded on #1155). The committed probe suite
(Phase 1) re-validates on every CI run where zsh is present.

### Track W — the wrap idiom and rc contract (opportunistic mechanism)

Kept verbatim even though the current expected wrap count is ~0 (Inventory
correction 1): this is the documented fix-of-choice for any future
genuinely self-contained bash-ism fence, and the tripwire's wrap-detection
check needs the exact opener shape below.

```
bash <<'ZSKILLS_BASH_FENCE'
<original fence body, byte-unchanged>
ZSKILLS_BASH_FENCE
```

- The delimiter MUST be quoted (`'ZSKILLS_BASH_FENCE'`) so the zsh parent
  performs zero expansion on the body; the body is parsed only by the child
  bash. Nested heredocs inside the body are tolerated (validated).
- **rc-propagation contract:** the compound's exit status IS the child's
  exit status (validated). An `exit N` inside the body terminates the
  CHILD only — the fence's observable result becomes "nonzero rc + the
  fence's stderr". Every §Track-W fence's `exit` today is a fence-end bail,
  so the operational meaning is preserved: **nonzero child rc is the
  fence's abort signal.** When wrapping, the implementer must read the
  surrounding prose; if it promises session-terminating behavior ("aborts
  the skill"), leave it (the model treats nonzero rc + error text as the
  abort instruction) unless it literally claims shell-state effects, in
  which case adjust the prose consciously in the same edit.
- The child inherits only EXPORTED environment (`CLAUDE_PROJECT_DIR`,
  `CLAUDE_PLUGIN_ROOT` are env vars → available). Unexported shell vars
  from earlier fences are NOT visible — which is exactly why only
  verified-self-contained fences may be wrapped. (`$ARGUMENTS` is textually
  substituted into the skill body at load time, so post-substitution text
  inside the quoted heredoc is inert literal — no issue, but the
  classification protocol records it.)
- **Delimiter-collision residual (accepted):** `ZSKILLS_BASH_FENCE` appears
  nowhere in `skills/**/*.md`, but runtime-spliced content (load-time
  `$ARGUMENTS`, user prose, issue titles embedded in a wrapped body) could
  in principle contain a line that is exactly the delimiter, terminating
  the heredoc early and executing the remainder in the parent zsh. This is
  adversarial-input-low probability and accepted as residual risk —
  recorded here so a future wrap of a fence that splices arbitrary runtime
  strings makes the call consciously.

### Track G — the extended canonical guard (v2)

```bash
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
```

- Placed as the first executable line of the fence (after comments).
  Fence-local by necessity: each fence is a separate shell invocation;
  setopt does not persist across fences.
- v2 adds `SH_WORD_SPLIT` to the shipped #1169 form (correction-4 class).
  Strictly increases bash-parity; no behavior change under bash
  (`ZSH_VERSION` unset → no-op line).
- The four shipped #1169 guards (`run-plan/SKILL.md` ≈L101/≈L212,
  `do/SKILL.md` ≈L292, `land-pr/SKILL.md` ≈L69) are upgraded in place to v2
  in Phase 3. During Phases 1–4 the tripwire accepts any
  `setopt … KSH_ARRAYS … BASH_REMATCH` line as a guard; fences flagged for
  word-split reliance (check b2) additionally require `SH_WORD_SPLIT`.
- **v2 is NOT full bash parity — glob-in-var is a known, recorded
  residual.** Reproduced 2026-06-12: with all three v2 options set,
  `v="*.md"; echo $v` prints the literal `*.md` under zsh while bash
  glob-expands — zsh needs `GLOB_SUBST`, which v2 deliberately does NOT
  set (its blast radius is unprobed and the tree has zero current users:
  the one glob-existence site, `compgen -G`, is R5-rewritten to a quoted
  `find -name`, which is shell-neutral). A guarded fence must not rely on
  expanding a glob stored in a variable. Pinned by probe section s12 and
  named in the WI 1.4 authoring note.

### Track R — replacement idioms per site class

**R1. `mapfile -t ARR < <(cmd)` / `mapfile -t ARR <<< "$STR"` →**

```bash
ARR=()
while IFS= read -r _line || [ -n "$_line" ]; do ARR+=("$_line"); done < <(cmd)
```

(same shape with `<<< "$STR"` — herestrings work in both shells). The
`|| [ -n "$_line" ]` clause preserves mapfile's capture of an unterminated
final line. Sites: `work-on-plans/modes/execute.md` ≈L190/214/277
(`READY_LINES`), `fix-issues/modes/sprint.md` ≈L359/708 (`OPEN_NUMS`),
≈L1833 (`CANDIDATE_ISSUES`). Do NOT name the array `LINES` (zsh special
parameter — correction 5).

**R2. `read -r -a ARR <<<"$STR"` (whitespace-token split) →**

```bash
ARR=()
while IFS= read -r _tok || [ -n "$_tok" ]; do
  [ -n "$_tok" ] && ARR+=("$_tok")
done < <(printf '%s' "$STR" | head -n 1 | tr ' \t' '\n\n')
```

Deterministic split via `tr` — no reliance on shell word-splitting, no new
setopt. The `head -n 1` is LOAD-BEARING for bash-identity: `read -r -a`
stops at the first newline, so on multi-line input the old construct
tokenizes ONLY line 1 (probe-reproduced 2026-06-12: on `$'1 2\n3 4'`,
`read -r -a` yields 2 elements; a tr-only pipeline yields 4). With
`head -n 1` the replacement is old-vs-new identical under bash across
multi-line, single-line, leading/trailing-whitespace, and empty inputs,
and bash-vs-zsh identical (both probe-validated 2026-06-12; probe section
s6 asserts BOTH comparisons). Empty tokens from whitespace runs are
filtered (`[ -n "$_tok" ]`), matching `read -a` semantics. The
`|| [ -n "$_tok" ]` guard captures the final unterminated token (validated
— without it BOTH shells drop the last token). Sites: the 13 sprint.md
sites (correction 3) — their inputs (`RESEARCHED`, `MISSING`,
`SKIP_TAGGED`, `DASHBOARD_PICKS`, …) are expected single-line, but the
implementer does NOT need to prove that per site: `head -n 1` preserves
today's bash behavior either way.

**R3. `${var,,}` →**

```bash
PR_PHRASE="PR $(printf '%s' "$PR_STATE" | tr '[:upper:]' '[:lower:]')"
```

Sites: `cleanup-merged/SKILL.md` ≈L480 (`PR_PHRASE`), ≈L793 (`RPR_PHRASE`).

**R4. `${!var}` env-var indirection →** the one site
(`work-on-plans/modes/execute.md` ≈L495–497, the SEAM_HARDENING test seam)
reads a harness-INJECTED (hence exported) env var
`_ZSKILLS_TEST_RUNPLAN_RESULT_<SLUG_UC>`; the eval-free replacement is
`printenv`:

```bash
_perslug_val=$(printenv "$_perslug_var" 2>/dev/null || true)
if [ -n "$_perslug_val" ]; then
  RUNPLAN_RESULT="$_perslug_val"
else
  …existing awk fallback unchanged…
fi
```

(validated byte-identical). The seam's contract is unchanged: production
(`_ZSKILLS_TEST_HARNESS` ≠ 1) never enters the block; the harness injects
via environment so `printenv` sees exactly what `${!var}` saw. `unset`
list at the block end gains `_perslug_val`.

**R5. `compgen -G "pattern"` glob-existence test →**

```bash
if [ -n "$(find "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID" -maxdepth 1 -name 'cron-recovery-needed.*' -print -quit 2>/dev/null)" ]; then
```

Fully shell-neutral (the pattern is a quoted `find -name` argument — no
shell glob expansion, so zsh's NOMATCH abort never engages). Site:
`skills/run-plan/SKILL.md` ≈L463.

Track-R fences KEEP/GAIN the Track-G guard for their remaining fixable
constructs (regex, 0-based indexing) — the rewrite removes only the
unfixable construct, not the fence's other bash-isms.

### The marker — `allow-zsh-unwrapped` (clones the allow-hardcoded format)

```
<!-- allow-zsh-unwrapped: <construct> reason: <why this fence is exempt> -->
```

- Line immediately above the fence opener; lowercase case-sensitive prefix;
  ` reason: ` delimiter (so multi-token construct names work); markers
  STACK (consecutive marker lines above one fence); any non-blank
  non-marker line resets the block — all per the allow-hardcoded spec in
  `references/canonical-config-prelude.md` (root file; the marker spec is
  added there in Phase 1, alongside the existing format — no skill bump for
  that file).
- `<construct>` names the flagged construct token verbatim as the scanner
  reports it (e.g. `BASH_REMATCH`, `mapfile`, `for-in-scalar`,
  `quoted-subscript`).

## The declare -A decision

**Why a decision is needed:** 20 associative-array declarations across 12
files (19 `declare -A` + 1 `local -A`; census grep MUST be
`(declare|local|typeset) -A` — correction 3), including the canonical
caller-loop `LP` (`land-pr/references/caller-loop-pattern.md` ≈L84) and
its 11 clones: `run-plan/modes/pr.md` ≈L425, `do/modes/pr.md` ≈L526,
`commit/modes/pr.md` ≈L167, `fix-issues/modes/pr.md` ≈L165 (named `LP` on
disk), `fix-issues/modes/sync.md` ≈L348, `fix-issues/modes/sprint.md`
≈L1438 (`LP_NOACT`) / ≈L2865 (`LP_SPRINT`) / ≈L672 (`local -A LP_DASH`,
the dashboard-empty sync-land fence), `draft-tests/modes/land.md` ≈L204,
`draft-plan/SKILL.md` ≈L965 (named `LP` on disk), `refine-plan/SKILL.md`
≈L785 — all inside SKILL-INVOKE fences (unwrappable). zsh supports `declare -A`
natively (alias of `typeset -A`) and `KSH_ARRAYS` does not affect
associative subscripts, so setopt is irrelevant here — the question is
whether the exact subscript patterns behave identically.

**Pre-drafting probe result (validated 2026-06-12, recorded on #1155):**
the as-written pattern is **NOT byte-identical**. zsh uses the subscript
text VERBATIM — `LP["$KEY"]="$VALUE"` stores under a key containing the
literal quote characters, while the read sites use bare literals
(`${LP[STATUS]:-}`) and look up the unquoted key → **every read returns
empty, the `case "${LP[STATUS]}"` falls through to `*)`, and the caller
loop silently misroutes** (the worst failure class: no error, wrong
branch). bash strips subscript quotes, so the two styles are
interchangeable there — which is exactly how the mixed style survived.
CONSISTENT styles are byte-identical in both shells; consistent-UNQUOTED is
the one that works for both assignment and lookup with variable and literal
keys.

**Branch B — subscript-quoting normalization (SELECTED-EXPECTED).**
Mechanical, one line per site: unquote every associative-array subscript
whose key is a simple variable, parameter expansion, or fixed token. The
rule covers all THREE quoted spellings — quoted-variable (`LP["$KEY"]`),
quoted-parameter-expansion (`S["${tok%%:*}"]`), and quoted-LITERAL
(`LP["STATUS"]`, correction 6) — because consistent-UNQUOTED is the one
style that is byte-identical in both shells for assignment AND lookup
across variable, expansion, and literal keys (probe s4 exercises all
three).

```bash
# before (mixed — broken under zsh):
LP["$KEY"]="$VALUE"     …      STATUS="${LP[STATUS]:-}"
# after (consistent unquoted — byte-identical bash/zsh, validated):
LP[$KEY]="$VALUE"       …      STATUS="${LP[STATUS]:-}"
# parameter-expansion keys likewise:
SKIP_TAGGED_SET[${tok%%:*}]="${tok#*:}"
```

Safe under bash because subscripts are not word-split or glob-expanded in
assoc-array context, and every key here is a case-allowlisted token
(`STATUS|PR_URL|…`), an issue number, or a sanitized slug — never
whitespace-bearing. Sites (25 quoted-subscript lines repo-wide, verified
by the check-(c) grep 2026-06-12): the one assignment line in each of the
11 LP-family clones + canonical (incl. `LP_DASH["$KEY"]`
`fix-issues/modes/sprint.md` ≈L679); `fix-issues/modes/sprint.md`
membership sets (`RESEARCHED_SET["$__r"]` ≈L847/886/1042/1076/1911/2205,
`RESEARCHED_SET["$N"]` ≈L850/1045/1917/2211,
`SKIP_TAGGED_SET["${tok%%:*}"]` ≈L901/1088);
`work-on-plans/modes/execute.md` `SLUG_TO_FILE["$slug"]` ≈L330 (lookups
≈L341/459/582 are already unquoted). Quoted-LITERAL subscripts: zero
current sites (correction 6) — the rule and check (c) cover the spelling
forward. `do/SKILL.md`'s `_DO_SEEN` is ALREADY
consistently unquoted (`_DO_SEEN[$_n]`) — probe-passed, no edit; this
resolves the research's "do/SKILL.md ≈L214 INSUFFICIENT" flag without a
rewrite. Branch B also adds a short comment to the canonical pattern
(`caller-loop-pattern.md`, directly above the `declare -A LP` line):
"zsh portability (#1155): assoc subscripts must be UNQUOTED — zsh uses the
subscript text verbatim, so `LP["$KEY"]` and `${LP[STATUS]}` address
different keys. Keep assignment and lookup styles consistent-unquoted."

**Branch A — verified-accept as-written (NOT expected):** only if the
Phase-1 committed probe run somehow shows the exact mixed-quoting pattern
byte-identical (it did not on 2026-06-12). Then: no clone edits; add the
verified-accept comment line to `caller-loop-pattern.md` + record the probe
output in Findings.

**Branch C — flat-var rewrite (fallback, only if the probe also falsifies
Branch B):** replace `LP` with flat scalars assigned in the existing
`case "$KEY"` arms (`LP_STATUS="$VALUE"`, …) in the canonical pattern and
all clones; membership sets become delimited-string membership checks
(`case " $SEEN " in *" $_n "*) …`). Specced for completeness; the Branch-B
probe section already passes, so reaching C means the probe suite itself
found a new divergence — STOP and surface before proceeding.

**Verification work item (Phase 1):** the committed probe
`tests/test-zsh-fence-semantics.sh` runs the EXACT patterns (mixed-quoted
LP, normalized LP, membership set, parameter-expansion key, plus every
Track-R idiom, the v2 guard + word-split loop, wrap rc-propagation, and the
`LINES` special-param canary) under `bash` and `zsh`, diffing per-section
output. Decision rule: mixed-quoted section identical → Branch A;
normalized section identical (expected) → Branch B; both diverge → Branch C
+ STOP-and-surface. The selected branch is recorded in `## Findings —
Phase 1` below.

## Per-fence classification protocol (Track assignment)

Run for every fence the executing phase touches; the appendix is advisory,
this protocol is binding. For fence F in file X:

1. **SKILL-INVOKE?** Body contains a `Skill:` dispatch line → never wrap.
   Constructs: fixable → Track G; unfixable → Track R.
2. **Cross-fence writes:** list every variable/function F defines; grep X
   (and, for `SKILL.md`, the skill's `modes/`, `subcommands/`,
   `references/` files) for reads of each in OTHER fences or in routing
   prose. Any hit → not self-contained.
3. **Cross-fence reads:** list every variable F reads that is not (a)
   exported env (`CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, harness
   `_ZSKILLS_TEST_*`), (b) re-derived at fence-top (R-5-1 convention), or
   (c) load-time-substituted (`$ARGUMENTS`). Any hit → not self-contained.
4. Self-contained (2 and 3 empty) → **Track W**: wrap byte-unchanged,
   re-read surrounding prose per the rc contract.
5. Not self-contained, constructs all fixable → **Track G**: insert v2
   guard as first executable line.
6. Not self-contained, any unfixable construct → **Track R** rewrite (idiom
   table above) + v2 guard for the remaining fixable constructs.
7. Display-only / prohibition-by-name → marker, never a scanner special
   case.

When in doubt between W and G for a regex-only fence, choose G — it is
semantically inert under bash and cannot sever variable flow. Record each
W decision in the phase report with the protocol's step-2/step-3 evidence
(the greps run). **Expected outcome: most or ALL candidates land in G**
(every one of the eight inspected so far has — correction 1). Zero wraps
is an acceptable, even likely, result of running this protocol honestly;
no AC anywhere in this plan requires a minimum wrap count.

## The conformance tripwire (lands Phase 1, full enforcement Phase 5)

New section in `tests/test-skill-conformance.sh` (4009 lines), titled
`=== zsh fence-portability tripwire (#1155) ===`, cloning the
"Positive-side fence-local drift check (WI 5.2)" state machine ≈L2730–2952:
per-file line loop; blockquote normalization (strip leading `> `);
fence-opener regex `^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$` with
`fence_type=exec` for empty/`bash`/`sh`/`shell` info-strings; per-fence
accumulators reset on open; marker detection on `prev_line` (and stacked
marker lines per the allow-hardcoded precedent ≈L2107+); evaluate-on-close
emitting `ZSH-FENCE: $file:$open_line — <check>: <construct> — <remedy>`.
Full-line comments inside fences (`^[[:space:]]*#`) are skipped before
construct matching (several fences DOCUMENT constructs in comments — e.g.
do/SKILL.md's #1155 comment block mentions `$BASH_REMATCH`).
**Heredoc-body skip (required for check (c)'s quoted-literal extension):**
inside an exec fence, a non-comment line matching
`<<-?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?` records the
delimiter and suppresses ALL construct checks until a line whose content
(after optional leading whitespace) is exactly that delimiter. Heredoc
bodies are data fed to another interpreter (`<<'PY'` Python blocks — 11
current `doc["key"]`-shaped lines would otherwise false-positive the
extended check (c)), not shell executed by this fence; skipping them is
strictly more correct for every check, and it is also what makes a
`bash <<'ZSKILLS_BASH_FENCE'`-wrapped body legitimately exempt (the child
IS bash). Residual: an unquoted-delimiter heredoc body does undergo
parent expansion — accepted, recorded here.

Per-fence accumulators and close-time checks (bash ERE, exact):

- **(a) setopt-unfixable construct present** — any non-comment body line
  matching:
  - `(^|[^A-Za-z0-9_])(mapfile|readarray|compgen)([^A-Za-z0-9_]|$)`
  - `(^|[^A-Za-z0-9_])read[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*a([[:space:]]|$)`
  - `\$\{![A-Za-z_]`
  - `\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)[^}]*\}`
  → fence must be **wrapped** (first non-comment, non-blank body line is
  exactly `bash <<'ZSKILLS_BASH_FENCE'`) OR carry a marker naming the
  construct. NOT satisfied by a guard. SKILL-INVOKE fences (body line
  matching `Skill:[[:space:]]*\{`) get the rewrite-remedy message instead
  of the wrap-remedy message but still FAIL (Settled decision 6).
- **(b) regex construct present** — body line matching
  `(\[\[[^]]*=~|BASH_REMATCH)` → fence must be wrapped OR guarded (body
  line matching `setopt[[:space:]][^#]*KSH_ARRAYS[^#]*BASH_REMATCH`) OR
  markered. The FAIL message includes the v2 guard line VERBATIM (a
  sibling-PR author hitting this check mid-flight must be able to fix from
  the failure output alone, with no other doc in their tree yet).
- **(b2) word-split reliance** — body line matching
  `for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+(\$[A-Za-z_]|\$\{[A-Za-z_][A-Za-z0-9_:%#-]*\})`
  (the `${…}` alternative's char class excludes `[`, so `"${ARR[@]}"` and
  `$(…)` forms never match) → fence must be wrapped OR guarded with a
  setopt line that ALSO contains `SH_WORD_SPLIT` OR markered.
- **(c) quoted assoc subscript — variable OR literal** — body line
  (heredoc bodies skipped, see above) matching EITHER
  `[A-Za-z0-9_]\["\$` (quoted-variable/expansion key) OR
  `[A-Za-z0-9_]\["[A-Za-z0-9_]+"\]` (quoted-LITERAL key — misroutes
  identically, correction 6) → FAIL with the normalize-remedy ("unquote
  the subscript — zsh addresses quoted and unquoted keys differently; see
  caller-loop-pattern.md"), marker escape available. Current-tree truth:
  the variable form has 25 hits (all normalized by Phases 2–4), the
  literal form has 0 shell hits and 11 Python-heredoc lines that the
  heredoc skip excludes (correction 6) — WI 1.5's self-check asserts the extended check
  fires on a synthetic `LP["STATUS"]=` fixture and does NOT fire on the
  existing Python lines. (Only active when Branch B is selected; Branch A
  would drop this check, Branch C makes it moot — the Phase-1 implementer
  wires the selected branch.)
- **(d) zsh special-parameter assignment** — body line matching
  `^[[:space:]]*(path|status|LINES|COLUMNS|argv|fpath|cdpath)=` → FAIL
  ("collides with a zsh tied/read-only special parameter — rename"),
  marker escape available.

**Scoping/ratchet:** if `tests/fixtures/zsh-fence-pending.txt` exists,
violations in files listed there are counted and printed as
`ZSH-FENCE-PENDING: <n> violations in <file>` but do not fail; violations
in any UNLISTED file FAIL immediately (new/edited files are born
compliant — this protective half is the ratchet's point and stays
strict). A listed file with ZERO violations, or a listed file that no
longer exists (deleted/renamed), emits
`ZSH-FENCE-STALE: <file> — listed but clean/missing; drop the entry (the
list must be EMPTY by Phase 5)` as a **WARN, not a FAIL**. Rationale
(adversarial-review finding, both reviewers): a FAIL here forces SIBLING
PRs that incidentally clean or delete a listed file to edit this plan's
fixture to pass CI — collateral the plan has no right to impose,
especially with the concurrent #1161–#1164 sprint touching land-pr/do.
Drainage discipline is owned by THIS plan's phases instead: each of
Phases 2–4 carries a `grep -cE … zsh-fence-pending.txt # 0` AC for its
files (same-commit drainage, including any entry gone stale via
deletion/rename — the phase that owns the skill, or Phase 4's final
sweep, drops the entry in the same commit), and Phase 4's AC requires the
list fully empty. When the fixture is absent (Phase 5 deletes it),
enforcement is unconditional.

**Fixture format (`tests/fixtures/zsh-fence-pending.txt`):** one
repo-relative path per line (e.g. `skills/fix-issues/modes/sprint.md`),
LF-terminated, no blank lines, no comments, no duplicates, sorted
(`LC_ALL=C sort`). The scanner FAILs on a malformed fixture (duplicate or
non-`skills/`-prefixed line) — the file is mechanically seeded and must
stay mechanically diffable; sibling PRs never need to touch it (see
above), so merge conflicts on it are confined to this plan's own
rebases.

**Anti-vacuous checks (always on, fixture or not):** after the scan, FAIL
unless (i) total exec fences scanned > 0, and (ii) fences containing
check-(b) constructs ≥ a floor COMPUTED from the recorded census — WI 1.3
records the actual check-(b) fence count in `## Findings — Phase 1`
(drafting estimates: research ~52, an independent review census ≈46) and
pins the initial floor at 75% of that recorded actual, rounded down (the
floor is a literal in the suite with a comment citing the Findings
entry; it is never an asserted-in-advance number). Guards do not remove
the constructs, so the count is stable post-plan; Phase 5 re-pins at 75%
of the final scanner-reported actual. (iii) once unscoped (Phase 5):
guard-satisfied fences ≥ 75% of the Phase-1-recorded **guard-expected
census** — defined mechanically, because at Phase-1 time nothing has yet
been dispositioned by the protocol (that happens during Phases 2–4): the
count of distinct scanner-flagged fences in the SAME fixture-absent
seeding run (WI 1.3) whose flagged constructs are all (b)/(b2)/(c)-class,
i.e. no (a)-class hit in the fence. Recorded as a literal in `## Findings
— Phase 1`; Phase 5 reads that recorded number (drafting estimate ~45).
The proxy is satisfiable with margin: (a)-class (Track R) fences also
gain guards for their remaining fixable constructs (adding to the
guard-satisfied numerator beyond the base), while the rare (c)-only
fence whose construct is normalized away without needing a guard (e.g.
the `SLUG_TO_FILE` normalize-only site) drops out — well inside the 25%
slack. Also (iii):
the scanner-reported wrapped-fence count must EQUAL the repo grep
count for the wrap opener — **there is NO minimum wrap floor; zero
wraps is an acceptable outcome** (Settled decision 1), and any wrap that
exists must have passed the classification protocol (phase-report
evidence). A regression that gutted the scanner's fence detection trips
(i)/(ii) instead of passing vacuously.

File enumeration: the same source-tree scope as the WI-5.2 block
(`skills/**/*.md` source files only; the `.claude/skills/` mirror is
byte-identical by the parity suite and is not double-scanned).

## Critical invariants every phase must honor

1. **Skill-versioning quadruple gate.** ANY edit to any regular file under
   `skills/<S>/` (SKILL.md, modes, subcommands, references) requires a
   `metadata.version` bump and mirror refresh in the SAME commit:
   ```bash
   today=$(TZ=America/New_York date +%Y.%m.%d)
   hash=$(bash scripts/skill-content-hash.sh skills/<S>)
   bash scripts/frontmatter-set.sh skills/<S>/SKILL.md metadata.version "$today+$hash"
   bash scripts/mirror-skill.sh <S>
   ```
   Compute the hash AFTER all content edits to that skill, per commit. If a
   `git commit` is DENIED by `block-stale-skill-version.sh`, the deny
   message carries the exact bump command — run it, re-stage, re-commit; do
   NOT treat the deny as a test failure. Never edit `.claude/skills/`
   directly.
2. **Tests are never weakened.** The tripwire's pending-list is a scoped
   ROLLOUT mechanism, not a skip list: unlisted files FAIL hard from day
   one, stale entries WARN loudly, and drainage is enforced by the phase
   ACs (Phase 4 requires the list empty; Phase 5 deletes it); no existing
   assertion is loosened anywhere in this plan.
   `tests/test-zsh-fence-semantics.sh` + the tripwire section register as a
   suite/run-all/registry change only if a NEW standalone suite file is
   added (the semantics probe is one — its `tests/run-all.sh` +
   `tests/test-suite-registry.sh` registrations ride the same Phase-1
   commit). The tripwire itself is an addition INSIDE the existing
   conformance suite — no triplet change.
3. **Behavior identity under bash is the hard bar for every Track-R rewrite
   and Branch-B normalization.** Each rewritten line's bash behavior must
   be argued in the commit (and is probe-covered). zsh improvement never
   excuses a bash regression.
4. **Suite green at every phase boundary**, output captured out-of-tree:
   ```bash
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
   ```
   Then READ the file; report the command and per-suite pass COUNTS.
   **The extract-and-run suites are the behavioral gate for fence edits:**
   `tests/test-commit-parsing.sh` extracts the two real commit/SKILL.md
   fences this plan guards; `test-do-issue-num-parser.sh`,
   `test-land-pr-post-merge-ff.sh`, `test-land-pr-drive-automerge.sh`,
   and `test-commit-pr-caller-loop.sh` extract and EXECUTE fences
   receiving guards/normalization. Guard insertion is bash-inert
   (`ZSH_VERSION` unset) and Branch-B unquoting is bash-equivalent, so
   these stay green — a red one of THESE after a fence edit is the
   highest-signal failure this plan can produce; read it first.
5. **All line refs are ≈L — verify by content.** The tree WILL have
   shifted (a concurrent sprint is editing land-pr scripts/stubs/guides,
   #1161–#1164). Fence edits to `land-pr/` and `do/` may rebase-conflict on
   `metadata.version` lines — resolve single-region by recomputing the
   bump, never via `checkout --ours/--theirs`.
6. **Fence bodies wrap byte-unchanged.** Track W adds exactly two lines
   (opener + delimiter); any in-body change is a separate, separately-argued
   edit. Track G adds exactly one line. Diffs stay mechanically reviewable.
7. **Historical surfaces are off-limits:** `CHANGELOG.md`, `docs/plans/`,
   `docs/reports/`, `docs/issues/` get no body rewrites from this plan.

## Execution context

`main_protected: true` — execute via `/run-plan docs/plans/ZSH_FENCE_WRAP_PLAN.md`
in worktree mode. Implementation dispatches to `subagent_type: "implementer"`;
verification to the verifier subagent. One commit per phase unless the phase
says otherwise (Phases 2–4 may use per-skill commits — each self-contained
with its bumps/mirrors and pending-list removals). No attended/live sessions
are required; the probe runs headlessly (`/usr/bin/zsh` 5.9 is present in
the dev container — verified 2026-06-12; if zsh is ABSENT at execution
time, Phase 1's decision probe is a STOP-and-surface, not a guess). In CI
the suite does NOT silently skip: `.github/workflows/test.yml` has zero
zsh references today (verified 2026-06-12 — whether `ubuntu-latest` ships
zsh is unknown and must not be assumed), so WI 1.6 adds an explicit
install step and the suite hard-FAILs under `${CI:-}` when zsh is
missing; only LOCAL zsh-less runs skip, with a WARN.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Probe + declare-A decision + tripwire infrastructure (pending-scoped) | ✅ Done | 5da09e7 | Verified PASS; suite 8169/8169; semantics probe 15/15 (Branch B); tripwire non-vacuous (28 pending, canaries n1-n5); declare-A literal+var covered; zsh-in-CI; infra-only |
| 2 — Track R rewrites + normalization + guards: fix-issues, work-on-plans, cleanup-merged | ✅ Done | 980d0b9 | Verified PASS; suite 8169/8169 (behavior-identical); all R-constructs=0; Branch-B normalized; pending 28->20; per-skill suites green |
| 3 — Caller-loop family + guard v2 upgrade: land-pr, run-plan, do, commit, draft-tests | ✅ Done | e3d451c | Verified PASS; suite 8169/8169; caller-loop Branch-B normalized (byte-identical, real loop executes green); guard v2 ×4; pending 20->7; PR-landing unchanged |
| 4 — Remaining skills: draft-plan, refine-plan, update-zskills, zskills-dashboard, verify-changes, research-and-go, research-and-plan | ✅ Done | 8e7a8c2 | Verified PASS; suite 8169/8169; scanner 0 violations repo-wide (65 check-b guarded); pending list EMPTY + genuinely clean; per-skill suites green |
| 5 — Unscoped tripwire + floors + docs + #1155 close-out | ⬚ | | |

---

## Phase 1 — Probe + declare-A decision + tripwire infrastructure (pending-scoped)

### Goal

Land everything later phases depend on — the validated-semantics probe
suite, the recorded declare-A branch selection, the marker spec, and the
full tripwire scanner gated by a seeded pending-list — without touching any
skill fence, so concurrent sibling PRs cannot be blocked **on the seeded
violations or on incidental cleanups/deletions** (stale entries WARN —
Settled decision 5). The one way a sibling CAN go red is the intended
one: adding a NEW zsh-divergent fence to an unlisted file — and that FAIL
message is self-sufficient (verbatim guard line, marker format).

### Work Items

- [ ] **1.1 — Probe suite `tests/test-zsh-fence-semantics.sh`.** Sections,
  each run under `bash` and `zsh` with per-section output diffed
  byte-identical: (s1) v2 guard + `[[ =~ ]]`/`${BASH_REMATCH[n]}` captures +
  0-based indexed access; (s2) word-split `for tok in $SCALAR` under the v2
  guard; (s3) mixed-quoted assoc pattern (`LP["$KEY"]=` assign /
  `${LP[STATUS]}` read — the AS-WRITTEN caller-loop shape, expected to
  DIVERGE; the suite asserts the recorded expectation, see decision rule —
  PLUS the quoted-LITERAL spelling `LP["STATUS"]=` / `${LP[STATUS]}` read,
  expected to DIVERGE identically, correction 6); (s4) normalized assoc
  pattern (consistent-unquoted assign+read across all THREE key shapes —
  variable, `${tok%%:*}` expansion, fixed literal — KEY=VALUE loop with
  case allowlist, membership-set dedupe) — expected IDENTICAL; (s5) R1
  mapfile replacement incl. unterminated final line; (s6) R2 split — TWO
  comparisons, both required: (s6a) OLD `read -r -a` vs NEW R2 idiom
  under BASH on multi-line (`$'1 2\n3 4'` — both must yield 2 tokens; the
  `head -n 1` is what makes this pass), single-line, leading/trailing
  whitespace runs, and empty inputs (the old-vs-new regression axis that
  a bash-vs-zsh-only probe is structurally blind to); (s6b) NEW idiom
  bash-vs-zsh byte-identical incl. final-token guard; (s7) R3 tr
  lowercase; (s8) R4 printenv indirection; (s9) R5 find-based
  glob-existence (hit + no-hit); (s10) wrap rc propagation
  (`bash <<'ZSKILLS_BASH_FENCE'` with inner `exit 3` → compound rc 3) +
  nested-heredoc tolerance; (s11) `LINES=()` special-param canary (asserts
  zsh REJECTS it — pinning why check (d) exists; bash side runs the rename
  control); (s12) GLOB_SUBST residual pin (asserts `v="*.md"; echo $v`
  with the v2 opts set prints LITERAL under zsh and expands under bash —
  pinning that the guard is NOT full parity, so a future "add GLOB_SUBST"
  change must consciously update this section). **zsh-absence behavior:**
  when `command -v zsh` fails AND `${CI:-}` is non-empty → FAIL with the
  actionable message "zsh required in CI — the 'Install zsh' step in
  .github/workflows/test.yml (WI 1.6) should have provided it; run
  `sudo apt-get install -y zsh`"; when `${CI:-}` is empty (local dev) →
  print one `WARN: SKIP (zsh not installed — semantics suite not
  exercised)` line, exit 0. Register in `tests/run-all.sh` +
  `tests/test-suite-registry.sh` (triplet, same commit) — the registry
  count includes the suite, so a CI run that didn't execute it is
  visible.
- [ ] **1.2 — declare-A decision.** Run 1.1 with zsh present (STOP and
  surface if zsh is unavailable — the decision MUST be empirical). Decision
  rule: s3 identical → Branch A; s3 diverges AND s4 identical → **Branch B
  (expected)**; s4 diverges → Branch C + STOP-and-surface. Record the
  selected branch, verbatim probe output for s3/s4, and the zsh version in
  `## Findings — Phase 1`. Wire the tripwire's check (c) per the selected
  branch (Branch B: active as specced; Branch A: omitted, and Phases 2–4's
  normalization items convert to the single comment-line item; Branch C:
  check (c) replaced by an assoc-declaration-forbidden check matching
  `(declare|local|typeset) -A` — the full census grep per correction 3, NOT
  `declare -A` alone, which cannot see the `local -A LP_DASH` site — and
  Phases 2–4 carry the flat-var rewrites).
- [ ] **1.3 — Tripwire section** in `tests/test-skill-conformance.sh` as
  specced above (checks a/b/b2/c/d, marker machinery, SKILL-INVOKE remedy
  modulation, blockquote normalization, comment-line skip, heredoc-body
  skip, pending-list scoping, stale-entry WARN, fixture-format validation,
  anti-vacuous (i)/(ii)). Seed `tests/fixtures/zsh-fence-pending.txt`
  mechanically — **the seeding procedure, exactly** (there is no separate
  "report mode" switch): run the suite once with the fixture ABSENT,
  capture the output, and collect the distinct `<file>` values from the
  `ZSH-FENCE: <file>:<line> — …` lines
  (`grep '^ZSH-FENCE:' out | sed 's/^ZSH-FENCE: //; s/:.*//' | LC_ALL=C sort -u`);
  that sorted unique list IS the fixture. Record the seeded file count
  and the check-(b) fence census in Findings, and pin anti-vacuous floor
  (ii) at 75% of the recorded census, rounded down (this recorded census
  is the ground truth superseding the appendix, per Inventory
  correction 4; if it lands far from the ~46–52 drafting estimates,
  STOP and surface before pinning). From the SAME seeding-run output,
  also compute and record the **floor-(iii) base census** (the
  guard-expected set): the count of distinct scanner-flagged fences
  whose flagged constructs are all (b)/(b2)/(c)-class — no (a)-class
  hit in the fence (the anti-vacuous section defines this proxy; Phase 5
  reads the recorded literal from Findings, never re-derives it).
- [ ] **1.4 — Marker spec + authoring note** added to
  `references/canonical-config-prelude.md` as a sibling subsection of the
  allow-hardcoded spec: format line, stacking, reset rule, construct-token
  naming, two worked examples (display-only illustration fence;
  prohibition-by-name). Immediately below it, a short **"Writing portable
  fences" note** (≤10 lines, same file — zero extra doc surface): default
  remedy = the v2 guard line (quoted verbatim); setopt-unfixable
  constructs (`mapfile`, `read -a`, `${!var}`, `${var,,}`, `compgen`) =
  use the Track-R idioms (pointer to this plan/`test-zsh-fence-semantics.sh`
  sections); assoc subscripts = consistent-unquoted; display-only fences =
  the marker; wrap only a PROVEN self-contained fence; named residuals
  (glob-in-var, argument-position word-split) = don't rely on them. This
  is the proactive teacher so the first post-plan fence author does not
  learn the policy from red CI. Root file — no skill bump.
- [ ] **1.5 — Conformance self-checks green:** the seeded pending list must
  make `bash tests/test-skill-conformance.sh` pass on the UNTOUCHED tree
  (every current violation is in a listed file), and synthetic
  fixture-driven negative tests are included in the tripwire's own sanity
  block, mirroring the WI-5.2 precedent: (n1) a temp file with an
  unguarded `BASH_REMATCH` fence NOT in the pending list → scanner FAILs;
  (n2) a temp file with a quoted-LITERAL assoc assignment
  (`LP["STATUS"]="x"`) in a bash fence → extended check (c) FAILs; (n3) a
  temp file with the same `doc["key"]` text inside a `<<'PY'` heredoc →
  scanner PASSes (heredoc skip proven non-vacuously); (n4) a temp file
  with a stale pending entry → output contains `ZSH-FENCE-STALE` AND the
  suite still exits 0 (WARN-not-FAIL semantics pinned); (n5) a temp file
  with a properly wrapped fence — first non-comment, non-blank body line
  exactly `bash <<'ZSKILLS_BASH_FENCE'`, closing delimiter line present —
  whose body contains BOTH a `mapfile` line (check-(a) class) and a
  `BASH_REMATCH` line (check-(b) class) → scanner PASSes (the wrap
  satisfies checks (a) and (b) via the wrap-acceptance rule + heredoc-body
  skip). With the expected wrap count in the tree being ZERO, n5 is the
  ONLY thing exercising the wrap-acceptance path — without it the logic
  could be silently wrong from day one and the first future author to
  legitimately wrap a self-contained fence would hit a false FAIL carrying
  the wrong (guard) remedy advice.

- [ ] **1.6 — zsh in CI.** `.github/workflows/test.yml`, job `test` (the
  job that runs "Run full test suite"): add a step named **"Install zsh
  (zsh-fence semantics suite)"** immediately before "Run full test suite",
  body `sudo apt-get update && sudo apt-get install -y zsh` (verified
  2026-06-12: the workflow currently has ZERO zsh references and both jobs
  are bare `ubuntu-latest`; whether the runner image ships zsh must not be
  assumed). The `plugin-mode` job does not run the test suites — no change
  there. Combined with 1.1's CI hard-FAIL on absent zsh and the registry
  count, this makes a vacuously-green semantics suite impossible in CI:
  the job log must show the suite RAN (registry includes it) and zsh-less
  CI turns red instead of silently skipping. **Known side effect:** the
  pre-existing `tests/test-zsh-fence-resolution.sh` (issue #1149, helper
  self-location under zsh — registered at `tests/run-all.sh` ≈L241;
  distinct scope from the new semantics suite, no name/role collision)
  skips its zsh arms (cases 2–6: sourceable-helper resolution, validator
  path, init-done fallback, #1154 regex extraction) with a notice when
  zsh is absent — meaning those arms have plausibly never executed in CI.
  This install step flips them ON for every CI push from Phase 1 onward.
  Expected green (they pass in the dev container's zsh 5.9); if one goes
  red in the Phase-1 PR, that is a pre-existing #1149/#1154 bug SURFACED
  by zsh becoming available, not a defect in this plan's tripwire/probe
  code — investigate it as such, do not misattribute.

### Design & Constraints

- No `skills/` edits in this phase → no version bumps, no mirror runs.
  (1.6 edits `.github/workflows/` — also not a skill surface.)
- The probe suite is the plan's single source of shell-semantics truth; if
  any section diverges from the recorded 2026-06-12 expectations, STOP and
  surface (the replacement idioms in Phases 2–4 are only as good as s5–s10).
- Python is available for the scanner if line-state bash gets unwieldy, but
  the WI-5.2 precedent is pure bash — prefer cloning it (no jq, ever).

### Acceptance Criteria

```bash
bash tests/test-zsh-fence-semantics.sh                  # PASS (12 sections, byte-identical or recorded-divergence asserted)
bash tests/test-skill-conformance.sh                    # PASS incl. new tripwire section
grep -c . tests/fixtures/zsh-fence-pending.txt          # = seeded count recorded in Findings — binding check is equality with Findings; expected ≈28 FILES (the appendix inventory spans 28 distinct files across 15 skills; a seed near 28 means the scanner agrees with the appendix, NOT that it over-detects)
grep -n 'allow-zsh-unwrapped' references/canonical-config-prelude.md  # spec + authoring note present
grep -n 'Install zsh' .github/workflows/test.yml        # WI 1.6 step present
git diff --stat HEAD~1 -- skills/ | wc -l               # 0 — no skill edits
bash tests/run-all.sh   # green, captured to /tmp/zskills-tests/
```

### Dependencies

None. (Phases 2–4 each depend on 1.2's recorded branch and 1.3's ratchet.)

---

## Phase 2 — Track R rewrites + normalization + guards: fix-issues, work-on-plans, cleanup-merged

### Goal

Make the three worst files fully compliant — they hold EVERY `mapfile`,
`read -r -a`, `${var,,}` and `${!var}` site — and drain them from the
pending list.

### Work Items

- [ ] **2.1 — `fix-issues/modes/sprint.md`:** R2-rewrite the 13 `read -r -a`
  sites (≈L782, 817, 818, 844, 845, 897, 1019, 1020, 1039, 1040, 1084,
  1909, 2203 — verify by content; several sit inside SKILL-INVOKE fences,
  where rewrite is the only remedy); R1-rewrite the 3 `mapfile` sites
  (≈L359/708/1833; the ≈L346 prose mention is not a fence — untouched);
  Branch-B-normalize `RESEARCHED_SET`/`SKIP_TAGGED_SET` quoted subscripts
  (≈L847/850/886/901/1042/1045/1076/1088/1911/1917/2205/2211) and the
  `LP_NOACT` (≈L1444) / `LP_SPRINT` (≈L2871) / **`LP_DASH` (≈L679;
  declared `local -A` ≈L672 in the dashboard-empty sync-land SKILL-INVOKE
  fence — correction 3, the site a `declare -A`-only grep misses)**
  assignment lines; insert v2 guards per protocol step 5/6 in every
  construct-bearing fence (incl. the blockquoted ≈L1692 `for f in $STAGED`
  recipe fence).
- [ ] **2.2 — `fix-issues/` remainder:** SKILL.md ≈L121/134/221/249/282
  (demoted to Track G — correction 1) + ≈L198; modes/pr.md `LP[…]`
  normalization (≈L171 — the clone is named `LP` on disk, correction 3) +
  guards (≈L49/165 fences); modes/sync.md `LP` normalization (≈L354) +
  guards; subcommands/add-remove.md ≈L22 (G) and ≈L115 (**demoted to
  Track G — correction 1**: reads `$REMOVE_MODE`/`$REMOVE_ISSUE_NUM` set
  in SKILL.md ≈L223/230).
- [ ] **2.3 — `work-on-plans/modes/execute.md`:** R1 × 3 (≈L190/214/277,
  array stays `READY_LINES` — safe name); R4 printenv seam rewrite
  (≈L490–505, inside the `_ZSKILLS_TEST_HARNESS` gate; production path
  byte-unchanged); `SLUG_TO_FILE["$slug"]` → `[$slug]` (≈L330); v2 guards
  for the fences' regex/indexing. `subcommands/add-rank-remove.md`:
  ≈L184/248 guards; ≈L415 W-candidate via protocol.
- [ ] **2.4 — `cleanup-merged/SKILL.md`:** R3 × 2 (≈L480/793) + v2 guards
  for the two cross-fence counter/regex fences (≈L372-region/727-region per
  the research census — verify by content).
- [ ] **2.5 — Per-skill closeout (×3, each in its commit):** Inv-1 bump +
  mirror; remove the skill's files from
  `tests/fixtures/zsh-fence-pending.txt` in the same commit (this phase's
  AC enforces drainage; the scanner WARNs on stale entries); full suite
  green.
- [ ] **2.6 — Test-replica sync (tests/ files, no skill bump):**
  `tests/test-fix-issues-phase2-source-filter.sh` ≈L249/250/273 replicate
  `read -r -a …_ARR <<<…` and `tests/test-fix-issues-bootstrap.sh`
  ≈L579/643 replicate `LP["$KEY"]="$VALUE"`. They run under bash so
  nothing breaks, but post-rewrite they would no longer match the shipped
  idiom — update them to the R2 idiom / normalized subscripts in this
  phase so replica and source never diverge. (This also keeps Phase 4's
  "no mixed assoc subscripts anywhere" story honest beyond `skills/`.)

### Design & Constraints

- Rewrites replace ONLY the construct line(s); surrounding logic
  byte-unchanged (Invariant 6 spirit). Each rewritten site cites its idiom
  (R1/R2/R3/R4) in the commit message.
- sprint.md's four SKILL-INVOKE fences (≈L598/1370/2176/2786) must remain
  SKILL-INVOKE-detected by the scanner after editing (don't disturb the
  `Skill:` dispatch lines).
- The seam rewrite (2.3/R4) keeps the entry-point unset-guard loop
  (execute.md ≈L36–40, `< <(env)` — process substitution works in zsh)
  untouched.

### Acceptance Criteria

```bash
grep -rnE 'read[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*a([[:space:]]|$)' skills/fix-issues/ --include='*.md' | grep -v '^\S*:[0-9]*:\s*#' | wc -l   # 0
grep -rnE 'mapfile[[:space:]]+-t' skills/work-on-plans/ skills/fix-issues/ --include='*.md' | wc -l    # 0 — anchored on `mapfile -t` (all 6 exec sites have it); the ≈L346 prose mention (`use \`grep -oE | mapfile\`:`) has no -t, is NOT excluded by a backtick/comment filter, and stays untouched — an earlier AC draft used such a filter and could never reach 0. The tripwire (fence-aware) is the authoritative check.
grep -rnE '\$\{[A-Za-z_]+,,' skills/cleanup-merged/ | wc -l                       # 0
grep -rnE '\$\{!' skills/work-on-plans/ --include='*.md' | wc -l                  # 0
grep -rnE '[A-Za-z0-9_]\["\$' skills/fix-issues/ skills/work-on-plans/ --include='*.md' | wc -l   # 0 (Branch B)
grep -cE '(fix-issues|work-on-plans|cleanup-merged)/' tests/fixtures/zsh-fence-pending.txt        # 0
grep -rnE 'read -r -a|LP\["\$KEY"\]' tests/test-fix-issues-phase2-source-filter.sh tests/test-fix-issues-bootstrap.sh | wc -l   # 0 — replicas synced (WI 2.6)
bash tests/test-skill-conformance.sh && bash tests/test-zsh-fence-semantics.sh && bash tests/run-all.sh   # green, captured per Invariant 4
```

### Dependencies

Phase 1 (recorded branch; ratchet active).

---

## Phase 3 — Caller-loop family + guard v2 upgrade: land-pr, run-plan, do, commit, draft-tests

### Goal

Normalize the canonical caller-loop pattern and its non-fix-issues clones,
upgrade the four shipped #1169 guards to v2, fix the missed `compgen` site,
wrap/guard these skills' remaining fences, and drain them from the pending
list.

### Work Items

- [ ] **3.1 — Canonical pattern `land-pr/references/caller-loop-pattern.md`:**
  Branch-B normalize the `LP["$KEY"]` assignment (≈L90) + add the
  zsh-portability comment line above `declare -A LP` (decision section,
  verbatim there); v2 guard in the canonical loop fence (it carries case
  patterns/regex). This is the template the 12 clones mirror — land it
  first within the phase.
- [ ] **3.2 — Clones in this phase's skills:** `run-plan/modes/pr.md`
  (≈L431), `do/modes/pr.md` (≈L532), `commit/modes/pr.md` (≈L173),
  `draft-tests/modes/land.md` (≈L208) — one assignment line each + v2
  guards per protocol.
- [ ] **3.3 — Guard v2 upgrades (#1169 sites):** `run-plan/SKILL.md`
  ≈L101/≈L212, `do/SKILL.md` ≈L292, `land-pr/SKILL.md` ≈L69 → the v2
  string. `do/SKILL.md`'s `_DO_SEEN` is verified already-consistent — no
  subscript edit (records the research's "INSUFFICIENT" flag as RESOLVED by
  Branch B).
- [ ] **3.4 — `run-plan/SKILL.md` ≈L463:** R5 compgen→find rewrite (+ v2
  guard for that fence's other constructs). ≈L1119: **Track G** (demoted —
  correction 1: the tracking-marker fence reads `$PLAN_FILE`,
  `$LANDING_MODE`, `$PR_WORKTREE_PATH`, `$TRACKING_ID`, `$PHASE`
  cross-fence; wrapping would silently corrupt tracking markers and
  re-open the PR #211 hole — do NOT wrap it). `subcommands/
  stop-next-status.md` ≈L21 `for tok in $ARGUMENTS` fence: v2 guard.
  Remaining run-plan config-chain fences (≈L135/172/189): v2 guards.
- [ ] **3.5 — Remaining fences in land-pr (≈L155/249/469/720 → G), do
  (≈L798/902 → G; ≈L978 → **G**, demoted — correction 1: writes
  `FORCE`/`ROUNDS` read downstream, reads `$REMAINING`; modes/pr.md ≈L18 →
  W-candidate via protocol, presumed G; modes/worktree.md ≈L18 → G;
  modes/pr.md ≈L77 → G), commit (≈L35/69 → G), draft-tests (SKILL.md
  ≈L90 → G; ≈L175 → W-candidate via protocol, presumed G).
- [ ] **3.6 — Display-only marker:** `draft-tests/references/design-constraints.md`
  ≈L58 gets `<!-- allow-zsh-unwrapped: BASH_REMATCH reason: display-only idiom illustration, never executed -->`
  (Settled decision 7; draft-tests stays in the bump set).
- [ ] **3.7 — Per-skill closeout (×5):** Inv-1 bump + mirror + pending-list
  removal + suites green. Expect rebase friction with the concurrent
  land-pr sprint (#1161–#1164) — Invariant 5 discipline.

### Design & Constraints

- The 11 LP-family clones (correction 3) stay BYTE-PARALLEL to the
  canonical pattern in the loop body (existing review convention); the
  normalization is the same one-line diff in each (Phase 2 handles the
  fix-issues five — pr, sync, LP_NOACT, LP_SPRINT, LP_DASH; this phase
  the four here + canonical; Phase 4 the last two).
- Track-W candidates here (do/modes/pr:18, draft-tests:175 — do:978 is
  already demoted) require the protocol's grep evidence in the phase
  report; default to G on any doubt (protocol final rule). Zero wraps in
  this phase is an expected, acceptable outcome (Settled decision 1).

### Acceptance Criteria

```bash
grep -rn 'compgen' skills/ --include='*.md' | grep -v '^\S*:[0-9]*:\s*#' | wc -l                   # 0
grep -rn 'setopt KSH_ARRAYS BASH_REMATCH 2>' skills/ --include='*.md' | wc -l                      # 0 — all guards are v2
grep -rnE '[A-Za-z0-9_]\["\$' skills/land-pr/ skills/run-plan/ skills/do/ skills/commit/ skills/draft-tests/ --include='*.md' | wc -l   # 0
grep -cE '(land-pr|run-plan|do|commit|draft-tests)/' tests/fixtures/zsh-fence-pending.txt          # 0
bash tests/test-skill-conformance.sh && bash tests/run-all.sh                                      # green, captured
```

### Dependencies

Phases 1–2 (branch recorded; ratchet active; fix-issues clones already done
in Phase 2 keeps this phase's clone set to 4+canonical).

---

## Phase 4 — Remaining skills: draft-plan, refine-plan, update-zskills, zskills-dashboard, verify-changes, research-and-go, research-and-plan

### Goal

Bring the long tail compliant (mostly Track G — these are regex/word-split
fences plus two LP clones and up to three W-candidates) and empty the
pending list down to zero entries.

### Work Items

- [ ] **4.1 — LP clones:** `draft-plan/SKILL.md` ≈L969 and
  `refine-plan/SKILL.md` ≈L789 — Branch-B one-liners + v2 guards in their
  SKILL-INVOKE fences.
- [ ] **4.2 — Track G rollout:** draft-plan ≈L76/230 (`for tok in
  $ARGUMENTS`) + ≈L167; refine-plan ≈L86/173/189 + ≈L160; update-zskills
  ≈L386 + ≈L447 (demoted, correction 1) + ≈L868; zskills-dashboard ≈L175
  (demoted — function def) + ≈L342/514; verify-changes ≈L198 + ≈L110;
  research-and-go ≈L91/284; research-and-plan ≈L366.
- [ ] **4.3 — W-candidates via protocol:** update-zskills ≈L1433,
  zskills-dashboard ≈L670, research-and-plan ≈L142 — all presumed G
  (every inspected candidate so far has demoted, correction 1); wrap only
  on clean step-2/3 grep evidence recorded in the phase report.
- [ ] **4.4 — Per-skill closeout (×7):** Inv-1 bump + mirror + pending-list
  removal + suites green. Per-skill commits are fine (7 small commits).

### Design & Constraints

- Any fence the Phase-1 scanner found in files the appendix missed
  (correction 4 — e.g. additional subcommand files) belongs to whichever of
  Phases 2–4 owns that skill; Phase 4 sweeps anything left on the pending
  list regardless of skill, so the list — not the appendix — defines
  done.

### Acceptance Criteria

```bash
grep -c . tests/fixtures/zsh-fence-pending.txt    # 0 (file empty; deletion is Phase 5)
grep -rnE '[A-Za-z0-9_]\["\$' skills/ --include='*.md' | wc -l   # 0 — no quoted-VARIABLE assoc subscripts anywhere (Branch B). The quoted-LITERAL spelling is enforced by the tripwire only (its heredoc skip excludes the 11 Python `doc["key"]` lines the check-(c) literal regex would count, correction 6 — do not "fix" those)
bash tests/test-skill-conformance.sh              # green with empty pending list = full-tree compliance already proven by the tripwire (incl. every for-in-$ARGUMENTS fence guarded via check b2)
bash tests/run-all.sh                             # green, captured
```

### Dependencies

Phases 1–3.

---

## Phase 5 — Unscoped tripwire + floors + docs + #1155 close-out

### Goal

Make enforcement unconditional and permanent, pin the anti-vacuous floors
to measured reality, finish the documentation surface, and leave #1155
closable.

### Work Items

- [ ] **5.1 — Delete `tests/fixtures/zsh-fence-pending.txt`** and the
  scanner's pending-branch becomes dead code — REMOVE the branch (don't
  leave an untaken path); the only fixture-related logic kept is: fixture
  present → FAIL ("pending mechanism was retired in #1155 close-out —
  full compliance is mandatory"). Activate anti-vacuous (iii):
  guard-satisfied fences ≥ 75% of the Phase-1-recorded guard-expected
  census — the WI-1.3 floor-(iii) base literal in `## Findings —
  Phase 1` (computed, not asserted — drafting estimate ~45), and assert the
  scanner-reported wrapped-fence count EQUALS the repo grep count for
  `bash <<'ZSKILLS_BASH_FENCE'` — **no minimum: every Track-W wrap that
  landed passed the classification protocol (phase-report evidence), and
  zero wraps is an acceptable outcome.** Re-pin floor (ii) at 75% of the
  final scanner-reported check-(b) census.
- [ ] **5.2 — Docs:** verified 2026-06-12 that `CLAUDE_TEMPLATE.md`,
  `.claude/rules/zskills/managed.md`, and `references/canonical-config-prelude.md`
  contain zero mentions of the guard/wrap idiom today — re-verify by grep
  (`grep -n 'KSH_ARRAYS\|ZSKILLS_BASH_FENCE\|allow-zsh-unwrapped' CLAUDE_TEMPLATE.md`);
  if still zero, the Phase-1 marker spec + "Writing portable fences"
  authoring note in canonical-config-prelude.md (WI 1.4) are
  the complete doc surface and NO CLAUDE_TEMPLATE/managed.md edit happens
  (record as verified-absent). If a mention has appeared since (concurrent
  sprints), update it to the v2 string in the same style and re-render via
  the managed-rules flow only if CLAUDE_TEMPLATE.md itself changed.
- [ ] **5.3 — #1155 close-out comment** (posted at landing, referenced from
  the PR): three-track disposition table (counts per track from the final
  scanner run), the declare-A branch + probe evidence pointer, the
  guard-v2 rationale, and the tripwire's enforcement summary. The PR body
  carries `Closes #1155` (single issue — one keyword).
- [ ] **5.4 — Final sweep:** full suite; verify end-state items 1–5 from
  the Overview verbatim and quote each command + result in the phase
  report.

### Acceptance Criteria

```bash
test ! -f tests/fixtures/zsh-fence-pending.txt && echo gone        # gone
bash tests/test-skill-conformance.sh                               # green, unscoped, floors active
bash tests/test-zsh-fence-semantics.sh                             # green (CI has zsh via WI 1.6; local zsh-less runs WARN+SKIP)
bash tests/run-all.sh                                              # green, captured
grep -rn "bash <<'ZSKILLS_BASH_FENCE'" skills/ --include='*.md' | wc -l   # == wrapped-fence count the scanner reports (0 is acceptable; every nonzero wrap has protocol evidence in a phase report)
```

### Dependencies

Phases 1–4 (empty pending list).

---

## Findings — Phase 1

> (Heading deliberately does NOT match `^## Phase \d` — keeps /run-plan's
> phase extraction from treating this section as a phase.)
> Populated by the Phase 1 implementer: selected declare-A branch (expected
> B) with verbatim s3/s4 probe output and zsh version; seeded pending-list
> file count; check-(b) fence census + the computed initial floor (ii)
> (75% of census, rounded down); the floor-(iii) base census (the
> guard-expected set — scanner-flagged fences with only (b)/(b2)/(c)-class
> hits, computed from the same seeding run per WI 1.3; Phase 5 reads this
> literal); any files the appendix missed.

**Run environment.** zsh 5.9 (`x86_64-debian-linux-gnu`), the dev
container's `/usr/bin/zsh`. Seeding run recorded 2026-06-15. `${CI:-}`
empty (local), so the semantics suite executed (zsh present). All 15
sections of `tests/test-zsh-fence-semantics.sh` PASS.

**declare-A decision: BRANCH B (subscript normalization) — SELECTED.**
The decision rule (s3 diverges AND s4 identical → Branch B) is satisfied:

- **s3 (as-written mixed-quoted assoc) — DIVERGES (as expected).** Verbatim
  probe output (the snippet assigns `LP["$KEY"]="success"` / `L3["STATUS"]="ok"`
  then reads `${LP[STATUS]:-EMPTY}` / `${L3[STATUS]:-EMPTY}`):
  - bash: `a=success` / `b=ok`
  - zsh:  `a=EMPTY`   / `b=EMPTY`

  zsh stores the subscript text verbatim (including the quote characters), so
  the bare-literal read misses → the caller-loop misroute class. Both the
  quoted-VARIABLE and quoted-LITERAL spellings diverge identically
  (correction 6 confirmed).
- **s4 (consistent-unquoted normalization) — IDENTICAL.** All three key
  shapes (variable `LP[$KEY]`, parameter-expansion `SKIP_TAGGED_SET[${tok%%:*}]`,
  fixed literal `FIX[STATUS]`), the case-allowlist loop, and the
  membership-set dedupe produce byte-identical output under bash and zsh.

Therefore the tripwire's check (c) is wired ACTIVE (the Branch-B spelling):
quoted-variable (`[A-Za-z0-9_]\["\$`) AND quoted-literal
(`[A-Za-z0-9_]\["[A-Za-z0-9_]+"\]`) subscripts both FAIL, with the
normalize-remedy. Phases 2–4 carry the one-line-per-site normalization edits;
Branch A (accept) and Branch C (flat-var rewrite) are NOT taken.

**Seeded pending-list file count: 28** (`grep -c .
tests/fixtures/zsh-fence-pending.txt` = 28). This MATCHES the appendix
inventory's "28 distinct files across 15 skills" — the scanner agrees with
the appendix, it does not over-detect. The seeded files (the scanner report
is ground truth, superseding the appendix per correction 4) include
`skills/run-plan/subcommands/stop-next-status.md`, which the research
per-skill totals omitted (correction 4 anticipated this) — no NEW files
beyond what the appendix lists were found.

**check-(b) fence census: 46.** This is within the drafting estimate band
(research ~52, independent review census ≈46 — it matches the review census
exactly), so no STOP-and-surface. Initial **floor (ii) = floor(46 × 0.75)
= 34** — pinned as the literal `ZF_CHECKB_FLOOR=34` in
`tests/test-skill-conformance.sh` with a comment citing this Findings entry.

**floor-(iii) base census (guard-expected set): 67.** From the same
fixture-absent seeding run: 67 distinct scanner-flagged fences whose flagged
constructs are all (b)/(b2)/(c)-class (no (a)-class / Track-R hit in the
fence). Phase 5 reads this literal (do not re-derive); it pins anti-vacuous
floor (iii) at 75% of 67.

**Wrapped-fence count: 0** (`wrapped_fences=0` in the seeding-run summary) —
as expected (Settled decision 1; every inspected Track-W candidate has
demoted to G). The wrap-acceptance path is exercised solely by the n5
synthetic self-check.

**Full seeding-run summary line** (fixture absent):
`ZSH-FENCE-SUMMARY: exec_fences=523 check_b_fences=46 guard_expected_fences=67 wrapped_fences=0 unlisted_violations=83 fixture_malformed=0`
(the 83 unlisted_violations is the total violation COUNT across the 28 files
when no fixture scopes them; with the seeded fixture present,
unlisted_violations drops to 0 and all 28 files report as PENDING).

---

## Fence inventory (advisory appendix — non-phase)

> (Heading deliberately does NOT match `^## Phase \d` — keeps /run-plan's
> phase extraction from treating this section as a phase.)
> Compiled from the consolidated research re-verified 2026-06-12 against
> worktree @ main 17339d9a, with the corrections above applied. ≈L refs —
> verify by content. The Phase-1 scanner report supersedes this table where
> they disagree. The table spans **28 distinct files across 15 skills** —
> the expected order of magnitude for the seeded pending list (Phase 1 AC).

| File | Fence ≈L | Constructs | Disposition |
|---|---|---|---|
| land-pr/SKILL.md | 63 (guarded) | regex/BASH_REMATCH | G — upgrade to v2 |
| land-pr/SKILL.md | 155 | regex (function def, used later) | G (demoted from W) |
| land-pr/SKILL.md | 249, 469, 720 | regex, cross-fence BRANCH/PR_NUMBER/STATUS | G |
| land-pr/references/caller-loop-pattern.md | 40 | declare -A LP (mixed subscripts), SKILL-INVOKE | normalize + comment + G |
| run-plan/SKILL.md | 94, 208 (guarded) | regex chain CONFIG_CONTENT/LANDING_MODE/… | G — upgrade to v2 |
| run-plan/SKILL.md | 135, 172, 189 | regex, cross-fence | G |
| run-plan/SKILL.md | ≈463 | compgen -G, cross-fence | R5 + G |
| run-plan/SKILL.md | 1119 | regex; reads PLAN_FILE/LANDING_MODE/PR_WORKTREE_PATH/TRACKING_ID/PHASE cross-fence | **G (demoted from W — correction 1; do NOT wrap)** |
| run-plan/modes/pr.md | 425 | LP clone, SKILL-INVOKE | normalize + G |
| run-plan/subcommands/stop-next-status.md | 21 | for-in-$ARGUMENTS | G (scanner-found class) |
| do/SKILL.md | 214 (guarded ≈292) | regex, _DO_SEEN (consistent — OK), cross-fence FORCE/ROUNDS/AUTO_FLAG/ISSUE_NUMS | G — upgrade to v2 |
| do/SKILL.md | 798, 902 | regex, cross-fence | G |
| do/SKILL.md | 978 | regex; writes FORCE/ROUNDS read downstream, reads REMAINING | G (demoted from W — correction 1) |
| do/modes/pr.md | 18 | regex | W-candidate (protocol; presumed G) |
| do/modes/pr.md | 77 | regex, cross-fence | G |
| do/modes/pr.md | 431/526 | LP clone, SKILL-INVOKE | normalize + G |
| do/modes/worktree.md | 18 | regex | G |
| commit/SKILL.md | 35 | regex, cross-fence FIRST_TOKEN | G |
| commit/SKILL.md | 69 | regex, reads/sets FIRST_TOKEN | G (demoted from W) |
| commit/modes/pr.md | 73/167 | LP clone, SKILL-INVOKE, nested heredocs | normalize + G |
| fix-issues/SKILL.md | 121, 134, 198, 221, 249, 282 | regex, cross-fence flags | G (121/134/221/249/282 demoted from W) |
| fix-issues/modes/sprint.md | 13 read-a sites; mapfile 359/708/1833; sets; LP_NOACT 1438; LP_SPRINT 2865; **LP_DASH 672 (`local -A`)/679**; SKILL-INVOKE 598/1370/2176/2786; bq 1692 | read -a, mapfile, declare/local -A, regex, for-in-scalar | R1+R2 + normalize + G |
| fix-issues/modes/pr.md | 49/165 | LP clone, SKILL-INVOKE, nested heredoc | normalize + G |
| fix-issues/modes/sync.md | 267/348 | LP clone, SKILL-INVOKE | normalize + G |
| fix-issues/subcommands/add-remove.md | 22 | regex, cross-fence | G |
| fix-issues/subcommands/add-remove.md | 115 | regex; reads REMOVE_MODE/REMOVE_ISSUE_NUM (set SKILL.md ≈L223/230) | G (demoted from W — correction 1) |
| work-on-plans/modes/execute.md | 190, 214, 277 | mapfile + regex | R1 + G |
| work-on-plans/modes/execute.md | 324–341, 459, 582 | SLUG_TO_FILE mixed subscript | normalize (≈330) |
| work-on-plans/modes/execute.md | 490–505 | ${!var} (test seam) | R4 |
| work-on-plans/subcommands/add-rank-remove.md | 184, 248 | regex, cross-fence | G |
| work-on-plans/subcommands/add-rank-remove.md | 415 | regex | W-candidate (protocol; presumed G) |
| cleanup-merged/SKILL.md | ≈372-region (${,,} @480), ≈727-region (@793) | ${var,,}, regex, cross-fence counters | R3 + G |
| draft-tests/SKILL.md | 90 | for-in-$ARGUMENTS | G |
| draft-tests/SKILL.md | 175 | regex | W-candidate (protocol; presumed G) |
| draft-tests/modes/land.md | 168/204 | LP clone, SKILL-INVOKE | normalize + G |
| draft-tests/references/design-constraints.md | 58 | BASH_REMATCH (display-only) | marker |
| draft-plan/SKILL.md | 76, 230 | for-in-$ARGUMENTS | G |
| draft-plan/SKILL.md | 167 | regex, cross-fence | G |
| draft-plan/SKILL.md | 930/965 | LP clone, SKILL-INVOKE, nested heredoc | normalize + G |
| refine-plan/SKILL.md | 86, 173, 189 | for-in-$ARGUMENTS | G |
| refine-plan/SKILL.md | 160 | regex, cross-fence | G |
| refine-plan/SKILL.md | 750/785 | LP clone, SKILL-INVOKE | normalize + G |
| update-zskills/SKILL.md | 386 | for-in-$ARGUMENTS | G |
| update-zskills/SKILL.md | 447 | regex, cross-fence config family | G (demoted from W) |
| update-zskills/SKILL.md | 868 | regex, cross-fence | G |
| update-zskills/SKILL.md | 1433 | regex | W-candidate (protocol; presumed G) |
| zskills-dashboard/SKILL.md | 175 | regex (function def, used later) | G (demoted from W) |
| zskills-dashboard/SKILL.md | 342, 514 | regex, cross-fence | G |
| zskills-dashboard/SKILL.md | 670 | regex | W-candidate (protocol; presumed G) |
| verify-changes/SKILL.md | 110, 198 | regex; for-in-$ARGUMENTS | G |
| research-and-go/SKILL.md | 91, 284 | regex, cross-fence | G |
| research-and-plan/SKILL.md | 142 | regex | W-candidate (protocol; presumed G) |
| research-and-plan/SKILL.md | 366 | for-in-$ARGUMENTS | G |

Already-guarded (#1169, upgrade-in-place): run-plan ≈L101/≈L212, do ≈L292,
land-pr ≈L69. Cross-shell-safe already: do/SKILL.md `_DO_SEEN` (consistent
unquoted subscripts); the 3 `for f in $(…)` loops (zsh splits command
substitutions); `< <(env)` process substitutions.

## Plan Quality

**Drafting process:** `/draft-plan` with 2 rounds of adversarial review.
Round 1: reviewer (12 findings) + devil's advocate (10 findings) — all 22
addressed with live reproductions, including the structural demotion of
Track W from deliverable to opportunistic mechanism (the draft's one
"verified" wrap was falsified by both adversarial seats). Round 2:
combined adversarial seat (reviewer + devil's advocate), 0 CRITICAL /
0 MAJOR / 6 MINOR — all 6 fixed in the final refine pass. Converged at
round 2.

**Strengths:**

- **Empirical spine:** every replacement idiom, the guard extension, the
  wrap rc contract, and the declare-A divergence were probe-validated under
  zsh 5.9 on 2026-06-12 (recorded on #1155) BEFORE drafting — Phase 1
  commits the probe as a durable suite so the assumptions stay pinned.
- **The plan text is the implementer's only context:** the wrap idiom,
  guard v2 string, all five Track-R replacement idioms, the marker format,
  the normalization diff shape, and the tripwire's exact regexes appear
  verbatim above.
- **Honesty over the original sketch:** the uniform-wrap framing is
  explicitly retired AND the wrap track is demoted to an opportunistic
  mechanism — eight drafting/review-time demotions are recorded
  (including the draft's own one "verified" wrap, falsified by both
  adversarial reviewers), no AC requires a minimum wrap count, and zero
  wraps is an acceptable end state. The plan's value rests on guard v2,
  the Track-R rewrites, the subscript normalization, and the tripwire.
- **Ratchet over big-bang, without sibling collateral:** the tripwire
  lands first; unlisted files fail hard from day one, stale entries WARN
  (so sibling PRs are never forced to edit this plan's fixture), drainage
  is enforced by phase ACs, and Phase 5 removes the scaffold entirely.

**Remaining concerns:**

- **The shell-semantics evidence base is local.** Every probe behind the
  declare-A decision, the Track-R idioms, and the v2 guard ran under the
  dev container's zsh 5.9 (x86_64-debian-linux); macOS zsh has not been
  exercised directly. Mitigation, not elimination: Phase 1 commits the
  probes as `tests/test-zsh-fence-semantics.sh`, and once WI 1.6 installs
  zsh in CI the assumptions re-validate on every push — but a zsh-version-
  or platform-specific divergence would surface only then, as a Phase-1
  STOP-and-surface.
- **Track W may produce zero wraps.** Every inspected candidate (8/8) has
  demoted to Track G; the wrap idiom, rc contract, and tripwire
  wrap-detection may ship with no in-tree user. This is an accepted
  outcome (Settled decision 1) and the n5 self-check keeps the acceptance
  path tested — but the wrap machinery is, honestly, speculative
  infrastructure until a genuinely self-contained fence appears.

**Round History:**

| Round | Reviewer | Devil's Advocate | Resolved |
|---|---|---|---|
| 1 | 12 findings | 10 findings | all 22 addressed with live reproductions (incl. Track-W demoted from deliverable to opportunistic) |
| 2 | combined adversarial seat — 0 CRITICAL / 0 MAJOR / 6 MINOR (F1–F6) | (combined with reviewer seat) | all 6 fixed in the final refine pass; CONVERGED |
