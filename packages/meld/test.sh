#!/usr/bin/env bash
# Smoke test for the meld package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

APPIMAGE="${1}/bin/meld.AppImage"
chmod +x "${APPIMAGE}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${TMPDIR}"
"${APPIMAGE}" --appimage-extract > /dev/null

# GDK_BACKEND=offscreen is not a valid GTK3 display backend; use Xvfb instead.
dnf install -y xorg-x11-server-Xvfb 2>/dev/null | grep -E '^(Complete|Nothing)' || true
Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 1

DISPLAY=:99 squashfs-root/AppRun --version
STATUS=$?

kill "${XVFB_PID}" 2>/dev/null || true
exit "${STATUS}"
