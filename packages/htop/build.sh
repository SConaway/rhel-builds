#!/usr/bin/env bash
# Builds htop from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="3.5.3"
NAME="htop"
SOURCE_URL="https://github.com/htop-dev/htop/releases/download/${VERSION}/htop-${VERSION}.tar.xz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc make ncurses-devel tar curl ca-certificates xz

echo "==> Downloading htop v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/htop-${VERSION}.tar.xz"
tar -xJf "/build/src/htop-${VERSION}.tar.xz" -C /build/src

echo "==> Building htop"
cd "/build/src/htop-${VERSION}"
./configure
make -j"$(nproc)"

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp htop "${STAGING}/bin/htop"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
