#!/usr/bin/env bash
# Usage: ./scripts/get-changelog-url.sh <pkg> <old-version> <new-version>
# Prints a URL for the upstream changelog/release notes of <new-version>,
# or nothing + exit 0 if none can be found (caller omits the link).
#
# Order: per-package special cases (changelog lives in a file in the repo, or
# on a non-GitHub host), then the GitHub Release page for the tag, then a
# GitHub compare view between the old and new tags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

PKG="${1:?Usage: $0 <package> <old-version> <new-version>}"
OLD="${2:?}"
NEW="${3:?}"

# Succeeds if the GitHub API knows the given path; $1 = repo, $2 = api suffix.
gh_exists() { gh api "repos/$1/$2" >/dev/null 2>&1; }

# Succeeds if a repo has a tag named $2 (tried with and without a 'v' prefix);
# prints the matching tag.
find_tag() {
    local repo="$1" ver="$2" t
    for t in "v${ver}" "${ver}"; do
        if gh_exists "${repo}" "git/ref/tags/${t}"; then
            echo "${t}"
            return 0
        fi
    done
    return 1
}

case "${PKG}" in
    tmux)
        # Changelog is the CHANGES file at the release tag.
        if tag=$(find_tag tmux/tmux "${NEW}"); then
            echo "https://github.com/tmux/tmux/blob/${tag}/CHANGES"
            exit 0
        fi
        ;;
    git)
        # Release notes live in Documentation/RelNotes/<ver>.{adoc,txt}.
        if tag=$(find_tag git/git "${NEW}"); then
            for ext in adoc txt; do
                if gh_exists git/git "contents/Documentation/RelNotes/${NEW}.${ext}?ref=${tag}"; then
                    echo "https://github.com/git/git/blob/${tag}/Documentation/RelNotes/${NEW}.${ext}"
                    exit 0
                fi
            done
        fi
        ;;
    zsh)
        # Not on GitHub releases; NEWS in the project's SourceForge repo.
        url="https://sourceforge.net/p/zsh/code/ci/zsh-${NEW}/tree/NEWS"
        if curl -fsIL -o /dev/null "${url}"; then
            echo "${url}"
            exit 0
        fi
        ;;
esac

# Generic GitHub fallback. Repo comes from the package's SOURCE_URL, or from
# the override list for packages whose SOURCE_URL isn't on GitHub / is computed.
repo=""
case "${PKG}" in
    git)  repo="git/git" ;;
    zsh)  repo="zsh-users/zsh" ;;
    opencode|opencode-v2) repo="anomalyco/opencode" ;;
    *)
        src=$(grep -oP '^SOURCE_URL="\K[^"]+' "packages/${PKG}/build.sh" 2>/dev/null || true)
        repo=$(echo "${src}" | grep -oP 'github\.com/\K[^/]+/[^/]+' || true)
        ;;
esac
[[ -n "${repo}" ]] || exit 0

new_tag=$(find_tag "${repo}" "${NEW}" || true)
[[ -n "${new_tag}" ]] || exit 0

if gh_exists "${repo}" "releases/tags/${new_tag}"; then
    echo "https://github.com/${repo}/releases/tag/${new_tag}"
    exit 0
fi

old_tag=$(find_tag "${repo}" "${OLD}" || true)
if [[ -n "${old_tag}" ]]; then
    echo "https://github.com/${repo}/compare/${old_tag}...${new_tag}"
else
    echo "https://github.com/${repo}/tree/${new_tag}"
fi
