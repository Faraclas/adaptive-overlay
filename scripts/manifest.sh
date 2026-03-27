#!/bin/bash
# manifest.sh — run pkgdev manifest inside the adaptive-overlay testenv container.
#
# Generates or updates the Manifest file for a package by fetching distfiles
# and recording their checksums. The overlay is mounted read-write so the
# resulting Manifest file persists on the host.
#
# Usage:
#   scripts/manifest.sh <category/package>
#   scripts/manifest.sh app-editors/zed
#   scripts/manifest.sh media-sound/carla
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay scripts/manifest.sh media-sound/carla
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
    echo "  e.g. $(basename "$0") app-editors/zed" >&2
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

# --- Derive portage paths ----------------------------------------------------
PKG_DIR="/var/db/repos/adaptive-overlay/${PACKAGE_DIR}"

# --- Print plan --------------------------------------------------------------
echo "==> Generating Manifest for ${PACKAGE_DIR}"
echo "    Runtime : ${RUNTIME}"
echo "    Image   : ${IMAGE}"
echo "    Overlay : ${OVERLAY_DIR}"
echo ""

# --- Run pkgdev manifest inside the container --------------------------------
# The overlay is mounted read-write so that the generated Manifest file
# is written back to the host filesystem.
# Network access is required to fetch distfiles.

"${RUNTIME}" run --rm \
    --user root \
    -v "${OVERLAY_DIR}:/mnt/adaptive-overlay:rw" \
    "${IMAGE}" \
    bash -c "
        set -euo pipefail

        # Mount overlay where portage expects it
        rm -rf /var/db/repos/adaptive-overlay
        ln -s /mnt/adaptive-overlay /var/db/repos/adaptive-overlay

        # Generate the Manifest
        cd '${PKG_DIR}'
        echo '==> pkgdev manifest'
        pkgdev manifest
    "
