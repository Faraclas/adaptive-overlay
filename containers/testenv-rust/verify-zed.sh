#!/bin/bash
# verify-zed.sh — verify the zed build output after a successful compile.
#
# Called by test-ebuild.yml with one argument: the path to the portage
# build image directory, e.g.:
#   /var/tmp/portage/app-editors/zed-0.227.1/image
#
# Checks:
#   1. Expected binaries exist in the image
#   2. zedit --version reports a plausible version string
#   3. ldd on the main zed-editor binary shows no missing libraries

set -euo pipefail

BUILD_IMAGE="${1:-}"

if [ -z "${BUILD_IMAGE}" ]; then
    echo "Usage: $(basename "$0") <build-image-dir>" >&2
    exit 1
fi

if [ ! -d "${BUILD_IMAGE}" ]; then
    echo "error: build image directory not found: ${BUILD_IMAGE}" >&2
    exit 1
fi

PASS=0
FAIL=0

pass() { echo "  ✓ $*"; (( PASS++ )) || true; }
fail() { echo "  ✗ $*" >&2; (( FAIL++ )) || true; }

echo "==> Verifying zed build image: ${BUILD_IMAGE}"
echo ""

# ---------------------------------------------------------------------------
# 1. Check expected binaries and symlinks exist
# ---------------------------------------------------------------------------
echo "--- Binaries ---"

ZEDIT="${BUILD_IMAGE}/usr/bin/zedit"
ZED_SYMLINK="${BUILD_IMAGE}/usr/bin/zed"
ZED_EDITOR="${BUILD_IMAGE}/usr/libexec/zed-editor"

if [ -f "${ZEDIT}" ]; then
    pass "usr/bin/zedit exists"
else
    fail "usr/bin/zedit not found"
fi

if [ -L "${ZED_SYMLINK}" ] || [ -f "${ZED_SYMLINK}" ]; then
    pass "usr/bin/zed exists (symlink to zedit)"
else
    fail "usr/bin/zed not found"
fi

if [ -f "${ZED_EDITOR}" ]; then
    pass "usr/libexec/zed-editor exists"
else
    fail "usr/libexec/zed-editor not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Version check — zedit --version should report a plausible semver string
# ---------------------------------------------------------------------------
echo "--- Version ---"

if [ -f "${ZEDIT}" ]; then
    VERSION_OUTPUT=$("${ZEDIT}" --version 2>&1 || true)
    echo "  zedit --version: ${VERSION_OUTPUT}"

    if echo "${VERSION_OUTPUT}" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
        pass "version string looks valid"
    else
        fail "version string does not contain a semver pattern"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 3. ldd check — zed-editor should have no missing shared libraries
# ---------------------------------------------------------------------------
echo "--- Dynamic linkage (zed-editor) ---"

if [ -f "${ZED_EDITOR}" ]; then
    LDD_OUTPUT=$(ldd "${ZED_EDITOR}" 2>&1 || true)
    echo "${LDD_OUTPUT}" | sed 's/^/  /'
    echo ""

    if echo "${LDD_OUTPUT}" | grep -q "not found"; then
        MISSING=$(echo "${LDD_OUTPUT}" | grep "not found")
        fail "missing shared libraries detected:"
        echo "${MISSING}" | sed 's/^/    /' >&2
    else
        pass "no missing shared libraries"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "--- Summary ---"
echo "  Passed : ${PASS}"
echo "  Failed : ${FAIL}"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    echo "::error::zed verification failed with ${FAIL} check(s) failing"
    exit 1
fi

echo "::notice::zed verification passed (${PASS} checks)"
