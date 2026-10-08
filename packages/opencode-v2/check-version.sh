#!/usr/bin/env bash
# Latest opencode 2.x version. v2 is tagged but has no GitHub Releases yet, so
# the generic checker (releases/latest) would return the 1.x line.
set -euo pipefail
gh api --paginate repos/anomalyco/opencode/tags --jq '.[].name' \
    | grep -E '^v2\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | sed 's/^v//'
