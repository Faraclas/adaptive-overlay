#!/bin/bash
# agent-finalize-ebuild.sh — pipe an upgrade report to GitHub Copilot CLI
# for intelligent ebuild finalization, then run manifest + lint.
#
# Reads structured JSON output from upgrade-ebuild.sh, constructs a
# prompt combining the skills doc + ebuild content + change report, and
# pipes it to the Copilot CLI. The edited ebuild is written back to disk,
# followed by manifest generation and linting.
#
# Usage:
#   scripts/agent-finalize-ebuild.sh <json-file>
#   scripts/agent-finalize-ebuild.sh /tmp/upgrade-result.json
#
# The JSON file must be output from:
#   scripts/upgrade-ebuild.sh <cat/pkg> --apply --json
#
# Options:
#   --model <name>   Model to use (default: claude-sonnet-4.6)
#   --skip-manifest  Skip manifest generation after agent edits
#   --skip-lint      Skip lint after agent edits
#   --dry-run        Print the prompt but do not call Copilot
#   -h, --help       Show this help text
#
# Must be run from the root of the adaptive-overlay repo, or set
# OVERLAY_DIR to point to it explicitly:
#   OVERLAY_DIR=~/code/repos/adaptive-overlay \
#     scripts/agent-finalize-ebuild.sh /tmp/upgrade.json
#
# Environment variables:
#   OVERLAY_DIR    Path to the adaptive-overlay repo root.
#                  Defaults to the current working directory.
#
# Requirements: bash (4+), jq, copilot (GitHub Copilot CLI)

set -euo pipefail

# =========================================================================
# Defaults
# =========================================================================

MODEL="claude-sonnet-4.6"
SKIP_MANIFEST=0
SKIP_LINT=0
DRY_RUN=0
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
        --model)
            shift
            MODEL="${1:-}"
            if [[ -z "${MODEL}" ]]; then
                echo "error: --model requires a value." >&2
                exit 1
            fi
            ;;
        --skip-manifest) SKIP_MANIFEST=1 ;;
        --skip-lint)     SKIP_LINT=1 ;;
        --dry-run)       DRY_RUN=1 ;;
        -h|--help)       show_help ;;
        -*)
            echo "error: unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "${JSON_FILE}" ]]; then
                JSON_FILE="$1"
            else
                echo "error: unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ -z "${JSON_FILE}" ]]; then
    echo "Usage: $(basename "$0") <json-file> [options]" >&2
    echo "  e.g. $(basename "$0") /tmp/upgrade-result.json" >&2
    exit 1
fi

if [[ ! -f "${JSON_FILE}" ]]; then
    echo "error: JSON file not found: ${JSON_FILE}" >&2
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
# Verify copilot CLI is available
# =========================================================================

if ! command -v copilot &>/dev/null; then
    echo "error: 'copilot' (GitHub Copilot CLI) not found" \
         "in PATH." >&2
    echo "  Install it or check your PATH." >&2
    exit 1
fi

# =========================================================================
# Parse the upgrade JSON
# =========================================================================

echo "==> Reading upgrade report: ${JSON_FILE}"

JSON=$(cat "${JSON_FILE}")

STATUS=$(echo "${JSON}" | jq -r '.status')
if [[ "${STATUS}" == "up-to-date" ]]; then
    echo "    Package is already up to date — nothing to do."
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

# Resolve ebuild path relative to overlay root.
FULL_EBUILD_PATH="${OVERLAY_DIR}/${EBUILD_PATH}"

if [[ ! -f "${FULL_EBUILD_PATH}" ]]; then
    echo "error: ebuild not found: ${FULL_EBUILD_PATH}" >&2
    echo "  Did upgrade-ebuild.sh run with --apply?" >&2
    exit 1
fi

echo "    Package  : ${PACKAGE}"
echo "    Version  : ${CURRENT} → ${UPSTREAM}"
echo "    Ebuild   : ${EBUILD_PATH}"

# =========================================================================
# Resolve the skills doc
# =========================================================================

# Map package to skills doc. Currently only zed has one; this can be
# extended with a lookup table or packages.json field as needed.
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
# Read current ebuild content
# =========================================================================

EBUILD_CONTENT=$(cat "${FULL_EBUILD_PATH}")

# =========================================================================
# Construct the prompt
# =========================================================================

echo ""
echo "==> Constructing prompt for Copilot (model: ${MODEL})"

# Build the prompt in parts for clarity.
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
# Dry-run: print prompt and exit
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
# Call Copilot CLI
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
# Post-process the response
# =========================================================================

echo "==> Post-processing Copilot response..."

# Strip markdown code fences if the model wrapped the output.
# Handles ```bash, ```ebuild, ```sh, or bare ``` at start/end.
CLEANED="${RESULT}"

# Remove leading code fence (```<optional-lang> followed by newline).
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

# Sanity check: the result should look like an ebuild.
if ! echo "${CLEANED}" | head -5 | grep -q 'EAPI'; then
    echo "error: Copilot output does not look like a" \
         "valid ebuild (no EAPI found in first 5 lines)." >&2
    echo ""
    echo "==> Raw output (first 20 lines):"
    echo "${RESULT}" | head -20
    echo ""
    echo "The raw output has been saved to:" \
         "/tmp/agent-finalize-raw-output.txt"
    echo "${RESULT}" > /tmp/agent-finalize-raw-output.txt
    exit 1
fi

# =========================================================================
# Write the edited ebuild back
# =========================================================================

echo "==> Writing finalized ebuild: ${EBUILD_PATH}"

# Back up the original.
cp "${FULL_EBUILD_PATH}" "${FULL_EBUILD_PATH}.bak"
echo "    Backup: ${EBUILD_PATH}.bak"

echo "${CLEANED}" > "${FULL_EBUILD_PATH}"

# Show a quick diff summary.
echo ""
echo "==> Changes made by agent:"
if diff -u "${FULL_EBUILD_PATH}.bak" "${FULL_EBUILD_PATH}" \
    > /tmp/agent-finalize-diff.txt 2>&1; then
    echo "    (no differences — ebuild unchanged)"
else
    # Print a compact summary: count of lines added/removed.
    ADDED=$(grep -c '^+[^+]' /tmp/agent-finalize-diff.txt \
        || true)
    REMOVED=$(grep -c '^-[^-]' /tmp/agent-finalize-diff.txt \
        || true)
    echo "    +${ADDED} / -${REMOVED} lines"
    echo ""
    cat /tmp/agent-finalize-diff.txt
fi

# Clean up the backup.
rm -f "${FULL_EBUILD_PATH}.bak"

# =========================================================================
# Manifest generation
# =========================================================================

if [[ "${SKIP_MANIFEST}" -eq 0 ]]; then
    echo ""
    echo "==> Running manifest generation..."
    if ! bash "${OVERLAY_DIR}/scripts/manifest.sh" "${PACKAGE}"; then
        echo ""
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
# Lint
# =========================================================================

if [[ "${SKIP_LINT}" -eq 0 ]]; then
    echo ""
    echo "==> Running lint..."
    if ! bash "${OVERLAY_DIR}/scripts/lint.sh" "${PACKAGE}"; then
        echo ""
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
# Summary
# =========================================================================

echo ""
echo "==> Agent finalization complete."
echo ""
echo "    Package : ${PACKAGE}"
echo "    Version : ${CURRENT} → ${UPSTREAM}"
echo "    Ebuild  : ${EBUILD_PATH}"
echo "    Model   : ${MODEL}"
echo ""
echo "==> Next steps:"
echo "    1. Review the ebuild: ${EBUILD_PATH}"
echo "    2. Build test (optional):"
echo "       scripts/test-build.sh ${PACKAGE}"
echo "    3. Commit and push."
