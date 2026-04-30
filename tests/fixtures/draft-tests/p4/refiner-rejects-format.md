## Refined draft

(No changes.)

## Disposition table

| Finding | Evidence | Disposition |
|---------|----------|-------------|
| AC-1.1 spec asserts `expect 0` but the actual function returns `0.0` (float). Blast radius: moderate — finding-format-violation absorbed; reviewer omitted blast radius. | Verified | Justified — finding-format-violation: reviewer omitted `Blast radius:` line; refiner rejected the finding pending re-emission. |
| AC-2.1 spec says "expect raises ValueError". Blast radius: moderate — finding-format-violation absorbed. | Judgment | Justified — finding-format-violation: reviewer omitted `Blast radius:` line; refiner rejected. |
