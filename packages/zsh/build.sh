#!/usr/bin/env bash
# Builds zsh from source inside an AlmaLinux 8/9 container.
# Called by the top-level build.sh. Writes artifacts to /build/output.
set -euo pipefail

VERSION="5.9.2"
NAME="zsh"
SOURCE_URL="https://downloads.sourceforge.net/project/zsh/zsh/${VERSION}/zsh-${VERSION}.tar.xz"

DISTRO_ID=$(. /etc/os-release && echo "${ID}")
DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID}" | cut -d. -f1)
PLATFORM="${DISTRO_ID}${DISTRO_VERSION}"
ARCH=$(uname -m)

ARTIFACT_NAME="${NAME}-${VERSION}-${PLATFORM}-${ARCH}"

echo "==> Installing build dependencies"
dnf install -y --allowerasing gcc make ncurses-devel pcre2-devel tar curl ca-certificates xz

echo "==> Downloading zsh v${VERSION}"
mkdir -p /build/src
curl -fL "${SOURCE_URL}" -o "/build/src/zsh-${VERSION}.tar.xz"
tar -xJf "/build/src/zsh-${VERSION}.tar.xz" -C /build/src

# --disable-dynamic links every module directly into the zsh binary instead of
# as separate .so files under a compiled-in $prefix/lib path. Without it, the
# module search path is baked in at configure time and breaks the moment the
# tarball is extracted anywhere other than that exact path.
echo "==> Building zsh"
cd "/build/src/zsh-${VERSION}"
./configure --prefix=/opt/zsh --enable-pcre --enable-multibyte \
    --enable-function-subdirs --disable-dynamic
make -j"$(nproc)"

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
INSTALL_ROOT="/build/install"
rm -rf "${INSTALL_ROOT}"
make install DESTDIR="${INSTALL_ROOT}"

mkdir -p "${STAGING}/bin" "${STAGING}/share"
cp "${INSTALL_ROOT}/opt/zsh/bin/zsh" "${STAGING}/bin/zsh.bin"
cp -r "${INSTALL_ROOT}/opt/zsh/share/zsh" "${STAGING}/share/zsh"
cp -r "${INSTALL_ROOT}/opt/zsh/share/man" "${STAGING}/share/man"

# Completion/autoload functions still live under share/zsh/<version>/functions
# rather than the compiled-in prefix, so fpath has to be set at runtime. The
# module search path itself no longer matters since --disable-dynamic removed
# all loadable modules.
FUNC_DIRS=$(find "${STAGING}/share/zsh" -type d | sed 's#.*/share/#${ROOT}/share/#' | paste -sd: -)
cat > "${STAGING}/bin/zsh" <<WRAPPER
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export FPATH="${FUNC_DIRS}"
exec -a zsh "\${ROOT}/bin/zsh.bin" "\$@"
WRAPPER
chmod +x "${STAGING}/bin/zsh"

echo "==> Packaging"
TARBALL="/build/output/${ARTIFACT_NAME}.tar.gz"
tar -czf "${TARBALL}" -C /build/staging "${ARTIFACT_NAME}"

echo "==> Generating checksums"
cd /build/output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "==> Done"
cat "${ARTIFACT_NAME}.tar.gz.sha256"
