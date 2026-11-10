#!/usr/bin/env bash
# Builds maim (X11 screenshot tool) plus slop (region selector) from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="5.8.2"
NAME="maim"
SOURCE_URL="https://github.com/naelstrof/maim/archive/refs/tags/v${VERSION}.tar.gz"

# maim links libslopy (not packaged for EL), so slop is built from source and
# shipped in the same tarball. Pinned manually; the update checker tracks maim.
SLOP_VERSION="7.7"
SLOP_URL="https://github.com/naelstrof/slop/archive/refs/tags/v${SLOP_VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled crb
dnf install -y --allowerasing gcc gcc-c++ make cmake tar gzip curl ca-certificates patchelf \
    glew-devel glm-devel imlib2-devel libXcomposite-devel libXfixes-devel libicu-devel libjpeg-turbo-devel libpng-devel zlib-devel libwebp-devel libXext-devel libXrender-devel libXrandr-devel \
    libX11-devel mesa-libGL-devel mesa-libEGL-devel mesa-libGLU-devel libglvnd-devel

echo "==> Building slop v${SLOP_VERSION}"
mkdir -p /build/src
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
curl -fL "${SLOP_URL}" -o /build/src/slop.tar.gz
tar -xzf /build/src/slop.tar.gz -C /build/src
cmake -S "/build/src/slop-${SLOP_VERSION}" -B /build/src/slop-build -DCMAKE_INSTALL_PREFIX="${STAGING}" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib -DSLOP_OPENGL_ENABLED=true
cmake --build /build/src/slop-build -j"$(nproc)"
cmake --install /build/src/slop-build
export LD_LIBRARY_PATH="${STAGING}/lib"

echo "==> Downloading maim v${VERSION}"
curl -fL "${SOURCE_URL}" -o "/build/src/maim-${VERSION}.tar.gz"
tar -xzf "/build/src/maim-${VERSION}.tar.gz" -C /build/src

echo "==> Building maim"
cmake -S "/build/src/maim-${VERSION}" -B /build/src/maim-build -DCMAKE_INSTALL_PREFIX="${STAGING}" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="${STAGING}" \
    -DCMAKE_INCLUDE_PATH="${STAGING}/include" -DCMAKE_LIBRARY_PATH="${STAGING}/lib" \
    -DCMAKE_INSTALL_LIBDIR=lib
cmake --build /build/src/maim-build -j"$(nproc)"
cmake --install /build/src/maim-build

echo "==> Bundling libraries absent from a stock RHEL desktop"
mkdir -p "${STAGING}/lib"
BUNDLE_RE='/(libGLEW|libGLU|libImlib2|libicu[a-z0-9]*)[^/]*\.so'
is_elf() { [[ -f "$1" ]] && [[ "$(head -c4 "$1")" == $'\x7f'ELF ]]; }
bundle_deps() {
    local deps
    deps=$(ldd "$1" | awk '/=> \//{print $3}' | grep -E "${BUNDLE_RE}" || true)
    for dep in ${deps}; do cp -Ln "${dep}" "${STAGING}/lib/"; done
}
for bin in "${STAGING}"/bin/*; do is_elf "${bin}" && bundle_deps "${bin}"; done
for lib in "${STAGING}"/lib/*.so*; do bundle_deps "${lib}"; done

echo "==> Setting RPATH so the tarball is relocatable"
for bin in "${STAGING}"/bin/*; do
    if is_elf "${bin}"; then patchelf --set-rpath '$ORIGIN/../lib' "${bin}"; fi
done
for lib in "${STAGING}"/lib/*.so*; do
    if [[ ! -L "${lib}" ]]; then patchelf --set-rpath '$ORIGIN' "${lib}"; fi
done
ls "${STAGING}/lib"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
