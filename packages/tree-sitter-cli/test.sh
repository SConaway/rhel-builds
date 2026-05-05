#!/usr/bin/env bash
# Smoke test for the tree-sitter-cli package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

"${1}/tree-sitter" --version
