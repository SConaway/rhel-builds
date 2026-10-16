#!/usr/bin/env bash
# Smoke test for the i3 package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

# Runtime libs present on a real RHEL8 desktop but absent in the minimal test image,
# plus a virtual X server to actually start i3 against.
dnf install -y -q pango cairo libxkbcommon libxcb xorg-x11-server-Xvfb

ROOT="${1}"
export PATH="${ROOT}/bin:${PATH}"

echo "--- i3 --version ---"
i3 --version

echo "--- ldd (must have no missing libs) ---"
for b in "${ROOT}"/bin/*; do
    head -c4 "${b}" | grep -q ELF || continue
    if ldd "${b}" | grep "not found"; then
        echo "ERROR: unresolved libraries in ${b}" >&2
        exit 1
    fi
done

echo "--- start i3 under Xvfb ---"
Xvfb :99 -screen 0 1024x768x24 &
XVFB=$!
export DISPLAY=:99
sleep 2
i3 -c "${ROOT}/etc/i3/config" &
I3=$!
sleep 2
i3-msg -t get_version
i3-msg -t get_workspaces
i3-msg exit || true
kill "${XVFB}" 2>/dev/null || true
wait "${I3}" 2>/dev/null || true
