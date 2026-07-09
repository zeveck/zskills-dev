# Plan Report — General Claude→Codex porting capability

## Phase — 3 Construct scanner, converters, AGENTS.md renderer wrapper

**Plan:** docs/plans/CODEX_PORT_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-codex-port-plan
**Branch:** feat/codex-port-plan
**Commit:** 17a69aa2

### Work Items
| # | Item | Status |
|---|------|--------|
| 3.1 | `codex-scan.py` (488) — 10-class v1 DATA table (verifier: exact match vs the normative reference), fence+prose scanning, discover/gate, extension-dispatched allow-markers, root-only meta-record exemption | Done |
| 3.2 | `codex-scan-gate.sh` (194) — pinned CLI, fail-closed, census floors derived+checked over the same skills/ scope (all >0, ≤50% observed) | Done |
| 3.3 | `agents-to-toml.py` (211) — TOML conversion, tools:/hooks: degradations section | Done |
| 3.4 | `hooks-translate.py` (191) — alias/native plugin-root styles, 3 substrate drops each with reason, trust-review note | Done |
| 3.5 | `render-agents-md.sh` (118) — D24 wrapper (zero forked logic; byte-identical pass-through proven), 32 KiB dual-delivery check | Done |
| 3.6 | `test-porting-scanner.sh` (35 checks) + `test-porting-converters.sh` (21 checks) with all enumerated cases incl. NOTES.md counter-case + live census | Done |
| 3.7 | Drift-gate consumer registrations (124/124); allow-hardcoded markers confirmed unneeded (conformance 841/841) | Done |

### Verification
- Verifier: fresh agent, PASS; Layer-3 validation exit 0. Class table diffed against the plan's normative reference: exact match. Both converters re-run by the verifier against the real `agents/verifier.md` / `hooks/hooks.json`.
- Live-tree discover (AC-quoted): `CODEX-SCAN-SUMMARY: files=129 hits=1645 violations=0 unknown=27 per-class=cron:107,agent-dispatch:60,bg-monitor:18,skill-tool:29,arguments:162,ask-user:9,plugin-root:819,project-dir:415,frontmatter-flags:18,claude-model-dispatch:8` — every class > 0.
- unknown=27 spot-checked: all genuine unclassified Claude constructs (24× `CLAUDE_TEMPLATE` references, 3× `CLAUDE_CODE_SESSION_ID`); no false tokenization; the designed self-amendment path (Phase 4) covers them.
- Test suite fresh: **Overall: 8447/8447 passed, 0 failed** (baseline 8389; +58 fully attributed).
- All 9 ACs run literally and passed (marker cases `allow-md` / `allow-sh` both suppress and un-suppress).

### Plan-text drift
- None (the reference table's live-tree scale column is explicitly "context, NOT frozen expectations").

## Phase — 2 Runner behavioral matrix: happy / failures / every suites

**Plan:** docs/plans/CODEX_PORT_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-codex-port-plan
**Branch:** feat/codex-port-plan
**Commit:** e11492a2

### Work Items
| # | Item | Status |
|---|------|--------|
| 2.1 | `tests/test-porting-runner-happy.sh` — 8 cases (mid-run-stop exits 31 BEFORE chunk 2; no resume token in finish-auto argv; streaming; env export end-to-end) | Done |
| 2.2 | `tests/test-porting-runner-failures.sh` — 20 cases (full taxonomy 20–26/30/124/125; rc-26 forensics `child_raw_rc=7` quoted; stderr-reason discipline sweep with coverage assertion) | Done |
| 2.3 | `tests/test-porting-runner-every.sh` — 8 cases (session-lost exit 32 with argv proof of no silent fresh exec; parse_schedule matrix; next-output contract) | Done |
| 2.4 | Three `run_suite` registrations (total four `test-porting-runner-*`) | Done |

### Matrix-discovered Phase-1 fixes (in-scope per D&C; each adversarially adjudicated SPEC-CONSISTENT by the verifier)
1. Removed the stale-stop-marker preflight refusal (never spec-pinned; contradicted STOP-IN-LOOP and WI 2.3's pinned behavior; direct-unattended coverage retained; unedited preflight suite still 27/27).
2. `ZSKILLS_RUNNER_SCHEDULE_SECONDS` test override (single use site, post-validation — cannot smuggle production behavior).
3. `schedule_seconds=` in dry-run resolved output (additive; makes the parse matrix assertable).
4. Validation-ladder reorder: dirty-artifacts (25) before gate (24) — code 25 was unreachable under spec order; taxonomy is normative.
5. Per-rung authoritative `runner_stop_reason` values (the reason line is the authoritative stop classification).
6. `last_verdict` carry in every-mode (fixes `next`'s last-verdict contract).
7. fake-codex `env.log` (additive observability).
8. fake-codex `premature-final` fixture fix — the premature-final rung was previously unreachable; now genuinely tested.

### Verification
- Verifier: fresh agent, PASS; Layer-3 validation exit 0. Every enumerated case ticked against actual test code; all 8 fixes judged with code evidence (none test-weakening).
- Test suite fresh: **Overall: 8389/8389 passed, 0 failed**; baseline 8353; +36 exactly the new cases. Suite runtimes 17s/26s/39s.
- All ACs run literally: three self-derived `Results:` lines green; registration grep = 4; five named novel classes grep-hit; rc-26 raw child rc cited (7).

### Plan-text drift
- 2 advisory tokens (impl + verifier), both against the "Scale expectation (not a gate)" bullet (1,307 total suite lines vs ~1,000–1,200) — non-AC, non-derivable form; no correction.

## Phase — 1 Unified runner + gate + invariants + fake-codex + preflight suite

**Plan:** docs/plans/CODEX_PORT_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-codex-port-plan
**Branch:** feat/codex-port-plan
**Commit:** 9c3e3893

### Work Items
| # | Item | Status |
|---|------|--------|
| 1.1 | `scripts/porting/zskills-runner.sh` (2,039 lines) — both modes, ALL 15 named spec changes verifier-audited, code-26 mapping, streaming pumper, inlined claims, every-mode session persistence, child prompt template byte-identical to spec after substitution | Done |
| 1.2 | `scripts/porting/zskills-gate.sh` (295) — GATE-UNIFY four modes, read-only verified (zero mutations in code) | Done |
| 1.3 | `scripts/porting/post-run-invariants-codex.sh` (277) — re-fork of the 235-line upstream; diff shows only the `--base-branch/--remote/--report` parametrization, dual-read preserved | Done |
| 1.4 | `tests/mocks/fake-codex.sh` (574) — 21-mode failure matrix incl. `mid-run-stop` + `pr-wrong-tracking`; probe-id anchors verified against Phase 0 registry | Done |
| 1.5 | `tests/test-porting-runner-preflight.sh` — 27 enumerated refusal/purity cases, count self-derived, registered | Done |
| 1.6 | `run_suite` registration + runner/gate in `RESOLVE_PYTHON_CONSUMERS`; inlined resolvers byte-match `hooks/_lib/resolve-python.sh` | Done |

### Verification
- Verifier: fresh agent, verdict PASS; Layer-3 response validation exit 0. Salvage from the fork clones was used per Design & Constraints; shipped scripts confirmed self-contained (no scratchpad-path references).
- Verifier made one in-review fix: the no-args exit path was missing the `runner_stop_reason` stderr line (the runner's own "every terminal exit" contract) — 3 lines added, behavior re-verified, full suite re-run post-fix.
- Test suite (fresh, twice — pre- and post-fix): `bash tests/run-all.sh` → **Overall: 8353/8353 passed, 0 failed** (223 suites). Baseline 8324/8324; +29 fully attributed (+27 new preflight cases, +2 drift-gate consumers). No regressions.
- All 7 AC commands run literally and passed (help grammars + 13-row exit table; dry-run purity with zero fixture mutations; dangerous `--codex-arg` rc=2 naming the flag; suite 27/27 self-derived; registration grep = 1; `fake-codex-fail-fast-99` rc=99).
- Runner size 2,039 vs the plan's ~1,150–1,350 estimate: explicitly "not a gate"; verifier judged the overage spec-mandated (every-mode, claims, schema cross-check, no-jq Python heredocs) with no dead code or duplication.

### Plan-text drift
- Implementer emitted 4 advisory tokens, all against the Design & Constraints "Scale expectation (not a gate)" bullet — non-AC, non-derivable form; no correction. Verifier independently re-measured: zero AC drift (the "235 lines at draft time" claim re-measured exact).

### Notes
- Hook signal surfaced by the verifier: `config_hooks_tamper` denied an inline write of a throwaway `$TMPDIR` fixture `zskills-config.json` (basename match fires outside the repo config path). Fail-safe direction, but a possible false-positive class for test fixtures — tracked as issue #1190.

## Phase — 0 Real-Codex probe kit, scripts/porting/ bootstrap, literal-scan widening

**Plan:** docs/plans/CODEX_PORT_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-codex-port-plan
**Branch:** feat/codex-port-plan
**Commit:** 222c0d15

### Work Items
| # | Item | Status |
|---|------|--------|
| 0.1 | `scripts/porting/codex-probe.sh` (self-contained, BSD/MSYS-safe, `--list`/`--out`/`--only`/`--validate`, probe-RUN codex resolution, atomic write) | Done |
| 0.2 | Probe registry — exactly the 25 pinned ids, per-id `asserts` (16 plan-pinned assertions transcribed), `load_bearing` flags, trust-establishment ordering | Done |
| 0.3 | Results schema `zskills-codex-probe/v1` + `--validate` enforcement + SAMPLE fixture at `tests/fixtures/porting/probe-results-sample.json` | Done |
| 0.4 | EXT_FILES widening (`scripts/porting` `*.sh` + `*.py`) in `tests/test-skill-conformance.sh` — zero allow-hardcoded markers needed | Done |
| 0.5 | `tests/test-porting-probe-kit.sh` (27 checks, hermetic absent-codex refusal, fake-codex honesty run) registered via `run_suite` | Done |
| 0.6 | `codex-probe.sh` in `RESOLVE_PYTHON_CONSUMERS` (`tests/test-hook-helper-drift.sh`, 120/120) | Done |
| 0.7 | ATTENDED (owner, non-gating): run probe on real-Codex machine — **ATTENDED-PENDING #1189** | Pending (owner) |

### Verification
- Verifier: fresh agent, verdict PASS; Layer-3 response validation exit 0.
- Test suite: `bash tests/run-all.sh` (full, fresh — diff touches `tests/`, provenance reuse not permitted) → **Overall: 8324/8324 passed, 0 failed** (223 suites). New suite `test-porting-probe-kit.sh` 27/27; `test-hook-helper-drift.sh` 120/120; `test-skill-conformance.sh` 841/841.
- Baseline reconciliation vs 8300/8300: +27 new suite, +1 drift consumer, −4 attended-gated environmental skips in `test-plugin-live-load.sh` (0 failed in both runs; suite untouched by this diff).
- All 8 acceptance-criteria commands run literally and passed (registry count 25 with matching stderr header; absent-codex refusal exact string + rc=1 + no file; `--validate` OK and names deleted id on mutation; widened find lines present; one `run_suite` line; drift consumer registered).
- Scope: exactly 6 paths changed; no `skills/**`, `hooks/**`, `agents/**`, `.claude/**` edits; `docs/porting/probe-results.json` correctly NOT created (honest Phase 4 gate signal).

### Plan-text drift
- 1 token emitted (implementer): WI 0.4 line-anchor `≈L2806-2811` vs measured `L2807-2812` — non-derivable form (Work-Item line anchor, not an AC numeric; token bullet id `0.4` rejected by the parse grammar). Content-located anchor; edit unaffected; no plan correction made. Verifier independently re-measured all AC numerics: zero drift.
- Advisory (non-numeric): WI 0.2's `load_bearing` prose ("every id named in Phase 4's triage table") is vacuous under a wildcard reading; implementer used the self-consistent 16-pinned-assertions reading. Phase 4's dispatch should restate the intended triage set.

### Attended residue
- **ATTENDED-PENDING:** owner probe run (WI 0.7) — issue #1189 carries the branch protocol. Phase 4 gates on `docs/porting/probe-results.json` reaching `feat/codex-port-plan`; the finish-auto pipeline will Failure-Protocol STOP at the Phase 3→4 boundary if still absent.
