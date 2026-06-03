# Skill Discrepancies — for user ruling

> This file surfaces **cross-skill / cross-mode inconsistencies and surprising
> behavior** found while rewriting the catalog docs. It is the second
> deliverable of `docs/plans/USER_DOC_REWRITE_PLAN.md`. It lives **outside** the
> viewer catalog (in `docs/reports/`) so it stays a working doc, not a published
> page.
>
> **Divergence is not automatically a bug.** Some is deliberate (e.g. `/do`'s
> `stop [query]`/`next [query]` disambiguators). Every entry carries the
> orchestrator's **hypothesis of intent** (intentional vs. surprising) and a
> **request for the user's ruling**. Entries **never assert a verdict — they
> ask.** Per the "surface bugs, don't patch" rule, real skill bugs found here
> are NOT silently documented as features and NOT patched in the doc-rewrite
> work; they go to the user, who decides whether to file a skill-fix issue.
>
> **Bounded intake** (to avoid a judgment swamp): log an entry only when the
> inconsistency (a) would change a user-facing doc claim, or (b) looks like a
> real skill bug. Pure stylistic variation is **not** logged. Soft cap ~20
> entries; beyond that, record the *count* of un-enumerated extras rather than
> listing every one.

---

## Entry template

```
### <short title>

- **Type:** [intentional? | surprising? | source bug — surface, don't patch]
- **What diverges:** <the concrete inconsistency, one or two sentences>
- **Evidence:** <file:line citations, verified this session>
- **Why it matters / doc impact:** <which user-facing claim this would change,
  or why it reads as a bug>
- **Orchestrator's hypothesis:** <intentional vs. surprising, with reasoning>
- **Question for the user:** <the specific ruling requested>
```

---

## Seed entries (all verified this session)

### Mode-availability is config-conditional

- **Type:** intentional?
- **What diverges:** The landing modes a skill accepts depend on
  `.claude/zskills-config.json`. Under `main_protected: true`, `direct` and
  `cherry-pick` are illegal (agents can't commit/push to main), and appending a
  `pr` token is redundant because PR mode is already forced. Under
  `main_protected: false`, all modes are live. So the *same* skill advertises
  different usable modes depending on config.
- **Evidence:** `CLAUDE.md` "## Execution Modes" / "When `main_protected: true`,
  agents cannot commit, cherry-pick, or push to main"; `skills/do/SKILL.md:40`
  (`[worktree|direct|pr]`), `:51-55` (mode→config mapping).
- **Why it matters / doc impact:** Every execution-skill doc must lead with the
  protected-main default and not present the full mode matrix as universally
  available (R3/R4). It is a real modality and should be described *consistently*
  across `/do`, `/quickfix`, `/commit`, `/run-plan`, `/fix-issues`.
- **Orchestrator's hypothesis:** Intentional — config-gated modality is a
  deliberate safety design, not an accident.
- **Question for the user:** Confirm this is intended, and that docs should lead
  with the protected-main default rather than enumerate the full matrix.

### `/do`'s `stop [query]` / `next [query]` disambiguators vs. bare `stop`/`next` elsewhere

- **Type:** intentional?
- **What diverges:** `/do` accepts `stop [query]` and `next [query]` (an
  optional query to target a specific scheduled instance), whereas other
  schedulable skills (`/fix-issues`, `/qe-audit`, `/briefing`, `/run-plan`,
  `/work-on-plans`) use bare `stop` / `next`.
- **Evidence:** `skills/do/SKILL.md:3` argument-hint
  `... | stop [query] | next [query] | now [query]`; compare
  `skills/fix-issues/SKILL.md:3` (`... | stop | next`),
  `skills/qe-audit/SKILL.md:3` (`... | stop | next`),
  `skills/briefing/SKILL.md:3` (`... | stop | next`).
- **Why it matters / doc impact:** The `/do` doc should explain the `[query]`
  disambiguator; the peer docs should NOT, to avoid implying a feature they lack.
- **Orchestrator's hypothesis:** Intentional — `/do` can fan out multiple
  parallel crons in one session (each with its own description), so it needs a
  query to target one; the others run a single recurring job, so bare
  `stop`/`next` suffice.
- **Question for the user:** Confirm intended, so the docs document it only for
  `/do`.

### Stale `argument-hint` frontmatter (source bug — surface, don't patch)

- **Type:** source bug — surface, don't patch
- **What diverges:** Several `skills/<name>/SKILL.md` `argument-hint` fields are
  **incomplete vs. the skill's actual documented arguments**. The skill *body*
  (and the existing doc) is MORE correct than the frontmatter. Verified each
  against both the frontmatter line and the body:
  - **`do`** — `argument-hint` omits `direct` and `--force`.
    `skills/do/SKILL.md:3` lists `[worktree] [pr] [auto] … [--rounds N]` but the
    body documents `direct` (`:40` `[worktree|direct|pr]`, `:51` "**direct** —
    work on main in place") and `--force` (`:13`, `:73` "**--force** (optional)").
  - **`quickfix`** — `argument-hint` omits `--force`.
    `skills/quickfix/SKILL.md:3` ends `[--branch <name>] [--rounds N]`, but the
    body documents `--force` (`:64` "**--force** (optional)") and even notes at
    `:81` that it's "kept lean per #961" out of the hint — i.e. deliberately
    omitted from the hint, but it IS a real arg.
  - **`research-and-plan`** — `argument-hint` omits `auto`.
    `skills/research-and-plan/SKILL.md:3` is `[output FILE] <broad goal …>`, but
    the body documents `auto` (`:41` "**auto** (optional) — skip the
    decomposition confirmation checkpoint").
  - **`update-zskills`** — `argument-hint` omits many flags.
    `skills/update-zskills/SKILL.md:3` is only
    `[install] [cherry-pick|locked-main-pr|direct]`, but the body documents
    `--rerender` (`:1259`), `--with-addons` (`:1029`), `--switch-install-path`
    (`:1044`), `--migrate-paths` (`:18`), and others.
  - **`briefing`** — `argument-hint` omits the `1d` period.
    `skills/briefing/SKILL.md:3` period list omits `1d`, but the body documents
    it (`:41` "**Period shorthand:** `1h`, `6h`, `24h` (default), `1d`, `2d`,
    `7d`").
- **Why it matters / doc impact:** Phase docs derive the "Arguments" section
  partly from `argument-hint`. If they trust the hint over the body, they will
  under-document real args. RUBRIC.md's target-doc template already says the
  body wins; this entry records the source-level mismatch so the user can decide
  whether to fix the frontmatter.
- **Orchestrator's hypothesis:** Surprising for most; partly intentional for
  `quickfix` (explicitly trimmed "per #961"). Either way the frontmatter is the
  less-correct surface.
- **Question for the user:** Should the stale `argument-hint` fields be brought
  into sync with the bodies (a skill-source fix, separate from doc-rewrite), or
  left as-is with the docs sourcing from the body?

### `managed.md` imprecisely lumps `/run-plan` with the Skill-blocked recurring skills

- **Type:** doc imprecision — likely-intentional flag; fix the prose, probably NOT the flag
- **What diverges:** The rendered rule in `.claude/rules/zskills/managed.md`
  (and its template `CLAUDE_TEMPLATE.md`) states that "every recurring-skill we
  ship (`/fix-issues`, `/do`, `/qe-audit`, `/run-plan`) sets
  `disable-model-invocation: true` and Skill-tool dispatch is blocked by
  design." But `skills/run-plan/SKILL.md:3` is `disable-model-invocation: false`.
  The other three named skills ARE `true`. **Nuance (likely the real story):**
  `/run-plan` is not "recurring" in the same sense — it recurs only over a
  *finite* plan's phases and terminates when the plan completes, whereas
  `/fix-issues`/`/qe-audit`/`/work-on-plans` recur *indefinitely*. So
  `/run-plan` being `disable-model-invocation: false` is plausibly **by design**
  (a bounded, model-invocable executor), and the actual defect is the managed.md
  *prose* lumping it in with the indefinite-recurrence skills.
- **Evidence:** `.claude/rules/zskills/managed.md:24` (and identically
  `CLAUDE_TEMPLATE.md:24`) — the four-skill list including `/run-plan`;
  `skills/run-plan/SKILL.md:3` → `disable-model-invocation: false`;
  contrast `skills/fix-issues/SKILL.md:3`, `skills/qe-audit/SKILL.md:3`,
  `skills/work-on-plans/SKILL.md:3` → all `true`.
- **Why it matters / doc impact:** This rule is loaded into every agent's
  context. It would make an agent **wrongly refuse to launch `/run-plan` via the
  Skill tool**, believing it is blocked — when in fact `/run-plan` permits model
  invocation. (Note: `/work-on-plans` is correctly `true` but is NOT in the
  list; the list both over-claims `/run-plan` and under-lists `/work-on-plans`.)
  The fix is in `CLAUDE_TEMPLATE.md` (then re-render), not in any catalog doc.
- **Orchestrator's hypothesis:** The flag is likely intentional (finite
  recurrence); the *prose* is imprecise. Still behavior-affecting — an agent
  could wrongly refuse to Skill-launch `/run-plan` — so worth fixing the wording.
- **Question for the user:** Confirm `/run-plan`'s `disable-model-invocation:
  false` is intentional (finite recurrence). If so, fix the `CLAUDE_TEMPLATE.md`
  prose so it stops lumping `/run-plan` with the indefinitely-recurring skills
  (and add the omitted `/work-on-plans`), then re-render `managed.md`.

### `clear-tracking.sh` path is wrong/inconsistent in the tracking guides

- **Type:** source bug — surface, don't patch
- **What diverges:** The two tracking guides cite **mutually inconsistent**
  paths for `clear-tracking.sh`, none matching the path the hook actually emits.
  The truth (what the hook tells the user to run) is
  `.claude/skills/update-zskills/scripts/clear-tracking.sh`.
  - `docs/guides/tracking-overview.md` → `scripts/clear-tracking.sh`
    (`:159`, `:224`, `:661`, `:685`).
  - `docs/guides/inspecting-and-monitoring.md` → bare `clear-tracking.sh`
    (`:36`, `:140`, `:142`, `:144`, `:175`) **and**
    `skills/update-zskills/scripts/clear-tracking.sh` (`:326`).
  - Hook truth: `hooks/block-unsafe-project.sh.template:332`, `:334`, `:346`,
    `:357`, `:602`, `:616` all emit
    `! bash .claude/skills/update-zskills/scripts/clear-tracking.sh`.
- **Why it matters / doc impact:** A user copies the guide's path and the
  command fails (`scripts/clear-tracking.sh` does not exist there). The guides
  must be rewritten to cite the hook-emitted path
  (`.claude/skills/update-zskills/scripts/clear-tracking.sh`) — this lands in
  Phase 7 (`tracking-overview.md`) and the `inspecting-and-monitoring.md`
  rewrite, but is surfaced here because it is a real, user-hitting error.
- **Orchestrator's hypothesis:** Surprising — stale paths from before the
  script moved into `.claude/skills/update-zskills/scripts/` (see
  `CLAUDE.md` "script machinery moved to `.claude/skills/<owner>/scripts/`").
- **Question for the user:** Confirm the canonical path is
  `.claude/skills/update-zskills/scripts/clear-tracking.sh` and that the guides
  should be corrected to match the hook (Phase 7 / inspecting rewrite)?

---

_Un-enumerated extras beyond the soft cap: 0 (seed set only; later phases append)._
