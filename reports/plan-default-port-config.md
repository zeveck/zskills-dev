# Plan Report — Default Port Config

## Phase — 5 Documentation surfaces [UNFINALIZED]

**Plan:** plans/DEFAULT_PORT_CONFIG.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-default-port-config (PR mode, branch `feat/default-port-config`)
**Commits:** 0b0c1d6

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 5.1 | Replace `localhost:8080/...` with `localhost:<port>/...` in `skills/briefing/SKILL.md` (3 sites: lines 141, 151, 158) | Done | Matches existing `<port>` convention at line 133 |
| 5.2 | Reword `skills/manual-testing/SKILL.md` line 23 comment to reference `dev_server.default_port` and dev-port.sh stub | Done | Plan said line 18; SKILL_FILE_DRIFT_FIX (#122) shifted it to 23 (same comment text) |
| 5.3 | Mirror to `.claude/skills/briefing/` and `.claude/skills/manual-testing/` | Done | `diff -rq` empty for both |

### Verification

- **Test suite:** 1348/1348 passed (no change — Phase 5 adds no new tests).
- **Acceptance criteria:** All 5 ACs verified by independent fresh-eyes verifier.
- **Mirror:** byte-identical between source and `.claude/skills/...`.
- **Plan's "What's out" exclusions confirmed**: tests/test-hooks.sh (still has 16 `8080` deny-pattern test cases), tests/test-port.sh (still has 8 `8080` literal references), CLAUDE.md (still has 1 HTML-commented `8080` aside) — all left alone as documented.

### Plan-text drift (informational)

- `phase=5 bullet=5.2 field=line plan=18 actual=23` — cosmetic. SKILL_FILE_DRIFT_FIX added `zskills-resolve-config.sh` prelude to the dev-server-startup section, shifting the target comment down 5 lines. Same comment text; edit applied as written.

## Phase — 4 briefing.py / briefing.cjs path-fix + drop literal + omit-URL on failure [UNFINALIZED]

**Plan:** plans/DEFAULT_PORT_CONFIG.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-default-port-config (PR mode, branch `feat/default-port-config`)
**Commits:** 623f6df

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.0 | Fix port.sh path lookup BEFORE removing fallback (load-bearing ordering) | Done | `'.claude', 'skills', 'update-zskills', 'scripts', 'port.sh'` at briefing.py:808, 1122 and briefing.cjs:714, 1092 |
| 4.1 | Drop `'8080'` literal in briefing.py at 4 sites; emit no URL when port is None | Done | `port = None` initializer; URL emission gated; comments rewritten |
| 4.2 | Same in briefing.cjs at 4 sites with `null` | Done | symmetric Python ↔ JS edits |
| 4.3 | Invariant comment at top of both files | Done | briefing.py:19-22 (#), briefing.cjs:15-18 (//) |
| 4.4 | Extend `tests/test-briefing-parity.sh` with port-failure parity cases | Done | 5 new tests; literal fixture path `/tmp/zskills-briefing-fixture-noport`; both run exit 0, no `localhost:` URL, byte-equivalent output |
| 4.5 | Mirror to `.claude/skills/briefing/` | Done | `bash scripts/mirror-skill.sh briefing`; `diff -rq` empty |

### Verification

- **Test suite:** 1348/1348 passed, 0 failed (baseline 1343/1343 + 5 new parity-test cases).
- **Acceptance criteria:** All 11 ACs verified by independent fresh-eyes verifier.
- **Mirror:** byte-identical between source and `.claude/skills/...` copy for both briefing.py and briefing.cjs.
- **Hash file:** `tier1-shipped-hashes.txt` updated with new briefing.py (`5d799f0…`) and briefing.cjs (`09e579c1…`) blob hashes — satisfies test-update-zskills-migration case 6c (commit-cohabitation invariant).

### Spec deviations

- **WI 4.0 ordering preserved.** Path fix applied alongside fallback removal in the same staged diff; both edits coexist coherently. (The plan calls out load-bearing ordering for landing sequencing; in this single-commit context, both edits are atomic.)

### Plan-text drift (informational)

- `phase=4 bullet=AC field=grep-substring-conflict plan='scripts', 'port.sh' grep returns 0 actual=2`. The acceptance criterion `grep -c "'scripts', 'port.sh'" briefing.py = 0` is unsatisfiable post-WI-4.0 because the new mandated path `'.claude', 'skills', 'update-zskills', 'scripts', 'port.sh'` contains `'scripts', 'port.sh'` as a tail substring. The redundant canonical AC `grep -c "scripts/port.sh" = 0` (the actual anti-stale check) does pass. Verifier independently confirmed: AC intent (no old-path remnants) is satisfied; the conflicting AC literal is a spec authoring oversight.

## Phase — 3 Template prose refinement + Step B placeholder mapping [UNFINALIZED]

**Plan:** plans/DEFAULT_PORT_CONFIG.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-default-port-config (PR mode, branch `feat/default-port-config`)
**Commits:** f85a546

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | Refine `CLAUDE_TEMPLATE.md:22` dev-server prose | Done | Substitutes `{{DEFAULT_PORT}}` + acknowledges dev-port.sh stub override |
| 3.2 | Add `{{DEFAULT_PORT}}` and `{{MAIN_REPO_PATH}}` rows to placeholder mapping in `skills/update-zskills/SKILL.md` | Done | `{{MAIN_REPO_PATH}}` was an active shipping bug |
| 3.3 | Verify Step B substitution picks up new rows | Done | Documentation-only |
| 3.4 | Reconcile SKILL.md runtime-read-fields prose | Done | `main_repo_path` and `default_port` now documented as dual runtime-read + install-substituted |
| 3.5 | Mirror `.claude/skills/update-zskills/SKILL.md` (cp `.claude/CLAUDE_TEMPLATE.md` skipped — no .claude/ template existed) | Done | `diff -rq` empty |
| 3.6 | Extend `tests/test-update-zskills-rerender.sh` with placeholder substitution end-to-end cases | Done (extended, not created — file existed post-rebase from SKILL_FILE_DRIFT_FIX) | Test 7 with 6 cases (7a-7f) |

### Verification

- **Test suite:** 1343/1343 passed (baseline 1337/1337 + 6 new Test 7 cases). Independent fresh-eyes verifier confirmed all 8 ACs.
- **Mirror:** `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- **Conformance reconciliation:** see Spec deviations.

### Spec deviations (verified, intentional)

- **`tests/test-skill-conformance.sh` updated** (NOT in original Phase 3 plan). SKILL_FILE_DRIFT_FIX (#122) introduced two conformance assertions encoding the OLD prose: (a) negative-grep on `(UNIT_TEST_CMD|FULL_TEST_CMD|UI_FILE_PATTERNS|MAIN_REPO_PATH)` placeholder mapping rows; (b) literal `'Runtime-read fields (not install-filled)'`. Phase 3.2 + 3.4 explicitly invert both. Reconciled to lock in the post-Phase-3 contract: dropped `MAIN_REPO_PATH` only from the negative-grep; updated literal to the new wording. Verifier independently confirmed not test-weakening — both assertions still LOCK IN the new contract.

### Plan-text drift (informational)

- `phase=3 bullet=3.4 field=line_number plan=326 actual=325` — cosmetic. Confirmed.
- `phase=3 bullet=3.2 field=line_range plan=319-324 actual=318-323` — cosmetic. Confirmed.

## Phase — P1.A CHANGELOG correction + greenfield port_script template removal [UNFINALIZED]

**Plan:** plans/DEFAULT_PORT_CONFIG.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-default-port-config (PR mode, branch `feat/default-port-config`)
**Commits:** b66bbc5

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| P1.A.1 | Correct `CHANGELOG.md` aspirational backfill claim | Done | New entry: backfill is "tracked as future work"; fail-loud diagnostic mentioned |
| P1.A.2 | Remove `"port_script": ""` from greenfield install template at `skills/update-zskills/SKILL.md:282` | Done | Strip-legacy block at line 1080-area preserved (still needed for old consumer configs) |
| P1.A.3 | Mirror to `.claude/skills/update-zskills/SKILL.md` | Done | `diff -rq skills/update-zskills .claude/skills/update-zskills` empty |

### Verification

- **Test suite:** 1275/1275 passed, 0 failed (no change from post-rebase baseline; this phase touches only docs/template).
- **Acceptance criteria:** All 4 ACs verified by separate verification agent.
- **Mirror:** byte-identical between source and `.claude/skills/...` copy.

### Spec deviations

None.

### Notes

Phase P1.A's footprint is documentation + greenfield-template only. No tests added because both files are non-runtime artifacts. Backfill into existing configs remains future work (captured in plan's Out of Scope and now in CHANGELOG).

## Phase — 2 port.sh runtime-read tightening + fail-loud + fixture isolation [UNFINALIZED]

**Plan:** plans/DEFAULT_PORT_CONFIG.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-default-port-config (PR mode, branch `feat/default-port-config`)
**Commits:** cbccfe1

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | Tighten regex `[^}]*` → `[^{}]*` (port.sh:38 area, now line 41) | Done | Tight pattern refuses nested-object traversal |
| 2.2 | Add `PROJECT_ROOT` env override (port.sh:18 area, now line 21) | Done | Mirrors existing REPO_ROOT override |
| 2.3 | Remove `DEFAULT_PORT=8080` literal; add fail-loud guard (main-repo branch only) | Done | Fail-loud emits resolved absolute config path; `unset _ZSK_REPO_ROOT _ZSK_CFG` moved after main-repo branch |
| 2.4 | Append precedence comment to header doc-comment | Done | Documents `DEV_PORT env -> dev-port.sh stub -> dev_server.default_port -> worktree-hash` |
| 2.5 | Three fixture-based test cases in `tests/test-port.sh` | Done (with spec deviation) | See "Spec deviations" below |
| 2.6 | Mirror to `.claude/skills/update-zskills/scripts/port.sh` via `scripts/mirror-skill.sh` | Done | `diff -rq skills/update-zskills .claude/skills/update-zskills` empty |

### Verification

- **Test suite:** 1216/1216 passed, 0 failed (baseline 1213/1213 + 3 new fixture cases). Output at `/tmp/zskills-tests/zskills-pr-default-port-config/.test-results.txt`.
- **Acceptance criteria:** All 10 ACs verified by separate verification agent (independent fresh-eyes review). Two ACs noted plan/actual mismatches recorded as advisory drift tokens (line numbers shifted +3 due to WI 2.4's added comment block; AC2's grep regex literal needed escaped-quote shape). No regressions.
- **Mirror:** byte-identical between source and `.claude/skills/...` copy.
- **Worktree state:** clean after commit; `.zskills-tracked` and `.worktreepurpose` untracked (correct).

### Spec deviations (verified, intentional)

- **WI 2.5 third fixture (nested-only `default_port`):** the plan-text fixture put `"limits": {"default_port": 9999}` BEFORE `"main_repo_path"`. Under the still-loose `main_repo_path` regex `[^}]*`, the inner `}` of `limits` blocks `main_repo_path` from being matched at the outer level → `MAIN_REPO=""` → script falls through to worktree-hash branch and exits 0 — contradicting the plan's `[[ $rc -ne 0 ]]` assertion. The implementer inverted the JSON field order (`main_repo_path` first, then nested `limits`). This preserves the plan's stated INTENT ("default_port appears only inside nested 'limits' object → tight regex must NOT match") while making the test mechanically work. Verifier independently confirmed: plan's order produces port=14688 (worktree-hash), not fail-loud; implementer's order correctly fail-louds. Comment in `tests/test-port.sh` documents the rationale inline.

### Plan-text drift (informational)

Four advisory tokens emitted by the agents and independently confirmed by the verifier; none qualify for Phase 3.5 auto-correction (drift parser only handles 1-indexed AC bullets with positive-integer ordinals, not WI numbers like `2.5` / `AC2`). Recorded here for future plan refinement:

- `phase=2 bullet=2.2 field=line-number plan=18 actual=21` — WI 2.4's appended precedence comment shifted later assignments down by 3 lines.
- `phase=2 bullet=AC3 field=line-number plan=18 actual=21` — same cause.
- `phase=2 bullet=AC2 field=grep-regex-quote-shape` — port.sh's regex inside `[[ =~ ]]` uses backslash-escaped quotes (`\"default_port\"`); AC's literal grep pattern with bare quotes produces a false-negative. Use escaped-quote form to verify.
- `phase=2 bullet=2.5 field=fixture-json-order` — recorded above under Spec deviations.

These do NOT block downstream phases. The line-number drift is purely cosmetic; AC2's grep-shape mismatch is verifier-side procedural; the JSON-order issue was resolved in-flight without touching the spec.
