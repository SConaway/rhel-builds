#!/usr/bin/env bash
# zsh's build.sh sources from downloads.sourceforge.net, not github.com, so it
# doesn't match the generic checker's github.com SOURCE_URL pattern.
# SourceForge's best_release API reports the file its own download button
# points to, which tracks the latest stable release without pulling in
# pre-releases/betas that a directory listing sort could pick up.
set -euo pipefail

version=$(curl -fsSL https://sourceforge.net/projects/zsh/best_release.json \
    | grep -oP '"filename": *"/zsh/\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=/zsh-)' \
    | head -n1)

echo "${version}"
