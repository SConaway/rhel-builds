#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_ROOT="${1:?Usage: $0 <artifact-root>}"

BINARY="${ARTIFACT_ROOT}/bin/opencode2"

if [[ ! -f "${BINARY}" ]]; then
    echo "ERROR: binary not found at ${BINARY}" >&2
    exit 1
fi

echo "==> opencode2 --version"
"${BINARY}" --version

# v2's `models` lists only configured providers, so it is empty on a fresh
# install. Exercise the CLI without needing credentials instead.
echo "==> opencode2 debug paths"
PATHS=$("${BINARY}" debug paths)
echo "${PATHS}"
if [[ -z "${PATHS}" ]]; then
    echo "ERROR: 'opencode2 debug paths' returned no output" >&2
    exit 1
fi
