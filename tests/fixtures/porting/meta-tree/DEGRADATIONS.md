# DEGRADATIONS — port-instance record (meta-record exemption fixture)

Per WI 12.1 this file REQUIRES rows that verbatim-match the
frontmatter-flags class patterns — scanning it would make the whole-tree
gate fail on an artifact the port itself requires, hence the root-relative
path exemption.

| Claude construct | Codex disposition |
|---|---|
| user-invocable: false | none — documented degradation |
| allowed-tools | no per-agent allowlist enforcement — documented degradation |
| agent-frontmatter hooks: block | delivered via .codex/hooks.json instead |
| disable-model-invocation | openai.yaml allow_implicit_invocation: false |
