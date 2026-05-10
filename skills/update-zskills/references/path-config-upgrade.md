# Agent Upgrade Prompt — Path Config Long Tail

Run this after `/update-zskills --migrate-paths` if the migration printed
a "see path-config-upgrade.md" notice for `start-dev.sh` / `stop-dev.sh`
or for plan files that were skipped (e.g., `status: complete` non-canary
plans containing executable references).

Tasks:

1. **Update `scripts/start-dev.sh`.** Read the file. If it writes to
   `var/dev.pid` or `var/dev.log`, propose a diff swapping those paths
   to `.zskills/dev-server.pid` and `.zskills/dev-server.log`
   respectively.

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])var/dev\.(pid|log) reason: Phase 5b upgrade prompt names the legacy var/ paths that customized start-dev.sh / stop-dev.sh stubs reference -->
   ```bash
   # Before:  echo $$ > var/dev.pid
   # After:   echo $$ > .zskills/dev-server.pid
   ```

   If you see customization beyond the shipped defaults, surface the diff
   and ask the user before editing.

2. **Update `scripts/stop-dev.sh`.** Same pattern as task 1; the PID-read
   path moves identically (`var/dev.pid` → `.zskills/dev-server.pid`).

3. **Audit preserved-token list at `.zskills/audit/migration-warnings.md`.**
   `migrate-paths.sh` writes this file (when present, with a markdown H1
   header) to enumerate every legacy `plans/X.md` or `reports/Y.md` token
   it preserved in frozen `status: complete` non-canary plans. Read each
   entry, decide per-token whether the reference should be manually
   upgraded to the new location, propose diffs, ask the user before
   applying. Also re-scan active plan files (`status: active` or
   `proposal`) for any shell commands referencing legacy paths the
   cross-ref rewrite missed (e.g., absolute-path forms like
   `$MAIN_ROOT/plans/...` — those are flagged in the same warnings file).

4. **Mid-version-skip recovery.** If `.pre-paths-migration` already
   exists AND the `migrate-paths.sh` script has been updated to include
   cross-ref rewrite (verify by
   `grep -c "cross_ref_rewrite" .claude/skills/update-zskills/scripts/migrate-paths.sh`
   returns ≥1), the migration ran under an OLDER 5a-only version and the
   cross-ref rewrites for in-tree plan files were never applied. Apply
   them now:

   <!-- allow-hardcoded: re:plans/ re:.zskills reason: Phase 5b upgrade prompt names the migrate-paths --rewrite-only invocation that backfills cross-references after a mid-version skip -->
   ```bash
   bash .claude/skills/update-zskills/scripts/migrate-paths.sh \
     --rewrite-only "$MAIN_ROOT"
   ```

   The `--rewrite-only` flag is added in 5b.1 to support this path. It
   skips file-move steps 1–7 entirely, resolves `<TARGET_PLANS>` from the
   existing config's `output.plans_dir`, and runs ONLY the cross-ref
   rewrite. Idempotent: re-running against an already-rewritten tree
   appends a trailer line to `.pre-paths-migration` but does not modify
   plan content.

5. **Re-run tests.** Run `bash tests/run-all.sh` (or your project's test
   command) and verify everything passes.
