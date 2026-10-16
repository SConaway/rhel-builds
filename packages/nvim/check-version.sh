#!/usr/bin/env bash
# Latest stable Neovim version. Upstream also publishes rolling "nightly" and
# "stable" releases, so pick the highest vX.Y.Z tag instead of releases/latest.
set -euo pipefail
gh api --paginate repos/neovim/neovim/tags --jq '.[].name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | sed 's/^v//'
