#!/usr/bin/env bash
# Builds alacritty from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="0.17.0"
NAME="alacritty"
SOURCE_URL="https://github.com/alacritty/alacritty/archive/refs/tags/v${VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing epel-release
if [[ "${DISTRO_VERSION}" == "8" ]]; then
    dnf config-manager --set-enabled powertools
else
    dnf config-manager --set-enabled crb
fi
dnf install -y --allowerasing \
    gcc gcc-c++ make cmake pkg-config \
    freetype-devel fontconfig-devel \
    libxcb-devel libxkbcommon-devel \
    ncurses \
    tar curl ca-certificates

echo "==> Installing Rust toolchain"
export RUSTUP_HOME=/build/rustup
export CARGO_HOME=/build/cargo
curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
source /build/cargo/env

echo "==> Downloading alacritty v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/alacritty-${VERSION}.tar.gz"
tar -xzf "/build/src/alacritty-${VERSION}.tar.gz" -C /build/src

echo "==> Building alacritty"
cd "/build/src/alacritty-${VERSION}"
cargo build --release -p alacritty

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp target/release/alacritty "${STAGING}/bin/alacritty"

echo "==> Packaging binary"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Source extra/ contents"
find extra/ -type f | sort

echo "==> Packaging extras (completions + config)"
EXTRAS_NAME="${NAME}-extras-${VERSION}"
EXTRAS_STAGING="/build/staging/${EXTRAS_NAME}"
mkdir -p "${EXTRAS_STAGING}/completions"
cp extra/completions/alacritty.bash  "${EXTRAS_STAGING}/completions/alacritty.bash"
cp extra/completions/alacritty.fish  "${EXTRAS_STAGING}/completions/alacritty.fish"
cp extra/completions/_alacritty      "${EXTRAS_STAGING}/completions/_alacritty"
# sample toml not present in all releases
if [[ -f "extra/alacritty.toml" ]]; then
    cp extra/alacritty.toml "${EXTRAS_STAGING}/alacritty.toml"
else
    echo "==> Note: no extra/alacritty.toml in source, skipping"
fi
# terminfo (alacritty.info defines both alacritty and alacritty-direct since v0.12)
if [[ -f "extra/alacritty.info" ]]; then
    mkdir -p "${EXTRAS_STAGING}/terminfo"
    tic -xe alacritty,alacritty-direct -o "${EXTRAS_STAGING}/terminfo" extra/alacritty.info
else
    echo "==> Note: no extra/alacritty.info in source, skipping terminfo"
fi
# .desktop file
if [[ -f "extra/linux/Alacritty.desktop" ]]; then
    mkdir -p "${EXTRAS_STAGING}/desktop"
    cp extra/linux/Alacritty.desktop "${EXTRAS_STAGING}/desktop/Alacritty.desktop"
else
    echo "==> Note: no extra/linux/Alacritty.desktop in source, skipping"
fi
mkdir -p /build/output/extras
EXTRAS_TARBALL="/build/output/extras/${EXTRAS_NAME}.tar.gz"
tar -czf "${EXTRAS_TARBALL}" -C /build/staging "${EXTRAS_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz"  > "${ARTIFACT_NAME}.tar.gz.sha256"
cd /build/output/extras
sha256sum "${EXTRAS_NAME}.tar.gz"    > "${EXTRAS_NAME}.tar.gz.sha256"

echo "==> Done"
cat "/build/output/${ARTIFACT_NAME}.tar.gz.sha256"
cat "/build/output/extras/${EXTRAS_NAME}.tar.gz.sha256"
