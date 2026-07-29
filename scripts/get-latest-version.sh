#!/usr/bin/env bash
# Usage: ./scripts/get-latest-version.sh <pkg>
# Prints the latest upstream version string to stdout (no leading 'v'),
# or nothing + exit 0 if it can't be determined (caller treats as skip).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

PKG="${1:?Usage: $0 <package>}"
BUILD_SCRIPT="packages/${PKG}/build.sh"
OVERRIDE="packages/${PKG}/check-version.sh"

# 1. Per-package override always wins, for upstreams that don't fit the
#    generic GitHub-tags pattern (crates.io-only releases, non-GitHub hosts,
#    weird tagging schemes, etc). Convention: must be executable, take no
#    arguments, print the version to stdout.
if [[ -x "${OVERRIDE}" ]]; then
    "${OVERRIDE}"
    exit 0
fi

SOURCE_URL=$(grep -oP '^SOURCE_URL="\K[^"]+' "${BUILD_SCRIPT}" || true)

if [[ "${SOURCE_URL}" == *"github.com"* ]]; then
    repo=$(echo "${SOURCE_URL}" | grep -oP 'github\.com/\K[^/]+/[^/]+')

    # Prefer latest Release; fall back to most recent tag for repos that
    # tag without cutting a GitHub Release.
    version=$(gh api "repos/${repo}/releases/latest" --jq .tag_name 2>/dev/null || true)
    if [[ -z "${version}" ]]; then
        version=$(gh api "repos/${repo}/tags" --jq '.[0].name' 2>/dev/null || true)
    fi

    # Strip a leading 'v' if present, to match this repo's bare-version
    # convention (VERSION="1.26.2", not "v1.26.2").
    echo "${version#v}"
else
    # Unknown source type with no override: caller skips.
    exit 0
fi
