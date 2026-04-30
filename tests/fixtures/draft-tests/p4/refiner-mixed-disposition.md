## Refined draft

Specs updated for AC-1.2 (added missing case) and AC-2.1 (replaced vague
"works correctly" with a literal expected value).

## Disposition table

| Finding | Evidence | Disposition |
|---------|----------|-------------|
| AC-1.2 has no spec referencing it. Blast radius: major — gap leaves behavior beta untested. | Verified | Fixed — appended `- [unit] [risk: AC-1.2] given input "b", expect "B".` |
| Spec for AC-2.1 says "works correctly" — no literal expected. Blast radius: moderate — vague-expected anti-pattern. | Verified | Fixed — replaced with `expect raises ValueError("empty input")`. |
| Concurrency stress test missing for AC-1.1. Blast radius: minor — concurrency is not load-bearing for this code path per Bach calibration. | Judgment | Justified — minor blast, dropped per WI 4.5. |
| Test of jest framework internals. Blast radius: minor — framework code is not product code per NOT-a-finding list. | Judgment | Justified — NOT-a-finding (framework code). |
