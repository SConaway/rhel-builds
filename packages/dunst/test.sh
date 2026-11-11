#!/usr/bin/env bash
# Smoke test for the dunst package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

dnf install -y -q pango cairo gdk-pixbuf2 glib2 dbus-daemon dbus-tools libX11 libXrandr \
    libXScrnSaver libXinerama libwayland-client libwayland-cursor xorg-x11-server-Xvfb

ROOT="${1}"
export PATH="${ROOT}/bin:${PATH}"

echo "--- dunst --version ---"
dunst --version

echo "--- ldd (must have no missing libs) ---"
for b in "${ROOT}"/bin/* "${ROOT}"/lib/*.so*; do
    [[ -f "${b}" ]] || continue
    head -c4 "${b}" | grep -q ELF || continue
    if ldd "${b}" | grep "not found"; then
        echo "ERROR: unresolved libraries in ${b}" >&2
        exit 1
    fi
done

echo "--- run dunst under Xvfb + a session bus ---"
Xvfb :99 -screen 0 1024x768x24 &
XVFB=$!
export DISPLAY=:99
sleep 2
cat > /tmp/inner.sh <<'INNER'
set -eu
dunst &
DUNST=$!
sleep 2
gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    smoke 0 "" "hello" "from dunst test" '[]' '{}' 0
sleep 1
n=$(dunstctl count displayed)
echo "displayed notifications: ${n}"
[ "${n}" -ge 1 ]
kill "${DUNST}"
INNER
dbus-run-session -- bash /tmp/inner.sh
kill "${XVFB}" 2>/dev/null || true
echo "dunst OK"
