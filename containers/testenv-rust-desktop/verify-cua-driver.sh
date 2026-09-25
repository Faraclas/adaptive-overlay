#!/bin/bash
# verify-cua-driver.sh — verify the x11-misc/cua-driver build output.
#
# Called by scripts/test-build.sh (and CI) with one argument: the portage
# build image directory, e.g.
#   /var/tmp/portage/x11-misc/cua-driver-0.28.3/image
#
# Checks:
#   1. Expected binaries exist and are executable
#   2. cua-driver --version reports the ebuild version
#   3. ldd shows no missing libraries
#   4. The Gentoo portage-managed patch is active (update --apply refuses)
#   5. The WinRects extension is installed when USE=gnome was used

set -euo pipefail

BUILD_IMAGE="${1:-}"
if [ -z "${BUILD_IMAGE}" ] || [ ! -d "${BUILD_IMAGE}" ]; then
    echo "Usage: $(basename "$0") <build-image-dir>" >&2
    exit 1
fi

PASS=0
FAIL=0
pass() { echo "  ✓ $*"; (( PASS++ )) || true; }
fail() { echo "  ✗ $*" >&2; (( FAIL++ )) || true; }

# PV from the image path: .../cua-driver-0.28.3[-rN]/image
PVR="$(basename "$(dirname "${BUILD_IMAGE}")")"
PVR="${PVR#cua-driver-}"
PV="${PVR%-r[0-9]*}"

echo "==> Verifying cua-driver build image: ${BUILD_IMAGE} (PV=${PV})"
echo ""

echo "--- Binaries ---"
for b in cua-driver cua-cursor-theme; do
    if [ -x "${BUILD_IMAGE}/usr/bin/${b}" ]; then
        pass "/usr/bin/${b}"
    else
        fail "/usr/bin/${b} missing or not executable"
    fi
done
DRV="${BUILD_IMAGE}/usr/bin/cua-driver"

echo ""
echo "--- Version ---"
VER_OUT="$(CUA_DRIVER_RS_TELEMETRY_ENABLED=0 "${DRV}" --version 2>&1 || true)"
echo "    ${VER_OUT}"
if grep -q "${PV}" <<<"${VER_OUT}"; then
    pass "--version reports ${PV}"
else
    fail "--version does not report ${PV}"
fi

echo ""
echo "--- Shared libraries ---"
for b in cua-driver cua-cursor-theme; do
    MISSING="$(ldd "${BUILD_IMAGE}/usr/bin/${b}" 2>&1 | grep "not found" || true)"
    if [ -z "${MISSING}" ]; then
        pass "${b}: all libraries resolved"
    else
        fail "${b}: missing libraries:"
        echo "${MISSING}" >&2
    fi
done

echo ""
echo "--- Portage-managed patch ---"
# The patch treats any binary under /usr/bin as package-managed. The image
# binary is not there, so copy it into /usr/bin of this throwaway
# container, run update --apply (must refuse without downloading), and
# remove the copy again.
TMP_BIN="/usr/bin/cua-driver-verify.$$"
install -m 0755 "${DRV}" "${TMP_BIN}"
UPD_OUT="$(CUA_DRIVER_RS_TELEMETRY_ENABLED=0 \
    timeout 30 "${TMP_BIN}" update --apply 2>&1 || true)"
rm -f "${TMP_BIN}"
if grep -qi "emerge" <<<"${UPD_OUT}"; then
    pass "update --apply refuses and points at emerge"
else
    fail "update --apply did not refuse with emerge guidance:"
    echo "${UPD_OUT}" | head -5 >&2
fi

echo ""
echo "--- GNOME extension ---"
EXT="${BUILD_IMAGE}/usr/share/gnome-shell/extensions/winrects@cua"
if [ -d "${EXT}" ]; then
    for f in metadata.json extension.js; do
        if [ -f "${EXT}/${f}" ]; then
            pass "winrects@cua/${f}"
        else
            fail "winrects@cua/${f} missing"
        fi
    done
else
    echo "  - winrects@cua not installed (USE=-gnome); skipped"
fi

echo ""
echo "==> ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
