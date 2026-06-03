# Doc-Rewrite Rubric (R1–R7)

> The standard every rewritten catalog doc (`docs/skills/*.md`, `docs/guides/*.md`)
> is held to. Phase implementers and verifiers are pointed at THIS file.
> Source of truth: `docs/plans/USER_DOC_REWRITE_PLAN.md` "## The Rubric".
> If this file and the plan ever disagree, the plan wins — fix this file.

The audience for every doc is a **technical-but-uninitiated reader**: someone
who knows software but does not know zskills internals. Write for that reader.

---

## R1 — Right-shape-but-inaccurate is the dominant risk

A doc can read perfectly and still lie. This is the failure mode that did the
most damage: pages that *look* clean but assert things that are false, stale, or
overstated.

- Every factual claim is verified against **current** source: `skills/<name>/SKILL.md`
  plus its `modes/` and `references/`, `CLAUDE.md`, and the relevant hooks.
- A claim with no supporting source line **does not ship**.
- The codebase moves underneath the docs — re-derive ground truth from HEAD,
  never from a prior audit's findings (those are expired hypotheses).

## R2 — Universals demand an exception hunt

"all", "always", "every", "never", "regardless of mode" read as authoritative
and are the easiest claims to falsify with a single carve-out. For each
universal, perform a **dedicated** search for the falsifying exception.

- If a falsifying exception exists → rescope the claim to plain truth.
- If none is exhibited → treat the universal as **unverified, not passed**.

**The hunt is a checklist, not a vibe.** "Ran one grep, found nothing" is not a
hunt. For each universal, check:

- **(a) Config fields that gate it** — `execution.landing`, `main_protected`
  (and any other `.claude/zskills-config.json` field the behavior depends on).
- **(b) Hook fences** — `hooks/*.sh` (e.g. `block-unsafe-*`, `block-main-edits`)
  that conditionally allow/deny the behavior.
- **(c) The CLAUDE.md decision/flag tables** — "Which skill for which input"
  and the flag-convention rules.
- **(d) The skill's own `modes/` files** — mode-specific behavior the
  top-level prose may not mention.
- **(e) The peer-skill docs** — a sibling skill may carry the carve-out.

## R3 — Plain-and-true beats technically-correct-and-messy

When a simple statement would overstate, do **not** bolt on qualifiers until it
is bulletproof — that produces the hedge-soup seen in `installing-zskills.md`.

**The altitude ladder, in priority order:**

- **(a) Raise altitude** to the observable behavior the user can rely on.
- **(b) Drop the edge case** if the user won't hit it or won't care.
- **(c) Only if genuinely user-relevant**, add **one short scoped clause** —
  never a qualifier-nest.

A sentence the reader has to re-parse to extract the real behavior has already
failed R3, even if every clause is technically true.

## R4 — Modes are a thin axis; describe behavior once

A skill's behavior is stated **uniformly**. The only things a mode changes are:
*does it use a worktree? does it open a PR? how much ceremony?*

- Do **not** narrate behavior mode-by-mode.
- The phrases "regardless of mode" and "in PR mode… / in worktree mode…" are
  themselves the tell of mode-by-mode thinking — delete them and state the
  behavior plainly.
- Which *modes are even available* is config-conditional (`direct`/`cherry-pick`
  are illegal under `main_protected`), so docs lead with the common
  protected-main default and don't drown the reader in the full mode matrix.

**R4 flattens *narration*, not *truth*.** Where a mode genuinely changes
behavior in a way the user can hit — e.g. `/do` skips `/verify-changes` for
content-only changes (`skills/do/SKILL.md`, `modes/pr.md`) — keep it as **one
short scoped clause** (R3-c). Deleting a *true* carve-out to satisfy R4 is a
regression, not a fix. That is the R2↔R4 balance: R2 makes you hunt for the
carve-out; R4 makes you state it once, plainly, instead of narrating it per mode.

## R5 — No internals voice

Banned from user prose **unless the user observably encounters the term** (e.g.
the term appears in a message the user reads, or names a command they type).
Lead with what the user does or expects, never with how the implementation works.

The finalized banned-term list lives below ("Banned-term list") and as
`grep -E` patterns in `banned-terms.txt`. Acceptance for any later phase is the
concrete command:

```
grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt <phase docs>
```

returning no hits.

## R6 — Companion skills must agree across docs

Every doc's "companion skills" section is drawn from **one canonical
companion-skill graph** (`COMPANIONS.md`, this directory), so the docs
cross-reference each other consistently. Do not invent companion relationships
per doc — read them off the graph.

## R7 — Peers read as peers

Co-equal skills (e.g. `/do` ↔ `/quickfix`) get **equal-quality** docs regardless
of which the author personally uses. The usage-log mining (`USAGE_MAP.md`) is a
**single-user-biased** signal — it informs realistic "typical usage" examples,
but **never** justifies under-serving a peer skill the sample happens to avoid.

---

## Target doc template

Every skill doc answers, in **plain prose for a technical newcomer**, these
four things (existing skeleton — summary / usage / arguments / examples — maps
onto them; this is rewrite-in-place at the right altitude, not a restructure):

1. **What it does (behavior).** The observable behavior and output — what the
   skill *does for the user*, stated once and uniformly (R4). Behavior and
   observable output, never internals (R5).
2. **Typical usage.** The realistic, common way the skill is invoked, with
   concrete argument examples. Drawn from `USAGE_MAP.md` (a biased sample — use
   it for *examples*, never to deprioritize a peer, R7).
3. **Companion skills.** Which skills are commonly used before/after/alongside
   this one. Drawn verbatim-in-relationship from `COMPANIONS.md` (R6).
4. **Arguments.** The skill's accepted arguments, sourced from `argument-hint`
   **and verified against the skill body** — where the body documents an arg the
   `argument-hint` omits, the body wins (several `argument-hint` fields are stale;
   see `../SKILL_DISCREPANCIES.md`). Cite `skills/<name>/SKILL.md:line`.

Nothing overstated. Every factual claim traceable to a source line (R1).

---

## Banned-term list (prose)

These are **implementer-voice** terms that leak internal reasoning onto a
user-facing page. Ban them from prose **unless the user observably encounters
the term** (it shows up in a message they read or names a command they type).
The machine-checkable form is `banned-terms.txt`; this is the human-readable
rationale. Seeded from R5 and expanded by grepping the current catalog docs for
internals vocabulary.

| Term / pattern | Why it's internals voice | Plain-altitude replacement |
|---|---|---|
| `materialiser` / `materialise` | names a hook implementation detail | "writes the files into your project on session start" |
| `sentinel` / `sentinel-gated` | internal guard-file mechanism | "only runs once" / drop |
| `atomic` / `atomically` | an implementation guarantee, not user-visible | drop, or "all-or-nothing" only if the user can hit a partial state |
| `Phase 0a` / `Phase N` / `Phase Nx` | internal plan/skill phase numbers | describe what happens, not which phase does it |
| `WI N.N` / `WI N` | work-item IDs from plans | drop |
| `Tier 1` / `Tier 2` | internal classification (e.g. create-worktree) | describe the actual distinction in plain words |
| `${CLAUDE_PLUGIN_ROOT}` | a path env var only the install machinery uses | drop, or "where the plugin is installed" |
| `lock-LAST` | migration-script invariant | drop |
| `D25` / `D4` / `D[0-9]+` (design-decision refs) | internal design-decision shorthand | drop |
| `flock` | a syscall used by a script | "won't run two copies at once" |
| `collect.py` / `render-index` / `build-catalog.sh` (impl script names) | name internal scripts the user never runs | describe the behavior, not the script |
| `git-common-dir` | a git plumbing detail | drop |
| `static-grep` / `git-tokenwalk` | internal scan-strategy names | drop |
| `preset-owned` / `preset` | install-machinery vocabulary | drop or "the default config" |
| `disable-model-invocation` | frontmatter field name | "you type it; the model won't auto-launch it" |
| `subagent_type` / `inject-bash-timeout` / `verify-response-validate` | dispatch/hook plumbing | drop |
| internal `#issue` links (bare `#NNNN`) | issue numbers a user can't action | drop, or link only if user-relevant |

The list is **not exhaustive** — R5's rule is the governing principle. If a term
names *how the implementation works* rather than *what the user does or sees*,
it is banned even if it is not in this table. Add new offenders to
`banned-terms.txt` as later phases surface them.
