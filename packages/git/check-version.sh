#!/usr/bin/env bash
# git's build.sh sources from mirrors.edge.kernel.org, not github.com, so it
# doesn't match the generic checker's github.com SOURCE_URL pattern. This
# override queries git/git on GitHub instead, since kernel.org doesn't
# expose a "latest" API.
#
# git/git's tags also aren't sorted by version (they're sorted by tag
# creation time, so an -rcN tag for the *next* release can sort above the
# current stable tag) and include -rcN pre-release tags that this repo
# doesn't want proposed as bumps. Filter to stable X.Y.Z tags and pick the
# highest by version sort.
set -euo pipefail

version=$(gh api repos/git/git/tags --jq '.[].name' \
    | grep -oP '^v\K[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n1)

echo "${version}"
