#!/usr/bin/env bash
# Latest opencode 1.x version. Pinned to 1.x so this package keeps tracking v1
# once upstream starts publishing v2 as the latest GitHub release
# (v2 is the separate opencode-v2 package).
set -euo pipefail
gh api --paginate repos/anomalyco/opencode/tags --jq '.[].name' \
    | grep -E '^v1\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | sed 's/^v//'
