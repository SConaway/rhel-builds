#!/usr/bin/env bash
# Builds dunst from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="1.13.2"
NAME="dunst"
SOURCE_URL="https://github.com/dunst-project/dunst/archive/refs/tags/v${VERSION}.tar.gz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled crb
dnf install -y --allowerasing gcc make tar gzip curl ca-certificates pkgconf-pkg-config patchelf \
    glib2-devel dbus-devel pango-devel cairo-devel gdk-pixbuf2-devel \
    libX11-devel libXScrnSaver-devel libXinerama-devel libXrandr-devel \
    wayland-devel wayland-protocols-devel perl-podlators

echo "==> Downloading dunst v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/dunst-${VERSION}.tar.gz"
tar -xzf "/build/src/dunst-${VERSION}.tar.gz" -C /build/src

# EL8 ships glib 2.56; dunst uses g_rc_box_* (glib >= 2.58, only in draw.c).
# Provide a tiny equivalent when building against an older glib.
cat > /build/glib-compat.h <<'COMPAT'
#include <glib.h>
#if !GLIB_CHECK_VERSION(2, 58, 0)
typedef struct { gint refcount; gint pad[3]; } rcbox_hdr_compat;
static inline gpointer g_rc_box_alloc(gsize n) {
    rcbox_hdr_compat *h = g_malloc0(sizeof(*h) + n);
    h->refcount = 1;
    return h + 1;
}
static inline gpointer g_rc_box_acquire(gpointer p) {
    g_atomic_int_inc(&((rcbox_hdr_compat *)p - 1)->refcount);
    return p;
}
static inline void g_rc_box_release_full(gpointer p, GDestroyNotify clear) {
    rcbox_hdr_compat *h = (rcbox_hdr_compat *)p - 1;
    if (g_atomic_int_dec_and_test(&h->refcount)) {
        if (clear) clear(p);
        g_free(h);
    }
}
#endif
COMPAT

echo "==> Building dunst"
cd "/build/src/dunst-${VERSION}"
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
# dunstify (optional helper) needs libnotify headers; use notify-send from the libnotify package.
make -j"$(nproc)" doc dunst dunstctl service EXTRA_CFLAGS="-include /build/glib-compat.h" WAYLAND=1 SYSTEMD=0 VERSION="${VERSION}"
make install-dunst install-dunstctl install-dunstrc install-service PREFIX="${STAGING}" WAYLAND=1 SYSTEMD=0 VERSION="${VERSION}" \
    SERVICEDIR_DBUS="${STAGING}/share/dbus-1/services" SERVICEDIR_SYSTEMD="${STAGING}/lib/systemd/user"

echo "==> Bundling libraries absent from a stock RHEL desktop"
mkdir -p "${STAGING}/lib"
BUNDLE_RE='/(libXss|libXinerama)[^/]*\.so'
is_elf() { [[ -f "$1" ]] && [[ "$(head -c4 "$1")" == $'\x7f'ELF ]]; }
for bin in "${STAGING}"/bin/*; do
    is_elf "${bin}" || continue
    for dep in $(ldd "${bin}" | awk '/=> \//{print $3}' | grep -E "${BUNDLE_RE}" || true); do
        cp -Ln "${dep}" "${STAGING}/lib/"
    done
done

echo "==> Setting RPATH so the tarball is relocatable"
for bin in "${STAGING}"/bin/*; do
    if is_elf "${bin}"; then patchelf --set-rpath '$ORIGIN/../lib' "${bin}"; fi
done
for lib in "${STAGING}"/lib/*.so*; do
    [[ -e "${lib}" && ! -L "${lib}" ]] && patchelf --set-rpath '$ORIGIN' "${lib}"
done
ls "${STAGING}/lib" "${STAGING}/bin"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
