#!/usr/bin/env bash
# Builds i3 from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="4.25.1"
NAME="i3"
SOURCE_URL="https://i3wm.org/downloads/i3-${VERSION}.tar.xz"

XCB_UTIL_XRM_VERSION="1.3"
XCB_UTIL_XRM_URL="https://github.com/Airblader/xcb-util-xrm/releases/download/v${XCB_UTIL_XRM_VERSION}/xcb-util-xrm-${XCB_UTIL_XRM_VERSION}.tar.bz2"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools
dnf install -y --allowerasing gcc make tar xz bzip2 curl ca-certificates \
    pkgconf-pkg-config m4 file meson ninja-build patchelf perl \
    libev-devel yajl-devel pcre2-devel pango-devel cairo-devel \
    startup-notification-devel libxkbcommon-devel libxkbcommon-x11-devel \
    xcb-util-devel xcb-util-wm-devel xcb-util-keysyms-devel xcb-util-cursor-devel \
    libxcb-devel

# xcb-util-xrm is not packaged for EL8, so build it from source (shared; its
# .so gets bundled into the tarball below).
echo "==> Building xcb-util-xrm v${XCB_UTIL_XRM_VERSION}"
mkdir -p /build/src
curl -fL "${XCB_UTIL_XRM_URL}" -o /build/src/xcb-util-xrm.tar.bz2
tar -xjf /build/src/xcb-util-xrm.tar.bz2 -C /build/src
XRM_PREFIX="/build/xrm"
cd "/build/src/xcb-util-xrm-${XCB_UTIL_XRM_VERSION}"
./configure --prefix="${XRM_PREFIX}" --disable-static
make -j"$(nproc)"
make install
export PKG_CONFIG_PATH="${XRM_PREFIX}/lib/pkgconfig:${XRM_PREFIX}/lib64/pkgconfig"
export LD_LIBRARY_PATH="${XRM_PREFIX}/lib"
export CFLAGS="-I${XRM_PREFIX}/include"
export LDFLAGS="-L${XRM_PREFIX}/lib"

echo "==> Downloading i3 v${VERSION}"
curl -fL "${SOURCE_URL}" -o "/build/src/i3-${VERSION}.tar.xz"
tar -xJf "/build/src/i3-${VERSION}.tar.xz" -C /build/src

echo "==> Building i3"
cd "/build/src/i3-${VERSION}"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
meson setup build --prefix="${STAGING}" --sysconfdir="${STAGING}/etc" \
    --buildtype=release -Ddocs=false -Dmans=false
ninja -C build
ninja -C build install

echo "==> Bundling libraries absent from a stock RHEL desktop"
mkdir -p "${STAGING}/lib"
BUNDLE_RE='/(libev|libyajl|libstartup-notification|libxkbcommon-x11|libxcb-(util|keysyms|icccm|cursor|xrm|image|render-util))[^/]*\.so'
is_elf() { [[ -f "$1" ]] && [[ "$(head -c4 "$1")" == $'\x7f'ELF ]]; }

bundle_deps() {
    local deps
    deps=$(ldd "$1" | awk '/=> \//{print $3}' | grep -E "${BUNDLE_RE}" || true)
    for dep in ${deps}; do
        cp -Ln "${dep}" "${STAGING}/lib/"
    done
}

for bin in "${STAGING}"/bin/*; do
    is_elf "${bin}" && bundle_deps "${bin}"
done
# libs pulled in by bundled libs (e.g. libxcb-cursor -> libxcb-image)
for lib in "${STAGING}"/lib/*.so*; do
    bundle_deps "${lib}"
done

echo "==> Setting RPATH so the tarball is relocatable"
for bin in "${STAGING}"/bin/*; do
    if is_elf "${bin}"; then patchelf --set-rpath '$ORIGIN/../lib' "${bin}"; fi
done
for lib in "${STAGING}"/lib/*.so*; do
    if [[ ! -L "${lib}" ]]; then patchelf --set-rpath '$ORIGIN' "${lib}"; fi
done
ls "${STAGING}/lib"

echo "==> Adding session helpers"
mkdir -p "${STAGING}/share/doc/i3"
cat > "${STAGING}/share/doc/i3/xsession.example" <<'XS'
# Example ~/.xsession (adjust I3_ROOT to where you unpacked the tarball)
I3_ROOT="$HOME/opt/i3"
export PATH="$I3_ROOT/bin:$PATH"
[ -f ~/.config/i3/config ] || { mkdir -p ~/.config/i3; cp "$I3_ROOT/etc/i3/config" ~/.config/i3/config; }
exec i3
XS

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
