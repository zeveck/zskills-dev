# Queued /quickfix Prompts

Four `/quickfix` invocations to run when ready. Prompts 1 and 2 address recurring failure modes in `/draft-plan` and `/refine-plan`; Prompt 3 fixes `/update-zskills` source-asset discovery; Prompt 4 adds positional-tail guidance to `/refine-plan`. Prompts 1, 2, and 4 are independent of each other (no line-range overlap, but 1 and 2 both edit `skills/draft-plan/SKILL.md` so let one PR land before kicking off the other). Prompt 3 must wait for SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX, and DEFAULT_PORT_CONFIG to land first.

Source context: produced 2026-04-26 from a session where both bugs surfaced (file collision in `/tmp/draft-plan-review-round-1.md` exposed the convergence-by-refiner-self-declaration pattern). Re-reviewed 2026-04-27 by three independent Opus agents; revisions to Prompts 2 and 4 incorporated below (Edit-replace clarification on QF2, prose-mirror clarification on QF4, in-scope spaces-in-paths fix added to QF4 Sub-edit 5).

---

## Prompt 1 — Slug-namespace `/draft-plan` review files

```
/quickfix Fix /draft-plan: slug-namespace the round review file path so concurrent invocations don't collide.

Edit skills/draft-plan/SKILL.md (then mirror to .claude/skills/draft-plan/ via `rm -rf` + `cp -r` + `diff -rq`):

L126 currently reads:
  - `/tmp/draft-plan-review-round-N.md` — reviewer + devil's advocate findings

Change to:
  - `/tmp/draft-plan-review-<slug>-round-N.md` — reviewer + devil's advocate findings

Use the same <slug> Phase 1 already constructs for `/tmp/draft-plan-research-<slug>.md`. Today the unnamespaced review path collides when two /draft-plan invocations run sequentially or in parallel; this matches the research file's namespacing convention.
```

---

## Prompt 2 — Convergence rule fix across `/draft-plan` and `/refine-plan`

```
/quickfix Fix /draft-plan and /refine-plan: make convergence the orchestrating skill's judgment, not the refiner agent's self-declaration. The bug is missing-guardrail (current text describes WHAT convergence means but is silent on WHO judges it, leaving the orchestrator to drift into rubber-stamping refiner output). Same fix applies symmetrically to both skills. (/research-and-plan Step 3 has a related — but distinct — pair of issues, out of scope here; file as a follow-up issue at the end.)

Two edit sites per skill — four total source edits, plus mirrors:

Edit 1 — skills/draft-plan/SKILL.md Phase 5 — Convergence Check (L472 area).
Edit 2 — skills/draft-plan/SKILL.md Key Rules section (L562 area).
Edit 3 — skills/refine-plan/SKILL.md Phase 4 — Convergence Check (L377 area).
Edit 4 — skills/refine-plan/SKILL.md Key Rules section (L518 area).

Then mirror BOTH skills to .claude/skills/{draft-plan,refine-plan}/ via `rm -rf` + `cp -r` + `diff -rq`.

For Edits 1 and 3 (the Convergence-Check phase bodies): add this paragraph at the top of the phase, before the existing numbered steps:

> Convergence is the **orchestrator's judgment**, not the refiner's self-call. Do NOT accept "CONVERGED" from the refiner agent as authoritative — the refiner just refined; it is biased toward declaring its own work done. This is a recurring failure mode in practice.

Then **replace the existing numbered "Check convergence" list (steps 1-2) with** this expanded version (preserve step 3 "Track round history" as-is):

  - Count remaining substantive issues from the refiner's disposition table (Justified-not-fixed entries plus any gaps the refinement introduced).
  - 0 substantive issues → converged → next phase.
  - >0 substantive issues AND rounds < max → another review+refine cycle. Honor the user's rounds budget; don't stop early.
  - Only short-circuit before max rounds when remaining substantive issues are genuinely 0.

For Edits 2 and 4 (the Key Rules sections): the existing bullet spans THREE LINES in each skill, verbatim:

  - **Convergence means no new substantive issues.** Not "the same issues
    rephrased." If the devil's advocate keeps finding real new problems, the
    plan isn't ready.

Replace the entire three-line bullet with this single-line bullet:

  - **Convergence is the orchestrator's call** based on the refiner's disposition table, not the refiner's self-declaration. Run all budgeted rounds unless issues drop to 0.

After landing, file a follow-up GitHub issue: `gh issue create --title "Apply orchestrator-convergence fix to /research-and-plan Step 3 (follow-up)" --body "Step 3 (L217-253) has TWO related issues: (a) the same orchestrator-judgment gap as /draft-plan and /refine-plan (silent on WHO judges convergence), AND (b) a separate severity-thresholding concern (the rule is "no CRITICAL or MAJOR issues" rather than 'no substantive issues at all'). Both should be evaluated together; the fix is not a literal copy of the /draft-plan + /refine-plan symmetric quickfix because Step 3 dispatches reviewer + DA in parallel and applies fixes inline (no single named refiner agent)."`
```

---

## Prompt 3 — `/update-zskills` source-asset discovery: extend probe + stop-and-ask

Source context: queued 2026-04-26 from a session triaging Simon Greenwold's feedback. Originally drafted as a standalone `/quickfix` invocation; queued instead because (a) low urgency — doesn't break installs, just produces silent re-clone when a non-`/tmp` clone exists; (b) `skills/update-zskills/SKILL.md` is going to churn from active plans (DEFAULT_PORT_CONFIG, SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX) — running this now would create a refine-after-rebase loop. Anchored on Step 0's section name and the 4-tier probe (not line numbers) so it survives the file churn.

```
/quickfix Fix /update-zskills: extend the source-asset locator probe and replace the silent auto-clone fallback with stop-and-ask.

Edit skills/update-zskills/SKILL.md Step 0 ("Locate Portable Assets" — the section describing the existing 4-tier probe: zskills-portable/ → ./zskills/ → /tmp/zskills → silent auto-clone). Then mirror to .claude/skills/update-zskills/ via `rm -rf` + `cp -r` + `diff -rq`.

Two changes:

A. Extend the probe between tiers 3 and 4. After /tmp/zskills fails, check these locations IN ORDER (first valid wins; same validity test as the existing tiers — directory contains CLAUDE_TEMPLATE.md + hooks/ + scripts/ + skills/):
  1. $PWD/../zskills (project's sibling)
  2. $PWD/../../zskills (grandparent-sibling)
  3. ~/src/zskills
  4. ~/code/zskills
  5. ~/projects/zskills
  6. ~/zskills

B. Replace the silent tier-4 auto-clone with stop-and-ask. Print the list of locations that were checked. Ask in plain prose (NOT AskUserQuestion, per the skill's Key Rule 7): "Couldn't locate zskills source. Options: (a) paste a path to your clone, (b) type 'clone' to clone fresh to /tmp/zskills, (c) type 'abort' to cancel." Validate any pasted path; abort exits cleanly with a message; 'clone' falls back to the original auto-clone behavior.

Feedback context: Simon Greenwold cloned to a non-/tmp path and /update-zskills "flailed around like crazy." The fix is better discovery + honest "help me out" — no env var, no flag, no new knowledge required of the user.
```

---

## Prompt 4 — Add positional-tail guidance arg to /refine-plan

```
/quickfix Add optional positional-tail guidance arg to /refine-plan AND tighten the Detection rule to fix a paths-with-spaces bug. Mirror /draft-plan's description-detection pattern (which is prose-level, not bash regex — no new shell variable required; remaining unrecognized tokens, joined with spaces, are the guidance).

Edit skills/refine-plan/SKILL.md (then mirror to .claude/skills/refine-plan/ via `rm -rf` + `cp -r` + `diff -rq`):

1. Update the Arguments section's syntax block from:
     /refine-plan <plan-file> [rounds N]
   to:
     /refine-plan <plan-file> [rounds N] [guidance...]

2. Update the Detection block (currently in the Arguments section) so any tokens not matched as the plan file or `rounds N` keyword (note: `rounds` requires a numeric argument, so guidance text starting with the word "rounds" not followed by a number is NOT misclassified) join (space-separated) into the guidance, which gets prepended to agent prompts in step 3. Empty guidance is the current default behavior. Mirror /draft-plan's prose-level detection — no new bash variable required.

3. Update Phase 2 — Adversarial Review (parallel agents). When dispatching the reviewer and devil's advocate agents, if guidance is non-empty, prepend it to each agent's prompt as an explicit "User-driven scope/focus directive" section. Agents treat it as priming context that shapes WHAT they pressure-test, NOT as factual claims to act on without verification (verify-before-fix discipline still applies).

4. Add an Examples bullet to Arguments showing usage:
   - `/refine-plan plans/FOO.md anti-deferral focus`
   - `/refine-plan plans/FOO.md rounds 3 expand audit to all config fields`

5. Tighten the Detection rule for the plan file: the current rule reads (in skills/refine-plan/SKILL.md L48-49):
     "The **first token** ending in `.md` or containing `/` is the plan file."
   Drop the "or containing `/`" clause so the rule becomes:
     "The **first token** ending in `.md` is the plan file. If the token contains `/`, use as-is; otherwise prepend `plans/`."
   This mirrors /draft-plan's first-token-ending-in-.md rule exactly. Closes a bug where a path with embedded spaces (e.g., `/refine-plan plans/My Phase.md`) tokenizes into `plans/My` + `Phase.md`; the partial path matched the "containing /" clause and produced a misleading "plan file `plans/My` not found" error. After this fix, `plans/My` doesn't end in `.md` so it falls through, and the user gets the existing clear "No plan file specified. Usage: ..." error instead.

Why: in a recent session, /refine-plan needed user-driven priming to surface deferred work. Without this arg, the orchestrator manually injected priming into agent prompts — workable but error-prone (forgotten across invocations, no audit trail). Mirroring /draft-plan's positional-tail keeps the convention consistent with the /refine-plan SKILL's existing arg style (no --flags today; bareword + keyword + positional). Multi-word guidance natural without quoting. Sub-edit 5 closes a previously deferred hole rather than filing a follow-up issue, since we're already in the Detection block.

NO behavior change to existing valid invocations: omitting guidance is the current default; every previously-correct path-with-or-without-slash still works (`plans/X.md` still matches; `X.md` still gets `plans/` prepended). Sub-edit 5 only changes behavior for the previously-broken paths-with-spaces case (now fails fast with a clearer message). Empty guidance → reviewer/DA prompts unchanged from today's output.
```

