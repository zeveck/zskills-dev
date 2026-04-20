# Plan Report — /create-worktree Skill (Unify Worktree Creation)

## Phase — 2 Migrate /run-plan (both modes) (landed; CANARY10 gate PASSED ✅)

**Plan:** plans/CREATE_WORKTREE_SKILL.md
**Status:** Landed on main; CANARY10 re-run passed all 9 checks (PR #37 → squash `773b2c3`); Phase 2 closed
**CANARY10 gate verdict:** PASSED — PR merged cleanly, CI 10s, remote branch auto-deleted, local main FF, no divergence
**Worktree:** /tmp/zskills-cp-create-worktree-skill-phase-2 (cleaned up)
**Branch:** cp-create-worktree-skill-2 (deleted)
**Worktree commits:** 8fc406c, 67aa8e9
**Main commits:** 27d5243 (`refactor(run-plan): migrate cherry-pick site to scripts/create-worktree.sh`), 021226a (`refactor(run-plan): migrate PR site + remove stale worktreepurpose echo`)
**Post-cherry-pick tests:** run-all 594/594 after each commit

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 2.1 | Cherry-pick site at `:608` → create-worktree.sh `--prefix cp` | Done | 27d5243 |
| 2.2 | PR site at `:819` → create-worktree.sh `--prefix pr --branch-name "$BRANCH_NAME" --allow-resume` | Done | 021226a |
| 2.3 | Remove dead pre-flight + inline `.zskills-tracked` echo at both sites | Done | both commits |
| 2.4 | Delete stale agent-side `.worktreepurpose` echo at `:635-639` | Done | 021226a |
| 2.5 | Mirror `.claude/skills/run-plan/` | Done | both commits (mirror invariant requires per-commit) |
| 2.6 | Verification greps clean | Done | grep `git worktree add` = 0; `worktree-add-safe.sh` = 0; `create-worktree.sh` ≥ 2 |
| 2.7 | `bash tests/run-all.sh` green | Done | 594/594 after each commit |
| 2.8 | **Manual CANARY10 re-run** | **Pending** | gate — orchestrator runs `/run-plan plans/CANARY10_PR_MODE.md finish auto pr` |
| 2.9 | Throwaway-plan smoke (cherry-pick) | Deferred | implementer can't self-invoke `/run-plan` from inside a worktree; orchestrator runs after landing |

### Verification (verifier 0e7a834-equivalent agent)
- All 8 acceptance criteria PASS
- 594/594 run-all + 86/86 conformance
- Hygiene clean; no leaked worktrees/branches
- 8 judgment calls evaluated; all ACCEPT (the most consequential: `--branch-name "$BRANCH_NAME"` added to PR-mode call to preserve `${BRANCH_PREFIX}${PLAN_SLUG}` — without it, the literal plan example would have changed PR branches from `feat/<slug>` to `pr-<slug>`, silently breaking existing users)

### Implementer judgment calls (verifier accepted all)
1. **`--branch-name "$BRANCH_NAME"` in PR-mode** — preserves `${BRANCH_PREFIX}${PLAN_SLUG}` (default `feat/<slug>`); plan literal would have changed branch to `pr-<slug>`. Same decoupling pattern as Phase 3 WI 3.1.
2. **Mirror in BOTH commits** — `tests/test-skill-invariants.sh:99-103` enforces per-commit mirror-sync. Deferring to C2 would regress mid-phase tests.
3. **Conformance test updates in `tests/test-skill-conformance.sh`** — old literals (`worktree-add-safe.sh`, `cp-${PLAN_SLUG}`, `ZSKILLS_ALLOW_BRANCH_RESUME=1`) replaced with new-form anchors (`--prefix cp`, `bash "$MAIN_ROOT/scripts/create-worktree.sh"`, `--allow-resume`). Equivalent regression coverage; not test weakening.
4. **AWK formula bug** — plan's acceptance #4 awk range matches start+end on same line, returns 0; sed-scoped `576,752p` shows count dropped 4 → 2 as intended.
5. **PR-mode "Pipeline association" `.zskills-tracked` echo block at old `:843-847` removed** — within WI 2.3 ("dead code at each site"); redundant with create-worktree.sh's tracked-file write.
6. **Orchestrator commit-discipline block at `:700-704` left untouched** — describes the contract (write `.zskills-tracked` before dispatching agents), not creating a worktree. Carve-out defensible; minor doc trim opportunity for Phase 4.

## Phase — 1b Full test suite + run-all + update-zskills registration (landed)

**Plan:** plans/CREATE_WORKTREE_SKILL.md
**Status:** Landed on main; 594/594 green
**Worktree:** /tmp/zskills-cp-create-worktree-skill-phase-1b (cleanup pending)
**Branch:** cp-create-worktree-skill-1b
**Worktree commit:** 0e7a834
**Main commit:** e257f25 (`test(create-worktree): extend smoke to 20 cases; register; update-zskills bullet`)
**Post-landing tests:** test-hooks 255/255; run-all 594/594

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| 1b.1 | Extend test to 20 cases | Done | tests/test-create-worktree.sh; per-PID slug isolation, EXIT trap cleanup, 1-13 summarized + 14-20 verbatim regression guards |
| 1b.2 | Register in tests/run-all.sh | Done | alphabetical between test-compute-cron-fire and test-skill-conformance |
| 1b.3 | Bullet in skills/update-zskills/SKILL.md | Done | line 452 alongside other shared-helper bullets |
| 1b.4 | Mirror update-zskills | Done | `diff -r` empty |

### Verification
- 5/5 acceptance criteria PASS
- `bash tests/test-create-worktree.sh` → 20/20
- `bash tests/run-all.sh` → 594/594 (test-hooks 255/255 baseline preserved)
- Manual probes: whitespace slug rc=5; slash-in-prefix rc=5 with `--branch-name` hint
- Hygiene: no ephemerals tracked or staged; no test residue (worktrees, branches) post-suite

### Phase 1a script gap closures (in-scope by spec anchor)
The implementer extended `scripts/create-worktree.sh` to close two gaps Phase 1a's 2-case smoke didn't catch:
1. **CWD-invariance:** `WT_PATH=$(cd "$MAIN_ROOT" && realpath -m "$RAW_PATH")` — Phase 1a Design statement requires path resolution to anchor on MAIN_ROOT. Required for case 17.
2. **TOCTOU remap broadened:** also remap when `refs/heads/${BRANCH}` exists post-collision (gated on `WAS_RC ∉ {3,4,5}`). Required for case 18 spec literal "rc=2 even when underlying returns 128".

Both gated against the Phase 1a Design + spec text; verifier judged scope-legitimate. 40 +/- lines of script delta.

### Implementer judgment calls (verifier accepted all)
1. Case 17 `--root` substituted to `../$PROJECT_NAME/cwdinv-root-…` because `/workspaces/` parent isn't writable in this env. Still proves CWD-invariance via `realpath -m` canonicalization from three different CWDs.
2. Case 19 rollback uses `git hash-object`+`mktree`+`commit-tree` plumbing to commit `.zskills-tracked/keep` subtree on a base branch, then `--from` checkout materializes the dir → `printf >` fails → rc=8.
3. Case 20 `--no-preflight` guard uses ephemeral `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url` instead of mutating shared `.git/config`.
4. Test `SCRIPT` resolution prefers worktree copy over MAIN_ROOT copy when newer (so in-flight changes are exercised).
5. `run-all.sh` insertion alphabetical within suite block; existing entries not reordered.

## Phase — 1a Ship scripts/create-worktree.sh + skill wrapper + smoke test (landed)

**Plan:** plans/CREATE_WORKTREE_SKILL.md
**Status:** Landed on main; tests green
**Worktree:** /tmp/zskills-cp-create-worktree-skill-phase-1a
**Branch:** cp-create-worktree-skill-1a (post-landing cleanup pending)
**Worktree commit:** 1a39c95
**Main commit:** 17c752f (`feat(create-worktree): ship script + skill wrapper + smoke test`)
**Post-landing tests:** test-hooks 255/255; test-create-worktree 2/2

### Work Items
| # | Item | Status | Code pointer |
|---|------|--------|--------------|
| 1a.1 | scripts/create-worktree.sh exists + executable + `set -eu` | Done | scripts/create-worktree.sh:1,26 |
| 1a.2 | Flag parser + slug validator (rc 5 on bad input, slash-in-prefix) | Done | scripts/create-worktree.sh:70-143 |
| 1a.3 | MAIN_ROOT pre-cd; install-integrity; non-empty PROJECT_NAME | Done | scripts/create-worktree.sh:33-54 |
| 1a.4 | Config reader for execution.worktree_root (no jq, /tmp default) | Done | scripts/create-worktree.sh:148-156 |
| 1a.5 | Path template (4 forms) | Done | scripts/create-worktree.sh:165-180 |
| 1a.6 | Branch resolution + main collision guard | Done | scripts/create-worktree.sh:185-197 |
| 1a.7 | Pre-flight prune/fetch/ff-merge w/ rc 6/7 | Done | scripts/create-worktree.sh:204-223 |
| 1a.8 | worktree-add-safe.sh wrap with conditional ZSKILLS_ALLOW_BRANCH_RESUME | Done | scripts/create-worktree.sh:228-236 |
| 1a.9 | TOCTOU rc=2 remap (verbatim form) | Done | scripts/create-worktree.sh:241-245 |
| 1a.10 | Sanitized PIPELINE_ID write; prefix-aware fallback | Done | scripts/create-worktree.sh:251-255 |
| 1a.11 | Post-create rollback + exit 8 | Done | scripts/create-worktree.sh:258-270 |
| 1a.12 | Single-line stdout; chatter on stderr | Done | scripts/create-worktree.sh:275 |
| 1a.13 | skills/create-worktree/SKILL.md (thin wrapper) | Done | skills/create-worktree/SKILL.md |
| 1a.14 | Mirror to .claude/skills/create-worktree/ | Done | `diff -r` empty |
| 1a.15 | Schema extension execution.worktree_root | Done | config/zskills-config.schema.json (lines 40-45) |
| 1a.16 | tests/test-create-worktree.sh — 2 cases; not in run-all | Done | tests/test-create-worktree.sh |

### Verification
- All 4 acceptance criteria PASS
- Exit-code probes: bad slug → rc 5; slash-in-prefix → rc 5 with `--branch-name` hint; unknown flag → rc 5; missing slug → rc 5
- Test-suite regression: baseline 255/255 → after 255/255 (no regressions)
- Smoke: `bash tests/test-create-worktree.sh` 2/2 PASS
- Hygiene: `git ls-files | grep -E '\.worktreepurpose|\.zskills-tracked|\.landed'` empty; staged set leak-free
- Six locked decisions all honored (script-first, --branch-name decoupling, --root option, scope, thin SKILL.md wrapper, decisions immutable)

### Implementer judgment calls
1. `git worktree prune` failure mapped to rc=5 (install/env family) — spec was silent on prune-fail.
2. Test case 2 pre-creates target dir to isolate rc=2 from branch-state classification.
3. Test resolves paths against MAIN_ROOT (mirror of script's own resolution); first attempt failed when test used worktree basename.
4. Test falls back to worktree-local script path when `$MAIN_ROOT/scripts/create-worktree.sh` doesn't exist (so smoke can validate code under review pre-landing).
