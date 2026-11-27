#!/usr/bin/env bash
# Usage: ./scripts/release.sh <package> <notes>
# Publishes a GitHub release from the tarballs under artifacts/, unless one
# already exists. "{version}" in <notes> is replaced with the upstream version.
#
# On a <package>-v* tag push the version comes from the tag. Otherwise (a push
# to main) it comes from VERSION= in the package's build.sh, and the tag is
# created at the commit being built.
set -euo pipefail

PKG="${1:?Usage: $0 <package> <notes>}"
NOTES="${2:?Usage: $0 <package> <notes>}"

if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
    VERSION="${GITHUB_REF_NAME#"${PKG}-v"}"
else
    VERSION=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "packages/${PKG}/build.sh")
    if [[ -z "${VERSION}" ]]; then
        echo "==> ${PKG}: no static VERSION= line, release by pushing a tag"
        exit 0
    fi
fi

TAG="${PKG}-v${VERSION}"

if gh release view "${TAG}" >/dev/null 2>&1; then
    echo "==> Release ${TAG} already exists, nothing to do"
    exit 0
fi

PRERELEASE=()
[[ "${VERSION}" == *-test* ]] && PRERELEASE=(--prerelease)

mapfile -t FILES < <(find artifacts/ -type f \( -name '*.tar.gz' -o -name '*.sha256' \) | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "ERROR: no release files under artifacts/" >&2
    exit 1
fi

gh release create "${TAG}" ${PRERELEASE[@]+"${PRERELEASE[@]}"} \
    --target "${GITHUB_SHA}" \
    --title "${PKG} v${VERSION}" \
    --notes "${NOTES//\{version\}/${VERSION%%-*}}" \
    "${FILES[@]}"
