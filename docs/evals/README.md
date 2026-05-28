# Layer-3 Judgment Evals

These are **not** CI-gated tests and **not** standing regression canaries.
They are one-time / periodic **live behavioral evaluations of LLM judgment
quality** — the kind of verification that no shell smoke can catch and that
dogfooding only catches when it fails catastrophically.

They were moved here from `docs/plans/` because a Job-B (live, attended,
snapshot-in-time) artifact left under `docs/plans/` *looks* like a Job-A
(every-commit, CI, deterministic) asset, so agents either run it as gospel
(it's stale) or it rots. Keeping them in a clearly-labeled `evals/` directory
removes that ambiguity. See the memory anchor `canary-job-a-b-equivocation`
and the `docs/reports/skill-coverage-ledger-2026-05-28.md` disposition map.

## What's here

| Eval | Validates | How to run |
|---|---|---|
| `CANARY11_SCOPE_VIOLATION.md` | `/verify-changes` reviewer CATCHES a deliberate over-reaching commit (scope-vs-plan judgment). Bash mechanism is locked by `tests/test-scope-halt.sh`; this evaluates the LLM layer above it. | Manually, with `CANARY11_TEST_PLAN.md` as the synthetic input plan |
| `CANARY11_TEST_PLAN.md` | Synthetic narrow one-file plan used as input for the CANARY11 eval. | Input fixture — not run standalone |
| `REBASE_CONFLICT_CANARY.md` | `/run-plan` Phase-6 agent-assisted intelligent rebase-conflict merge (the ≤5-files "read both sides and merge intelligently" branch + abort fallback). Mechanical rebase paths are covered by `test-land-pr-auto-rebase-behind.sh` + `test-land-pr-rebase-rc14-parser.sh`; this evaluates the judgment branch. | Manually, two-session |

## What is NOT here

Deterministic-surface canaries belong in `tests/` as shell smokes (Layer 1).
Integration reality is measured via dogfooding (Layer 2). Do not add markdown
canaries that *could* be a shell test — convert them instead.
