#!/usr/bin/env bash
# Top-level test script. Runs the package test inside a Docker container.
# Usage: ./test.sh <package> [rhel-version]
# Example: ./test.sh git rhel8
# If rhel-version is omitted, tests on both rhel8 and rhel9.
# For rhel9, falls back to the rhel8 tarball if no rhel9 build exists
# (AlmaLinux 8 binaries are glibc-forwards-compatible with AlmaLinux 9).
set -euo pipefail

PACKAGE="${1:?Usage: $0 <package> [rhel-version]}"
RHEL_ARG="${2:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${SCRIPT_DIR}/packages/${PACKAGE}"

if [[ ! -d "${PACKAGE_DIR}" ]]; then
    echo "ERROR: No package directory found at ${PACKAGE_DIR}" >&2
    exit 1
fi

if [[ ! -f "${PACKAGE_DIR}/test.sh" ]]; then
    echo "ERROR: No test script found at ${PACKAGE_DIR}/test.sh" >&2
    exit 1
fi

case "${RHEL_ARG}" in
    all)        VERSIONS=(rhel8 rhel9) ;;
    rhel8|8)    VERSIONS=(rhel8) ;;
    rhel9|9)    VERSIONS=(rhel9) ;;
    *) echo "ERROR: Unknown RHEL version '${RHEL_ARG}'. Use rhel8 or rhel9." >&2; exit 1 ;;
esac

PASS=0
FAIL=0

for RHEL_VERSION in "${VERSIONS[@]}"; do
    case "${RHEL_VERSION}" in
        rhel8) IMAGE="almalinux:8" ;;
        rhel9) IMAGE="almalinux:9" ;;
    esac

    # Find tarball for this version; fall back to rhel8 if rhel9 has no dedicated build
    TARBALL=$(find "${SCRIPT_DIR}/output/${PACKAGE}/${RHEL_VERSION}" \
        -name "*.tar.gz" ! -name "*.sha256" 2>/dev/null | head -1) || true

    if [[ -z "${TARBALL}" && "${RHEL_VERSION}" == "rhel9" ]]; then
        TARBALL=$(find "${SCRIPT_DIR}/output/${PACKAGE}/rhel8" \
            -name "*.tar.gz" ! -name "*.sha256" 2>/dev/null | head -1) || true
        if [[ -n "${TARBALL}" ]]; then
            echo "==> No rhel9 build found; using rhel8 tarball to test on ${IMAGE}"
        fi
    fi

    if [[ -z "${TARBALL}" ]]; then
        echo "ERROR: No tarball found for ${PACKAGE} ${RHEL_VERSION}." >&2
        echo "       Run: ./build.sh ${PACKAGE} ${RHEL_VERSION}" >&2
        exit 1
    fi

    echo "==> Testing ${PACKAGE} on ${IMAGE} ($(basename "${TARBALL}"))..."

    if docker run --rm \
        --network=host \
        -v "${TARBALL}:/artifact.tar.gz:ro" \
        -v "${PACKAGE_DIR}:/build/package:ro" \
        "${IMAGE}" \
        bash -c '
            set -eu
            cd /tmp
            ARTIFACT_DIR=$(tar tf /artifact.tar.gz | head -1 | cut -d/ -f1)
            tar xf /artifact.tar.gz
            bash /build/package/test.sh "/tmp/${ARTIFACT_DIR}"
        '; then
        echo "[PASS] ${PACKAGE} on ${IMAGE}"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] ${PACKAGE} on ${IMAGE}"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]]
