#!/usr/bin/env bash
# Smoke test for the tree-sitter-cli package. Runs inside the container; receives artifact root as $1.
set -euo pipefail

TS="${1}/tree-sitter"

echo "--- tree-sitter --version ---"
"${TS}" --version

# Exercise the actual grammar-generation engine (not just the version flag) by
# generating a parser from a minimal grammar.js. tree-sitter generate embeds a
# JS engine to evaluate grammar.js, so this works with no C compiler or node.
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "--- tree-sitter generate ---"
cat > "${TMPDIR}/grammar.js" <<'EOF'
module.exports = grammar({
  name: 'mini',
  rules: {
    source_file: $ => 'hello',
  },
});
EOF

(cd "${TMPDIR}" && "${TS}" generate --js-runtime native)

if [[ ! -f "${TMPDIR}/src/parser.c" ]]; then
    echo "ERROR: generate did not produce src/parser.c" >&2
    exit 1
fi

if ! grep -q 'tree_sitter_mini' "${TMPDIR}/src/parser.c"; then
    echo "ERROR: generated parser.c missing expected tree_sitter_mini entry point" >&2
    exit 1
fi

echo "Generated parser for grammar 'mini' successfully"
