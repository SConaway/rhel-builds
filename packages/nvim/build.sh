#!/usr/bin/env bash
# Builds Neovim from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="0.12.6"
NAME="nvim"
SOURCE_URL="https://github.com/neovim/neovim/archive/refs/tags/v${VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc gcc-c++ make cmake gettext unzip patch git tar gzip curl ca-certificates

echo "==> Downloading neovim v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/neovim-${VERSION}.tar.gz"
tar -xzf "/build/src/neovim-${VERSION}.tar.gz" -C /build/src

echo "==> Building neovim (bundled deps: LuaJIT, libuv, tree-sitter, etc.)"
cd "/build/src/neovim-${VERSION}"
STAGING="/build/staging/${ARTIFACT_NAME}"
make -j"$(nproc)" CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="${STAGING}" CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_LIBDIR=lib"

echo "==> Installing into staging directory"
make install

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
