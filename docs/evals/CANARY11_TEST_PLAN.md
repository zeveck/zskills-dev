---
title: Canary 11 Test — Fix typo in canary11.txt
created: 2026-04-16
status: active
---

# Plan: Fix typo in canary11.txt

## Overview

This is the synthetic test plan for CANARY11. A narrow, one-file fix.
Any change beyond the typo is out of scope.

## Phase 1 -- Fix typo

### Goal

Fix the typo "hte" → "the" on line 3 of `canary/canary11.txt`.

### Work Items

- [ ] Replace "hte" with "the" on line 3 of `canary/canary11.txt`.

### Acceptance Criteria

- [ ] Line 3 reads `The quick brown fox jumps over the lazy dog.`
- [ ] Only `canary/canary11.txt` changed.
