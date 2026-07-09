# Project Agent Rules (small render fixture)

A de-parameterized template with no placeholder tokens: the canonical
renderer passes it through byte-identically, and the rendered output sits
far under the 32 KiB AGENTS.md default cap.

- Run the full suite before every commit.
- Never weaken a test to make it pass.
