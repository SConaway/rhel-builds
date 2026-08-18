#!/usr/bin/env bash
# Smoke test for the tmux package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

TMUX="${1}/bin/tmux"
SOCKET_NAME="smoketest"

echo "--- tmux -V ---"
"${TMUX}" -V

echo "--- tmux new-session (detached) ---"
"${TMUX}" -L "${SOCKET_NAME}" new-session -d -s smoke "sleep 30"

echo "--- tmux list-sessions ---"
OUTPUT=$("${TMUX}" -L "${SOCKET_NAME}" list-sessions)
echo "${OUTPUT}"

if [[ "${OUTPUT}" != *"smoke"* ]]; then
    echo "ERROR: expected session 'smoke' not found in list-sessions output" >&2
    exit 1
fi

echo "--- tmux kill-server ---"
"${TMUX}" -L "${SOCKET_NAME}" kill-server

echo "--- ldd ${TMUX} ---"
ldd "${TMUX}"
