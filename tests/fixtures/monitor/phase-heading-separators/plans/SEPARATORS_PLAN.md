---
title: Phase Heading Separators
status: active
created: 2026-05-07
---

# Phase Heading Separators

## Overview

Regression fixture for issue #183 — `/plans` previously demoted plans with
colon-separated phase headings to Reference. This fixture exercises all four
accepted separators (em-dash, en-dash, colon, hyphen) in a single plan so the
aggregator must classify it as `executable` with `phase_count=4`.

## Phase 1 — Em-dash separator

Canonical form.

## Phase 2: Colon separator

The form that issue #183 reports as silently broken.

## Phase 3 – En-dash separator

Unicode en-dash, often produced by editor autocorrect.

## Phase 4 - Hyphen separator

Plain ASCII hyphen.
