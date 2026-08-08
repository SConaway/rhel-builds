#!/usr/bin/env bash
# Smoke test for the leaf package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

LEAF="${1}/bin/leaf"

echo "--- leaf --version ---"
"${LEAF}" --version

echo "--- leaf --inline (render markdown from stdin) ---"
OUTPUT=$(echo '# Hello World' | "${LEAF}" --inline plain)
echo "${OUTPUT}"

if [[ "${OUTPUT}" != *"Hello World"* ]]; then
    echo "ERROR: rendered output missing expected heading text" >&2
    exit 1
fi
