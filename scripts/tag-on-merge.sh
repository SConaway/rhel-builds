#!/usr/bin/env bash
# Usage: ./scripts/tag-on-merge.sh <bump-branch-name>
# e.g.:  ./scripts/tag-on-merge.sh bump/leaf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

HEAD_REF="${1:?Usage: $0 <bump-branch-name>}"
PKG="${HEAD_REF#bump/}"

BUILD_SCRIPT="packages/${PKG}/build.sh"

if [[ ! -f "${BUILD_SCRIPT}" ]]; then
    echo "ERROR: ${BUILD_SCRIPT} not found on main after merge of ${HEAD_REF}" >&2
    exit 1
fi

VERSION=$(grep -oP '^VERSION="\K[^"]+' "${BUILD_SCRIPT}" || true)
if [[ -z "${VERSION}" ]]; then
    echo "ERROR: could not read VERSION= from ${BUILD_SCRIPT}" >&2
    exit 1
fi

TAG="${PKG}-v${VERSION}"

if git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "==> Tag ${TAG} already exists locally, nothing to do"
    exit 0
fi

if git ls-remote --exit-code --tags origin "${TAG}" >/dev/null 2>&1; then
    echo "==> Tag ${TAG} already exists on origin, nothing to do"
    exit 0
fi

echo "==> Creating and pushing tag ${TAG}"
git tag "${TAG}"
git push origin "${TAG}"
