#!/usr/bin/env bash
# Smoke test for the zsh package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

ROOT="${1}"
ZSH="${ROOT}/bin/zsh"

echo "--- zsh --version ---"
"${ZSH}" --version

echo "--- basic command execution ---"
OUTPUT=$("${ZSH}" -f -c 'echo hello from $ZSH_NAME')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"hello from zsh"* ]]; then
    echo "ERROR: unexpected output from basic zsh -c invocation" >&2
    exit 1
fi

echo "--- autoload / fpath (completion functions) ---"
OUTPUT=$("${ZSH}" -f -c 'autoload -Uz compinit && echo AUTOLOAD_OK')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"AUTOLOAD_OK"* ]]; then
    echo "ERROR: failed to autoload compinit via fpath" >&2
    exit 1
fi

echo "--- relocation check (run from a copied location) ---"
COPY_DIR="$(mktemp -d)/zsh-relocated"
cp -r "${ROOT}" "${COPY_DIR}"
OUTPUT=$("${COPY_DIR}/bin/zsh" -f -c 'autoload -Uz compinit && echo RELOCATED_OK')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"RELOCATED_OK"* ]]; then
    echo "ERROR: zsh did not work correctly after being moved to a different path" >&2
    exit 1
fi

echo "--- ldd ${ROOT}/bin/zsh.bin ---"
ldd "${ROOT}/bin/zsh.bin"
