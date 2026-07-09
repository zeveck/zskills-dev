# Ported tree — meta-record exemption fixture

Shipped prose in this tree is clean; only the root meta-records (GAPS.md,
DEGRADATIONS.md, PORT_MANIFEST.json, PORTING-NOTES.md) name Claude
constructs, and those are exempt by exact root-relative path. The suite
copies the GAPS.md text into a root NOTES.md — NOT on the exempt list — and
asserts the same gate then fails.
