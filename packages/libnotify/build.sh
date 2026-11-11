#!/usr/bin/env bash
# Builds libnotify (libnotify.so + notify-send) from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="0.8.9"
NAME="libnotify"
SOURCE_URL="https://download.gnome.org/sources/libnotify/0.8/libnotify-${VERSION}.tar.xz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled crb
dnf install -y --allowerasing gcc make python39 python39-pip ninja-build tar xz curl ca-certificates \
    pkgconf-pkg-config patchelf glib2-devel gdk-pixbuf2-devel

# libnotify needs meson >= 0.64; EL8's is 0.58, so use a pip-installed one.
python3.9 -m venv /build/venv
/build/venv/bin/pip install -q meson==1.4.2
export PATH="/build/venv/bin:${PATH}"

echo "==> Downloading libnotify v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/libnotify-${VERSION}.tar.xz"
tar -xJf "/build/src/libnotify-${VERSION}.tar.xz" -C /build/src

echo "==> Building libnotify"
cd "/build/src/libnotify-${VERSION}"
# EL8 has glib 2.56, but libnotify wants >= 2.62. It needs only two things
# beyond 2.56: g_clear_signal_handler() (2.62) and one g_uri_is_valid() call
# (GUri, 2.66), shimmed here. Meson links with --no-undefined, so any other
# missing glib symbol fails the build loudly instead of breaking at runtime.
sed -i "s/glib_req_version = '>= 2.62.0'/glib_req_version = '>= 2.56.0'/" meson.build
sed -i 's/g_uri_is_valid (priv->icon_name, G_URI_FLAGS_PARSE_RELAXED, NULL)/compat_is_uri (priv->icon_name)/' libnotify/notification.c
grep -q compat_is_uri libnotify/notification.c
cat > /build/glib-compat.h <<'COMPAT'
#include <glib-object.h>
#if !GLIB_CHECK_VERSION(2, 62, 0)
static inline void g_clear_signal_handler(gulong *id, gpointer instance) {
    if (*id > 0) { g_signal_handler_disconnect(instance, *id); *id = 0; }
}
#endif
static inline gboolean compat_is_uri(const char *s) {
    char *sc = g_uri_parse_scheme(s);
    gboolean r = sc != NULL;
    g_free(sc);
    return r;
}
COMPAT
sed -i '1i #include "/build/glib-compat.h"' libnotify/notification.c

STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}"
meson setup build --prefix="${STAGING}" --libdir=lib --buildtype=release \
    -Dtests=false -Dman=false -Dgtk_doc=false -Ddocbook_docs=disabled \
    -Dintrospection=disabled
ninja -C build
ninja -C build install

echo "==> Setting RPATH so the tarball is relocatable"
is_elf() { [[ -f "$1" ]] && [[ "$(head -c4 "$1")" == $'\x7f'ELF ]]; }
for bin in "${STAGING}"/bin/*; do
    if is_elf "${bin}"; then patchelf --set-rpath '$ORIGIN/../lib' "${bin}"; fi
done
for lib in "${STAGING}"/lib/*.so*; do
    if [[ ! -L "${lib}" ]]; then patchelf --set-rpath '$ORIGIN' "${lib}"; fi
done

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
