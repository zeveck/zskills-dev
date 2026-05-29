#!/bin/bash
# claim-self-reentry.sh — Ownership-aware self-re-entry decision for the
# twin claim primitives (claim-issue.sh / claim-plan.sh).
#
# Invoked ONLY on the already-exists (EEXIST) branch of cmd_acquire in
# either twin, as a bash SUBPROCESS — NEVER sourced for the decision (the
# exit 10 / exit 0 contract below would terminate a sourcing caller).
#
# Usage:
#   bash claim-self-reentry.sh <claim_dir> <caller_pipeline_id>
#
# Given an ABSOLUTE <claim_dir> (the caller has already resolved MAIN_ROOT
# via `git rev-parse --git-common-dir` parent — this helper does NOT
# re-resolve MAIN_ROOT, it operates on the path it is handed) and the
# caller's pipeline_id, decide whether the existing claim is the caller's
# OWN (self-re-entry → proceed) or another pipeline's (foreign → decline).
#
# Exit-code contract:
#   0  — self-re-entry: the existing claim's stored pipeline_id matches the
#        caller's; the caller already owns this claim and may proceed.
#   10 — foreign / never-steal: either claim.json is ABSENT (an in-flight
#        acquire window or a crashed-mkdir stub — not ours to claim), the
#        stored pipeline_id differs from the caller's, OR claim.json is
#        truncated/malformed (read yields empty → "" != caller → foreign).
#        Returned deterministically; NEVER a python traceback or non-10
#        exit on a malformed claim.json.
#   2  — usage error (wrong number of args).
#
# Logic (D3): if <claim_dir>/claim.json is absent → 10 (never steal). Else
# read the stored pipeline_id via Python stdlib json (NO jq) with a
# try/except → print('') reader captured into a shell variable (mirrors the
# release-style readers at claim-issue.sh / claim-plan.sh — NOT the bare
# json.load() in set-phase which raises on truncation). A truncated /
# half-written / malformed claim.json therefore yields an empty captured
# string → "" != caller → 10. Exit 0 iff the captured pipeline_id equals
# the caller's, else 10.

set -u

# ---------------------------------------------------------------------------
# Python interpreter resolution. Honours the project's documented
# ZSKILLS_PYTHON override (see CLAUDE.md "Python is required" section).
# ---------------------------------------------------------------------------
_CLAIM_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$_CLAIM_PYTHON" ]; then
  echo "claim-self-reentry.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 127
fi

claim_dir="${1:-}"
caller_pipeline_id="${2:-}"

if [ -z "$claim_dir" ] || [ "$#" -ne 2 ]; then
  echo "Usage: claim-self-reentry.sh <claim_dir> <caller_pipeline_id>" >&2
  exit 2
fi

claim_file="${claim_dir}/claim.json"

# claim.json absent → never steal (in-flight acquire window or crashed mkdir
# stub). Foreign.
if [ ! -f "$claim_file" ]; then
  exit 10
fi

# Read the stored pipeline_id with the SAFE release-style reader: a
# try/except that prints '' on any failure (missing key, truncated JSON,
# malformed JSON). A malformed claim.json therefore yields an empty string,
# never a traceback — so "" != caller → foreign (10), deterministically.
stored=$("$_CLAIM_PYTHON" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id', ''))
except Exception:
    print('')
" "$claim_file")

if [ "$stored" = "$caller_pipeline_id" ] && [ -n "$caller_pipeline_id" ]; then
  exit 0
fi
exit 10
