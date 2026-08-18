#!/usr/bin/env bash
# Builds tmux from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="3.7c"
NAME="tmux"
SOURCE_URL="https://github.com/tmux/tmux/releases/download/${VERSION}/tmux-${VERSION}.tar.gz"

LIBEVENT_VERSION="2.1.13-stable"
LIBEVENT_URL="https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/libevent-${LIBEVENT_VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc make bison ncurses-devel tar curl ca-certificates

# libevent is not part of a minimal RHEL install, so build it statically from
# source and link it into tmux to keep the tarball self-contained (ncurses/tinfo
# are always present on RHEL, so those stay dynamically linked).
echo "==> Downloading libevent v${LIBEVENT_VERSION}"
mkdir -p /build/src
curl -fL "${LIBEVENT_URL}" -o "/build/src/libevent-${LIBEVENT_VERSION}.tar.gz"
tar -xzf "/build/src/libevent-${LIBEVENT_VERSION}.tar.gz" -C /build/src

echo "==> Building libevent (static)"
LIBEVENT_PREFIX="/build/libevent-static"
cd "/build/src/libevent-${LIBEVENT_VERSION}"
./configure --prefix="${LIBEVENT_PREFIX}" --disable-shared --enable-static --disable-openssl
make -j"$(nproc)"
make install

echo "==> Downloading tmux v${VERSION}"
curl -fL "${SOURCE_URL}" -o "/build/src/tmux-${VERSION}.tar.gz"
tar -xzf "/build/src/tmux-${VERSION}.tar.gz" -C /build/src

echo "==> Building tmux"
cd "/build/src/tmux-${VERSION}"
LIBEVENT_CORE_CFLAGS="-I${LIBEVENT_PREFIX}/include" \
LIBEVENT_CORE_LIBS="-L${LIBEVENT_PREFIX}/lib -levent_core" \
./configure
make -j"$(nproc)"

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp tmux "${STAGING}/bin/tmux"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
