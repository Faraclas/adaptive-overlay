#!/bin/bash
# ouroboros-home.sh — manage the persistent Gentoo Ouroboros habitat container.
#
# Portage builds and owns the Python/C/Rust dependency layer inside the
# container (app-ai/ouroboros), while the agent's mutable Git repository
# ("brain"), durable state, Cargo cache, and project workbench are mounted
# from the host:
#   ~/.local/share/ouroboros-brain -> /home/agent/ouroboros
#   ~/.local/share/ouroboros-data  -> /home/agent/data
#   ~/.local/share/ouroboros-cargo -> /home/agent/.cargo
#   ~/agent-workspaces             -> /workspaces
#
# Optional credentials on the host (mounted/injected automatically if present):
#   ~/.config/ouroboros/.env       -> injected via --env-file
#   ~/.config/ouroboros/ssh        -> mounted read-only at /home/agent/.ssh:ro
#
# Usage:
#   ouroboros-home.sh build [--version V]       build localhost/ouroboros-home:V
#   ouroboros-home.sh up [TAG]                  create/start container and
#                                               bootstrap brain repo if empty
#   ouroboros-home.sh start-server              start Ouroboros server (:8765)
#   ouroboros-home.sh stop-server               stop Ouroboros server
#   ouroboros-home.sh restart-server            restart Ouroboros server
#   ouroboros-home.sh stage <repo|path> [br]    stage a host Git repo/worktree
#                                               into ~/agent-workspaces/projects
#   ouroboros-home.sh harvest <name|path> [br]  fetch commits from staged repo
#                                               back into the host repo/worktree
#   ouroboros-home.sh workspaces                list staged project workspaces
#   ouroboros-home.sh cli <args...>             run `ouroboros <args...>` inside
#   ouroboros-home.sh test [pytest-args]        run pytest on the brain repo
#   ouroboros-home.sh check                     verify Portage Python hygiene
#   ouroboros-home.sh snapshot <TAG>            save container state as :TAG
#   ouroboros-home.sh reset [TAG]               reset container rootfs to :TAG
#                                               (preserves brain/data/workspaces)
#   ouroboros-home.sh shell [--root]            interactive shell (agent or root)
#   ouroboros-home.sh run <cmd...>              run command as agent (bash -lc)
#   ouroboros-home.sh root <cmd...>             run command as root (bash -lc)
#   ouroboros-home.sh down                      remove container (volumes kept)
#   ouroboros-home.sh status                    show container and images
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly.

set -euo pipefail

NAME="ouroboros-home"
IMAGE="localhost/ouroboros-home"
BRAIN_DIR="${OUROBOROS_BRAIN_HOST_DIR:-${HOME}/.local/share/ouroboros-brain}"
DATA_DIR="${OUROBOROS_DATA_HOST_DIR:-${HOME}/.local/share/ouroboros-data}"
CARGO_DIR="${OUROBOROS_CARGO_HOST_DIR:-${HOME}/.local/share/ouroboros-cargo}"
WORKSPACES_DIR="${OUROBOROS_WORKSPACES_HOST_DIR:-${HOME}/agent-workspaces}"
CONFIG_DIR="${OUROBOROS_CONFIG_HOST_DIR:-${HOME}/.config/ouroboros}"
REPOS_ROOT="${HOME}/code/repos"
PORT="${OUROBOROS_HOST_PORT:-8765}"

CMD="${1:-}"
[ $# -gt 0 ] && shift

usage() {
    sed -n '/^# Usage:/,/^# Must be run/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
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
    find "${OVERLAY_DIR}/app-ai/ouroboros" -name 'ouroboros-*.ebuild' ! -name '*9999*' \
        | sed 's|.*/ouroboros-||; s|\.ebuild$||' | sort -V | tail -n1
}

resolve_host_repo() {
    local spec="$1"
    if [ -d "${spec}" ] && git -C "${spec}" rev-parse --is-inside-work-tree &>/dev/null; then
        (cd "${spec}" && pwd -P)
        return 0
    fi
    if [ -d "${REPOS_ROOT}/${spec}" ] && git -C "${REPOS_ROOT}/${spec}" rev-parse --is-inside-work-tree &>/dev/null; then
        (cd "${REPOS_ROOT}/${spec}" && pwd -P)
        return 0
    fi
    local sub
    for sub in "${REPOS_ROOT}"/*/"${spec}"; do
        if [ -d "${sub}" ] && git -C "${sub}" rev-parse --is-inside-work-tree &>/dev/null; then
            (cd "${sub}" && pwd -P)
            return 0
        fi
    done
    echo "error: could not resolve Git repository '${spec}' (checked path and ${REPOS_ROOT})." >&2
    return 1
}

bootstrap_brain_if_empty() {
    "${RUNTIME}" exec -u agent -w /home/agent/ouroboros "${NAME}" bash -lc '
        set -euo pipefail
        git config --global user.name "Elias Faraclas"
        git config --global user.email "10173012+Faraclas@users.noreply.github.com"
        if [ -f /home/agent/.ssh/id_ed25519 ]; then
            git config --global url."git@github.com:Faraclas/ouroboros.git".insteadOf "https://github.com/Faraclas/ouroboros.git"
            git config --global url."git@github.com:Faraclas/ouroboros.git".insteadOf "https://github.com/Faraclas/ouroboros"
        fi
        if [ ! -d /home/agent/ouroboros/.git ]; then
            echo "==> Bootstrapping /home/agent/ouroboros from /usr/share/ouroboros/seed"
            cp -a /usr/share/ouroboros/seed/. /home/agent/ouroboros/
            git init -q -b ouroboros /home/agent/ouroboros
            git -C /home/agent/ouroboros config user.name "Elias Faraclas"
            git -C /home/agent/ouroboros config user.email "10173012+Faraclas@users.noreply.github.com"
            git -C /home/agent/ouroboros remote add upstream https://github.com/razzant/ouroboros.git || true
            git -C /home/agent/ouroboros add -A
            git -C /home/agent/ouroboros commit -q -m "Initial seed bootstrap from Portage"
            git -C /home/agent/ouroboros tag -f v7.9.0 HEAD
        fi
        if [ ! -f /home/agent/data/settings.json ] && [ -n "${COPILOT_GITHUB_TOKEN:-}" ]; then
            python3 -c "
import os
from ouroboros.config import SETTINGS_PATH, load_settings, prepare_settings_for_persist, serialize_settings
from ouroboros.utils import write_text_atomic
s = dict(load_settings())
s[\"OPENAI_COMPATIBLE_BASE_URL\"] = \"https://api.business.githubcopilot.com\"
s[\"OPENAI_COMPATIBLE_API_KEY\"] = os.environ[\"COPILOT_GITHUB_TOKEN\"].strip()
s[\"OUROBOROS_MODEL\"] = \"openai-compatible::claude-sonnet-5.5\"
s[\"OUROBOROS_MODEL_LIGHT\"] = \"openai-compatible::claude-haiku-5.5\"
s[\"OUROBOROS_MODEL_FALLBACKS\"] = \"openai-compatible::claude-opus-5.5,openai-compatible::gemini-4-argon\"
s[\"OUROBOROS_MODEL_VISION\"] = \"openai-compatible::claude-sonnet-5.5\"
s[\"OUROBOROS_MODEL_CONSCIOUSNESS\"] = \"openai-compatible::claude-haiku-5.5\"
s[\"OUROBOROS_MODEL_SAFETY\"] = \"openai-compatible::claude-haiku-5.5\"
to_write = prepare_settings_for_persist(s, authored_keys=(\"OUROBOROS_MODEL_SAFETY\",), allow_safety_lowering=True)
write_text_atomic(SETTINGS_PATH, serialize_settings(to_write))
"
        fi
    '
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
    [ -n "${VERSION}" ] || { echo "error: no app-ai/ouroboros ebuild found." >&2; exit 1; }
    echo "==> Building ${IMAGE}:${VERSION} using ${RUNTIME}"
    echo "    Overlay : ${OVERLAY_DIR}"
    "${RUNTIME}" build \
        --pull=newer \
        -f "${OVERLAY_DIR}/containers/ouroboros-home/Containerfile" \
        --build-arg "OUROBOROS_VERSION=${VERSION}" \
        --build-arg "MAKEOPTS=-j$(nproc)" \
        -t "${IMAGE}:${VERSION}" -t "${IMAGE}:latest" \
        "${OVERLAY_DIR}"
    echo "==> Built ${IMAGE}:${VERSION} (also :latest)."
    ;;
up)
    TAG="${1:-latest}"
    mkdir -p "${BRAIN_DIR}" "${DATA_DIR}" "${CARGO_DIR}" "${CONFIG_DIR}" \
        "${WORKSPACES_DIR}/projects" \
        "${WORKSPACES_DIR}/subagent_worktrees" \
        "${WORKSPACES_DIR}/Deliverables"
    if running; then
        echo "${NAME} is already running."
    elif exists; then
        "${RUNTIME}" start "${NAME}" >/dev/null
        echo "${NAME} started."
    else
        "${RUNTIME}" image exists "${IMAGE}:${TAG}" || {
            echo "error: ${IMAGE}:${TAG} not found; run '$(basename "$0") build'." >&2; exit 1; }
        EXTRA_ARGS=()
        if [ "${RUNTIME}" = "podman" ]; then
            EXTRA_ARGS+=(--userns=keep-id)
        fi
        # Selective allowlist of host environment variables (from ~/.bash_local
        # etc.) forwarded into the container without duplicating secrets on disk.
        PASSTHROUGH_VARS=(
            ${OUROBOROS_PASSTHROUGH_VARS:-
                OPENAI_API_KEY
                ANTHROPIC_API_KEY
                OPENROUTER_API_KEY
                DEEPSEEK_API_KEY
                GEMINI_API_KEY
                AZURE_OPENAI_ENDPOINT
                AZURE_FOUNDRY_ENDPOINT
                AZURE_FOUNDRY_API_KEY
                GITHUB_TOKEN
                COPILOT_GITHUB_TOKEN
                AZURE_DEVOPS_EXT_PAT
                PROJECT_TOKEN
            }
        )
        for var in "${PASSTHROUGH_VARS[@]}"; do
            if [ -n "${!var:-}" ]; then
                EXTRA_ARGS+=(-e "${var}")
            fi
        done
        # Optional override file if you ever want container-specific tokens
        # different from your host shell environment.
        if [ -f "${CONFIG_DIR}/.env" ]; then
            EXTRA_ARGS+=(--env-file "${CONFIG_DIR}/.env")
        fi
        if [ -d "${CONFIG_DIR}/ssh" ]; then
            EXTRA_ARGS+=(-v "${CONFIG_DIR}/ssh:/home/agent/.ssh:ro")
        fi
        "${RUNTIME}" run -d --init \
            --name "${NAME}" \
            --hostname "${NAME}" \
            "${EXTRA_ARGS[@]}" \
            -p "127.0.0.1:${PORT}:8765" \
            -v "${OVERLAY_DIR}:/mnt/adaptive-overlay:ro" \
            -v "${BRAIN_DIR}:/home/agent/ouroboros:rw" \
            -v "${DATA_DIR}:/home/agent/data:rw" \
            -v "${CARGO_DIR}:/home/agent/.cargo:rw" \
            -v "${WORKSPACES_DIR}:/workspaces:rw" \
            "${IMAGE}:${TAG}" >/dev/null
        echo "${NAME} created from ${IMAGE}:${TAG} (Web UI port 127.0.0.1:${PORT})."
    fi
    bootstrap_brain_if_empty
    ;;
start-server)
    need_running
    bootstrap_brain_if_empty
    "${RUNTIME}" exec -d -u agent -w /home/agent/ouroboros "${NAME}" bash -lc '
        mkdir -p /home/agent/data/logs
        while true; do
            PYTHONPATH=/home/agent/ouroboros python3 /home/agent/ouroboros/server.py \
                >>/home/agent/data/logs/habitat-server.log 2>&1
            rc=$?
            # Exit 42 is Ouroboros self-restart handoff; exit 0/99 is clean/panic stop.
            if [ "$rc" -ne 42 ]; then
                exit "$rc"
            fi
            sleep 1
        done
    '
    echo "Ouroboros server started on http://127.0.0.1:${PORT}"
    ;;
stop-server)
    need_running
    "${RUNTIME}" exec -u agent "${NAME}" bash -lc '
        pkill -f "[/]home/agent/ouroboros/server.py" 2>/dev/null || true
    '
    echo "Ouroboros server stopped."
    ;;
restart-server)
    "$0" stop-server
    "$0" start-server
    ;;
stage)
    SRC_SPEC="${1:-}"
    WORK_BRANCH="${2:-ouroboros-work}"
    [ -n "${SRC_SPEC}" ] || usage
    SRC_PATH="$(resolve_host_repo "${SRC_SPEC}")"
    REPO_NAME="$(basename "${SRC_PATH}")"
    DEST_PATH="${WORKSPACES_DIR}/projects/${REPO_NAME}"

    # Resolve common git dir so staging from a linked git worktree works cleanly.
    COMMON_GIT_DIR="$(git -C "${SRC_PATH}" rev-parse --path-format=absolute --git-common-dir)"
    HEAD_COMMIT="$(git -C "${SRC_PATH}" rev-parse HEAD)"
    USER_NAME="$(git -C "${SRC_PATH}" config user.name || echo "Elias Faraclas")"
    USER_EMAIL="$(git -C "${SRC_PATH}" config user.email || echo "10173012+Faraclas@users.noreply.github.com")"
    UPSTREAM_URL="$(git -C "${SRC_PATH}" remote get-url origin 2>/dev/null || true)"

    mkdir -p "${WORKSPACES_DIR}/projects"
    if [ -d "${DEST_PATH}/.git" ]; then
        echo "==> Updating existing staged workspace: ${DEST_PATH}"
        git -C "${DEST_PATH}" fetch --no-tags "${COMMON_GIT_DIR}" "${HEAD_COMMIT}"
        git -C "${DEST_PATH}" checkout -B "${WORK_BRANCH}" FETCH_HEAD
    else
        echo "==> Cloning ${SRC_PATH} -> ${DEST_PATH} (branch: ${WORK_BRANCH})"
        git clone --no-local "${COMMON_GIT_DIR}" "${DEST_PATH}"
        git -C "${DEST_PATH}" checkout -B "${WORK_BRANCH}" "${HEAD_COMMIT}"
        git -C "${DEST_PATH}" remote remove origin 2>/dev/null || true
        if [ -n "${UPSTREAM_URL}" ]; then
            git -C "${DEST_PATH}" remote add origin "${UPSTREAM_URL}" || true
        fi
    fi
    git -C "${DEST_PATH}" config user.name "${USER_NAME}"
    git -C "${DEST_PATH}" config user.email "${USER_EMAIL}"
    printf '%s\n' "${SRC_PATH}" > "${DEST_PATH}/.git/ouroboros-source-path"

    echo "==> Staged '${REPO_NAME}' for Ouroboros:"
    echo "    Host path      : ${DEST_PATH}"
    echo "    Container path : /workspaces/projects/${REPO_NAME}"
    echo "    Git identity   : ${USER_NAME} <${USER_EMAIL}>"
    echo "    Active branch  : ${WORK_BRANCH}"
    ;;
harvest)
    TARGET_SPEC="${1:-}"
    HARVEST_BRANCH="${2:-}"
    [ -n "${TARGET_SPEC}" ] || usage

    if [ -d "${WORKSPACES_DIR}/projects/$(basename "${TARGET_SPEC}")/.git" ]; then
        REPO_NAME="$(basename "${TARGET_SPEC}")"
    else
        SRC_RESOLVED="$(resolve_host_repo "${TARGET_SPEC}")"
        REPO_NAME="$(basename "${SRC_RESOLVED}")"
    fi
    STAGE_PATH="${WORKSPACES_DIR}/projects/${REPO_NAME}"
    [ -d "${STAGE_PATH}/.git" ] || {
        echo "error: no staged workspace found at ${STAGE_PATH}." >&2
        exit 1
    }

    if [ -f "${STAGE_PATH}/.git/ouroboros-source-path" ] && [ ! -d "${TARGET_SPEC}" ]; then
        HOST_REPO="$(cat "${STAGE_PATH}/.git/ouroboros-source-path")"
    else
        HOST_REPO="$(resolve_host_repo "${TARGET_SPEC}")"
    fi

    STAGE_BRANCH="$(git -C "${STAGE_PATH}" rev-parse --abbrev-ref HEAD)"
    HARVEST_BRANCH="${HARVEST_BRANCH:-ouroboros/${STAGE_BRANCH}}"

    git -C "${HOST_REPO}" fetch --no-tags "${STAGE_PATH}" "HEAD:refs/heads/${HARVEST_BRANCH}"
    echo "==> Harvested commits from ${STAGE_PATH} into ${HOST_REPO}"
    echo "    Local branch : ${HARVEST_BRANCH}"
    git -C "${HOST_REPO}" log -n 5 --oneline "${HARVEST_BRANCH}"
    ;;
workspaces)
    mkdir -p "${WORKSPACES_DIR}/projects"
    for dir in "${WORKSPACES_DIR}/projects"/*; do
        [ -d "${dir}/.git" ] || continue
        name="$(basename "${dir}")"
        branch="$(git -C "${dir}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
        email="$(git -C "${dir}" config user.email 2>/dev/null || echo "?")"
        src="$(cat "${dir}/.git/ouroboros-source-path" 2>/dev/null || echo "(cloned in container)")"
        printf "%-24s branch=%-18s email=%-38s source=%s\n" "${name}" "${branch}" "${email}" "${src}"
    done
    ;;
cli)
    [ $# -gt 0 ] || usage
    need_running
    exec "${RUNTIME}" exec $(tty_flags) -u agent -w /home/agent/ouroboros "${NAME}" \
        env PYTHONPATH=/home/agent/ouroboros python3 -m ouroboros.cli "$@"
    ;;
test)
    need_running
    if [ $# -eq 0 ]; then
        set -- -q --tb=short -m "not integration and not browser and not ui_browser and not ui_browser_docker and not portable_detail and not skill_smoke and not size_ratchet"
    fi
    exec "${RUNTIME}" exec $(tty_flags) -u agent -w /home/agent/ouroboros "${NAME}" \
        env PYTHONPATH=/home/agent/ouroboros pytest "$@"
    ;;
check)
    need_running
    exec "${RUNTIME}" exec -u agent -w /home/agent "${NAME}" \
        bash /mnt/adaptive-overlay/containers/ouroboros-home/home-check-system
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
shell)
    need_running
    if [ "${1:-}" = "--root" ]; then
        exec "${RUNTIME}" exec -it -u root -w /root "${NAME}" bash -l
    fi
    exec "${RUNTIME}" exec -it -u agent -w /home/agent/ouroboros "${NAME}" bash -l
    ;;
run|root)
    [ $# -gt 0 ] || usage
    need_running
    if [ "${CMD}" = "root" ]; then user=root; dir=/root; else user=agent; dir=/home/agent/ouroboros; fi
    exec "${RUNTIME}" exec $(tty_flags) -u "${user}" -w "${dir}" "${NAME}" bash -lc "$*"
    ;;
down)
    "${RUNTIME}" rm -f "${NAME}" >/dev/null
    echo "${NAME} removed (host brain/data/workspaces directories and images kept)."
    ;;
status)
    if exists; then
        "${RUNTIME}" ps -a --filter "name=^${NAME}\$" \
            --format '{{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}'
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
