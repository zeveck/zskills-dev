# /draft-tests — Test spec format, Key Rules, Edge Cases

The spec format vocabulary below is the **single source of truth** for
both the Phase 3 drafter ([modes/draft.md](../modes/draft.md)) and the
Phase 4 reviewer / devil's-advocate / refiner pass. Both phases cite
this file so the format stays consistent across drafting and review.

## Spec format — one-line bullet (canonical)

```
- [scope] [risk: AC-N.M] given <input>, when <action>, expect <literal>
```

Where:

- **scope** is one of `unit`, `integration`, `property`, `e2e`. The
  drafter picks the narrowest scope that exercises the AC. Reach for
  `[integration]` / `[e2e]` only when unit scope cannot observe the AC.
- **risk: AC-N.M** links the spec to the AC it exercises. The trailing
  `[a-z]?` after the second numeral admits sub-letter ACs (e.g.
  `[risk: AC-1.6c]`).
- **\<literal\>** is an exact value, named exception, or precisely-defined
  observable side effect. `assert f(0) == 0` is a literal. `Returns
  {status: 'ok', count: 3}` is a literal. `raises ValueError("empty
  input")` (named exception) counts as a literal. "Test the zero case"
  is NOT — that is a vague placeholder and is rejected by AC-3.3.

## Spec format — multi-line expansion

When a one-liner becomes unreadable (long inputs, multi-step setup,
non-trivial expected values), the drafter expands into:

```markdown
- [scope] [risk: AC-N.M] <short name>
  - Input: <literal>
  - Action: <literal>
  - Expected: <literal>
  - Rationale: <one sentence — why this spec exists, not how it works>
```

Expansion is the drafter's judgment call; the senior-QE review loop
(Phase 4) pushes back if one-liners are illegible or expansions are
gratuitous.

## Anti-pattern list (verbatim in drafter prompt)

The following anti-patterns are forbidden, listed verbatim in the
drafter's prompt:

> Anti-patterns — do NOT produce specs that exhibit any of the
> following:
>
> - **No happy-path-only coverage.** Every spec set must include at
>   least one error / boundary / negative case per AC, unless the AC
>   is provably positive-only.
> - **No assertion mirroring.** Do not assert that `f()` returns what
>   `f()` returns. Assert against an externally-known literal.
> - **No hallucinated APIs.** Check existence before referencing —
>   the implementer cannot test `widget.spin()` if no such method
>   exists. If the plan implies the API, name the AC; if it does
>   not, flag the gap to the user.
> - **No over-specific assertions baking in transient values.** Do
>   not pin to a specific timestamp, hash, or generated id; pin to
>   the structural claim ("returns a non-empty UUID v4 string").
> - **No mock-thrash.** Do not mock everything until the test
>   asserts on its own mock. Mock the boundary; assert on the
>   product code's behaviour.
> - **No empty try/catch scaffolds.** Every exception handler in a
>   spec must specify the exception type AND a partial message
>   match.
> - **No MAX_INT / Unicode / clock-skew cargo-cult tests** unless
>   the AC actually mentions those domains. The bar is product
>   intent, not folklore.

The Phase 4 reviewer / devil's advocate pass these anti-patterns to
its findings checklist verbatim — a draft that exhibits any of them is
a finding, not just a stylistic preference.

## Key Rules

- **NEVER modify Completed phases.** Immutability is verified
  mechanically via SHA-256 checksums. Not even heading typo fixes. AC-ID
  assignment is allowed ONLY in Pending phases.
- **Section boundary is the broad form, fenced-code-block-aware.** Any
  `## <name>` at column 0 outside fenced code blocks terminates the
  prior section. The bytes within fences are still part of the section;
  only the boundary detection skips them.
- **Single source of truth for delegate / ac-less classification.** The
  parsed-state file's `delegate_phases:` and `ac_less:` lists are the
  authoritative source. Phase 3 and Phase 4 MUST consume them — never
  re-derive by re-scanning the plan body.
- **Convergence is the orchestrator's call** based on the refiner's
  disposition table, not the refiner's self-declaration. Run all
  budgeted rounds unless the four positive conditions are all met.
- **Empty guidance preserves byte-identical reviewer/DA prompts.** The
  `User-driven scope/focus directive:` section is emitted ONLY when
  guidance text is non-empty.
- **No external JSON/YAML tooling.** Bash regex with `BASH_REMATCH`
  for all JSON / YAML parsing.
- **Edit `skills/draft-tests/` only.** Mirror to
  `.claude/skills/draft-tests/` via `bash scripts/mirror-skill.sh
  draft-tests` — NEVER inline `cp` / `rm -rf`. Per CLAUDE.md memory
  anchor `feedback_claude_skills_permissions.md`, edits to
  `.claude/skills/` trigger permission storms; mirror discipline is the
  workaround.
- **Ultrathink throughout.** Every agent should use careful, thorough
  reasoning.

## Edge Cases

- **Plan file doesn't exist** — error: `Plan file '<path>' not found.`
- **Plan file has no Progress Tracker** — error: `No Progress Tracker
  found in '<path>'. ...`
- **Plan with all-Completed phases AND no gaps** — exit clean with the
  `nothing to draft or backfill` message.
- **Plan with all-Completed phases AND ≥1 Completed-phase gap** — does
  NOT exit; proceeds into Phase 5 backfill.
- **Plan with sub-phases (3a/3b)** — each sub-phase classified
  independently. Sub-phase `3a` can be Completed while `3b` is Pending.
- **Pending phase with no `### Acceptance Criteria` block** — appended
  to `ac_less:`. No `### Tests` subsection is appended in Phase 3. No
  coverage-floor finding is synthesised in Phase 4. The advisory line
  is emitted in the skill's final output.
- **Pending phase with `### Execution: delegate ...`** — listed in
  `delegate_phases:`. No `### Tests` subsection is appended in Phase 3
  (test coverage is the delegated skill's responsibility). The
  coverage floor does not enforce on this phase.
- **Bullet inside an AC block with an ambiguous prefix** (`- [ ] 1.1 —
  ...`, `- [ ] AC-3.2 covered when X happens`, `- [ ] [scope] ...`) —
  left byte-identical. Advisory emitted naming the file:line.
