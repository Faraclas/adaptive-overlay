#!/bin/bash
# test-build.sh — build-test an ebuild inside the adaptive-overlay container.
#
# Runs `ebuild clean compile` for the given package inside the appropriate
# Gentoo test environment container. If a verify script exists for the
# package, it is run against the build image directory afterwards.
#
# Usage:
#   scripts/test-build.sh <category/package> <ebuild-file> [--no-clean]
#
#   scripts/test-build.sh media-sound/carla carla-2.5.10.ebuild
#   scripts/test-build.sh app-editors/zed zed-0.227.1.ebuild
#
# Options:
#   --no-clean   Skip the `clean` phase and run `compile` only.
#                Useful when retrying after a compile failure without
#                changing the ebuild — reuses the already-unpacked source.
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay \
#     scripts/test-build.sh app-editors/zed zed-0.227.1.ebuild
#
# Image resolution order (per image type):
#   1. localhost/adaptive-overlay-testenv:local       (testenv)
#      localhost/adaptive-overlay-testenv-rust:local  (testenv-rust)
#   2. ghcr.io/faraclas/adaptive-overlay/testenv:latest
#      ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest
#
# The testenv-rust image is selected automatically when the package
# directory is app-editors/zed.

set -euo pipefail

# --- Parse arguments ---------------------------------------------------------
PACKAGE_DIR="${1:-}"
EBUILD_FILE="${2:-}"
NO_CLEAN=0

for arg in "$@"; do
    case "${arg}" in
        --no-clean) NO_CLEAN=1 ;;
    esac
done

# --- Validate arguments ------------------------------------------------------
if [ -z "${PACKAGE_DIR}" ] || [ -z "${EBUILD_FILE}" ]; then
    echo "Usage: $(basename "$0") <category/package> <ebuild-file> [--no-clean]" >&2
    echo "  e.g. $(basename "$0") media-sound/carla carla-2.5.10.ebuild" >&2
    echo "  e.g. $(basename "$0") app-editors/zed zed-0.227.1.ebuild" >&2
    exit 1
fi

if [[ "${EBUILD_FILE}" != *.ebuild ]]; then
    echo "error: ebuild file must end in .ebuild, got: ${EBUILD_FILE}" >&2
    exit 1
fi

# --- Resolve the overlay root ------------------------------------------------
OVERLAY_DIR="${OVERLAY_DIR:-$(pwd)}"

if [ ! -f "${OVERLAY_DIR}/metadata/layout.conf" ]; then
    echo "error: '${OVERLAY_DIR}' does not look like the adaptive-overlay repo root." >&2
    echo "  Run this script from the repo root, or set OVERLAY_DIR." >&2
    exit 1
fi

# --- Pick container runtime --------------------------------------------------
if command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "error: neither podman nor docker found in PATH." >&2
    exit 1
fi

# --- Select image based on package -------------------------------------------
# app-editors/zed requires the Rust/LLVM image; everything else uses testenv.
if [ "${PACKAGE_DIR}" = "app-editors/zed" ]; then
    LOCAL_IMAGE="localhost/adaptive-overlay-testenv-rust:local"
    REMOTE_IMAGE="ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest"
else
    LOCAL_IMAGE="localhost/adaptive-overlay-testenv:local"
    REMOTE_IMAGE="ghcr.io/faraclas/adaptive-overlay/testenv:latest"
fi

if "${RUNTIME}" image exists "${LOCAL_IMAGE}" 2>/dev/null; then
    IMAGE="${LOCAL_IMAGE}"
else
    IMAGE="${REMOTE_IMAGE}"
fi

# --- Derive portage paths ----------------------------------------------------
EBUILD_STEM="${EBUILD_FILE%.ebuild}"
PKG_DIR="/var/db/repos/adaptive-overlay/${PACKAGE_DIR}"
BUILD_IMAGE="/var/tmp/portage/${PACKAGE_DIR%/*}/${EBUILD_STEM}/image"

# --- Resolve verify script ---------------------------------------------------
# Convention: containers/<image-dir>/verify-<package-name>.sh
# e.g. containers/testenv-rust/verify-zed.sh for app-editors/zed
PACKAGE_NAME="${PACKAGE_DIR##*/}"
if [ "${PACKAGE_DIR}" = "app-editors/zed" ]; then
    VERIFY_SCRIPT_REL="containers/testenv-rust/verify-${PACKAGE_NAME}.sh"
else
    VERIFY_SCRIPT_REL="containers/testenv/verify-${PACKAGE_NAME}.sh"
fi
VERIFY_SCRIPT="${OVERLAY_DIR}/${VERIFY_SCRIPT_REL}"

# --- Determine build phases --------------------------------------------------
if [ "${NO_CLEAN}" -eq 1 ]; then
    PHASES="compile install"
else
    PHASES="clean compile install"
fi

# --- Print plan --------------------------------------------------------------
echo "==> Building ${PACKAGE_DIR}/${EBUILD_FILE}"
echo "    Runtime : ${RUNTIME}"
echo "    Image   : ${IMAGE}"
echo "    Phases  : ${PHASES}"
echo "    Overlay : ${OVERLAY_DIR}"
if [ -f "${VERIFY_SCRIPT}" ]; then
    echo "    Verify  : ${VERIFY_SCRIPT_REL}"
else
    echo "    Verify  : (none — ${VERIFY_SCRIPT_REL} not found)"
fi
echo ""

# --- Run the build -----------------------------------------------------------
# The portage tmpdir must be writable, so it is NOT bind-mounted from the
# host. Portage writes its build tree inside the container, which is
# discarded when the container exits.
#
# The overlay is bind-mounted read-only so the ebuild and its files are
# visible to the container without copying.
#
# We run an inline bash script inside the container so we can:
#   1. Symlink the overlay to the portage-expected path
#   2. Run the ebuild from the correct package directory
#   3. Optionally run the verify script against the build image

"${RUNTIME}" run --rm \
    --user root \
    -v "${OVERLAY_DIR}:/mnt/adaptive-overlay:ro" \
    "${IMAGE}" \
    bash -c "
        set -euo pipefail

        # Mount overlay where portage expects it
        rm -rf /var/db/repos/adaptive-overlay
        ln -s /mnt/adaptive-overlay /var/db/repos/adaptive-overlay

        # Run the build
        cd '${PKG_DIR}'
        echo '==> ebuild ${EBUILD_FILE} ${PHASES}'
        ebuild './${EBUILD_FILE}' ${PHASES}
        BUILD_EXIT=\$?

        if [ \${BUILD_EXIT} -ne 0 ]; then
            echo ''
            echo 'Build FAILED.' >&2
            exit \${BUILD_EXIT}
        fi

        echo ''
        echo 'Build succeeded.'

        # Run verify script if present
        if [ -f '/mnt/adaptive-overlay/${VERIFY_SCRIPT_REL}' ]; then
            echo ''
            echo '==> Running verify script: ${VERIFY_SCRIPT_REL}'
            bash '/mnt/adaptive-overlay/${VERIFY_SCRIPT_REL}' '${BUILD_IMAGE}'
        fi
    "
