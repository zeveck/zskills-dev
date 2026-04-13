#!/bin/bash
hello() { echo "Hello from canary!"; }
# Self-test
if [ "$(hello)" = "Hello from canary!" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
