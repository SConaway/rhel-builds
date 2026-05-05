#!/usr/bin/env bash
# Smoke test for the git package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

GIT="${1}/usr/local/bin/git"

echo "--- git --version ---"
"${GIT}" --version

echo "--- git clone ---"
"${GIT}" clone https://github.com/octocat/Hello-World /tmp/hello-world
echo "Clone succeeded: $(ls /tmp/hello-world)"
