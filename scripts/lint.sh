#!/bin/bash
# lint.sh — run pkgcheck inside the adaptive-overlay testenv container.
#
# Usage:
#   lint.sh <category/package>
#   lint.sh media-sound/carla
#   lint.sh app-editors/zed
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay lint.sh media-sound/carla
#
# Image resolution order:
#   1. localhost/adaptive-overlay-testenv:local  (fast, your local build)
#   2. ghcr.io/faraclas/adaptive-overlay/testenv:latest  (fallback)

set -euo pipefail

LOCAL_IMAGE="localhost/adaptive-overlay-testenv:local"
REMOTE_IMAGE="ghcr.io/faraclas/adaptive-overlay/testenv:latest"
PACKAGE_DIR="${1:-}"

# --- Validate argument -------------------------------------------------------
if [ -z "${PACKAGE_DIR}" ]; then
    echo "Usage: $(basename "$0") <category/package>" >&2
    echo "  e.g. $(basename "$0") media-sound/carla" >&2
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

# --- Pick image: local first, remote as fallback -----------------------------
if "${RUNTIME}" image exists "${LOCAL_IMAGE}" 2>/dev/null; then
    IMAGE="${LOCAL_IMAGE}"
else
    IMAGE="${REMOTE_IMAGE}"
fi

echo "==> Linting ${PACKAGE_DIR} using ${RUNTIME}"
echo "    Overlay : ${OVERLAY_DIR}"
echo "    Image   : ${IMAGE}"
echo ""

# --- Run pkgcheck inside the container ---------------------------------------
"${RUNTIME}" run --rm \
    -v "${OVERLAY_DIR}:/var/db/repos/adaptive-overlay:ro" \
    "${IMAGE}" \
    pkgcheck scan \
        --exit error \
        -r adaptive-overlay \
        "${PACKAGE_DIR}"
