#!/bin/bash
# upgrade-ebuild.sh — detect and prepare ebuild version upgrades for
# packages in the adaptive-overlay.
#
# Compares the current overlay version against the latest upstream
# release, copies the ebuild, and — for Cargo/Rust packages — diffs
# upstream Cargo.toml to detect dependency changes (GIT_CRATES,
# RUST_MIN_VER, WEBRTC_COMMIT).  Non-Cargo packages (C/C++, meson,
# etc.) get a straightforward version bump without dependency diffing.
#
# The build system is read from the "build_system" field in
# .agent/packages.json.  If absent, it defaults to "cargo" for
# backward compatibility.
#
# Usage:
#   scripts/upgrade-ebuild.sh <category/package> [--version <ver>]
#                              [--apply] [--json] [--manifest]
#
# Examples:
#   scripts/upgrade-ebuild.sh app-editors/zed
#   scripts/upgrade-ebuild.sh app-editors/zed --version 0.229.0
#   scripts/upgrade-ebuild.sh app-editors/zed --apply --manifest
#
# Options:
#   --version <ver>  Target a specific upstream version instead of
#                    auto-detecting the latest release.
#   --apply          Apply detected GIT_CRATES / RUST_MIN_VER /
#                    WEBRTC_COMMIT changes to the new ebuild
#                    automatically (best-effort).
#   --manifest       Run `pkgdev manifest` after applying changes.
#                    Implies --apply.
#   --json           Output results as JSON instead of human-readable
#                    text.
#   -h, --help       Show this help text.
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay \
#     scripts/upgrade-ebuild.sh app-editors/zed
#
# Environment variables:
#   OVERLAY_DIR    Path to the adaptive-overlay repo root.
#                  Defaults to the current working directory.
#   GITHUB_TOKEN   Optional GitHub API token for higher rate limits.
#
# Requirements: bash (4+), curl, jq, diff, sort (with -V), grep, sed
#
# Phase 4 of the implementation plan.

set -euo pipefail

# =============================================================================
# Argument parsing
# =============================================================================

PACKAGE_DIR=""
TARGET_VERSION=""
DO_APPLY=0
DO_MANIFEST=0
OUTPUT_JSON=0

show_help() {
    sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            shift
            TARGET_VERSION="${1:-}"
            if [[ -z "${TARGET_VERSION}" ]]; then
                echo "error: --version requires a value." >&2
                exit 1
            fi
            ;;
        --apply)    DO_APPLY=1 ;;
        --manifest)
            DO_MANIFEST=1
            DO_APPLY=1
            ;;
        --json)     OUTPUT_JSON=1 ;;
        -h|--help)  show_help ;;
        -*)
            echo "error: unknown option: $1" >&2
            echo "Usage: $(basename "$0") <category/package> [options]" >&2
            exit 1
            ;;
        *)
            if [[ -z "${PACKAGE_DIR}" ]]; then
                PACKAGE_DIR="$1"
            else
                echo "error: unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ -z "${PACKAGE_DIR}" ]]; then
    echo "Usage: $(basename "$0") <category/package> [--version <ver>] [--apply] [--manifest] [--json]" >&2
    echo "  e.g. $(basename "$0") app-editors/zed" >&2
    echo "  e.g. $(basename "$0") app-editors/zed --version 0.229.0 --apply" >&2
    exit 1
fi

# =============================================================================
# Overlay root resolution
# =============================================================================

OVERLAY_DIR="${OVERLAY_DIR:-$(pwd)}"

if [[ ! -f "${OVERLAY_DIR}/metadata/layout.conf" ]]; then
    echo "error: '${OVERLAY_DIR}' does not look like the adaptive-overlay repo root." >&2
    echo "  Run this script from the repo root, or set OVERLAY_DIR." >&2
    exit 1
fi

PACKAGES_JSON="${OVERLAY_DIR}/.agent/packages.json"
if [[ ! -f "${PACKAGES_JSON}" ]]; then
    echo "error: ${PACKAGES_JSON} not found." >&2
    exit 1
fi

PKG_PATH="${OVERLAY_DIR}/${PACKAGE_DIR}"
if [[ ! -d "${PKG_PATH}" ]]; then
    echo "error: package directory '${PKG_PATH}' does not exist." >&2
    exit 1
fi

# =============================================================================
# Dependency check
# =============================================================================

for cmd in curl jq diff sort grep sed; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "error: required command '${cmd}' not found." >&2
        exit 1
    fi
done

# =============================================================================
# GitHub API helpers
# =============================================================================

CURL_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# gh_api URL — fetch a GitHub API endpoint with optional auth and
# standard headers.  Returns the response body on stdout.  Exits 1
# on failure.
gh_api() {
    local url="$1"
    curl -sf --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
        "${url}" 2>/dev/null
}

# gh_raw OWNER/REPO TAG PATH — fetch a raw file from a GitHub repo at
# a specific tag.  Prints file contents on stdout.
gh_raw() {
    local repo="$1" tag="$2" path="$3"
    curl -sf --max-time 30 \
        "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
        "https://raw.githubusercontent.com/${repo}/${tag}/${path}" 2>/dev/null
}

# =============================================================================
# Package metadata from packages.json
# =============================================================================

CATEGORY="${PACKAGE_DIR%%/*}"
PKG_NAME="${PACKAGE_DIR##*/}"

# Read package entry from packages.json.
PKG_ENTRY=$(jq -r \
    --arg cat "${CATEGORY}" \
    --arg name "${PKG_NAME}" \
    '.[] | select(.category == $cat and .name == $name)' \
    "${PACKAGES_JSON}")

if [[ -z "${PKG_ENTRY}" || "${PKG_ENTRY}" == "null" ]]; then
    echo "error: no entry for ${PACKAGE_DIR} in ${PACKAGES_JSON}." >&2
    exit 1
fi

UPSTREAM_REPO=$(echo "${PKG_ENTRY}" | jq -r '.upstream_repo // empty')
UPSTREAM_TYPE=$(echo "${PKG_ENTRY}" | jq -r '.upstream_type // empty')
VERSION_PATTERN=$(echo "${PKG_ENTRY}" | jq -r '.version_pattern // empty')
BUILD_SYSTEM=$(echo "${PKG_ENTRY}" | jq -r '.build_system // "cargo"')

if [[ -z "${UPSTREAM_REPO}" ]]; then
    echo "error: ${PACKAGE_DIR} has no upstream_repo defined — cannot auto-upgrade." >&2
    exit 1
fi

# =============================================================================
# Current overlay version
# =============================================================================

# overlay_latest_version — prints the highest ebuild version found.
overlay_latest_version() {
    local best=""
    for ebuild in "${PKG_PATH}"/${PKG_NAME}-*.ebuild; do
        [[ -f "${ebuild}" ]] || continue
        local base
        base=$(basename "${ebuild}" .ebuild)
        local ver="${base#"${PKG_NAME}"-}"
        best="${ver}"
    done
    # Use sort -V for proper ordering across all ebuilds.
    if compgen -G "${PKG_PATH}/${PKG_NAME}-*.ebuild" >/dev/null; then
        for ebuild in "${PKG_PATH}"/${PKG_NAME}-*.ebuild; do
            basename "${ebuild}" .ebuild
        done | sed "s/^${PKG_NAME}-//" | sort -V | tail -1
    else
        echo "none"
    fi
}

CURRENT_VERSION=$(overlay_latest_version)
if [[ "${CURRENT_VERSION}" == "none" ]]; then
    echo "error: no existing ebuilds found in ${PKG_PATH}." >&2
    exit 1
fi

# =============================================================================
# Determine target version
# =============================================================================

if [[ -n "${TARGET_VERSION}" ]]; then
    UPSTREAM_VERSION="${TARGET_VERSION}"
else
    # Auto-detect from GitHub API.
    case "${UPSTREAM_TYPE}" in
        github-release)
            # Fetch recent releases and pick the first non-draft,
            # non-prerelease that matches the version pattern.
            RELEASES=$(gh_api "https://api.github.com/repos/${UPSTREAM_REPO}/releases?per_page=10") || {
                echo "error: failed to query GitHub Releases API for ${UPSTREAM_REPO}." >&2
                exit 1
            }
            TAGS=$(echo "${RELEASES}" | jq -r '
                [.[] | select(.draft == false and .prerelease == false)]
                | .[].tag_name // empty
            ')
            UPSTREAM_VERSION=""
            while IFS= read -r tag; do
                [[ -z "${tag}" ]] && continue
                if echo "${tag}" | grep -qE "^${VERSION_PATTERN}$"; then
                    UPSTREAM_VERSION=$(echo "${tag}" | sed -E "s/^${VERSION_PATTERN}$/\\1/")
                    break
                fi
            done <<< "${TAGS}"
            if [[ -z "${UPSTREAM_VERSION}" ]]; then
                echo "error: could not determine latest version from GitHub Releases for ${UPSTREAM_REPO}." >&2
                exit 1
            fi
            ;;
        github-tag)
            TAGS_RESP=$(gh_api "https://api.github.com/repos/${UPSTREAM_REPO}/tags?per_page=30") || {
                echo "error: failed to query GitHub Tags API for ${UPSTREAM_REPO}." >&2
                exit 1
            }
            UPSTREAM_VERSION=$(echo "${TAGS_RESP}" \
                | jq -r '.[].name // empty' \
                | grep -E "^${VERSION_PATTERN}$" \
                | sed -E "s/^${VERSION_PATTERN}$/\\1/" \
                | sort -V \
                | tail -n 1)
            if [[ -z "${UPSTREAM_VERSION}" ]]; then
                echo "error: could not determine latest version from GitHub Tags for ${UPSTREAM_REPO}." >&2
                exit 1
            fi
            ;;
        *)
            echo "error: upstream_type '${UPSTREAM_TYPE}' is not supported for auto-detection." >&2
            echo "  Use --version <ver> to specify the target version explicitly." >&2
            exit 1
            ;;
    esac
fi

# Strip any leading 'v' if someone passed --version v0.229.0
UPSTREAM_VERSION="${UPSTREAM_VERSION#v}"

# =============================================================================
# Version comparison
# =============================================================================

# Strip revision suffix for comparison.
CURRENT_CLEAN=$(echo "${CURRENT_VERSION}" | sed -E 's/-r[0-9]+$//')

if [[ "${CURRENT_CLEAN}" == "${UPSTREAM_VERSION}" ]]; then
    if [[ "${OUTPUT_JSON}" -eq 1 ]]; then
        jq -n \
            --arg pkg "${PACKAGE_DIR}" \
            --arg current "${CURRENT_VERSION}" \
            --arg upstream "${UPSTREAM_VERSION}" \
            --arg build_system "${BUILD_SYSTEM}" \
            '{package: $pkg, current: $current, upstream: $upstream, build_system: $build_system, status: "up-to-date", changes: []}'
    else
        echo "==> ${PACKAGE_DIR} is already at version ${CURRENT_VERSION} — nothing to do."
    fi
    exit 0
fi

# Check that upstream is actually newer.
HIGHER=$(printf '%s\n%s\n' "${CURRENT_CLEAN}" "${UPSTREAM_VERSION}" | sort -V | tail -1)
if [[ "${HIGHER}" != "${UPSTREAM_VERSION}" ]]; then
    echo "error: upstream version ${UPSTREAM_VERSION} is not newer than current ${CURRENT_VERSION}." >&2
    exit 1
fi

# =============================================================================
# Source availability check
# =============================================================================

if [[ "${OUTPUT_JSON}" -eq 0 ]]; then
    echo "==> Upgrading ${PACKAGE_DIR}: ${CURRENT_VERSION} → ${UPSTREAM_VERSION}"
    echo ""
    echo "==> Checking source availability..."
fi

SOURCES_OK=1

# Main source tarball.
if curl -sfI --max-time 15 \
    "https://github.com/${UPSTREAM_REPO}/archive/refs/tags/v${UPSTREAM_VERSION}.tar.gz" \
    >/dev/null 2>&1; then
    [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✓ Main source tarball"
else
    [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✗ Main source tarball NOT available"
    SOURCES_OK=0
fi

# Crates tarball (Zed-specific — gentoo-crate-dist).
if [[ "${PKG_NAME}" == "zed" ]]; then
    if curl -sfI --max-time 15 \
        "https://github.com/gentoo-crate-dist/zed/releases/download/v${UPSTREAM_VERSION}/zed-${UPSTREAM_VERSION}-crates.tar.xz" \
        >/dev/null 2>&1; then
        [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✓ Crates tarball (gentoo-crate-dist)"
    else
        [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✗ Crates tarball not yet available (may lag by hours)"
        SOURCES_OK=0
    fi
fi

if [[ "${SOURCES_OK}" -eq 0 ]]; then
    echo "" >&2
    echo "error: not all required sources are available yet. Retry later." >&2
    exit 1
fi

[[ "${OUTPUT_JSON}" -eq 0 ]] && echo ""

# =============================================================================
# Copy ebuild
# =============================================================================

FROM_EBUILD="${PKG_NAME}-${CURRENT_VERSION}.ebuild"
TO_EBUILD="${PKG_NAME}-${UPSTREAM_VERSION}.ebuild"

if [[ -f "${PKG_PATH}/${TO_EBUILD}" ]]; then
    [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "==> ${TO_EBUILD} already exists — using it as-is for analysis."
else
    cp "${PKG_PATH}/${FROM_EBUILD}" "${PKG_PATH}/${TO_EBUILD}"
    [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "==> Copied ${FROM_EBUILD} → ${TO_EBUILD}"
fi

[[ "${OUTPUT_JSON}" -eq 0 ]] && echo ""

# =============================================================================
# Dependency change detection — Cargo.toml diff
# =============================================================================

# --- Collect all changes into arrays for structured reporting ----------------
#
# The script collects two kinds of data:
#   1. Structured change records (for JSON/agent consumption)
#   2. Human-readable descriptions (for terminal output)
#
# The JSON output provides structured data so an AI agent can act on
# each change precisely.  The agent is responsible for:
#   - Inserting new GIT_CRATES entries (with correct subpath)
#   - Removing old GIT_CRATES entries
#   - Updating RUST_MIN_VER (has container/toolchain implications)
# The script handles:
#   - Updating existing commit hashes (global sed replacement)
#   - Updating WEBRTC_COMMIT

declare -a CHANGE_DESCRIPTIONS=()
declare -A UPDATED_GIT_CRATES=()     # crate -> new_rev
declare -A ADDED_GIT_CRATES=()       # crate -> "url;rev"
declare -a REMOVED_GIT_CRATES=()     # crate names
NEW_RUST_MIN_VER=""
NEW_WEBRTC_COMMIT=""
declare -a NEW_WORKSPACE_MEMBERS=()

if [[ "${BUILD_SYSTEM}" == "cargo" ]]; then

[[ "${OUTPUT_JSON}" -eq 0 ]] && echo "==> Fetching upstream Cargo.toml for diff..."

OLD_CARGO=$(gh_raw "${UPSTREAM_REPO}" "v${CURRENT_CLEAN}" "Cargo.toml") || {
    echo "error: failed to fetch Cargo.toml for v${CURRENT_CLEAN}." >&2
    exit 1
}

NEW_CARGO=$(gh_raw "${UPSTREAM_REPO}" "v${UPSTREAM_VERSION}" "Cargo.toml") || {
    echo "error: failed to fetch Cargo.toml for v${UPSTREAM_VERSION}." >&2
    exit 1
}

CARGO_DIFF=$(diff <(echo "${OLD_CARGO}") <(echo "${NEW_CARGO}") || true)

# --- A) Parse git dependency changes from the diff ---------------------------

# Extract git deps from a Cargo.toml string.  Output format:
#   crate_name<TAB>git_url<TAB>rev_hash
# This handles both inline and multi-line dep declarations.
#
# Note: grep may return non-zero when no lines match, so we guard
# with `|| true` to avoid tripping `set -e`.
extract_git_deps() {
    local cargo_text="$1"
    local git_lines
    git_lines=$(echo "${cargo_text}" | grep -E 'git\s*=\s*"' || true)
    [[ -z "${git_lines}" ]] && return 0

    while IFS= read -r line; do
        # Extract the crate name (key before the = {).
        local crate_name
        crate_name=$(echo "${line}" | sed -n 's/^\s*\([a-zA-Z0-9_-]*\)\s*=\s*{.*/\1/p')
        [[ -z "${crate_name}" ]] && continue

        # Extract git URL.
        local git_url
        git_url=$(echo "${line}" | sed -n 's/.*git\s*=\s*"\([^"]*\)".*/\1/p')
        [[ -z "${git_url}" ]] && continue

        # Extract rev (may not exist — some use branch or tag).
        local rev
        rev=$(echo "${line}" | sed -n 's/.*rev\s*=\s*"\([^"]*\)".*/\1/p')
        [[ -z "${rev}" ]] && continue

        printf '%s\t%s\t%s\n' "${crate_name}" "${git_url}" "${rev}"
    done <<< "${git_lines}"
}

# Build maps of old and new git deps.
declare -A OLD_GIT_DEPS=()
declare -A OLD_GIT_URLS=()
while IFS=$'\t' read -r crate url rev; do
    [[ -z "${crate}" ]] && continue
    OLD_GIT_DEPS["${crate}"]="${rev}"
    OLD_GIT_URLS["${crate}"]="${url}"
done < <(extract_git_deps "${OLD_CARGO}")

declare -A NEW_GIT_DEPS=()
declare -A NEW_GIT_URLS=()
while IFS=$'\t' read -r crate url rev; do
    [[ -z "${crate}" ]] && continue
    NEW_GIT_DEPS["${crate}"]="${rev}"
    NEW_GIT_URLS["${crate}"]="${url}"
done < <(extract_git_deps "${NEW_CARGO}")

# Compare: updated revisions.
for crate in "${!NEW_GIT_DEPS[@]}"; do
    new_rev="${NEW_GIT_DEPS[${crate}]}"
    if [[ -n "${OLD_GIT_DEPS[${crate}]+x}" ]]; then
        old_rev="${OLD_GIT_DEPS[${crate}]}"
        if [[ "${old_rev}" != "${new_rev}" ]]; then
            UPDATED_GIT_CRATES["${crate}"]="${new_rev}"
            CHANGE_DESCRIPTIONS+=("GIT_CRATES updated: ${crate}  ${old_rev} → ${new_rev}")
        fi
    else
        ADDED_GIT_CRATES["${crate}"]="${NEW_GIT_URLS[${crate}]};${new_rev}"
        CHANGE_DESCRIPTIONS+=("GIT_CRATES added: ${crate}  url=${NEW_GIT_URLS[${crate}]}  rev=${new_rev}")
    fi
done

# Compare: removed deps.
for crate in "${!OLD_GIT_DEPS[@]}"; do
    if [[ -z "${NEW_GIT_DEPS[${crate}]+x}" ]]; then
        REMOVED_GIT_CRATES+=("${crate}")
        CHANGE_DESCRIPTIONS+=("GIT_CRATES removed: ${crate}")
    fi
done

# --- B) Check for new workspace members -------------------------------------

OLD_MEMBERS=$(echo "${OLD_CARGO}" | sed -n '/^members\s*=/,/]/p' | grep -oE '"[^"]*"' | tr -d '"' | sort || true)
NEW_MEMBERS=$(echo "${NEW_CARGO}" | sed -n '/^members\s*=/,/]/p' | grep -oE '"[^"]*"' | tr -d '"' | sort || true)
ADDED_MEMBERS=$(comm -13 <(echo "${OLD_MEMBERS}") <(echo "${NEW_MEMBERS}") || true)

if [[ -n "${ADDED_MEMBERS}" ]]; then
    while IFS= read -r member; do
        [[ -z "${member}" ]] && continue
        NEW_WORKSPACE_MEMBERS+=("${member}")
    done <<< "${ADDED_MEMBERS}"

    if [[ ${#NEW_WORKSPACE_MEMBERS[@]} -gt 0 ]]; then
        # Report new members but don't flood the API by fetching each
        # one's Cargo.toml individually.  For large workspaces (like
        # Zed with 200+ crates) this would exhaust rate limits.
        #
        # Instead, we note the new members and advise manual review.
        # The workspace-level Cargo.toml already captures most git
        # deps; sub-crate-only git deps are rare but possible.
        MEMBER_COUNT=${#NEW_WORKSPACE_MEMBERS[@]}
        CHANGE_DESCRIPTIONS+=("New workspace members (${MEMBER_COUNT}): review sub-crate Cargo.toml files for git deps not declared at workspace level")

        # If there are only a few new members (≤5), it's safe to
        # fetch them individually for a thorough check.
        if [[ "${MEMBER_COUNT}" -le 5 ]]; then
            for member in "${NEW_WORKSPACE_MEMBERS[@]}"; do
                MEMBER_CARGO=$(gh_raw "${UPSTREAM_REPO}" "v${UPSTREAM_VERSION}" "${member}/Cargo.toml" 2>/dev/null) || true
                if [[ -n "${MEMBER_CARGO}" ]]; then
                    while IFS=$'\t' read -r crate url rev; do
                        [[ -z "${crate}" ]] && continue
                        # Only flag if not already tracked at workspace level.
                        if [[ -z "${NEW_GIT_DEPS[${crate}]+x}" ]] && [[ -z "${ADDED_GIT_CRATES[${crate}]+x}" ]]; then
                            ADDED_GIT_CRATES["${crate}"]="${url};${rev}"
                            CHANGE_DESCRIPTIONS+=("GIT_CRATES added (from new member ${member}): ${crate}  url=${url}  rev=${rev}")
                        fi
                    done < <(extract_git_deps "${MEMBER_CARGO}")
                fi
            done
        fi
    fi
fi

# --- C) RUST_MIN_VER ---------------------------------------------------------

OLD_RUST_VER=$(echo "${OLD_CARGO}" | grep -E '^\s*rust-version\s*=' | sed -E 's/.*"([^"]+)".*/\1/' | head -1 || true)
NEW_RUST_VER=$(echo "${NEW_CARGO}" | grep -E '^\s*rust-version\s*=' | sed -E 's/.*"([^"]+)".*/\1/' | head -1 || true)

if [[ -n "${NEW_RUST_VER}" && "${OLD_RUST_VER}" != "${NEW_RUST_VER}" ]]; then
    NEW_RUST_MIN_VER="${NEW_RUST_VER}"
    CHANGE_DESCRIPTIONS+=("RUST_MIN_VER: ${OLD_RUST_VER:-unknown} → ${NEW_RUST_VER}")
fi

# --- D) WEBRTC_COMMIT (Zed-specific) ----------------------------------------

if [[ "${PKG_NAME}" == "zed" ]]; then
    # The WEBRTC_COMMIT may need updating if the livekit-rust-sdks rev changed.
    # Check if any livekit-related crate rev changed.
    LIVEKIT_CHANGED=0
    for crate in "${!UPDATED_GIT_CRATES[@]}"; do
        local_url="${NEW_GIT_URLS[${crate}]:-}"
        if [[ "${local_url}" == *"livekit"* ]]; then
            LIVEKIT_CHANGED=1
            break
        fi
    done

    if [[ "${LIVEKIT_CHANGED}" -eq 1 ]]; then
        # Try to determine the new WEBRTC_COMMIT from the livekit-rust-sdks repo.
        # The WEBRTC_COMMIT corresponds to a release tag like "webrtc-XXXX-N"
        # at livekit/rust-sdks.  We check the releases page.
        LIVEKIT_RELEASES=$(gh_api "https://api.github.com/repos/livekit/rust-sdks/releases?per_page=10" 2>/dev/null) || true
        if [[ -n "${LIVEKIT_RELEASES}" ]]; then
            LATEST_WEBRTC=$(echo "${LIVEKIT_RELEASES}" | jq -r '
                [.[] | select(.tag_name | startswith("webrtc-")) | .tag_name]
                | first // empty
            ' | sed 's/^webrtc-//')

            CURRENT_WEBRTC=$(grep -oP 'WEBRTC_COMMIT="\K[^"]+' "${PKG_PATH}/${TO_EBUILD}" 2>/dev/null || true)

            if [[ -n "${LATEST_WEBRTC}" && "${LATEST_WEBRTC}" != "${CURRENT_WEBRTC}" ]]; then
                NEW_WEBRTC_COMMIT="${LATEST_WEBRTC}"
                CHANGE_DESCRIPTIONS+=("WEBRTC_COMMIT: ${CURRENT_WEBRTC:-unknown} → ${LATEST_WEBRTC}  (verify at https://github.com/livekit/rust-sdks/releases)")
            fi
        else
            CHANGE_DESCRIPTIONS+=("WEBRTC_COMMIT: ⚠ livekit deps changed but could not query livekit/rust-sdks releases — manual check needed")
        fi
    fi
fi

fi  # end if BUILD_SYSTEM == "cargo"

# =============================================================================
# Apply changes to the new ebuild (if --apply)
# =============================================================================

APPLIED=()

if [[ "${DO_APPLY}" -eq 1 && "${BUILD_SYSTEM}" == "cargo" && ${#CHANGE_DESCRIPTIONS[@]} -gt 0 ]]; then
    EBUILD_FILE="${PKG_PATH}/${TO_EBUILD}"

    # --- Apply GIT_CRATES commit hash updates --------------------------------
    # For updated crates, we need to find all GIT_CRATES entries that share
    # the same repo and old commit, then update them to the new commit.
    #
    # Strategy: group updated crates by their git URL.  For each URL, find
    # the old commit (from OLD_GIT_DEPS of any crate with that URL) and
    # the new commit, then do a global sed replacement of old→new in the
    # GIT_CRATES block.
    declare -A URL_OLD_TO_NEW=()
    for crate in "${!UPDATED_GIT_CRATES[@]}"; do
        new_rev="${UPDATED_GIT_CRATES[${crate}]}"
        old_rev="${OLD_GIT_DEPS[${crate}]}"
        url="${NEW_GIT_URLS[${crate}]}"
        # Normalize URL for grouping (strip trailing .git).
        norm_url="${url%.git}"
        key="${norm_url}|${old_rev}"
        URL_OLD_TO_NEW["${key}"]="${new_rev}"
    done

    for key in "${!URL_OLD_TO_NEW[@]}"; do
        old_rev="${key##*|}"
        new_rev="${URL_OLD_TO_NEW[${key}]}"
        if [[ "${old_rev}" != "${new_rev}" ]]; then
            # Replace all occurrences of the old commit hash with the new one
            # within the ebuild.  This covers GIT_CRATES entries AND the
            # src_prepare() commit variables.
            sed -i "s/${old_rev}/${new_rev}/g" "${EBUILD_FILE}"
            APPLIED+=("Replaced commit ${old_rev:0:12}… → ${new_rev:0:12}…")
        fi
    done

    # --- RUST_MIN_VER is NOT auto-applied ------------------------------------
    # Changing RUST_MIN_VER has cascading implications:
    #   - The testenv-rust container has a specific Rust version baked in
    #   - If the new min version exceeds the container's Rust, builds fail
    #     or trigger a massive in-container recompile
    #   - The Containerfile may need updating (new rust-bin version,
    #     keyword accepts, possibly new LLVM version)
    #   - The container image must be rebuilt and published first
    # This is reported in the JSON for the agent to handle with awareness
    # of these downstream effects.
    if [[ -n "${NEW_RUST_MIN_VER}" ]]; then
        APPLIED+=("RUST_MIN_VER change detected (${NEW_RUST_MIN_VER}) — requires agent/manual handling (container rebuild may be needed)")
    fi

    # --- Apply WEBRTC_COMMIT -------------------------------------------------
    if [[ -n "${NEW_WEBRTC_COMMIT}" ]]; then
        OLD_WC=$(grep -oP 'WEBRTC_COMMIT="\K[^"]+' "${EBUILD_FILE}" || true)
        if [[ -n "${OLD_WC}" ]]; then
            sed -i "s/WEBRTC_COMMIT=\"${OLD_WC}\"/WEBRTC_COMMIT=\"${NEW_WEBRTC_COMMIT}\"/" "${EBUILD_FILE}"
            APPLIED+=("WEBRTC_COMMIT: ${OLD_WC} → ${NEW_WEBRTC_COMMIT}")
        fi
    fi

    # --- New and removed GIT_CRATES are the agent's responsibility -----------
    # The script reports them in the JSON output but does not attempt to
    # insert or remove entries — that requires understanding repo structure
    # (subpaths, workspace layout) which an AI agent handles better.
    if [[ ${#ADDED_GIT_CRATES[@]} -gt 0 ]]; then
        APPLIED+=("New GIT_CRATES entries require agent/manual insertion (${#ADDED_GIT_CRATES[@]} crate(s))")
    fi
    if [[ ${#REMOVED_GIT_CRATES[@]} -gt 0 ]]; then
        APPLIED+=("Removed GIT_CRATES entries require agent/manual removal (${#REMOVED_GIT_CRATES[@]} crate(s))")
    fi
fi

# =============================================================================
# Run manifest generation (if --manifest)
# =============================================================================

MANIFEST_RESULT=""
if [[ "${DO_MANIFEST}" -eq 1 ]]; then
    [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "" && echo "==> Generating Manifest..."

    # Prefer scripts/manifest.sh (runs in container — works everywhere).
    # Fall back to local pkgdev if the script is not available.
    MANIFEST_SCRIPT="${OVERLAY_DIR}/scripts/manifest.sh"

    if [[ -x "${MANIFEST_SCRIPT}" ]]; then
        [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    Using: scripts/manifest.sh (container)"
        if OVERLAY_DIR="${OVERLAY_DIR}" "${MANIFEST_SCRIPT}" "${PACKAGE_DIR}" 2>&1; then
            MANIFEST_RESULT="success"
            [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✓ Manifest generated successfully."
        else
            MANIFEST_RESULT="failed"
            [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✗ Manifest generation failed." >&2
        fi
    elif command -v pkgdev &>/dev/null; then
        [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    Using: pkgdev (local)"
        if (cd "${PKG_PATH}" && pkgdev manifest 2>&1); then
            MANIFEST_RESULT="success"
            [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✓ Manifest generated successfully."
        else
            MANIFEST_RESULT="failed"
            [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ✗ Manifest generation failed." >&2
        fi
    else
        MANIFEST_RESULT="skipped:no-tooling"
        [[ "${OUTPUT_JSON}" -eq 0 ]] && echo "    ⚠ Neither scripts/manifest.sh nor pkgdev found — skipping."
    fi
fi

# =============================================================================
# Output
# =============================================================================

if [[ "${OUTPUT_JSON}" -eq 1 ]]; then
    # Build structured JSON output for agent consumption.
    #
    # The JSON includes both human-readable descriptions AND structured
    # data so an agent can programmatically act on each change.

    # Human-readable change descriptions.
    CHANGES_JSON="[]"
    for desc in "${CHANGE_DESCRIPTIONS[@]+"${CHANGE_DESCRIPTIONS[@]}"}"; do
        CHANGES_JSON=$(echo "${CHANGES_JSON}" | jq --arg d "${desc}" '. + [$d]')
    done
    APPLIED_JSON="[]"
    for desc in "${APPLIED[@]+"${APPLIED[@]}"}"; do
        APPLIED_JSON=$(echo "${APPLIED_JSON}" | jq --arg d "${desc}" '. + [$d]')
    done

    # Structured: updated/added/removed GIT_CRATES — only meaningful for
    # Cargo packages but we always emit the keys (empty for non-Cargo).
    UPDATED_JSON="[]"
    ADDED_JSON_STRUCT="[]"
    REMOVED_JSON="[]"
    MEMBERS_JSON="[]"

    if [[ "${BUILD_SYSTEM}" == "cargo" ]]; then
        for crate in "${!UPDATED_GIT_CRATES[@]}"; do
            new_rev="${UPDATED_GIT_CRATES[${crate}]}"
            old_rev="${OLD_GIT_DEPS[${crate}]}"
            url="${NEW_GIT_URLS[${crate}]}"
            UPDATED_JSON=$(echo "${UPDATED_JSON}" | jq \
                --arg c "${crate}" --arg old "${old_rev}" \
                --arg new "${new_rev}" --arg url "${url}" \
                '. + [{crate: $c, old_rev: $old, new_rev: $new, url: $url}]')
        done

        for crate in "${!ADDED_GIT_CRATES[@]}"; do
            IFS=';' read -r url rev <<< "${ADDED_GIT_CRATES[${crate}]}"
            ADDED_JSON_STRUCT=$(echo "${ADDED_JSON_STRUCT}" | jq \
                --arg c "${crate}" --arg url "${url}" --arg rev "${rev}" \
                '. + [{crate: $c, url: $url, rev: $rev}]')
        done

        for crate in "${REMOVED_GIT_CRATES[@]+"${REMOVED_GIT_CRATES[@]}"}"; do
            REMOVED_JSON=$(echo "${REMOVED_JSON}" | jq --arg c "${crate}" '. + [$c]')
        done

        for member in "${NEW_WORKSPACE_MEMBERS[@]+"${NEW_WORKSPACE_MEMBERS[@]}"}"; do
            MEMBERS_JSON=$(echo "${MEMBERS_JSON}" | jq --arg m "${member}" '. + [$m]')
        done
    fi

    jq -n \
        --arg pkg "${PACKAGE_DIR}" \
        --arg current "${CURRENT_VERSION}" \
        --arg upstream "${UPSTREAM_VERSION}" \
        --arg build_system "${BUILD_SYSTEM}" \
        --arg from_ebuild "${FROM_EBUILD}" \
        --arg to_ebuild "${TO_EBUILD}" \
        --arg ebuild_path "${PKG_PATH}/${TO_EBUILD}" \
        --argjson changes "${CHANGES_JSON}" \
        --argjson applied "${APPLIED_JSON}" \
        --argjson updated_git_crates "${UPDATED_JSON}" \
        --argjson added_git_crates "${ADDED_JSON_STRUCT}" \
        --argjson removed_git_crates "${REMOVED_JSON}" \
        --argjson new_workspace_members "${MEMBERS_JSON}" \
        --arg rust_min_ver "${NEW_RUST_MIN_VER}" \
        --arg webrtc_commit "${NEW_WEBRTC_COMMIT}" \
        --arg manifest "${MANIFEST_RESULT}" \
        --arg status "upgrade-prepared" \
        '{
            package: $pkg,
            current: $current,
            upstream: $upstream,
            build_system: $build_system,
            from_ebuild: $from_ebuild,
            to_ebuild: $to_ebuild,
            ebuild_path: $ebuild_path,
            status: $status,
            changes_detected: $changes,
            changes_applied: $applied,
            git_crates: {
                updated: $updated_git_crates,
                added: $added_git_crates,
                removed: $removed_git_crates
            },
            new_workspace_members: $new_workspace_members,
            rust_min_ver: (if $rust_min_ver == "" then null else $rust_min_ver end),
            webrtc_commit: (if $webrtc_commit == "" then null else $webrtc_commit end),
            manifest: $manifest
        }'
else
    echo ""
    echo "==> Dependency change summary for ${PACKAGE_DIR} ${CURRENT_VERSION} → ${UPSTREAM_VERSION}"
    echo ""

    if [[ "${BUILD_SYSTEM}" != "cargo" ]]; then
        echo "    Non-Cargo package (build_system=${BUILD_SYSTEM}) — no dependency diffing performed."
        echo "    Straightforward version bump."
    elif [[ ${#CHANGE_DESCRIPTIONS[@]} -eq 0 ]]; then
        echo "    No dependency changes detected — straightforward version bump."
    else
        echo "    ${#CHANGE_DESCRIPTIONS[@]} change(s) detected:"
        echo ""
        for desc in "${CHANGE_DESCRIPTIONS[@]}"; do
            echo "    • ${desc}"
        done
    fi

    if [[ ${#APPLIED[@]} -gt 0 ]]; then
        echo ""
        echo "==> Applied changes (--apply):"
        for desc in "${APPLIED[@]}"; do
            echo "    ${desc}"
        done
    fi

    if [[ -n "${MANIFEST_RESULT}" ]]; then
        echo ""
        echo "    Manifest: ${MANIFEST_RESULT}"
    fi

    echo ""
    echo "==> Ebuild: ${PKG_PATH}/${TO_EBUILD}"

    # Provide next-steps guidance.
    if [[ "${DO_APPLY}" -eq 0 && ${#CHANGE_DESCRIPTIONS[@]} -gt 0 ]]; then
        echo ""
        echo "==> Next steps:"
        echo "    1. Review the changes above"
        echo "    2. Edit ${TO_EBUILD} to apply them (or re-run with --apply)"
        echo "    3. Run: cd ${PKG_PATH} && pkgdev manifest"
        echo "    4. Run: scripts/lint.sh ${PACKAGE_DIR}"
        echo "    5. Run: scripts/test-build.sh ${PACKAGE_DIR} ${TO_EBUILD}"
    elif [[ "${DO_APPLY}" -eq 1 && "${DO_MANIFEST}" -eq 0 ]]; then
        echo ""
        echo "==> Next steps:"
        echo "    1. Review applied changes in ${TO_EBUILD}"
        echo "    2. Run: cd ${PKG_PATH} && pkgdev manifest"
        echo "    3. Run: scripts/lint.sh ${PACKAGE_DIR}"
        echo "    4. Run: scripts/test-build.sh ${PACKAGE_DIR} ${TO_EBUILD}"
    elif [[ "${DO_MANIFEST}" -eq 1 && "${MANIFEST_RESULT}" == "success" ]]; then
        echo ""
        echo "==> Next steps:"
        echo "    1. Review applied changes in ${TO_EBUILD}"
        echo "    2. Run: scripts/lint.sh ${PACKAGE_DIR}"
        echo "    3. Run: scripts/test-build.sh ${PACKAGE_DIR} ${TO_EBUILD}"
    fi
fi

# Exit 0 on success — the upgrade is prepared (even if changes need manual review).
exit 0
