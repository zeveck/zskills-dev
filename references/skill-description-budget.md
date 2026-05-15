# Skill description budget

Project-internal budget for the total length of `description:` fields
across all source `SKILL.md` files in this repo (skills/*/SKILL.md and
block-diagram/*/SKILL.md). Enforced as a permanent conformance test;
see [How the budget is enforced](#5-how-the-budget-is-enforced).

## 1. Why a budget at all

Skill descriptions live at the level-1 progressive-disclosure surface
of Claude Code's skill system: they are loaded into every model context
where any skill is available, regardless of which skill (if any) the
agent ends up invoking. Unlike skill bodies, which the model loads only
on dispatch, descriptions are always-on overhead.

Uncapped growth in descriptions therefore proportionally erodes the
context budget available for the actual task. A 200k-token context
window is large, but it is finite, and descriptions compete against
codebase context, user messages, tool outputs, plan text, agent
transcripts, and any other always-loaded prompt material. A cap keeps
descriptions terse enough to fit the level-1-disclosure role and
forces authors to push detail into the body (where it's loaded only
when relevant).

## 2. The numbers

Anthropic's published skill-development guidance suggests roughly
~100 words/skill as the rule of thumb for description length. Scaled
to ~30 skills, that's ~3,000 words ≈ ~12,000 tokens ≈ ~6% of a 200k
context.

This project's chosen target is tighter: ~7,500 chars ≈ ~1,875 tokens
≈ <1% of context. The motivation is to leave headroom for skill growth
(more skills, occasional necessary description expansion) without
crossing the threshold where descriptions begin meaningfully crowding
out task context.

- **Hard cap: 7,500 chars** — test exits 1 above.
- **Soft warn: 7,000 chars** — test prints WARN, exits 0 between 7,000
  and 7,500.

Both thresholds are project policy, not Anthropic mandates. The
two-tier design (vs. a single hard cap) ensures that growth into the
7,000-7,500 band fires a visible WARN signal before the next addition
hard-fails CI, giving authors one round of warning to trim.

## 3. Per-skill ceiling

Normal-case skills aim for **≤ 350 chars** in their description.
Documented exceptions:

- **`/land-pr` — 450 chars.** Helper-only contract from PR #173.
  The description carries explicit "designed for agent dispatch /
  not for interactive human use" framing to prevent humans from
  invoking it directly; that framing is non-negotiable and pushes
  the description over the 350 default.
- **`/quickfix` — 400 chars.** Full-lifecycle framing from PR #164.
  The description enumerates the multi-stage workflow (research →
  fix → land) to disambiguate quickfix from neighboring one-shot
  skills; the enumeration earns the additional budget.

Per-skill numbers are informational only — the conformance test
enforces only the aggregate budget, not any per-skill cap. Some skills
legitimately need more description budget than others; the aggregate
budget is the discipline.

## 4. Policy signals to preserve

When trimming a description, preserve all of:

- **Trigger phrases** — the natural-language phrases that cue the
  model to dispatch the skill. Removing these breaks autoselection.
- **Sub-mode enumerations** — explicit listings of operating modes
  (e.g., `/run-plan next | stop | <plan-file>`). These cue the model
  to surface the right invocation syntax.
- **Cross-references** — references to peer skills, hooks, or
  artifacts the skill interacts with. These shape the model's mental
  model of the skill's place in the workflow.
- **Behavioral promises** — explicit statements of what the skill
  will and will not do (e.g., "auto-merge ONLY if --auto flag was
  passed"). These are part of the skill's contract.
- **Version/conformance discipline** — see CLAUDE.md
  `## Skill versioning` for the surrounding governance around skill
  edits. The SKILL.md descriptions of `/land-pr` and `/quickfix` in
  particular encode policy decisions that have already survived
  adversarial review; trimming them carelessly re-opens settled
  design.

What is fair game for trimming: prose elaboration, restatements,
historical motivation (move that to the skill body), and redundant
parenthetical asides.

## 5. How the budget is enforced

Two tests in `tests/`:

- **`tests/test-skill-description-budget.sh`** (this anchor's gate) —
  pure bash + awk; no jq. Extracts `description:` from every source
  SKILL.md, handling both block-scalar (`description: >-` + indented
  continuation) and single-line (`description: <text>`) forms.
  Computes the total char count. Hard-fails above 7,500; soft-warns
  between 7,000 and 7,500. Registered in `tests/run-all.sh` between
  the content-hash and version-compare entries.
- **`tests/test-skill-conformance.sh`** — literal-grep checks for
  required substrings in specific SKILL.md descriptions (e.g.,
  `/land-pr` must mention "not designed for direct user invocation").
  These tests are how policy signals named in
  [Section 4](#4-policy-signals-to-preserve) actually get pinned
  against accidental removal during a description trim.

Both gates run on every CI invocation of `bash tests/run-all.sh`.
A description trim PR must pass both: aggregate budget under the
hard cap AND every literal-grep conformance check still firing.
