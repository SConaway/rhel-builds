#!/usr/bin/env bash
# Smoke test for the htop package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

HTOP="${1}/bin/htop"

echo "--- htop --version ---"
"${HTOP}" --version

echo "--- htop -C (no-color, single sample) ---"
export TERM="${TERM:-xterm}"
"${HTOP}" -C -d 1 -n 1 >/dev/null

echo "--- ldd ${HTOP} ---"
ldd "${HTOP}"
