#!/usr/bin/env bash
# Smoke test for the alacritty package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

# Install runtime libs present on a real RHEL8 system but absent in the minimal test image.
dnf install -y -q fontconfig freetype libxcb libxkbcommon wayland

"${1}/bin/alacritty" --version
