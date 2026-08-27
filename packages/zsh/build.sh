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

# Dynamic module loading is kept enabled: some modules (zsh/stat, zsh/regex,
# zsh/pcre, zsh/net/socket, ...) are declared `link=dynamic` upstream with no
# static fallback, so --disable-dynamic silently drops them instead of linking
# them in. Relocatability is instead handled at runtime: module_path is
# compiled in as an absolute $prefix/lib path, but it's just a shell parameter,
# so it's set correctly by a .zshenv under a relocated ZDOTDIR (see below).
echo "==> Building zsh"
cd "/build/src/zsh-${VERSION}"
./configure --prefix=/opt/zsh --enable-pcre --enable-multibyte \
    --enable-function-subdirs
make -j"$(nproc)"

echo "==> Installing into staging directory"
STAGING="/build/staging/${ARTIFACT_NAME}"
INSTALL_ROOT="/build/install"
rm -rf "${INSTALL_ROOT}"
make install DESTDIR="${INSTALL_ROOT}"

mkdir -p "${STAGING}/bin" "${STAGING}/share" "${STAGING}/etc/zdotdir"
cp "${INSTALL_ROOT}/opt/zsh/bin/zsh" "${STAGING}/bin/zsh.bin"
cp -r "${INSTALL_ROOT}/opt/zsh/share/zsh" "${STAGING}/share/zsh"
cp -r "${INSTALL_ROOT}/opt/zsh/share/man" "${STAGING}/share/man"
cp -r "${INSTALL_ROOT}/opt/zsh/lib" "${STAGING}/lib"

# Completion/autoload functions live under share/zsh/<version>/functions and
# loadable modules under lib/zsh/<version>, both relative to the compiled-in
# /opt/zsh prefix, so fpath and module_path have to be set at runtime.
#
# fpath can be set via the FPATH env var, but module_path is deliberately
# PM_DONTIMPORT (Src/params.c) and can't be set that way. Instead, ZDOTDIR is
# pointed at a private dir whose .zshenv sets module_path, then restores
# ZDOTDIR to whatever it was originally (or unsets it) before any further
# startup file is read, so the user's own .zshenv/.zshrc/etc. still load from
# their real dotfile location.
FUNC_DIRS=$(find "${STAGING}/share/zsh" -type d | sed 's#.*/share/#${ROOT}/share/#' | paste -sd: -)
cat > "${STAGING}/etc/zdotdir/.zshenv" <<'ZSHENV'
module_path=("${_ZSH_TARBALL_ROOT}/lib/zsh/${ZSH_VERSION}")
unset _ZSH_TARBALL_ROOT
if [[ -n "${_ZSH_ORIG_ZDOTDIR:-}" ]]; then
  ZDOTDIR="${_ZSH_ORIG_ZDOTDIR}"
  unset _ZSH_ORIG_ZDOTDIR
else
  unset ZDOTDIR
fi
# This file itself took the place of $ZDOTDIR/.zshenv for the one startup
# stage that always runs, so the real one (if any) has to be sourced by hand;
# restoring ZDOTDIR above is only enough for the later stages (.zprofile,
# .zshrc, .zlogin), which zsh looks up fresh from the current ZDOTDIR value.
[[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"
ZSHENV
cat > "${STAGING}/bin/zsh" <<WRAPPER
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export FPATH="${FUNC_DIRS}"
export _ZSH_TARBALL_ROOT="\${ROOT}"
if [[ -n "\${ZDOTDIR:-}" ]]; then
    export _ZSH_ORIG_ZDOTDIR="\${ZDOTDIR}"
fi
export ZDOTDIR="\${ROOT}/etc/zdotdir"
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
