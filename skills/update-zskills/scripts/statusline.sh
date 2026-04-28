#!/usr/bin/env bash
# zskills statusline — context window + rate limit progress bars (no jq)
INPUT=$(cat)

extract_pct() {
  local after="${INPUT#*\"$1\"}"
  [ "$after" = "$INPUT" ] && return
  [[ "$after" =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+\.?[0-9]*) ]] && printf '%.0f' "${BASH_REMATCH[1]}"
}

bar() {
  local pct="$1" color="$2" w=10 reset="\033[0m" b=""
  local filled=$(( (pct * w + 99) / 100 ))
  [ "$filled" -gt "$w" ] && filled=$w
  for i in $(seq 1 $w); do [ "$i" -le "$filled" ] && b+="█" || b+="░"; done
  printf "${color}${b}${reset} %d%%" "$pct"
}

parts=()
ctx=$(extract_pct "context_window");  [ -n "$ctx" ]  && parts+=("$(bar "$ctx" "\033[35m")")
five=$(extract_pct "five_hour");      [ -n "$five" ] && parts+=("$(bar "$five" "\033[34m")")
week=$(extract_pct "seven_day");      [ -n "$week" ] && parts+=("$(bar "$week" "\033[32m")")

printf '%b' "$(IFS='  '; echo "${parts[*]}")"
