#!/usr/bin/env bash
# Smoke test for the maim package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

dnf install -y -q libX11 libXext libXrender libXrandr libXcomposite libXfixes libicu \
    libjpeg-turbo libpng libwebp mesa-libGL mesa-libEGL libglvnd-opengl xorg-x11-server-Xvfb file

ROOT="${1}"
export PATH="${ROOT}/bin:${PATH}"

echo "--- versions ---"
maim --version
slop --version

echo "--- ldd (must have no missing libs) ---"
for b in "${ROOT}"/bin/* "${ROOT}"/lib/*.so*; do
    [[ -f "${b}" ]] || continue
    head -c4 "${b}" | grep -q ELF || continue
    if ldd "${b}" | grep "not found"; then
        echo "ERROR: unresolved libraries in ${b}" >&2
        exit 1
    fi
done

echo "--- take screenshots under Xvfb ---"
Xvfb :99 -screen 0 1024x768x24 &
XVFB=$!
export DISPLAY=:99
sleep 2
cd "$(mktemp -d)"
maim shot.png
maim shot.jpg
file shot.png | grep -q 'PNG image data, 1024 x 768'
file shot.jpg | grep -q 'JPEG image data'
maim -g 100x100+10+10 crop.png
timeout 3 slop >/dev/null 2>&1 && rc=0 || rc=$?
[[ "${rc}" -eq 124 || "${rc}" -le 1 ]] || { echo "ERROR: slop exit ${rc}" >&2; exit 1; }
file crop.png | grep -q 'PNG image data, 100 x 100'
kill "${XVFB}" 2>/dev/null || true
echo "maim OK"
