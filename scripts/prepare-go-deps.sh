#!/bin/bash
# Prepare D2's go-module dependency archive, never on the host.
# Usage: scripts/prepare-go-deps.sh media-gfx/d2 --version VERSION --output DIR
# Optional: --image IMAGE (otherwise prefer the local headless Rust image).
# GO_DEPS_RUNTIME=podman|docker overrides runtime selection (CI uses Docker).
# DIR must be inside this repository or /home/elias/tmp. Nothing is published.
# The private --in-container entry point is shared by local and hosted runs.
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

IN_CONTAINER=0
PACKAGE=""
VERSION=""
OUTPUT=""
IMAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --in-container) IN_CONTAINER=1 ;;
        --version|--output|--image)
            option="$1"
            [[ $# -ge 2 && -n "$2" ]] || fail "${option} requires a value"
            case "${option}" in
                --version) VERSION="${2#v}" ;;
                --output) OUTPUT="$2" ;;
                --image) IMAGE="$2" ;;
            esac
            shift
            ;;
        -h|--help)
            sed -n '2,/^set /{ /^set /d; s/^# //; p; }' "$0"
            exit 0
            ;;
        -*) fail "unknown option: $1" ;;
        *) [[ -z "${PACKAGE}" ]] || fail "unexpected argument: $1"; PACKAGE="$1" ;;
    esac
    shift
done
[[ "${PACKAGE}" == media-gfx/d2 ]] || fail "only media-gfx/d2 is supported"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--version must be an exact stable D2 version (X.Y.Z)"
[[ -n "${OUTPUT}" ]] || fail "--output DIR is required"

if [[ "${IN_CONTAINER}" -eq 0 ]]; then
    ROOT=$(realpath "$(dirname "$0")/..")
    [[ -f "${ROOT}/metadata/layout.conf" ]] || fail "cannot find overlay root"
    OUTPUT=$(realpath -m -- "${OUTPUT}")
    case "${OUTPUT}/" in
        "${ROOT}/"*|/home/elias/tmp/*) ;;
        *) fail "output must be inside ${ROOT} or /home/elias/tmp" ;;
    esac
    mkdir -p -- "${OUTPUT}"
    if [[ -n "${GO_DEPS_RUNTIME:-}" ]]; then
        case "${GO_DEPS_RUNTIME}" in
            podman|docker) RUNTIME="${GO_DEPS_RUNTIME}" ;;
            *) fail "GO_DEPS_RUNTIME must be podman or docker" ;;
        esac
        command -v "${RUNTIME}" >/dev/null || fail "requested runtime ${RUNTIME} not found; no host Go fallback"
    elif command -v podman &>/dev/null; then
        RUNTIME=podman
    elif command -v docker &>/dev/null; then
        RUNTIME=docker
    else
        fail "neither podman nor docker found; no host Go fallback"
    fi
    if [[ -z "${IMAGE}" ]]; then
        IMAGE=localhost/adaptive-overlay-testenv-rust:local
        if ! "${RUNTIME}" image inspect "${IMAGE}" >/dev/null 2>&1; then
            IMAGE=ghcr.io/faraclas/adaptive-overlay/testenv-rust:latest
        fi
    fi
    USERNS_ARGS=()
    if [[ "${RUNTIME}" == podman && "${EUID}" -ne 0 ]]; then
        USERNS_ARGS=(--userns=keep-id)
    fi
    exec "${RUNTIME}" run --rm "${USERNS_ARGS[@]}" --user "$(id -u):$(id -g)" \
        -e ADAPTIVE_GO_DEPS_CONTAINER=1 \
        -v "${ROOT}:/overlay:ro" -v "${OUTPUT}:/output" \
        --entrypoint /bin/bash "${IMAGE}" \
        /overlay/scripts/prepare-go-deps.sh --in-container media-gfx/d2 \
        --version "${VERSION}" --output /output
fi

# Only the wrapper sets this marker. There is deliberately no host-mode option.
[[ "${ADAPTIVE_GO_DEPS_CONTAINER:-}" == 1 ]] || fail "use the container wrapper, not --in-container directly"
for cmd in go git tar xz sha256sum jq find sort cmp; do
    command -v "${cmd}" >/dev/null || fail "${cmd} missing from image; rebuild testenv-rust, do not install ad hoc"
done
export LC_ALL=C TZ=UTC
unset TAR_OPTIONS XZ_OPT XZ_DEFAULTS
umask 022
WORK=$(mktemp -d "${OUTPUT}/.go-deps.XXXXXXXX")
trap 'rm -rf -- "${WORK}"' EXIT
export HOME="${WORK}/home" GOPATH="${WORK}/gopath" GOCACHE="${WORK}/go-build"
export GOMODCACHE="${WORK}/go-mod" GOTOOLCHAIN=local GOENV=off GOWORK=off
export GO111MODULE=on GOFLAGS= CGO_ENABLED=0
# Do not fall back to mutable VCS checkouts or inherit host proxy exceptions.
export GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
export GOPRIVATE= GONOPROXY= GONOSUMDB= GOINSECURE=
mkdir -p "${HOME}" "${GOMODCACHE}"

git init -q "${WORK}/source"
git -C "${WORK}/source" fetch -q --depth=1 \
    https://github.com/d2lang/d2.git "refs/tags/v${VERSION}"
git -C "${WORK}/source" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
cd "${WORK}/source"
SOURCE_COMMIT=$(git rev-parse HEAD)
[[ -f go.mod && -f go.sum ]] || fail "tag must contain go.mod and go.sum"
[[ $(sed -n 's/^module //p' go.mod) == github.com/d2lang/d2 ]] || fail "unexpected D2 module path"
GO_MIN=$(sed -n 's/^go //p' go.mod)
[[ "${GO_MIN}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "cannot read Go minimum"
echo "==> D2 v${VERSION} (${SOURCE_COMMIT}), requires Go ${GO_MIN}"
go version
check_pinned_modules() {
    if [[ -n $(git status --porcelain -- go.mod go.sum) ]]; then
        git --no-pager diff -- go.mod go.sum >&2
        fail "module preparation changed pinned go.mod/go.sum after $1; review upstream sources"
    fi
}

# Follow go-module.eclass's download scope. Explicit 'all' also downloads
# graph modules unused by the root build/tests and can add unpinned sums.
# Go enforces the source's minimum with GOTOOLCHAIN=local, failing if too old.
go mod download -modcacherw
check_pinned_modules "module download"
export GOPROXY=off GOSUMDB=off
go mod verify
check_pinned_modules "module verification"
go list -mod=readonly -deps -test ./... >/dev/null
check_pinned_modules "offline root package/test resolution"

# Sumdb responses and locks are download-time state, not build inputs. Module
# proxy version lists can be written in nondeterministic download order.
rm -rf "${GOMODCACHE}/cache/download/sumdb"
find "${GOMODCACHE}/cache/download" -type f -name '*.lock' -delete
find "${GOMODCACHE}/cache/download" -type f -name list -exec sort -u -o '{}' '{}' \;
NAME="d2-${VERSION}-go-deps.tar.xz"
META="d2-${VERSION}-go-deps.json"
# Epoch zero is policy, not the generation time. Fix xz's thread count too,
# since parallel compression can change bytes depending on runner CPU count.
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --format=gnu --mode='u+rwX,go+rX,go-w' -C "${WORK}" -cf - go-mod \
    | xz --threads=1 -9 --check=crc64 > "${WORK}/${NAME}"
xz --test "${WORK}/${NAME}"
SHA256=$(sha256sum "${WORK}/${NAME}"); SHA256="${SHA256%% *}"
MOD_SHA=$(sha256sum go.mod); MOD_SHA="${MOD_SHA%% *}"
SUM_SHA=$(sha256sum go.sum); SUM_SHA="${SUM_SHA%% *}"
jq -n --arg version "${VERSION}" --arg commit "${SOURCE_COMMIT}" \
    --arg minimum "${GO_MIN}" --arg mod "${MOD_SHA}" --arg sum "${SUM_SHA}" \
    --arg archive "${NAME}" --arg sha256 "${SHA256}" \
    '{schema: 1, upstream: "d2lang/d2", tag: ("v" + $version),
      source_commit: $commit, go_min_version: $minimum,
      go_mod_sha256: $mod, go_sum_sha256: $sum, archive: $archive,
      sha256: $sha256, archive_epoch: 0}' > "${WORK}/${META}"

# Check the pair before writing either file. Hard links are atomic and refuse
# racing replacements; WORK and OUTPUT share a filesystem.
for file in "${NAME}" "${META}"; do
    if [[ -e "${OUTPUT}/${file}" || -L "${OUTPUT}/${file}" ]]; then
        cmp -s "${WORK}/${file}" "${OUTPUT}/${file}" || fail "${file} exists with different bytes; never replace a published source-release archive silently"
    fi
done
for file in "${NAME}" "${META}"; do
    if ! ln -T -- "${WORK}/${file}" "${OUTPUT}/${file}" 2>/dev/null; then
        cmp -s "${WORK}/${file}" "${OUTPUT}/${file}" || fail "cannot publish matching ${file} locally; refusing replacement"
    fi
done
printf '==> %s/%s\nSHA256: %s\n' "${OUTPUT}" "${NAME}" "${SHA256}"
