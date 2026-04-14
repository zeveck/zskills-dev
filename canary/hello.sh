#!/bin/bash
hello() { echo "Hello, $1!"; }

# Self-test (runs only when executed directly)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ "$(hello World)" = "Hello, World!" ] && echo "PASS" || { echo "FAIL"; exit 1; }
fi
