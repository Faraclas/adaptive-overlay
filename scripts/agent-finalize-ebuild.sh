#!/bin/bash
# agent-finalize-ebuild.sh — end-to-end local upgrade pipeline: detect
# upstream changes, apply mechanical updates, call GitHub Copilot CLI
# for intelligent finalization, generate Manifest, lint, and optionally
# build-test.
#
# This is the single entry point for the local upgrade path. It calls
# upgrade-ebuild.sh internally, so you do not need to run it separately.
#
# Usage:
#   scripts/agent-finalize-ebuild.sh <category/package>
#   scripts/agent-finalize-ebuild.sh app-editors/zed
#   scripts/agent-finalize-ebuild.sh app-editors/zed --version 0.229.0
#   scripts/agent-finalize-ebuild.sh app-editors/zed --build
#   scripts/agent-finalize-ebuild.sh --json /path/to/upgrade.json
#
# Options:
#   --version <ver>  Target a specific upstream version instead of
#                    auto-detecting the latest release.
#   --json <file>    Skip the upgrade script and use a pre-existing
#                    JSON report file instead.
#   --model <name>   Model to use (default: claude-sonnet-4.6)
#   --build          Run a build test after manifest + lint
#   --skip-manifest  Skip manifest generation after agent edits
#   --skip-lint      Skip lint after agent edits
#   --dry-run        Print the prompt but do not call Copilot
#   -h, --help       Show this help text
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay \
#     scripts/agent-finalize-ebuild.sh app-editors/zed
#
# Environment variables:
#   OVERLAY_DIR    Path to the adaptive-overlay repo root.
#                  Defaults to the current working directory.
#   GITHUB_TOKEN   Optional GitHub API token for higher rate
#                  limits (passed through to upgrade-ebuild.sh).
#
# Requirements: bash (4+), jq, copilot (GitHub Copilot CLI)
#
# Phase 4 of the implementation plan.

set -euo pipefail

# =========================================================================
# Defaults
# =========================================================================

MODEL="claude-sonnet-4.6"
SKIP_MANIFEST=0
SKIP_LINT=0
DO_BUILD=0
DRY_RUN=0
PACKAGE_DIR=""
TARGET_VERSION=""
JSON_FILE=""

# =========================================================================
# Argument parsing
# =========================================================================

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
        --json)
            shift
            JSON_FILE="${1:-}"
            if [[ -z "${JSON_FILE}" ]]; then
                echo "error: --json requires a file path." >&2
                exit 1
            fi
            ;;
        --model)
            shift
            MODEL="${1:-}"
            if [[ -z "${MODEL}" ]]; then
                echo "error: --model requires a value." >&2
                exit 1
            fi
            ;;
        --build)         DO_BUILD=1 ;;
        --skip-manifest) SKIP_MANIFEST=1 ;;
        --skip-lint)     SKIP_LINT=1 ;;
        --dry-run)       DRY_RUN=1 ;;
        -h|--help)       show_help ;;
        -*)
            echo "error: unknown option: $1" >&2
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

# Validate: need either a package or a JSON file, not both.
if [[ -n "${JSON_FILE}" && -n "${PACKAGE_DIR}" ]]; then
    echo "error: specify either <category/package> or" \
         "--json <file>, not both." >&2
    exit 1
fi

if [[ -z "${JSON_FILE}" && -z "${PACKAGE_DIR}" ]]; then
    echo "Usage: $(basename "$0") <category/package> [options]" >&2
    echo "       $(basename "$0") --json <file> [options]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $(basename "$0") app-editors/zed" >&2
    echo "  $(basename "$0") app-editors/zed --version 0.229.0" >&2
    echo "  $(basename "$0") app-editors/zed --build" >&2
    echo "  $(basename "$0") --json /path/to/report.json" >&2
    exit 1
fi

if [[ -n "${JSON_FILE}" && ! -f "${JSON_FILE}" ]]; then
    echo "error: JSON file not found: ${JSON_FILE}" >&2
    exit 1
fi

if [[ -n "${JSON_FILE}" && -n "${TARGET_VERSION}" ]]; then
    echo "error: --version cannot be used with --json" \
         "(version is already in the JSON)." >&2
    exit 1
fi

# =========================================================================
# Overlay root resolution
# =========================================================================

OVERLAY_DIR="${OVERLAY_DIR:-$(pwd)}"

if [[ ! -f "${OVERLAY_DIR}/metadata/layout.conf" ]]; then
    echo "error: '${OVERLAY_DIR}' does not look like" \
         "the adaptive-overlay repo root." >&2
    echo "  Run from the repo root, or set OVERLAY_DIR." >&2
    exit 1
fi

# =========================================================================
# Verify copilot CLI is available (skip for dry-run)
# =========================================================================

if [[ "${DRY_RUN}" -eq 0 ]]; then
    if ! command -v copilot &>/dev/null; then
        echo "error: 'copilot' (GitHub Copilot CLI) not" \
             "found in PATH." >&2
        echo "  Install it or check your PATH." >&2
        exit 1
    fi
fi

# =========================================================================
# Step 1: Run upgrade-ebuild.sh (or read existing JSON)
# =========================================================================

if [[ -n "${JSON_FILE}" ]]; then
    echo "==> Reading existing upgrade report: ${JSON_FILE}"
    JSON=$(cat "${JSON_FILE}")
else
    UPGRADE_ARGS=("${PACKAGE_DIR}" "--apply" "--json")
    if [[ -n "${TARGET_VERSION}" ]]; then
        UPGRADE_ARGS+=("--version" "${TARGET_VERSION}")
    fi

    echo "==> Running: scripts/upgrade-ebuild.sh" \
         "${UPGRADE_ARGS[*]}"
    echo ""

    JSON=$(bash "${OVERLAY_DIR}/scripts/upgrade-ebuild.sh" \
        "${UPGRADE_ARGS[@]}")

    echo ""
    echo "==> Upgrade script output:"
    echo "${JSON}" | jq .
fi

# =========================================================================
# Step 2: Parse the upgrade JSON
# =========================================================================

STATUS=$(echo "${JSON}" | jq -r '.status')

if [[ "${STATUS}" == "up-to-date" ]]; then
    echo ""
    echo "==> Package is already up to date — nothing to do."
    exit 0
fi

if [[ "${STATUS}" != "upgrade-prepared" ]]; then
    echo "error: unexpected status '${STATUS}' in JSON." >&2
    echo "  Expected 'upgrade-prepared'." >&2
    exit 1
fi

PACKAGE=$(echo "${JSON}" | jq -r '.package')
EBUILD_PATH=$(echo "${JSON}" | jq -r '.ebuild_path')
UPSTREAM=$(echo "${JSON}" | jq -r '.upstream')
CURRENT=$(echo "${JSON}" | jq -r '.current')

# Resolve ebuild path — handle both absolute and relative.
if [[ "${EBUILD_PATH}" == /* ]]; then
    FULL_EBUILD_PATH="${EBUILD_PATH}"
else
    FULL_EBUILD_PATH="${OVERLAY_DIR}/${EBUILD_PATH}"
fi

if [[ ! -f "${FULL_EBUILD_PATH}" ]]; then
    echo "error: ebuild not found: ${FULL_EBUILD_PATH}" >&2
    echo "  Did upgrade-ebuild.sh run with --apply?" >&2
    exit 1
fi

echo ""
echo "==> Upgrade prepared"
echo "    Package  : ${PACKAGE}"
echo "    Version  : ${CURRENT} → ${UPSTREAM}"
echo "    Ebuild   : ${EBUILD_PATH}"

# =========================================================================
# Step 3: Resolve the skills doc
# =========================================================================

# Map package to skills doc. Currently only zed has one;
# extend with a lookup table or packages.json field as needed.
SKILLS_DOC=""
case "${PACKAGE}" in
    app-editors/zed)
        SKILLS_DOC="${OVERLAY_DIR}/.agent/skills/update-zed-editor.md"
        ;;
esac

SKILLS_CONTENT=""
if [[ -n "${SKILLS_DOC}" && -f "${SKILLS_DOC}" ]]; then
    SKILLS_CONTENT=$(cat "${SKILLS_DOC}")
    echo "    Skills   : ${SKILLS_DOC##*/}"
elif [[ -n "${SKILLS_DOC}" ]]; then
    echo "warning: skills doc not found:" \
         "${SKILLS_DOC}" >&2
    echo "    Proceeding without package-specific skills."
else
    echo "    Skills   : (none — generic upgrade)"
fi

# =========================================================================
# Step 4: Read current ebuild content
# =========================================================================

EBUILD_CONTENT=$(cat "${FULL_EBUILD_PATH}")

# Save a copy for diffing later.
EBUILD_BEFORE="${EBUILD_CONTENT}"

# =========================================================================
# Step 5: Construct the prompt
# =========================================================================

echo ""
echo "==> Constructing prompt for Copilot (model: ${MODEL})"

PROMPT="You are an expert Gentoo Linux ebuild developer. Your task is
to finalize an ebuild upgrade by applying the changes described in the
upgrade report below.

IMPORTANT RULES:
- Output ONLY the complete edited ebuild file content.
- Do NOT include any explanations, commentary, or markdown fences.
- Do NOT omit any part of the ebuild — output the full file.
- Do NOT change anything that is not called for by the upgrade report.
- Preserve all formatting, comments, and whitespace conventions from
  the original ebuild.
- If the upgrade report shows no changes needing agent attention
  (empty added/removed arrays, null rust_min_ver), output the ebuild
  unchanged."

if [[ -n "${SKILLS_CONTENT}" ]]; then
    PROMPT="${PROMPT}

---

## Package-Specific Procedure

${SKILLS_CONTENT}"
fi

PROMPT="${PROMPT}

---

## Upgrade Report (from upgrade-ebuild.sh --apply --json)

\`\`\`json
${JSON}
\`\`\`

---

## Current Ebuild Content

\`\`\`bash
${EBUILD_CONTENT}
\`\`\`

---

## Task

Apply the changes described in the upgrade report to the ebuild
above. The mechanical changes (commit hash updates, version bump,
WEBRTC_COMMIT) have already been applied by the upgrade script.

Focus on:
1. Insert any new GIT_CRATES entries from git_crates.added
   (determine correct subpath as described in the skills doc)
2. Remove any GIT_CRATES entries listed in git_crates.removed
3. Handle RUST_MIN_VER if reported (update the variable)
4. Check new_workspace_members for additional git dependencies
5. Verify the overall ebuild is consistent and correct

Output the complete ebuild file. Nothing else."

# =========================================================================
# Step 6: Dry-run — print prompt and exit
# =========================================================================

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo ""
    echo "==> DRY RUN — prompt follows:"
    echo "=========================================="
    echo "${PROMPT}"
    echo "=========================================="
    echo ""
    PROMPT_BYTES=$(echo "${PROMPT}" | wc -c)
    echo "==> Prompt size: ${PROMPT_BYTES} bytes"
    echo "==> Would call: copilot -s --no-ask-user" \
         "--model ${MODEL}"
    exit 0
fi

# =========================================================================
# Step 7: Call Copilot CLI
# =========================================================================

echo "==> Calling Copilot CLI..."
echo ""

RESULT=$(echo "${PROMPT}" \
    | copilot -s --no-ask-user --model "${MODEL}" 2>/dev/null)

COPILOT_EXIT=$?

if [[ ${COPILOT_EXIT} -ne 0 ]]; then
    echo "error: copilot CLI exited with code" \
         "${COPILOT_EXIT}." >&2
    exit 1
fi

if [[ -z "${RESULT}" ]]; then
    echo "error: copilot returned empty output." >&2
    exit 1
fi

# =========================================================================
# Step 8: Post-process the response
# =========================================================================

echo "==> Post-processing Copilot response..."

# Strip markdown code fences if the model wrapped the output.
# Handles ```bash, ```ebuild, ```sh, or bare ``` at start/end.
CLEANED="${RESULT}"

# Remove leading code fence (```<optional-lang> + newline).
if echo "${CLEANED}" | head -1 | grep -qE '^\s*```'; then
    CLEANED=$(echo "${CLEANED}" | tail -n +2)
fi

# Remove trailing code fence (``` at end).
if echo "${CLEANED}" | tail -1 | grep -qE '^\s*```\s*$'; then
    CLEANED=$(echo "${CLEANED}" | head -n -1)
fi

# Strip C0 control characters (0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F)
# but preserve tab (0x09), newline (0x0A), and CR (0x0D).
CLEANED=$(echo "${CLEANED}" \
    | tr -d '\000-\010\013\014\016-\037')

# Strip leading preamble — LLMs sometimes emit reasoning or
# commentary before the actual ebuild content. An ebuild must
# start with a comment (#) or EAPI declaration. Drop all lines
# before the first line that starts with '#' or 'EAPI'.
FIRST_EBUILD_LINE=$(echo "${CLEANED}" \
    | grep -n '^\(#\|EAPI\)' | head -1 | cut -d: -f1)
if [[ -n "${FIRST_EBUILD_LINE}" \
    && "${FIRST_EBUILD_LINE}" -gt 1 ]]; then
    STRIPPED=$((FIRST_EBUILD_LINE - 1))
    echo "    Stripped ${STRIPPED} leading preamble line(s)"
    CLEANED=$(echo "${CLEANED}" | tail -n +"${FIRST_EBUILD_LINE}")
fi

# Sanity check: the result should look like an ebuild.
if ! echo "${CLEANED}" | head -5 | grep -q 'EAPI'; then
    echo "error: Copilot output does not look like a" \
         "valid ebuild (no EAPI found in first" \
         "5 lines)." >&2
    echo "" >&2
    echo "==> Raw output (first 20 lines):" >&2
    echo "${RESULT}" | head -20 >&2
    exit 1
fi

# =========================================================================
# Step 9: Write the edited ebuild back
# =========================================================================

echo "==> Writing finalized ebuild: ${EBUILD_PATH}"

echo "${CLEANED}" > "${FULL_EBUILD_PATH}"

# Show diff against the pre-agent version.
echo ""
echo "==> Changes made by agent:"
DIFF_OUTPUT=$(diff -u \
    <(echo "${EBUILD_BEFORE}") \
    <(cat "${FULL_EBUILD_PATH}") || true)

if [[ -z "${DIFF_OUTPUT}" ]]; then
    echo "    (no differences — ebuild unchanged)"
else
    ADDED=$(echo "${DIFF_OUTPUT}" | grep -c '^+[^+]' || true)
    REMOVED=$(echo "${DIFF_OUTPUT}" | grep -c '^-[^-]' || true)
    echo "    +${ADDED} / -${REMOVED} lines"
    echo ""
    echo "${DIFF_OUTPUT}"
fi

# =========================================================================
# Step 10: Manifest generation
# =========================================================================

if [[ "${SKIP_MANIFEST}" -eq 0 ]]; then
    echo ""
    echo "==> Running manifest generation..."
    if ! bash "${OVERLAY_DIR}/scripts/manifest.sh" "${PACKAGE}"; then
        echo "" >&2
        echo "error: manifest generation failed." >&2
        echo "  The agent edits may have introduced" \
             "invalid URIs or commit hashes." >&2
        echo "  Check the ebuild and re-run:" >&2
        echo "    scripts/manifest.sh ${PACKAGE}" >&2
        exit 1
    fi
    echo "    ✓ Manifest generated successfully."
else
    echo ""
    echo "==> Skipping manifest generation (--skip-manifest)"
fi

# =========================================================================
# Step 11: Lint
# =========================================================================

if [[ "${SKIP_LINT}" -eq 0 ]]; then
    echo ""
    echo "==> Running lint..."
    if ! bash "${OVERLAY_DIR}/scripts/lint.sh" "${PACKAGE}"; then
        echo "" >&2
        echo "warning: lint reported issues." >&2
        echo "  Review the output above and fix if" \
             "needed." >&2
        echo "  Re-run: scripts/lint.sh ${PACKAGE}" >&2
        # Don't exit — lint warnings are not fatal.
        # The human reviewer will decide.
    else
        echo "    ✓ Lint passed."
    fi
else
    echo ""
    echo "==> Skipping lint (--skip-lint)"
fi

# =========================================================================
# Step 12: Build test (optional)
# =========================================================================

if [[ "${DO_BUILD}" -eq 1 ]]; then
    echo ""
    echo "==> Running build test (this may take a while)..."
    TO_EBUILD=$(echo "${JSON}" | jq -r '.to_ebuild // empty')
    if ! bash "${OVERLAY_DIR}/scripts/test-build.sh" \
        "${PACKAGE}" "${TO_EBUILD}"; then
        echo "" >&2
        echo "error: build test failed." >&2
        echo "  Review the output above for errors." >&2
        echo "  Re-run:" >&2
        echo "    scripts/test-build.sh ${PACKAGE}" \
             "${TO_EBUILD}" >&2
        exit 1
    fi
    echo "    ✓ Build test passed."
fi

# =========================================================================
# Summary
# =========================================================================

echo ""
echo "==========================================="
echo "==> Agent finalization complete."
echo "==========================================="
echo ""
echo "    Package : ${PACKAGE}"
echo "    Version : ${CURRENT} → ${UPSTREAM}"
echo "    Ebuild  : ${EBUILD_PATH}"
echo "    Model   : ${MODEL}"
echo ""

# Report what was run.
STEPS_RUN="upgrade → agent"
if [[ "${SKIP_MANIFEST}" -eq 0 ]]; then
    STEPS_RUN="${STEPS_RUN} → manifest ✓"
fi
if [[ "${SKIP_LINT}" -eq 0 ]]; then
    STEPS_RUN="${STEPS_RUN} → lint ✓"
fi
if [[ "${DO_BUILD}" -eq 1 ]]; then
    STEPS_RUN="${STEPS_RUN} → build ✓"
fi
echo "    Pipeline: ${STEPS_RUN}"
echo ""

if [[ "${DO_BUILD}" -eq 0 ]]; then
    echo "==> Next steps:"
    echo "    1. Review the ebuild: ${EBUILD_PATH}"
    echo "    2. Build test (optional):"
    echo "       scripts/test-build.sh ${PACKAGE}"
    echo "    3. Commit and push."
else
    echo "==> Next steps:"
    echo "    1. Review the ebuild: ${EBUILD_PATH}"
    echo "    2. Commit and push."
fi
