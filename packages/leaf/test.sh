#!/usr/bin/env bash
# Smoke test for the leaf package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

"${1}/bin/leaf" --version
