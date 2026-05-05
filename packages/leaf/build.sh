#!/usr/bin/env bash
# Builds leaf from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="1.18.2"
NAME="leaf"
SOURCE_URL="https://github.com/RivoLink/leaf/archive/refs/tags/${VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc make tar curl ca-certificates

echo "==> Installing Rust toolchain"
export RUSTUP_HOME=/build/rustup
export CARGO_HOME=/build/cargo
curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
source /build/cargo/env

echo "==> Downloading leaf v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/leaf-${VERSION}.tar.gz"
tar -xzf "/build/src/leaf-${VERSION}.tar.gz" -C /build/src

echo "==> Building leaf"
cd "/build/src/leaf-${VERSION}"
cargo build --release

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp target/release/leaf "${STAGING}/bin/leaf"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
