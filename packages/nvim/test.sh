#!/usr/bin/env bash
# Smoke test for the nvim package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

NVIM="${1}/bin/nvim"

echo "--- nvim --version ---"
"${NVIM}" --version

echo "--- nvim headless (runtime + lua) ---"
OUTPUT=$("${NVIM}" --headless -u NONE -c 'lua io.stdout:write("lua-ok " .. vim.env.VIMRUNTIME .. "\n")' -c 'qa!' 2>&1)
echo "${OUTPUT}"

if [[ "${OUTPUT}" != *"lua-ok"* ]]; then
    echo "ERROR: lua execution failed" >&2
    exit 1
fi

echo "--- nvim treesitter parser (bundled lua) ---"
TS_OUT=$("${NVIM}" --headless -u NONE -c 'lua assert(vim.treesitter.language.add("lua")); io.stdout:write("ts-ok\n")' -c 'qa!' 2>&1)
echo "${TS_OUT}"
if [[ "${TS_OUT}" != *"ts-ok"* ]]; then
    echo "ERROR: bundled lua tree-sitter parser not found" >&2
    exit 1
fi

echo "--- ldd ${NVIM} ---"
ldd "${NVIM}"
