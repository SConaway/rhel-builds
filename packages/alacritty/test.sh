#!/usr/bin/env bash
# Smoke test for the alacritty package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

"${1}/bin/alacritty" --version
