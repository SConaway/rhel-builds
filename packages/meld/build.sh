#!/usr/bin/env bash
# Builds a Meld AppImage inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

NAME="meld"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

echo "==> Installing packages"
dnf install -y --allowerasing epel-release
if [[ "${DISTRO_VERSION}" == "8" ]]; then
    dnf config-manager --set-enabled powertools
else
    dnf config-manager --set-enabled crb
fi
dnf install -y --allowerasing \
    meld \
    python3-gobject \
    gtksourceview3 \
    gtk3 \
    glib2 \
    gobject-introspection \
    gdk-pixbuf2 gdk-pixbuf2-modules \
    pango cairo atk libepoxy \
    adwaita-icon-theme hicolor-icon-theme \
    fribidi harfbuzz libthai libdatrie \
    fontconfig freetype \
    libX11 libXext libXrender libXi libXft libXrandr libXcursor \
    libxcb \
    fuse-libs \
    file \
    appstream \
    gsettings-desktop-schemas \
    curl ca-certificates

VERSION=$(rpm -q --qf '%{version}' meld)
ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"
echo "==> meld ${VERSION}"

# --- assemble AppDir ---
APPDIR="/build/appdir"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/share"

cp /usr/bin/meld "${APPDIR}/usr/bin/meld"
cp -r /usr/share/meld "${APPDIR}/usr/share/"
# GtkSourceView 3 ships default colour schemes (classic, etc.) that meld's own
# scheme inherits from.  Without these, GtkSourceView logs "bad install" warnings
# and custom colours fall back to defaults.
cp -r /usr/share/gtksourceview-3.0 "${APPDIR}/usr/share/" 2>/dev/null || true


# meld installs its action icons (meld-change-apply-right, etc.) into the hicolor
# icon theme.  GTK resolves icons by searching $XDG_DATA_DIRS/icons/, so the
# hicolor tree must be present in the AppDir for those icons to be found at runtime.
mkdir -p "${APPDIR}/usr/share/icons"
cp -r /usr/share/icons/hicolor "${APPDIR}/usr/share/icons/" 2>/dev/null || true
gtk-update-icon-cache -f "${APPDIR}/usr/share/icons/hicolor" 2>/dev/null || true

# GIO modules: bundle the build-host's modules so that on the target system GIO
# doesn't try to load the (ABI-incompatible) system gvfs modules.
mkdir -p "${APPDIR}/usr/lib64/gio/modules"
cp /usr/lib64/gio/modules/*.so "${APPDIR}/usr/lib64/gio/modules/" 2>/dev/null || true

# Compile and bundle GSettings schemas so meld can find them via XDG_DATA_DIRS.
# meld reads org.gnome.meld and org.gnome.desktop.interface (for system font).
# Bundle all schemas to avoid chasing cross-references one by one.
mkdir -p "${APPDIR}/usr/share/glib-2.0/schemas"
find /usr/share/glib-2.0/schemas -name "*.xml" -exec cp {} "${APPDIR}/usr/share/glib-2.0/schemas/" \;
glib-compile-schemas "${APPDIR}/usr/share/glib-2.0/schemas/"

# meld Python package
MELD_PKG=$(python3 -c "import meld, os; print(os.path.dirname(meld.__file__))")
cp -r "${MELD_PKG}" "${APPDIR}/usr/lib/meld"
# Patch the hardcoded DATADIR ("/usr/share/meld") to a path relative to conf.py in the bundle.
# __file__ at runtime = <squashfs-root>/usr/lib/meld/conf.py  → ../.. → usr/share/meld
sed -i "s|^DATADIR = \"/usr/share/meld\"|DATADIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'share', 'meld')|" \
    "${APPDIR}/usr/lib/meld/conf.py"
# Remove cached bytecode so Python re-compiles with the patched source
find "${APPDIR}/usr/lib/meld" -name "*.pyc" -delete
find "${APPDIR}/usr/lib/meld" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# cairo (pycairo) Python bindings
CAIRO_PKG=$(python3 -c "import cairo, os; print(os.path.dirname(cairo.__file__))")
cp -r "${CAIRO_PKG}" "${APPDIR}/usr/lib/cairo"

# gi Python bindings — split across two directories; merge both into the bundle.
# lib64 path: __init__.py + compiled .so files
# lib path:   gi/repository/ (the import hook) + gi/overrides/
GI_LIB64=$(python3 -c "import gi, os; print(os.path.dirname(gi.__file__))")
GI_LIB=$(find /usr/lib -path "*/site-packages/gi" -maxdepth 6 -type d 2>/dev/null | head -1)
mkdir -p "${APPDIR}/usr/lib/gi"
cp -r "${GI_LIB64}/." "${APPDIR}/usr/lib/gi/"
[[ -n "${GI_LIB}" ]] && cp -r "${GI_LIB}/." "${APPDIR}/usr/lib/gi/"

# Bundle Python3 interpreter + stdlib so the AppImage is self-contained.
# Merge lib and lib64 paths into usr/lib so PYTHONHOME works with a single prefix.
PYTHON3_REAL=$(readlink -f "$(command -v python3)")
PYTHON3_VER=$(python3 -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))")
cp "${PYTHON3_REAL}" "${APPDIR}/usr/bin/python3"
# On AlmaLinux 8/9, Python's stdlib lives in lib64/python3.X/ and PYTHONHOME
# substitutes the prefix, so we must mirror the same lib64 layout in the bundle.
mkdir -p "${APPDIR}/usr/lib64/python${PYTHON3_VER}"
[[ -d "/usr/lib64/python${PYTHON3_VER}" ]] && cp -r "/usr/lib64/python${PYTHON3_VER}/." "${APPDIR}/usr/lib64/python${PYTHON3_VER}/"
[[ -d "/usr/lib/python${PYTHON3_VER}" ]]   && cp -r "/usr/lib/python${PYTHON3_VER}/."   "${APPDIR}/usr/lib64/python${PYTHON3_VER}/"
# Drop site-packages; gi and meld are found via PYTHONPATH instead
rm -rf "${APPDIR}/usr/lib64/python${PYTHON3_VER}/site-packages"
# Ensure libpython is bundled (python3 binary depends on it but it's not a .so scanned below)
find /usr/lib64 /usr/lib -name "libpython3*.so*" 2>/dev/null | \
    while read -r f; do cp -P "${f}" "${APPDIR}/usr/lib64/" 2>/dev/null || true; done

# GI typelibs — copy all of them to avoid chasing transitive deps one by one
mkdir -p "${APPDIR}/usr/lib/girepository-1.0"
find /usr/lib64 /usr/lib -name "*.typelib" 2>/dev/null | \
    while read -r f; do cp "${f}" "${APPDIR}/usr/lib/girepository-1.0/" 2>/dev/null || true; done

# GTK stack shared libraries
mkdir -p "${APPDIR}/usr/lib64"
for lib in \
    libgtk-3 libgdk-3 \
    libglib-2.0 libgobject-2.0 libgio-2.0 libgmodule-2.0 \
    libgirepository-1.0 \
    libgdk_pixbuf-2.0 \
    libpango-1.0 libpangocairo-1.0 libpangoft2-1.0 \
    libcairo libcairo-gobject \
    libatk-1.0 \
    libepoxy \
    libgtksourceview-3.0 \
    libfribidi libharfbuzz libthai libdatrie \
    libfontconfig libfreetype \
    libX11 libXext libXrender libXi libXft libXrandr libXcursor libXfixes \
    libxcb libxcb-render libxcb-shm \
    libpng libjpeg libffi \
    libxml2 libpcre libpcre2 liblzma; do
    find /usr/lib64 /usr/lib -name "${lib}.so*" 2>/dev/null | \
        while read -r f; do cp -P "${f}" "${APPDIR}/usr/lib64/" 2>/dev/null || true; done
done

# GTK input methods and pixbuf loaders
cp -r /usr/lib64/gtk-3.0     "${APPDIR}/usr/lib64/" 2>/dev/null || true
cp -r /usr/lib64/gdk-pixbuf-2.0 "${APPDIR}/usr/lib64/" 2>/dev/null || true

# Resolve transitive shared-library dependencies.
# Walk all .so files in the AppDir, copy missing system libs, dereference symlinks.
# Repeat until no new files are added (handles multi-hop chains).
echo "==> Resolving transitive .so dependencies"
BUNDLE_LIB="${APPDIR}/usr/lib64"
CHANGED=1
while [[ "${CHANGED}" -eq 1 ]]; do
    CHANGED=0
    find "${APPDIR}" \( -name "*.so*" -o -path "*/bin/*" \) -type f | while read -r f; do
        ldd "${f}" 2>/dev/null | grep "=> /" | awk '{print $3}' || true
    done | sort -u | while read -r dep; do
        # Never bundle glibc internals — they must come from the host to avoid
        # GLIBC_PRIVATE symbol conflicts across RHEL8/9.
        case "$(basename "${dep}")" in
            libc.so* | libc-*.so | libpthread.so* | libpthread-*.so | \
            libdl.so* | libdl-*.so | libm.so* | libm-*.so | \
            libresolv.so* | libresolv-*.so | librt.so* | librt-*.so | \
            ld-linux*.so*) continue ;;
        esac
        # Resolve to the actual file (not a symlink)
        real=$(readlink -f "${dep}" 2>/dev/null) || continue
        bname=$(basename "${real}")
        if [[ -f "${real}" ]] && ! [[ -f "${BUNDLE_LIB}/${bname}" ]]; then
            cp "${real}" "${BUNDLE_LIB}/" 2>/dev/null && echo "  added ${bname}" && echo 1 > /tmp/_ldd_changed
        fi
        # Also create the soname symlink if absent
        sname=$(basename "${dep}")
        if [[ "${sname}" != "${bname}" ]] && ! [[ -e "${BUNDLE_LIB}/${sname}" ]]; then
            ln -sf "${bname}" "${BUNDLE_LIB}/${sname}" 2>/dev/null || true
        fi
    done
    [[ -f /tmp/_ldd_changed ]] && CHANGED=1 && rm -f /tmp/_ldd_changed
done

# Desktop entry — appimagetool requires exactly one .desktop file in the AppDir root.
# Normalize Icon= to "meld" so it matches the icon file we copy below.
DESKTOP=$(find /usr/share/applications -iname "*meld*.desktop" 2>/dev/null | head -1)
if [[ -n "${DESKTOP}" ]]; then
    sed 's|^Icon=.*|Icon=meld|' "${DESKTOP}" > "${APPDIR}/meld.desktop"
else
    cat > "${APPDIR}/meld.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Meld
Exec=meld
Icon=meld
Type=Application
Categories=Development;
DESKTOP
fi

# Icon — must be named to match Icon=meld above
ICON=$(find /usr/share/icons -iname "*meld*.svg" 2>/dev/null | grep -v symbolic | head -1)
if [[ -n "${ICON}" ]]; then
    cp "${ICON}" "${APPDIR}/meld.svg"
else
    ICON=$(find /usr/share/icons -iname "*meld*.png" 2>/dev/null | sort -t/ -k7 -rn | head -1)
    [[ -n "${ICON}" ]] && cp "${ICON}" "${APPDIR}/meld.png"
fi

echo "==> AppDir desktop: $(ls "${APPDIR}"/*.desktop 2>/dev/null || echo 'MISSING')"
echo "==> AppDir icon:    $(ls "${APPDIR}"/meld.* 2>/dev/null || echo 'MISSING')"

# AppRun entry point
cat > "${APPDIR}/AppRun" <<'APPRUN'
#!/usr/bin/env bash
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${HERE}/usr/lib64:${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
export GI_TYPELIB_PATH="${HERE}/usr/lib/girepository-1.0:${GI_TYPELIB_PATH:-}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GIO_MODULE_DIR="${HERE}/usr/lib64/gio/modules"
export PYTHONHOME="${HERE}/usr"
export PYTHONPATH="${HERE}/usr/lib:${PYTHONPATH:-}"
exec "${HERE}/usr/bin/python3" "${HERE}/usr/bin/meld" "$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

# --- download and extract appimagetool (Docker containers lack FUSE) ---
echo "==> Downloading appimagetool"
curl -fL \
    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
    -o /build/appimagetool.AppImage
chmod +x /build/appimagetool.AppImage
cd /build
./appimagetool.AppImage --appimage-extract
APPIMAGETOOL="/build/squashfs-root/AppRun"

# --- create AppImage ---
echo "==> Creating AppImage"
ARCH="${ARCH}" "${APPIMAGETOOL}" "${APPDIR}" "/build/${ARTIFACT_NAME}.AppImage"

# --- wrap in tarball (matches repo convention) ---
STAGING="/build/staging/${ARTIFACT_NAME}"
mkdir -p "${STAGING}/bin"
cp "/build/${ARTIFACT_NAME}.AppImage" "${STAGING}/bin/${NAME}.AppImage"
chmod +x "${STAGING}/bin/${NAME}.AppImage"

mkdir -p /build/output
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksum"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"
echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
