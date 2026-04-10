#!/usr/bin/env bash
# Top-level build script. Runs the package build inside a Docker container.
# Usage: ./build.sh <package> <rhel-version>
# Example: ./build.sh tree-sitter-cli rhel8
set -euo pipefail

PACKAGE="${1:?Usage: $0 <package> <rhel-version>}"
RHEL_VERSION="${2:?Usage: $0 <package> <rhel-version>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${SCRIPT_DIR}/packages/${PACKAGE}"

if [[ ! -d "${PACKAGE_DIR}" ]]; then
    echo "ERROR: No package directory found at ${PACKAGE_DIR}" >&2
    exit 1
fi

case "${RHEL_VERSION}" in
    rhel8|8) IMAGE="almalinux:8" ;;
    rhel9|9) IMAGE="almalinux:9" ;;
    *) echo "ERROR: Unknown RHEL version '${RHEL_VERSION}'. Use rhel8 or rhel9." >&2; exit 1 ;;
esac

OUTPUT_DIR="${SCRIPT_DIR}/output/${PACKAGE}/${RHEL_VERSION}"
mkdir -p "${OUTPUT_DIR}"

echo "==> Building ${PACKAGE} for ${RHEL_VERSION} using image ${IMAGE}"
echo "==> Output will be written to ${OUTPUT_DIR}"

docker run --rm \
    --network=host \
    -v "${PACKAGE_DIR}:/build/package:ro" \
    -v "${OUTPUT_DIR}:/build/output" \
    "${IMAGE}" \
    bash /build/package/build.sh

echo "==> Build complete. Artifacts:"
find "${OUTPUT_DIR}" -type f | sort
