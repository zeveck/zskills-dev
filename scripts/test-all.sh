#!/bin/bash
# test-all.sh -- Run all test suites (unit + e2e + build).
#
# CONFIGURE: replace the body below with your test runner.
# zskills skills (run-plan, verify-changes) invoke this when
# `testing.full_cmd` resolves to `bash scripts/test-all.sh`.
#
# See .claude/skills/update-zskills/references/stub-callouts.md
# for the contract; typical implementations orchestrate unit +
# e2e + build (read testing.unit_cmd from
# .claude/zskills-config.json, derive a dev-server port,
# run e2e if the port is up, etc.). git history preserves
# the prior shipped orchestrator if you want a starting
# point.

echo "test-all.sh: not configured. Edit scripts/test-all.sh with your test runner. See .claude/skills/update-zskills/references/stub-callouts.md." >&2
exit 1
