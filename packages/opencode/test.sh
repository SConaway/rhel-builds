#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_ROOT="${1:?Usage: $0 <artifact-root>}"

BINARY="${ARTIFACT_ROOT}/bin/opencode"

if [[ ! -f "${BINARY}" ]]; then
    echo "ERROR: binary not found at ${BINARY}" >&2
    exit 1
fi

echo "==> opencode --version"
"${BINARY}" --version

echo "==> opencode models"
MODELS=$("${BINARY}" models)
echo "${MODELS}"

if [[ -z "${MODELS}" ]]; then
    echo "ERROR: 'opencode models' returned no output" >&2
    exit 1
fi
