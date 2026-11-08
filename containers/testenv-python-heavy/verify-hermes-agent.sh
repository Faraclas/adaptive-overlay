#!/bin/bash
# verify-hermes-agent.sh: check the app-ai/hermes-agent build image.
# Called by scripts/test-build.sh with the portage image directory, e.g.
#   /var/tmp/portage/app-ai/hermes-agent-0.23.0/image
set -u
IMAGE="${1:?usage: verify-hermes-agent.sh <build-image-dir>}"
PASS=0 FAIL=0
pass() { echo "  ok   $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $*" >&2; FAIL=$((FAIL + 1)); }

SITE=$(find "$IMAGE/usr/lib" -maxdepth 3 -type d -name site-packages | head -1)
echo "==> Verifying hermes-agent image: $IMAGE"
echo "    site-packages: ${SITE:-<not found>}"
[ -n "$SITE" ] || { echo "no site-packages in image" >&2; exit 1; }
CU="$SITE/tools/computer_use"

echo "--- Patched sources ---"
check() { # file, fixed-string, label
    if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3"; fi
}
if [ -f "$SITE/pm/extras.py" ]; then
    check "$SITE/hermes_cli/install-stamp.json" '"updateMechanism": "external"' \
        "install-stamp.json: external update mechanism (Portage steward)"
    check "$SITE/pm/extras.py" 'def available(extra: str) -> bool:' \
        "pm.extras: unpinned import-spec availability check"
else
    check "$SITE/tools/lazy_deps.py" "allow_lazy_installs" \
        "lazy_deps: pins-as-floors patch"
fi
check "$CU/cua_backend_session.py" 'name == "MCPError"' \
    "computer_use: MCPError(CONNECTION_CLOSED) reconnect"
check "$CU/tool.py" 'if action == "release":' \
    "computer_use: release action handler"
check "$CU/schema.py" '"release",' \
    "computer_use: release in the tool schema"
check "$CU/cua_backend_daemon.py" 'def ensure_alive' \
    "computer_use: private daemon revive on reconnect"
if [ -f "$SITE/hermes_cli/route_identity.py" ]; then
    check "$SITE/hermes_cli/route_identity.py" 'def is_claimed_root_route' \
        "route_identity: Copilot plan hosts are not relays"
fi

echo "--- TUI bundle ---"
TUI="$SITE/hermes_cli/tui_dist"
if [ -f "$TUI/entry.js" ]; then pass "tui_dist: entry.js"; else fail "tui_dist: entry.js"; fi
if grep -qF 'gateway_bootstrap.py' "$TUI/entry.js" 2>/dev/null; then
    # 0.22.5+: helpers resolved next to entry.js before ui-tui/scripts.
    for helper in gateway_bootstrap.py clipboard_image.py; do
        if [ -f "$TUI/scripts/$helper" ]; then
            pass "tui_dist: scripts/$helper"
        else
            fail "tui_dist: scripts/$helper"
        fi
    done
fi

echo "--- Imports (image on sys.path) ---"
if PYTHONPATH="$SITE" python3 -c '
import tools.computer_use.schema as s
assert "release" in s.COMPUTER_USE_SCHEMA["parameters"]["properties"]["action"]["enum"]
from tools.computer_use.cua_backend_session import _CuaDriverSession as S
from mcp.shared.exceptions import MCPError
from mcp.types import CONNECTION_CLOSED
assert S._is_closed_session_error(MCPError(code=CONNECTION_CLOSED, message="x"))
assert not S._is_closed_session_error(MCPError(code=-32602, message="x"))
' 2>&1; then
    pass "schema has release; CONNECTION_CLOSED is treated as closed"
else
    fail "import-level checks"
fi

COPILOT_PLUGIN="$SITE/plugins/model-providers/github-copilot"
if [ ! -f "$SITE/hermes_cli/copilot_auth.py" ]; then
    # 0.22.6+: Copilot left core; USE=copilot ships the github-copilot plugin.
    echo "--- Copilot plugin (bundled; synthetic credentials, no network) ---"
    if [[ " ${USE:-} " == *" -copilot "* ]]; then
        if [ ! -e "$COPILOT_PLUGIN" ]; then
            pass "copilot disabled: plugin not installed"
        else
            fail "copilot disabled but the plugin was installed"
        fi
    elif [ ! -f "$COPILOT_PLUGIN/__init__.py" ]; then
        fail "github-copilot plugin missing from plugins/model-providers"
    elif [ -e "$COPILOT_PLUGIN/tests" ]; then
        fail "github-copilot plugin tests were installed"
    elif env -i PATH="$PATH" PYTHONPATH="$SITE" HOME=/nonexistent-fixture/copilot \
        HERMES_HOME=/nonexistent-fixture/copilot python3 -c '
import sys
from pathlib import Path
from unittest.mock import patch
import providers
assert Path(providers.__file__).resolve().is_relative_to(Path(sys.argv[1]).resolve())
from providers import get_provider_profile
from agent.provider_route_hooks import route_answer
from hermes_cli import models
from hermes_cli.left_core_migration import plugin_present

for name in ("copilot", "copilot-acp"):
    assert get_provider_profile(name) is not None, name
assert plugin_present("github-copilot", Path("/nonexistent-fixture/copilot"))

host = "https://api.business.githubcopilot.com"
for key, integration in [("github_pat_fixture", "copilot-developer-cli"),
                         ("tid=exchanged", "vscode-chat")]:
    for images in (False, True):
        h = route_answer("client_headers", provider="copilot", base_url=host,
                         api_key=key, has_images=images)
        assert h["Copilot-Integration-Id"] == integration, (key, images)
        assert ("Copilot-Vision-Request" in h) is images

def cfg(base_url):
    return patch.object(models, "_get_model_config_dict",
                        return_value={"provider": "copilot", "base_url": base_url})
for url in (host, host + "/", "https://api.individual.githubcopilot.com"):
    with cfg(url):
        assert models._configured_relay_base_url("copilot") == "", url
for url in (host + "/v1", host + ":8443", "http://api.business.githubcopilot.com",
            "https://relay.example.com/v1"):
    with cfg(url):
        assert models._configured_relay_base_url("copilot") == url, url
' "$SITE" 2>&1; then
        pass "copilot plugin loads from the bundle; PAT integration id; plan host is native"
    else
        fail "Copilot plugin behavioral checks"
    fi
fi

echo "--- Headless Chrome service ---"
CHROME_UNIT="$IMAGE/usr/lib/systemd/user/hermes-chrome.service"
if [[ " ${USE:-} " == *" browser "* ]]; then
    if [ -f "$CHROME_UNIT" ]; then
        if grep -qxF 'Environment=DBUS_SESSION_BUS_ADDRESS=disabled:' "$CHROME_UNIT"; then
            pass "headless Chrome cannot activate the desktop session portals"
        else
            fail "headless Chrome session-bus isolation missing"
        fi
        check "$CHROME_UNIT" 'WantedBy=default.target' \
            "headless Chrome remains available before graphical login"
    else
        fail "browser enabled but headless Chrome service is missing"
    fi
    if [ ! -f "$SITE/hermes_cli/copilot_auth.py" ]; then
        # 0.22.6+: browser_exec (browser-harness) is the only browser tool.
        check "$IMAGE/etc/hermes/chromium-executable-path" \
            /usr/libexec/hermes-agent/hermes-agent-browser \
            "browser_exec launches the system Chrome wrapper"
        if [ ! -e "$IMAGE/etc/env.d/99hermes-agent-browser" ]; then
            pass "no agent-browser env.d entry"
        else
            fail "stale agent-browser env.d entry installed"
        fi
    fi
elif [ ! -e "$CHROME_UNIT" ]; then
    pass "browser disabled: headless Chrome service not installed"
else
    fail "browser disabled but headless Chrome service was installed"
fi

echo ""
echo "==> $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
