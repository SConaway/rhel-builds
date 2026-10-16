#!/usr/bin/env bash
# i3 releases are published as tarballs on i3wm.org; the GitHub repo's tags
# are not release tags, so the generic checker can't be used.
set -euo pipefail

curl -fsSL https://i3wm.org/downloads/ \
    | grep -oP 'i3-\K[0-9]+(\.[0-9]+)+(?=\.tar\.xz)' \
    | sort -uV \
    | tail -n1
