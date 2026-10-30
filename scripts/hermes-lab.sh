#!/bin/bash
# hermes-lab.sh — manage the local Hermes lab container.
#
# The lab is a long-lived container with app-ai/hermes-agent merged by
# Portage (as on the hosts) and an unprivileged user "lab". Use it to try
# plugins, config changes and upgrades before they touch a real host.
# Sources: containers/hermes-lab/. Local only; CI never builds it.
#
# Usage:
#   hermes-lab.sh build [--version V]  build localhost/hermes-lab:V (+ :latest)
#                                      default V: newest non-live ebuild
#   hermes-lab.sh up [TAG]             create/start the container from :TAG
#                                      (default :latest)
#   hermes-lab.sh shell [--root]       interactive shell (as lab, or root)
#   hermes-lab.sh run <cmd...>         run a command as lab (bash -lc)
#   hermes-lab.sh root <cmd...>        run a command as root (bash -lc)
#   hermes-lab.sh check                lab-check-system: is lab's Hermes still
#                                      only on Portage's Python? (exit 1 if not)
#   hermes-lab.sh snapshot <TAG>       save the lab's current state as :TAG
#   hermes-lab.sh reset [TAG]          discard lab state, start fresh from :TAG
#   hermes-lab.sh down                 remove the container (image is kept)
#   hermes-lab.sh status               show container and images
#
# Day to day, change the running lab (emerge a new ebuild or patch into
# it) rather than rebuilding the image; rebuild for a new Hermes release.
#
# The live overlay checkout is mounted read-only at /mnt/adaptive-overlay
# (= /var/db/repos/adaptive-overlay inside), so a new ebuild can be tried
# with `hermes-lab.sh root emerge -1 =app-ai/hermes-agent-<ver>`.
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly.

set -euo pipefail

NAME="hermes-lab"
IMAGE="localhost/hermes-lab"
CMD="${1:-}"
[ $# -gt 0 ] && shift

usage() {
    sed -n '/^# Usage:/,/^# The live/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 1
}

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

exists() { "${RUNTIME}" container inspect "${NAME}" &>/dev/null; }
running() {
    [ "$("${RUNTIME}" container inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null)" = "true" ]
}
need_running() {
    running || { echo "error: ${NAME} is not running; run '$(basename "$0") up'." >&2; exit 1; }
}
tty_flags() { if [ -t 0 ] && [ -t 1 ]; then echo "-it"; else echo "-i"; fi; }

latest_version() {
    find "${OVERLAY_DIR}/app-ai/hermes-agent" -name 'hermes-agent-*.ebuild' ! -name '*9999*' \
        | sed 's|.*/hermes-agent-||; s|\.ebuild$||' | sort -V | tail -n1
}

case "${CMD}" in
build)
    VERSION=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
            *) usage ;;
        esac
    done
    VERSION="${VERSION:-$(latest_version)}"
    [ -n "${VERSION}" ] || { echo "error: no app-ai/hermes-agent ebuild found." >&2; exit 1; }
    # The ebuild's PV may carry a revision (-rN); the image tag keeps it.
    echo "==> Building ${IMAGE}:${VERSION} using ${RUNTIME}"
    echo "    Overlay : ${OVERLAY_DIR}"
    "${RUNTIME}" build \
        -f "${OVERLAY_DIR}/containers/hermes-lab/Containerfile" \
        --build-arg "HERMES_VERSION=${VERSION}" \
        --build-arg "MAKEOPTS=-j$(nproc)" \
        -t "${IMAGE}:${VERSION}" -t "${IMAGE}:latest" \
        "${OVERLAY_DIR}"
    echo "==> Built ${IMAGE}:${VERSION} (also :latest)."
    echo "    A running lab keeps its old image until '$(basename "$0") reset'."
    ;;
up)
    TAG="${1:-latest}"
    if running; then
        echo "${NAME} is already running."
    elif exists; then
        "${RUNTIME}" start "${NAME}" >/dev/null
        echo "${NAME} started."
    else
        "${RUNTIME}" image exists "${IMAGE}:${TAG}" || {
            echo "error: ${IMAGE}:${TAG} not found; run '$(basename "$0") build'." >&2; exit 1; }
        "${RUNTIME}" run -d --init --name "${NAME}" --hostname "${NAME}" \
            -v "${OVERLAY_DIR}:/mnt/adaptive-overlay:ro" \
            "${IMAGE}:${TAG}" >/dev/null
        echo "${NAME} created from ${IMAGE}:${TAG}."
    fi
    ;;
shell)
    need_running
    if [ "${1:-}" = "--root" ]; then
        exec "${RUNTIME}" exec -it -u root -w /root "${NAME}" bash -l
    fi
    exec "${RUNTIME}" exec -it -u lab -w /home/lab "${NAME}" bash -l
    ;;
run|root)
    [ $# -gt 0 ] || usage
    need_running
    if [ "${CMD}" = "root" ]; then user=root; dir=/root; else user=lab; dir=/home/lab; fi
    exec "${RUNTIME}" exec $(tty_flags) -u "${user}" -w "${dir}" "${NAME}" bash -lc "$*"
    ;;
check)
    need_running
    exec "${RUNTIME}" exec -u lab -w /home/lab "${NAME}" \
        bash /mnt/adaptive-overlay/containers/hermes-lab/lab-check-system
    ;;
snapshot)
    TAG="${1:-}"
    [ -n "${TAG}" ] || usage
    case "${TAG}" in
        latest|[0-9]*) echo "error: '${TAG}' is reserved for built images." >&2; exit 1 ;;
    esac
    exists || { echo "error: no ${NAME} container to snapshot." >&2; exit 1; }
    "${RUNTIME}" commit -q "${NAME}" "${IMAGE}:${TAG}" >/dev/null
    echo "Saved ${NAME} as ${IMAGE}:${TAG}; restore with '$(basename "$0") reset ${TAG}'."
    ;;
reset)
    "${RUNTIME}" rm -f "${NAME}" >/dev/null 2>&1 || true
    exec "$0" up "$@"
    ;;
down)
    "${RUNTIME}" rm -f "${NAME}" >/dev/null
    echo "${NAME} removed (images kept)."
    ;;
status)
    if exists; then
        "${RUNTIME}" ps -a --filter "name=^${NAME}\$" \
            --format '{{.Names}}  {{.Image}}  {{.Status}}'
    else
        echo "${NAME}: no container"
    fi
    "${RUNTIME}" images --filter "reference=${IMAGE}" \
        --format '{{.Repository}}:{{.Tag}}  {{.Size}}  {{.CreatedSince}}'
    ;;
*)
    usage
    ;;
esac
