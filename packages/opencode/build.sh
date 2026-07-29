#!/usr/bin/env bash
# Builds opencode from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="1.18.9"
BUN_VERSION="1.3.14"
NAME="opencode"
SOURCE_URL="https://github.com/anomalyco/opencode/archive/refs/tags/v${VERSION}.tar.gz"
BUN_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64-baseline.zip"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing curl tar unzip ca-certificates git python38 make gcc-toolset-12-gcc gcc-toolset-12-gcc-c++

echo "==> Installing bun v${BUN_VERSION} (baseline)"
mkdir -p /build/bun
curl -fL "${BUN_URL}" -o /build/bun/bun.zip
unzip -q /build/bun/bun.zip -d /build/bun
# unzip produces bun-linux-x64-baseline/bun
mv /build/bun/bun-linux-x64-baseline/bun /build/bun/bun
chmod +x /build/bun/bun
export PATH="/build/bun:${PATH}"
bun --version

echo "==> Downloading opencode v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/opencode-${VERSION}.tar.gz"
tar -xzf "/build/src/opencode-${VERSION}.tar.gz" -C /build/src
SRC="/build/src/opencode-${VERSION}"

echo "==> Patching flag.ts: hardcode OPENCODE_DISABLE_AUTOUPDATE=true"
sed -i 's/OPENCODE_DISABLE_AUTOUPDATE: truthy("OPENCODE_DISABLE_AUTOUPDATE"),/OPENCODE_DISABLE_AUTOUPDATE: true,/' \
    "${SRC}/packages/core/src/flag/flag.ts"
grep "OPENCODE_DISABLE_AUTOUPDATE" "${SRC}/packages/core/src/flag/flag.ts"

echo "==> Installing dependencies"
cd "${SRC}"
export PYTHON=/usr/bin/python3.8
source /opt/rh/gcc-toolset-12/enable
bun install

echo "==> Building opencode (linux-x64-baseline)"
cd "${SRC}/packages/opencode"
OPENCODE_VERSION="${VERSION}" bun run build --single --baseline

echo "==> Checking build output"
BINARY="${SRC}/packages/opencode/dist/opencode-linux-x64-baseline/bin/opencode"
if [[ ! -f "${BINARY}" ]]; then
    echo "ERROR: Expected binary not found at ${BINARY}" >&2
    ls -la "${SRC}/packages/opencode/dist/" || true
    exit 1
fi

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp "${BINARY}" "${STAGING}/bin/opencode"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
