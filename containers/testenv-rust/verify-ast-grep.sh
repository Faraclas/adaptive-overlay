#!/bin/bash
# Verify staged dev-util/ast-grep image
set -euo pipefail

if [[ $# -ne 1 || ! -d $1 ]]; then
    echo "Usage: ${0##*/} <build-image-dir>" >&2
    exit 1
fi

IMAGE_DIR="$1"
BINARY="${IMAGE_DIR}/usr/bin/ast-grep"

if [[ ! -x "${BINARY}" ]]; then
    echo "error: ${BINARY} is missing or not executable" >&2
    exit 1
fi

echo "==> Testing ${BINARY} --version"
"${BINARY}" --version

echo "==> Running smoke test with ast-grep"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

cat <<'EOF' > "${TMPDIR}/test.py"
def hello():
    print("world")
EOF

# Test pattern search
output=$("${BINARY}" run -p 'print($A)' --lang python "${TMPDIR}")
if ! echo "${output}" | grep -q 'world'; then
    echo "error: ast-grep failed pattern match on test file" >&2
    echo "Output: ${output}" >&2
    exit 1
fi

echo "==> dev-util/ast-grep smoke test passed successfully!"
