## Findings

- AC-1.1 spec asserts `expect 0` but the actual function returns `0.0`
  (float). Verification: `grep -n "return 0" src/first.py:7`.
- AC-2.1 spec says "expect raises ValueError" but the production code
  raises `IndexError` on empty list. Verification: judgment — no
  verifiable anchor.
