#!/usr/bin/env bash
# Builds tree-sitter-cli from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="0.26.8"
NAME="tree-sitter"
SOURCE_URL="https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v${VERSION}.tar.gz"

# Detect distro for the artifact name
DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"  # e.g. almalinux8, almalinux9
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc make tar curl ca-certificates clang-devel

echo "==> Installing Rust via rustup"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
source "$HOME/.cargo/env"
rustc --version
cargo --version

echo "==> Downloading tree-sitter v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/tree-sitter-${VERSION}.tar.gz"
tar -xzf "/build/src/tree-sitter-${VERSION}.tar.gz" -C /build/src

echo "==> Building tree-sitter-cli"
cd "/build/src/tree-sitter-${VERSION}"
cargo build --release -p tree-sitter-cli

BINARY="target/release/tree-sitter"
if [[ ! -f "${BINARY}" ]]; then
    echo "ERROR: Expected binary not found at ${BINARY}" >&2
    exit 1
fi

echo "==> Packaging"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
cp "${BINARY}" "${STAGING}/tree-sitter"

TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
