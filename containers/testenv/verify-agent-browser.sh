#!/bin/bash
# verify-agent-browser.sh: verify the dev-util/agent-browser build output.
#
# Called by scripts/test-build.sh (and CI) with the portage build image dir,
# e.g. /var/tmp/portage/dev-util/agent-browser-0.26.0/image
#
# Checks:
#   1. /usr/bin/agent-browser exists and is executable
#   2. --version reports the ebuild version
#   3. ldd shows no missing libraries
#   4. The portage-managed patch is active (upgrade refuses, no network)
#   5. Skill data and the env.d file are installed and consistent
#   6. The binary can launch a headless browser if one exists in the image

set -euo pipefail
# shellcheck disable=SC2015  # pass() always returns 0

BUILD_IMAGE="${1:-}"
if [ -z "${BUILD_IMAGE}" ] || [ ! -d "${BUILD_IMAGE}" ]; then
    echo "Usage: $(basename "$0") <build-image-dir>" >&2
    exit 1
fi

PASS=0
FAIL=0
pass() { echo "  ok   $*"; (( PASS++ )) || true; }
fail() { echo "  FAIL $*" >&2; (( FAIL++ )) || true; }

PVR="$(basename "$(dirname "${BUILD_IMAGE}")")"
PVR="${PVR#agent-browser-}"
PV="${PVR%-r[0-9]*}"
BIN="${BUILD_IMAGE}/usr/bin/agent-browser"

echo "==> Verifying agent-browser ${PV} image: ${BUILD_IMAGE}"

[ -x "${BIN}" ] && pass "usr/bin/agent-browser is executable" || fail "usr/bin/agent-browser missing"

ver="$("${BIN}" --version 2>&1 || true)"
[ "${ver}" = "agent-browser ${PV}" ] && pass "--version: ${ver}" || fail "--version: '${ver}' (want 'agent-browser ${PV}')"

if ldd "${BIN}" 2>&1 | grep -q "not found"; then
    fail "ldd: missing libraries"; ldd "${BIN}" | grep "not found" >&2
else
    pass "ldd: all libraries resolve"
fi

# The patched check keys off /usr/bin, so run the image binary via a copy at
# the real path only if nothing is installed there; otherwise check the text.
if grep -aq "managed by your system package manager" "${BIN}"; then
    pass "portage-managed upgrade guard compiled in"
else
    fail "portage-managed upgrade guard missing (patch not applied?)"
fi
if [ ! -e /usr/bin/agent-browser ]; then
    cp "${BIN}" /usr/bin/agent-browser
    out="$(timeout 20 /usr/bin/agent-browser upgrade 2>&1 || true)"
    rm -f /usr/bin/agent-browser
    echo "${out}" | grep -q "managed by your system package manager" \
        && pass "upgrade refuses when run from /usr/bin" \
        || fail "upgrade did not refuse: ${out}"
fi

SK="${BUILD_IMAGE}/usr/share/agent-browser"
[ -f "${SK}/skill-data/core/SKILL.md" ] && pass "skill-data/core installed" || fail "skill-data/core/SKILL.md missing"
ENVD="$(ls "${BUILD_IMAGE}"/etc/env.d/*agent-browser 2>/dev/null | head -1)"
if [ -n "${ENVD}" ] && grep -q 'AGENT_BROWSER_SKILLS_DIR="/usr/share/agent-browser/skill-data"' "${ENVD}"; then
    pass "env.d sets AGENT_BROWSER_SKILLS_DIR"
else
    fail "env.d AGENT_BROWSER_SKILLS_DIR missing or wrong"
fi
out="$(AGENT_BROWSER_SKILLS_DIR="${SK}/skill-data" "${BIN}" skills list 2>&1 || true)"
echo "${out}" | grep -q "core" && pass "skills list finds core" || fail "skills list: ${out:0:200}"

CHROME=""
for c in /usr/bin/chromium /usr/bin/google-chrome-stable /usr/bin/google-chrome; do
    [ -x "$c" ] && { CHROME=$c; break; }
done
if [ -n "${CHROME}" ]; then
    HOME="$(mktemp -d)"
    export AGENT_BROWSER_EXECUTABLE_PATH="${CHROME}" HOME
    t="$(mktemp -d)"; printf '<html><head><title>verify-ok</title></head><body><h1>hello</h1></body></html>' > "$t/index.html"
    if timeout 60 "${BIN}" --session verify open "file://$t/index.html" >/dev/null 2>&1 \
       && timeout 30 "${BIN}" --session verify get title 2>&1 | grep -q verify-ok; then
        pass "launched ${CHROME} headless and read the page title"
    else
        fail "could not drive ${CHROME}"
    fi
    timeout 20 "${BIN}" --session verify close >/dev/null 2>&1 || true
else
    echo "  skip live browser test (no Chrome/Chromium in the image)"
fi

echo "==> ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
