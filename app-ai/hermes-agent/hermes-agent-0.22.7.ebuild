# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 systemd

DESCRIPTION="The agent that grows with you"
HOMEPAGE="https://github.com/NousResearch/hermes-agent"

# Tag v0.22.7 commit for install-stamp.json provenance
HERMES_COMMIT="b200f5bc60e31588ba2cb60e288029c4a54ba5fa"
# github-copilot plugin (Copilot left core in 0.22.6): the sha the core's
# plugin-catalog/github-copilot.yaml pins. Bump together with that file.
HERMES_COPILOT_COMMIT="346cfe972f72b6a966e84c1004cf8742554b193d"
HERMES_COPILOT_S="${WORKDIR}/hermes-labs-plugins-${HERMES_COPILOT_COMMIT}/github-copilot"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/NousResearch/hermes-agent.git"
else
	SRC_URI="https://github.com/NousResearch/hermes-agent/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
fi
SRC_URI+="
	copilot? (
		https://github.com/NousResearch/hermes-labs-plugins/archive/${HERMES_COPILOT_COMMIT}.tar.gz
			-> hermes-labs-plugins-${HERMES_COPILOT_COMMIT}.tar.gz
	)
"

LICENSE="MIT"
SLOT="0"
IUSE="browser computer-use +copilot +dashboard discord +mcp +websearch"
# Chrome and Chromium providers are glibc-only. The elibc_glibc guard in
# RDEPEND is also needed: pkgcheck does not apply REQUIRED_USE elibc logic
# when solving deps on musl profiles.
REQUIRED_USE="
	browser? ( elibc_glibc )
	computer-use? ( mcp )
"

# Need network for npm install
RESTRICT="network-sandbox !test? ( test )"

RDEPEND="
	acct-group/hermesagent
	acct-user/hermesagent
	sys-apps/ripgrep
	dev-python/openai[${PYTHON_USEDEP}]
	dev-python/python-dotenv[${PYTHON_USEDEP}]
	dev-python/rich[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/ruamel-yaml[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/tenacity[${PYTHON_USEDEP}]
	dev-python/tomli-w[${PYTHON_USEDEP}]
	dev-python/truststore[${PYTHON_USEDEP}]
	dev-python/fire[${PYTHON_USEDEP}]
	dev-python/prompt-toolkit[${PYTHON_USEDEP}]
	dev-python/certifi[${PYTHON_USEDEP}]
	dev-python/httpx2[${PYTHON_USEDEP}]
	dev-python/pydantic[${PYTHON_USEDEP}]
	dev-python/croniter[${PYTHON_USEDEP}]
	dev-python/snowballstemmer[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	dev-python/markdown[${PYTHON_USEDEP}]
	dev-python/pyjwt[${PYTHON_USEDEP}]
	dev-python/urllib3[${PYTHON_USEDEP}]
	dev-python/cryptography[${PYTHON_USEDEP}]
	dev-python/psutil[${PYTHON_USEDEP}]
	dev-python/websockets[${PYTHON_USEDEP}]
	dev-python/pathspec[${PYTHON_USEDEP}]
	dev-python/fastapi[${PYTHON_USEDEP}]
	dev-python/uvicorn[${PYTHON_USEDEP}]
	dev-python/httptools[${PYTHON_USEDEP}]
	dev-python/watchfiles[${PYTHON_USEDEP}]
	dev-python/python-multipart[${PYTHON_USEDEP}]
	dev-python/ptyprocess[${PYTHON_USEDEP}]
	dev-python/pillow[${PYTHON_USEDEP}]
	dev-python/aiohttp[${PYTHON_USEDEP}]
	dev-python/firecrawl-anydoc[${PYTHON_USEDEP}]
	net-libs/nodejs
	browser? ( dev-python/browser-harness[${PYTHON_USEDEP}] )
	elibc_glibc? (
		browser? (
			|| (
				www-client/google-chrome
				www-client/google-chrome-beta
				www-client/chromium
			)
		)
	)
	mcp? (
		dev-python/mcp[${PYTHON_USEDEP}]
	)
	websearch? (
		dev-python/ddgs[${PYTHON_USEDEP}]
	)
	computer-use? (
		x11-misc/cua-driver
		dev-python/starlette[${PYTHON_USEDEP}]
	)
	discord? (
		dev-python/discord-py[${PYTHON_USEDEP}]
	)
"
DEPEND="${RDEPEND}"
BDEPEND="
	net-libs/nodejs[npm]
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

hermes_agent_prepare_node_deps() {
	if [[ -d node_modules ]]; then
		return
	fi
	local workspaces=(
		--workspace apps/shared
		--workspace ui-tui
		--workspace ui-tui/packages/hermes-ink
	)
	if use dashboard; then
		workspaces+=( --workspace web )
	fi
	npm_config_cache="${T}/.npm" npm ci \
		--engine-strict=false \
		--ignore-scripts \
		--no-audit \
		--no-fund \
		--include=dev \
		--include=optional \
		--include-workspace-root=true \
		"${workspaces[@]}" || die
}

hermes_agent_build_tui() {
	hermes_agent_prepare_node_deps
	rm -rf ui-tui/dist || die
	node scripts/build/tui.mjs || die
}

hermes_agent_build_web() {
	hermes_agent_prepare_node_deps
	rm -rf hermes_cli/web_dist || die
	node scripts/build/web.mjs || die
}

PATCHES=(
	# computer_use: reconnect after mcp 2.x MCPError(CONNECTION_CLOSED) (a dead
	# cua-driver otherwise breaks every later call until restart), and add
	# action="release" to end this session's desktop connection cleanly, and
	# revive a dead private (yolo/bounded) cua-driver daemon on reconnect.
	"${FILESDIR}/${PN}-0.22.2-computer-use-release-reconnect.patch"
	# Find install-stamp.json in hermes_cli/, where python_install puts it.
	"${FILESDIR}/${PN}-0.22.5-install-stamp-path.patch"
	# Live catalog for a plan host (api.business.githubcopilot.com) in
	# model.base_url instead of the static fallback list.
	"${FILESDIR}/${PN}-0.22.7-copilot-plan-host-catalog.patch"
	# The bundled github-copilot plugin counts as installed: no "Copilot is
	# off" notice and no catalog fetch of a second copy on every start.
	"${FILESDIR}/${PN}-0.22.7-bundled-left-core-plugin.patch"
)

src_prepare() {
	sed -i -e "s/version = \"0.0.0\"/version = \"${PV}\"/" pyproject.toml || die
	export HERMES_NIX_BUILD=1

	if use copilot; then
		pushd "${HERMES_COPILOT_S}" >/dev/null || die
		# A fine-grained PAT needs the copilot-developer-cli integration id.
		eapply "${FILESDIR}/${PN}-copilot-plugin-pat-integration-id.patch"
		popd >/dev/null || die
	fi

	cat >> hermes_bootstrap.py <<- 'EOF' || die

	# Gentoo Portage defaults: use system binaries without requiring env.d reload
	if "PYTEST_CURRENT_TEST" not in os.environ and "pytest" not in sys.modules:
	    if os.path.isfile("/usr/bin/node"):
	        os.environ.setdefault("HERMES_NODE", "/usr/bin/node")
	    if os.path.isfile("/usr/bin/cua-driver"):
	        os.environ.setdefault("HERMES_CUA_DRIVER_CMD", "/usr/bin/cua-driver")
	EOF

	cat > "${T}/install-stamp.json" <<- EOF || die
	{
	  "schemaVersion": 2,
	  "commit": "${HERMES_COMMIT}",
	  "commitDate": null,
	  "branch": null,
	  "builtAt": null,
	  "dirty": false,
	  "source": "build",
	  "distribution": "portage",
	  "updateMechanism": "external",
	  "baseVersion": "${PV}",
	  "displayVersion": "${PV}",
	  "distance": 0,
	  "payload": "bootstrap",
	  "tag": "v${PV}"
	}
	EOF

	distutils-r1_src_prepare
}

src_compile() {
	distutils-r1_src_compile

	hermes_agent_build_tui
	if use dashboard; then
		hermes_agent_build_web
	fi
}

python_test() {
	hermes_agent_build_tui
	if use dashboard; then
		hermes_agent_build_web
	fi
	epytest
}

python_install() {
	distutils-r1_python_install

	python_domodule skills optional-skills plugins locales optional-mcps

	if use copilot; then
		# Next to core's own providers, where provider discovery loads it for
		# every profile; not in ${S}, whose tests expect no bundled Copilot.
		python_moduleinto plugins/model-providers/github-copilot
		python_domodule "${HERMES_COPILOT_S}"/{__init__.py,plugin.yaml,copilot,copilot_acp}
	fi

	python_moduleinto hermes_cli
	python_domodule "${T}/install-stamp.json"

	printf '{"type":"module"}\n' > ui-tui/dist/package.json || die
	# dist/ holds entry.js plus scripts/*.py helpers that the TUI resolves
	# next to entry.js (gateway bootstrap, clipboard images).
	python_moduleinto hermes_cli/tui_dist
	python_domodule ui-tui/dist/*
	if use dashboard; then
		python_moduleinto hermes_cli/web_dist
		python_domodule hermes_cli/web_dist/*
	fi
}

src_install() {
	distutils-r1_src_install
	newconfd "${FILESDIR}/hermesagent.confd" "hermesagent"
	newinitd "${FILESDIR}/hermesagent.initd" "hermesagent"
	if use browser; then
		exeinto /usr/libexec/hermes-agent
		doexe "${FILESDIR}/hermes-agent-browser"
		# browser_exec launches this Chromium when no CDP endpoint is set
		# (read by hermes_cli/browser_runtime.py, else it wants pm's own).
		insinto /etc/hermes
		echo /usr/libexec/hermes-agent/hermes-agent-browser \
			| newins - chromium-executable-path
		systemd_douserunit "${FILESDIR}/hermes-chrome.service"
	fi
	if use dashboard; then
		systemd_douserunit "${FILESDIR}/hermes-dashboard.service"
	fi
}

pkg_postinst() {
	elog " "
	elog "===== Hermes: config for Portage installs (do once, as your user) ====="
	elog "  Hermes cannot pip-install optional deps into a Portage install;"
	elog "  make missing features fail fast instead:"
	elog "    1. hermes config set security.allow_lazy_installs false"
	if use copilot; then
		elog "  GitHub Copilot (left Hermes core in 0.22.6) ships as the bundled"
		elog "  github-copilot plugin; it loads without plugins.enabled. Do not run"
		elog "  'hermes plugins install github-copilot'."
	fi

	elog " "
	elog "===== Hermes gateway (messaging, cron, kanban dispatcher) ====="
	elog "  systemd (as your user):"
	elog "    1. hermes gateway install"
	elog "    2. systemctl --user enable --now hermes-gateway"
	elog "  OpenRC (system service, runs as user hermesagent):"
	elog "    1. rc-update add hermesagent default"
	elog "    2. rc-service hermesagent start"
	elog "  After every Hermes upgrade: hermes gateway restart"

	if use dashboard; then
		elog " "
		elog "===== Hermes web dashboard (127.0.0.1:9119, not on the network) ====="
		elog "  Enable (as your user):"
		elog "    1. systemctl --user enable --now hermes-dashboard"
		elog "  Optional, keep running while logged out:"
		elog "    loginctl enable-linger <user>"
		elog "  Remote access: ssh -L 9119:127.0.0.1:9119 <user>@<host>"
		elog "    then open http://localhost:9119"
		elog "  After every Hermes upgrade: systemctl --user restart hermes-dashboard"
	fi

	if use browser; then
		elog " "
		elog "===== Hermes browser tools ====="
		elog "  browser_exec (dev-python/browser-harness) drives your system Chrome"
		elog "  (prefers google-chrome-beta, then -stable, then google-chrome, then"
		elog "  chromium; see /etc/hermes/chromium-executable-path). From 0.22.6 the"
		elog "  built-in browser_* tools and agent-browser are gone; config migration"
		elog "  52 drops browser.backend."
		elog "  Optional, persistent headless Chrome shared by all sessions"
		elog "  (CDP on 127.0.0.1:9222, profile ~/.hermes/chrome-debug), as your user:"
		elog "    1. systemctl --user enable --now hermes-chrome"
		elog "    2. hermes config set browser.cdp_url http://127.0.0.1:9222"
		elog "    3. hermes gateway restart"
		elog "  Undo: systemctl --user disable --now hermes-chrome"
		elog "        hermes config set browser.cdp_url ''"
		elog "  Warning: any local program can drive that browser through the"
		elog "  port. Never put real passwords into its profile."
	fi

	if use computer-use; then
		elog " "
		elog "===== Hermes computer use ====="
		elog "  Setup (as your user, on Wayland):"
		elog "    1. hermes config set computer_use.native_wayland true"
		elog "  GNOME also needs the WinRects extension (x11-misc/cua-driver[gnome])"
		elog "  and accessibility enabled; see the cua-driver postinst messages."
	fi
}
