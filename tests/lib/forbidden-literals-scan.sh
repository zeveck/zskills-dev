#!/bin/bash
# tests/lib/forbidden-literals-scan.sh — the forbidden-literals deny-list
# scan over skills/**/*.md, extracted as a SINGLE
# shared script so the single-source-of-truth guarantee is STRUCTURAL
# (shared code), not merely a shared fixture (#948).
#
# CONSUMERS (both call THIS script, neither re-implements the scan):
#   - tests/test-skill-conformance.sh — runs it against the REAL
#     skills/ tree for its `.md` deny-list section;
#     renders the emitted DRIFT lines via its own pass/fail.
#     Behavior + output unchanged.
#   - tests/test-hooks.sh — runs it DIRECTLY against a synthetic throwaway
#     fixture tree (a copy of forbidden-literals.txt with an appended
#     `__TEST_LITERAL__` + a synthetic SKILL.md containing that literal in
#     a bash fence) for its "Fixture-extension coverage" Surface 2 probe.
#     Sub-second — replaces the prior nested full-suite run (#587 #948).
#
# This is a SOURCEABLE-OR-EXECUTABLE library helper, NOT a suite. Do NOT
# register it in run-all.sh as a `run_suite`.
#
# ─────────────────────────────────────────────────────────────────────
# CONTRACT
#   run_forbidden_literals_scan <scan-root> [fixture-path]
#     <scan-root>     directory whose `skills/` subtree is walked for
#                     *.md files. (An absent subtree contributes no
#                     files.)
#     [fixture-path]  path to the forbidden-literals.txt fixture.
#                     Defaults to <scan-root>/tests/fixtures/forbidden-literals.txt.
#
#   STDOUT: one DRIFT line per hit (verbatim, including the remediation
#           hint). Empty when the scan is clean.
#   Exit:   0 when no hits, 1 when one or more hits were emitted, 2 when
#           the fixture is missing/unreadable.
#
#   Matching semantics are IDENTICAL to the prior inline scan in
#   test-skill-conformance.sh — same fixture format (FIXED substring
#   entries + `re:` extended-regex entries), same blockquote
#   normalisation, same exec-fence detection (bash/sh/shell/no-language),
#   same allow-hardcoded marker handling, same prose-imperative detection,
#   and the same tailored #179 skill-version-literal hint. This is a pure
#   relocation of the scan's call site, not a change to what it detects.
# ─────────────────────────────────────────────────────────────────────

run_forbidden_literals_scan() {
  local scan_root="$1"
  local fixture="${2:-$scan_root/tests/fixtures/forbidden-literals.txt}"

  if [ ! -r "$fixture" ]; then
    echo "FORBIDDEN-SCAN-ERROR: fixture $fixture missing or unreadable" >&2
    return 2
  fi

  # Read fixture once. Split into FIXED (substring) and REGEX (extended-regex) entries.
  local -a FIXED_LITERALS=()
  local -a REGEX_PATTERNS=()
  local entry
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    [[ "$entry" =~ ^# ]] && continue
    if [[ "$entry" =~ ^re: ]]; then
      REGEX_PATTERNS+=("${entry#re:}")
    else
      FIXED_LITERALS+=("$entry")
    fi
  done < "$fixture"

  local DRIFT_FAIL=0
  local -a DRIFT_HITS=()

  local skill_file line norm_line lang lit literal pattern
  local in_fence fence_type line_no
  local -A allowed_in_fence=()
  local -a prev_lines=()

  while IFS= read -r skill_file; do
    in_fence=0
    fence_type=""
    unset allowed_in_fence; declare -A allowed_in_fence=()
    prev_lines=()
    line_no=0
    while IFS= read -r line; do
      line_no=$((line_no + 1))
      # Blockquote normalisation: strip a leading `>` + optional space
      # before applying any structural regex. Without this, blockquoted
      # fenced bash blocks (` >    ```bash`) go undetected.
      norm_line="$line"
      if [[ "$norm_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
        norm_line="${BASH_REMATCH[1]}"
      fi

      if [ "$in_fence" -eq 0 ]; then
        # Outside any fence.
        if [[ "$norm_line" =~ ^[[:space:]]*\<!--[[:space:]]+allow-hardcoded:[[:space:]]+(.+)[[:space:]]+reason:.*--\>[[:space:]]*$ ]]; then
          local captured="${BASH_REMATCH[1]}"
          # Trim trailing whitespace.
          captured="${captured%"${captured##*[![:space:]]}"}"
          prev_lines+=("$captured")
        elif [[ "$norm_line" =~ ^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$ ]]; then
          # Fence-opener of any kind. Track exec vs other so non-shell
          # fences (json, markdown, etc.) don't get scanned for shell
          # literals — but their bounds are still tracked.
          lang="${BASH_REMATCH[1]}"
          in_fence=1
          if [ -z "$lang" ] || [ "$lang" = "bash" ] || [ "$lang" = "sh" ] || [ "$lang" = "shell" ]; then
            fence_type="exec"
          else
            fence_type="other"
          fi
          allowed_in_fence=()
          if [ "$fence_type" = "exec" ]; then
            for lit in "${prev_lines[@]:-}"; do
              [ -n "$lit" ] && allowed_in_fence["$lit"]=1
            done
          fi
          prev_lines=()
          continue
        else
          # Any other non-blank line resets the marker block.
          [ -n "$norm_line" ] && prev_lines=()
        fi
        # PROSE-IMPERATIVE detection: bullet/numbered line with a
        # code-span AND a sentence-start imperative verb.
        if [[ "$norm_line" =~ ^[[:space:]]*([-*]|[0-9]+\.) ]] \
           && [[ "$norm_line" =~ \`[^\`]+\` ]] \
           && [[ "$norm_line" =~ (^|[.\;\:][[:space:]]+|\*\*)(Run|Execute|Invoke)[[:space:]] ]]; then
          for literal in "${FIXED_LITERALS[@]}"; do
            if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
              DRIFT_HITS+=("DRIFT (prose-imperative): $skill_file:$line_no contains '$literal'. Replace with \$VAR (preferred), OR add on the line ABOVE this bullet: <!-- allow-hardcoded: $literal reason: <why> -->")
              DRIFT_FAIL=1
            fi
          done
          for pattern in "${REGEX_PATTERNS[@]}"; do
            if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
              if [[ "$pattern" == '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}' ]]; then
                DRIFT_HITS+=("DRIFT (prose-imperative): $skill_file:$line_no matches the skill-version-literal regex '$pattern'. Per-skill version values belong in metadata.version frontmatter, not pasted into prose imperatives. To mark this bullet as an illustrative example, add on the line ABOVE: <!-- allow-hardcoded: $pattern reason: documenting the format with an example value -->")
              else
                DRIFT_HITS+=("DRIFT (prose-imperative): $skill_file:$line_no matches forbidden regex '$pattern'. Replace with \$VAR (preferred), OR add on the line ABOVE this bullet: <!-- allow-hardcoded: $pattern reason: <why> -->")
              fi
              DRIFT_FAIL=1
            fi
          done
        fi
        continue
      fi

      # Inside a fence.
      if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
        in_fence=0
        fence_type=""
        allowed_in_fence=()
        prev_lines=()
        continue
      fi
      # Only scan exec-type fences (bash / sh / shell / no-language).
      if [ "$fence_type" != "exec" ]; then
        continue
      fi
      for literal in "${FIXED_LITERALS[@]}"; do
        if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
          DRIFT_HITS+=("DRIFT: $skill_file:$line_no contains '$literal' inside a bash fence without an allow-hardcoded marker. Replace with \$VAR (preferred), OR mark this fence as illustrative by adding on the line ABOVE the opening backticks: <!-- allow-hardcoded: $literal reason: <why> -->")
          DRIFT_FAIL=1
        fi
      done
      for pattern in "${REGEX_PATTERNS[@]}"; do
        if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
          # Tailored hint for the skill-version-literal regex (issue #179).
          if [[ "$pattern" == '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}' ]]; then
            DRIFT_HITS+=("DRIFT: $skill_file:$line_no matches the skill-version-literal regex '$pattern' inside a bash fence. Per-skill version values belong in metadata.version frontmatter, not in fence bodies. To mark this fence as an illustrative example, add on the line ABOVE the opening backticks: <!-- allow-hardcoded: $pattern reason: documenting the format with an example value -->. Alternatively, switch the fence language to \`\`\`text (non-exec, not scanned).")
          else
            DRIFT_HITS+=("DRIFT: $skill_file:$line_no matches forbidden regex '$pattern' inside a bash fence without an allow-hardcoded marker. Replace with \$VAR (preferred), OR mark this fence as illustrative by adding on the line ABOVE the opening backticks: <!-- allow-hardcoded: $pattern reason: <why> -->")
          fi
          DRIFT_FAIL=1
        fi
      done
    done < "$skill_file"
  done < <(find "$scan_root/skills" -name '*.md' 2>/dev/null | sort)

  local h
  for h in "${DRIFT_HITS[@]:-}"; do
    [ -n "$h" ] && printf '%s\n' "$h"
  done

  return "$DRIFT_FAIL"
}

# When executed directly (not sourced), run the scan with argv.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  run_forbidden_literals_scan "$@"
  exit $?
fi
