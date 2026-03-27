#!/bin/bash
# check-updates.sh — check for upstream version updates across all
# tracked packages in the adaptive-overlay.
#
# Reads .agent/packages.json, queries the GitHub Releases API for each
# package with upstream_type "github-release", scans the overlay tree
# for current ebuild versions, and reports which packages have newer
# upstream releases available.
#
# Usage:
#   scripts/check-updates.sh
#   scripts/check-updates.sh --json
#
# Options:
#   --json   Output results as a JSON array instead of a human-readable
#            table.  Useful for piping into other tools or workflows.
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay scripts/check-updates.sh
#
# Environment variables:
#   OVERLAY_DIR   Path to the adaptive-overlay repo root.
#                 Defaults to the current working directory.
#   GITHUB_TOKEN  Optional GitHub API token.  Unauthenticated requests
#                 are limited to 60/hour; authenticated get 5,000/hour.
#
# Requirements: bash, jq, curl, sort (with -V for version sorting)
#
# Phase 3.3 of the implementation plan.

set -euo pipefail

# --- Parse arguments ---------------------------------------------------------
OUTPUT_JSON=0
for arg in "$@"; do
    case "${arg}" in
        --json) OUTPUT_JSON=1 ;;
        -h | --help)
            sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            echo "Usage: $(basename "$0") [--json]" >&2
            exit 1
            ;;
    esac
done

# --- Resolve the overlay root ------------------------------------------------
OVERLAY_DIR="${OVERLAY_DIR:-$(pwd)}"

if [ ! -f "${OVERLAY_DIR}/metadata/layout.conf" ]; then
    echo "error: '${OVERLAY_DIR}' does not look like the" \
        "adaptive-overlay repo root." >&2
    echo "  Run this script from the repo root, or set" \
        "OVERLAY_DIR." >&2
    exit 1
fi

PACKAGES_JSON="${OVERLAY_DIR}/.agent/packages.json"

if [ ! -f "${PACKAGES_JSON}" ]; then
    echo "error: ${PACKAGES_JSON} not found." >&2
    exit 1
fi

# --- Dependency check --------------------------------------------------------
for cmd in jq curl sort; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "error: required command '${cmd}' not found." >&2
        exit 1
    fi
done

# --- GitHub API helper -------------------------------------------------------
# Build curl auth header if a token is available.
CURL_AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    CURL_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# github_latest_version OWNER/REPO VERSION_PATTERN
#   Queries the GitHub Releases API for the latest non-draft,
#   non-prerelease release and extracts the version using the
#   given regex pattern against the tag name.
#   Prints the extracted version string, or empty on failure.
#
#   Note: some projects (e.g. Surge XT) publish stable versions
#   as tags only, without creating GitHub Release objects.  For
#   those, use github_latest_tag_version / upstream_type
#   "github-tag" instead.
github_latest_version() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases"

    # Fetch up to 10 recent releases so we can skip prereleases
    # and drafts reliably even if the very latest is one.
    local response
    response=$(
        curl -sf --max-time 15 \
            -H "Accept: application/vnd.github+json" \
            "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
            "${api_url}?per_page=10" 2>/dev/null
    ) || return 1

    # Get all non-draft, non-prerelease tag names.
    local tags
    tags=$(
        echo "${response}" \
            | jq -r '
                [ .[]
                  | select(.draft == false
                           and .prerelease == false) ]
                | .[].tag_name // empty
            '
    )

    # Find the first tag that actually matches the version
    # pattern.  Tags like "Nightly" that don't match are
    # silently skipped.
    local tag
    while IFS= read -r tag; do
        [ -z "${tag}" ] && continue
        if echo "${tag}" | grep -qE "^${pattern}$"; then
            echo "${tag}" | sed -E "s/^${pattern}$/\\1/"
            return 0
        fi
    done <<< "${tags}"

    # No matching tag found.
    return 1
}

# github_latest_tag_version OWNER/REPO VERSION_PATTERN
#   Queries the GitHub Tags API and returns the highest version
#   whose tag matches the given pattern.  This is the right
#   approach for projects that create tags for stable releases
#   but do not create GitHub Release objects (e.g. Surge XT uses
#   tags like release_xt_1.3.4).
#
#   Because tags are returned in reverse-chronological order by
#   the API (most recent first), and we further sort matched
#   versions with `sort -V`, this correctly picks the highest
#   version even if the API page order is surprising.
github_latest_tag_version() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/tags"

    local response
    response=$(
        curl -sf --max-time 15 \
            -H "Accept: application/vnd.github+json" \
            "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
            "${api_url}?per_page=30" 2>/dev/null
    ) || return 1

    # Extract tag names, filter to those matching the pattern,
    # convert to versions, and pick the highest.
    local version
    version=$(
        echo "${response}" \
            | jq -r '.[].name // empty' \
            | grep -E "^${pattern}$" \
            | sed -E "s/^${pattern}$/\\1/" \
            | sort -V \
            | tail -n 1
    )

    if [ -n "${version}" ]; then
        echo "${version}"
        return 0
    fi

    return 1
}

# --- Scan overlay for current versions ---------------------------------------
# overlay_versions CATEGORY NAME
#   Scans <category>/<name>/*.ebuild and extracts version strings.
#   Prints the highest version found (by version sort), or "none".
overlay_versions() {
    local category="$1"
    local name="$2"
    local pkg_dir="${OVERLAY_DIR}/${category}/${name}"

    if [ ! -d "${pkg_dir}" ]; then
        echo "none"
        return
    fi

    # Extract version from filenames like carla-2.5.10.ebuild.
    # Strip the package name prefix and the .ebuild suffix, then
    # also strip any -rN revision suffix for comparison purposes.
    local versions=()
    for ebuild in "${pkg_dir}"/*.ebuild; do
        [ -f "${ebuild}" ] || continue
        local base
        base=$(basename "${ebuild}" .ebuild)
        # Remove <name>- prefix to get version[-rN]
        local ver="${base#"${name}"-}"
        versions+=("${ver}")
    done

    if [ ${#versions[@]} -eq 0 ]; then
        echo "none"
        return
    fi

    # Sort by version and take the highest.
    printf '%s\n' "${versions[@]}" | sort -V | tail -n 1
}

# Strip -rN revision suffix for clean comparison.
strip_revision() {
    echo "$1" | sed -E 's/-r[0-9]+$//'
}

# --- Main loop ---------------------------------------------------------------
PKG_COUNT=$(jq 'length' "${PACKAGES_JSON}")

# Collect results for JSON output or summary.
UPDATES_FOUND=0
JSON_RESULTS="[]"

# Column header (human-readable mode).
if [ "${OUTPUT_JSON}" -eq 0 ]; then
    printf "%-30s %-15s %-15s %s\n" \
        "PACKAGE" "CURRENT" "UPSTREAM" "STATUS"
    printf "%-30s %-15s %-15s %s\n" \
        "-------" "-------" "--------" "------"
fi

for i in $(seq 0 $((PKG_COUNT - 1))); do
    CATEGORY=$(jq -r ".[$i].category" "${PACKAGES_JSON}")
    NAME=$(jq -r ".[$i].name" "${PACKAGES_JSON}")
    UPSTREAM_REPO=$(jq -r ".[$i].upstream_repo // empty" \
        "${PACKAGES_JSON}")
    UPSTREAM_TYPE=$(jq -r ".[$i].upstream_type" "${PACKAGES_JSON}")
    VERSION_PATTERN=$(jq -r ".[$i].version_pattern // empty" \
        "${PACKAGES_JSON}")
    PKG_LABEL="${CATEGORY}/${NAME}"

    # Get current overlay version.
    CURRENT_VER=$(overlay_versions "${CATEGORY}" "${NAME}")
    CURRENT_CLEAN=$(strip_revision "${CURRENT_VER}")

    # Determine upstream version based on type.
    UPSTREAM_VER=""
    STATUS=""

    case "${UPSTREAM_TYPE}" in
        github-release)
            if [ -z "${UPSTREAM_REPO}" ] \
                || [ -z "${VERSION_PATTERN}" ]; then
                STATUS="error:missing-metadata"
            else
                UPSTREAM_VER=$(
                    github_latest_version \
                        "${UPSTREAM_REPO}" \
                        "${VERSION_PATTERN}"
                ) || true
                if [ -z "${UPSTREAM_VER}" ]; then
                    STATUS="error:api-failed"
                fi
            fi
            ;;
        github-tag)
            if [ -z "${UPSTREAM_REPO}" ] \
                || [ -z "${VERSION_PATTERN}" ]; then
                STATUS="error:missing-metadata"
            else
                UPSTREAM_VER=$(
                    github_latest_tag_version \
                        "${UPSTREAM_REPO}" \
                        "${VERSION_PATTERN}"
                ) || true
                if [ -z "${UPSTREAM_VER}" ]; then
                    STATUS="error:api-failed"
                fi
            fi
            ;;
        manual)
            UPSTREAM_VER="n/a"
            STATUS="manual"
            ;;
        *)
            UPSTREAM_VER="n/a"
            STATUS="unsupported:${UPSTREAM_TYPE}"
            ;;
    esac

    # Compare versions if we got an upstream version.
    if [ -z "${STATUS}" ]; then
        if [ "${CURRENT_VER}" = "none" ]; then
            STATUS="new-package"
            UPDATES_FOUND=$((UPDATES_FOUND + 1))
        elif [ "${CURRENT_CLEAN}" = "${UPSTREAM_VER}" ]; then
            STATUS="up-to-date"
        else
            # Use version sort to decide if upstream is newer.
            HIGHER=$(
                printf '%s\n%s\n' \
                    "${CURRENT_CLEAN}" "${UPSTREAM_VER}" \
                    | sort -V | tail -n 1
            )
            if [ "${HIGHER}" = "${UPSTREAM_VER}" ] \
                && [ "${HIGHER}" != "${CURRENT_CLEAN}" ]; then
                STATUS="UPDATE-AVAILABLE"
                UPDATES_FOUND=$((UPDATES_FOUND + 1))
            else
                STATUS="up-to-date"
            fi
        fi
    fi

    # Human-readable output.
    if [ "${OUTPUT_JSON}" -eq 0 ]; then
        printf "%-30s %-15s %-15s %s\n" \
            "${PKG_LABEL}" \
            "${CURRENT_VER}" \
            "${UPSTREAM_VER:-?}" \
            "${STATUS}"
    fi

    # Build JSON result entry.
    JSON_RESULTS=$(
        echo "${JSON_RESULTS}" | jq \
            --arg cat "${CATEGORY}" \
            --arg name "${NAME}" \
            --arg current "${CURRENT_VER}" \
            --arg upstream "${UPSTREAM_VER:-}" \
            --arg status "${STATUS}" \
            '. + [{
                category: $cat,
                name: $name,
                current_version: $current,
                upstream_version: $upstream,
                status: $status
            }]'
    )
done

# --- Output ------------------------------------------------------------------
if [ "${OUTPUT_JSON}" -eq 1 ]; then
    echo "${JSON_RESULTS}" | jq .
else
    echo ""
    if [ "${UPDATES_FOUND}" -gt 0 ]; then
        echo "${UPDATES_FOUND} package(s) with updates available."
    else
        echo "All trackable packages are up to date."
    fi
fi

# Exit with code 1 if updates were found — useful for CI to detect
# that action is needed without parsing output.
if [ "${UPDATES_FOUND}" -gt 0 ]; then
    exit 1
fi

exit 0
