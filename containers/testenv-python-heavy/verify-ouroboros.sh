#!/bin/bash
# verify-ouroboros.sh: check the app-ai/ouroboros build image.
# Called by scripts/test-build.sh with the portage image directory, e.g.
#   /var/tmp/portage/app-ai/ouroboros-7.9.0/image
set -u
IMAGE="${1:?usage: verify-ouroboros.sh <build-image-dir>}"
PASS=0 FAIL=0
pass() { echo "  ok   $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $*" >&2; FAIL=$((FAIL + 1)); }

SITE=$(find "$IMAGE/usr/lib" -maxdepth 3 -type d -name site-packages | head -1)
echo "==> Verifying ouroboros image: $IMAGE"
echo "    site-packages: ${SITE:-<not found>}"
[ -n "$SITE" ] || { echo "no site-packages in image" >&2; exit 1; }

echo "--- Installed modules and seed ---"
for path in \
    "$SITE/ouroboros/__init__.py" \
    "$SITE/supervisor/__init__.py" \
    "$SITE/server.py" \
    "$IMAGE/usr/bin/ouroboros" \
    "$IMAGE/usr/bin/ouroboros-web" \
    "$IMAGE/usr/share/ouroboros/seed/BIBLE.md" \
    "$IMAGE/usr/share/ouroboros/seed/server.py" \
    "$IMAGE/usr/share/ouroboros/seed/ouroboros/preflight_runner.py"
do
    if [ -e "$path" ] || [ -L "$path" ]; then
        pass "${path#"$IMAGE"}"
    else
        fail "${path#"$IMAGE"} missing"
    fi
done

echo "--- Runtime imports and tree-sitter integration ---"
if PYTHONPATH="$SITE" python3 -c '
import ouroboros.cli as cli
import ouroboros.code_intelligence as ci
import ouroboros.markdown_source as ms
import ouroboros.mcp_client as mcp_client
import tree_sitter_language_pack as tslp

assert tslp.get_parser("python") is not None
assert tslp.get_parser("markdown") is not None
assert ci._ts_parser("python") is not None
assert ms._markdown_parser("markdown", "BIBLE.md") is not None
assert hasattr(mcp_client, "_MCP_SDK_AVAILABLE")
' 2>&1; then
    pass "ouroboros imports and tree-sitter parser integration"
else
    fail "ouroboros import or dependency integration checks"
fi

echo ""
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
