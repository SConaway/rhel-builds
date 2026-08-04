#!/usr/bin/env bash
# Checks every package under packages/ for a newer upstream version and
# opens/updates a bump/<pkg> PR against main when one is found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

MAIN_BRANCH="main"

for pkg_dir in packages/*/; do
    pkg="$(basename "${pkg_dir}")"
    build_script="packages/${pkg}/build.sh"
    [[ -f "${build_script}" ]] || continue

    current_version=$(grep -oP '^VERSION="\K[^"]+' "${build_script}" || true)
    if [[ -z "${current_version}" ]]; then
        echo "==> ${pkg}: no VERSION= line found, skipping"
        continue
    fi

    new_version="$(./scripts/get-latest-version.sh "${pkg}" || true)"
    if [[ -z "${new_version}" ]]; then
        echo "==> ${pkg}: could not determine latest version, skipping"
        continue
    fi

    if [[ "${new_version}" == "${current_version}" ]]; then
        echo "==> ${pkg}: up to date (${current_version})"
        continue
    fi

    release_tag="${pkg}-v${new_version}"
    if git ls-remote --exit-code --tags origin "${release_tag}" >/dev/null 2>&1; then
        echo "==> ${pkg}: release ${release_tag} already exists, skipping"
        continue
    fi

    echo "==> ${pkg}: ${current_version} -> ${new_version}"
    branch="bump/${pkg}"

    existing_pr_json=$(gh pr list --head "${branch}" --state open \
        --json number,body --jq '.[0]' 2>/dev/null || true)

    if [[ -n "${existing_pr_json}" && "${existing_pr_json}" != "null" ]]; then
        pr_version=$(echo "${existing_pr_json}" \
            | grep -oP '(?<=<!-- new-version: )[^ ]+(?= -->)' || true)
        if [[ "${pr_version}" == "${new_version}" ]]; then
            echo "    PR already targets ${new_version}, skipping"
            continue
        fi
        echo "    stale PR targets ${pr_version}, updating to ${new_version}"
    fi

    git checkout "${MAIN_BRANCH}"
    git pull origin "${MAIN_BRANCH}"
    git branch -D "${branch}" 2>/dev/null || true
    git checkout -b "${branch}"

    sed -i "s/^VERSION=\"${current_version}\"/VERSION=\"${new_version}\"/" "${build_script}"

    # Sanity check: fail loudly if sed matched nothing (e.g. current_version
    # had regex-special characters) rather than silently pushing a no-op diff.
    if git diff --quiet "${build_script}"; then
        echo "    ERROR: sed did not modify ${build_script}, aborting this package" >&2
        git checkout "${MAIN_BRANCH}"
        continue
    fi

    git add "${build_script}"
    git commit -m "${pkg}: bump to ${new_version}"
    git push origin "${branch}" --force

    pr_title="${pkg}: bump to ${new_version}"
    pr_body=$(cat <<EOF
Automated version bump for \`${pkg}\`: \`${current_version}\` -> \`${new_version}\`.

This PR was opened automatically by the scheduled update checker. Review the
upstream changelog before merging. Merging will trigger an automatic
\`${pkg}-v${new_version}\` release tag.

<!-- new-version: ${new_version} -->
EOF
)

    if [[ -n "${existing_pr_json}" && "${existing_pr_json}" != "null" ]]; then
        pr_number=$(echo "${existing_pr_json}" | jq -r .number)
        gh pr edit "${pr_number}" --title "${pr_title}" --body "${pr_body}"
    else
        gh pr create --head "${branch}" --base "${MAIN_BRANCH}" \
            --title "${pr_title}" --body "${pr_body}"
    fi

    git checkout "${MAIN_BRANCH}"
done
