# QE Issues Tracker

> **DEPRECATED (2026-05-27, #685).** This markdown tracker is no longer
> maintained. GitHub issues filed by `/qe-audit` are the live durable
> record — query via `gh issue list --label qe-audit --state all` (or
> without the label filter if QE issues are unlabeled). This file is
> preserved as a historical reference for the 2026-05-15 seed audit only.

Issues filed by `/qe-audit` from commit audits and bash sessions. Open issues
list current findings; resolved issues archived below as a record of what
QE caught.

## Open Issues

### From 2026-05-15 audit (commits c1b0962..338017f)

- **#279** — `block-bypassed-land-pr`: 4 remaining prefix-flag bypass forms
  (`time -v`, `timeout --foreground`, `nohup --`, `command -p`). Source:
  9838431 (PR #255). Severity: Low (security-class).
- **#280** — `/fix-issues sync`: gh-JSON title parser corrupts on escaped
  quotes. Source: c5c928c (PR #269). Severity: Medium.
- **#281** — Dashboard worktree-path-asymmetry between POST and GET
  (Phase 5c deferred follow-up never filed). Source: 432295c (PR #253).
  Severity: Medium.
- **#282** — `/fix-issues` d6c39b0: success-set includes `created` —
  still closes issues with unmerged PR. Source: d6c39b0 (PR #271).
  Severity: Medium.
- **#283** — Dashboard `collect.py`: new aggregation logic (`_scan_git_history`,
  `_extract_pr_numbers_from_markers`, `_derive_repo_url`) shipped without
  targeted unit tests + dead `activity` arg on
  `_extract_pr_numbers_from_markers`. Source: 338017f, 2fae31a (PRs #274, #277).
  Severity: Low.
- **#284** — `/fix-issues` c5c928c: new bootstrap + row-writer + `/land-pr`
  dispatch paths lack fixture tests. Source: c5c928c (PR #269).
  Severity: Medium.

## Notable positives from this audit

- **712eae8** — `/run-plan` REMAINING_PHASES regex tightening: exemplary
  contrast-asserting fixture (tight + loose pattern against same fixture,
  count differential asserted) + source-pattern sentinel.
- **7799484** — Dashboard PID-file self-heal SIGTERM fix: tight fix with
  realistic regression test exercising the actual race.
- **0aedaf9** — `/quickfix` case-pattern widening: paired test case + grep
  conformance update.
- **9a87382** — `/land-pr` Step 7b FF-local-main: 4 explicit skip
  conditions, 11-case fixture coverage over 4 states, conformance sentinel.
- **c1b0962** — Worktree-gate preamble: canary E/I surfaced AND fixed a
  bash absolute-vs-relative path bug in the same commit ("tests prove the
  fix" — textbook discipline).
- **25d28e6** — `/quickfix` trap → explicit-finalize: high-value fix for
  a real tracking-marker correctness bug (every prior `/quickfix` stamped
  `status: complete` near-immediately regardless of outcome) + Case 58
  regression guard with site-count assertion.

## Resolved Issues

_(none yet)_

---

*Last audited: 2026-05-15 — commits c1b0962 through 338017f*
