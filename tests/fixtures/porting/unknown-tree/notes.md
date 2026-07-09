# Ported notes — unknown-construct fixture

The harness exports CLAUDE_CODE_SESSION_TRACE at startup; nothing in the v1
class table classifies that token, so the scanner reports it as
unknown-class and the gate fails closed (unknown findings are never
marker-suppressible — the remedy is a ruling appended to the class table).
