#!/usr/bin/env bash
# Builds git from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="2.54.0"
NAME="git"
SOURCE_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/git-${VERSION}.tar.gz"

# Detect distro for the artifact name
DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"  # e.g. almalinux8, almalinux9
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing \
    gcc make tar curl ca-certificates diffutils \
    openssl-devel libcurl-devel expat-devel zlib-devel \
    perl gettext pcre2-devel

echo "==> Downloading git v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/git-${VERSION}.tar.gz"
tar -xzf "/build/src/git-${VERSION}.tar.gz" -C /build/src

echo "==> Building git"
cd "/build/src/git-${VERSION}"
./configure --prefix=/usr/local --with-openssl --with-curl --with-expat
make -j"$(nproc)" all

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
make install DESTDIR="${STAGING}"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
