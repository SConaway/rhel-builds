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

echo "--- dynamic module loading (zsh/stat, zsh/regex) ---"
# Not run with -f: module_path is set via a .zshenv under a relocated ZDOTDIR
# (see build.sh), and -f (NO_RCS) skips that file, same as a real login shell
# would skip it if invoked non-interactively with rcs disabled.
OUTPUT=$("${ZSH}" -c 'zmodload zsh/stat; zmodload zsh/regex; echo MODULES_OK')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"MODULES_OK"* ]]; then
    echo "ERROR: failed to load dynamic modules zsh/stat and/or zsh/regex" >&2
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

echo "--- relocation check: dynamic module loading ---"
OUTPUT=$("${COPY_DIR}/bin/zsh" -c 'zmodload zsh/stat; zmodload zsh/regex; echo RELOCATED_MODULES_OK')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"RELOCATED_MODULES_OK"* ]]; then
    echo "ERROR: dynamic modules did not load after zsh was moved to a different path" >&2
    exit 1
fi

echo "--- ZDOTDIR passthrough (user's own .zshenv/.zshrc still load) ---"
USER_ZDOTDIR="$(mktemp -d)"
echo 'echo USER_ZSHENV_LOADED' > "${USER_ZDOTDIR}/.zshenv"
OUTPUT=$(ZDOTDIR="${USER_ZDOTDIR}" "${ZSH}" -c 'echo AFTER_ZSHENV')
echo "${OUTPUT}"
if [[ "${OUTPUT}" != *"USER_ZSHENV_LOADED"* ]] || [[ "${OUTPUT}" != *"AFTER_ZSHENV"* ]]; then
    echo "ERROR: user-supplied ZDOTDIR/.zshenv was not sourced" >&2
    exit 1
fi

echo "--- ldd ${ROOT}/bin/zsh.bin ---"
ldd "${ROOT}/bin/zsh.bin"
