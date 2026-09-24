# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 systemd

DESCRIPTION="The agent that grows with you"
HOMEPAGE="https://github.com/NousResearch/hermes-agent"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/NousResearch/hermes-agent.git"
else
	SRC_URI="https://github.com/NousResearch/hermes-agent/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
fi

LICENSE="MIT"
SLOT="0"
IUSE="browser +dashboard discord +mcp +websearch"

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
	dev-python/python-multipart[${PYTHON_USEDEP}]
	dev-python/ptyprocess[${PYTHON_USEDEP}]
	dev-python/pillow[${PYTHON_USEDEP}]
	dev-python/aiohttp[${PYTHON_USEDEP}]
	dev-python/firecrawl-anydoc[${PYTHON_USEDEP}]
	net-libs/nodejs
	browser? (
		|| (
			www-client/google-chrome
			www-client/google-chrome-beta
			www-client/chromium
		)
	)
	mcp? (
		dev-python/mcp[${PYTHON_USEDEP}]
	)
	websearch? (
		dev-python/ddgs[${PYTHON_USEDEP}]
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

PATCHES=(
	"${FILESDIR}/hermes-agent-python314-daemonpool.patch"
)

hermes_agent_build_tui() {
	pushd ui-tui >/dev/null || die
	rm -rf dist || die
	npm_config_cache="${T}/.npm" npm install --engine-strict=false --ignore-scripts --no-audit --no-fund || die
	npm_config_cache="${T}/.npm" npm run build || die
	popd >/dev/null || die
}

hermes_agent_build_web() {
	pushd web >/dev/null || die
	rm -rf ../hermes_cli/web_dist || die
	npm_config_cache="${T}/.npm" npm install --engine-strict=false --ignore-scripts --no-audit --no-fund || die
	npm_config_cache="${T}/.npm" npm run build || die
	popd >/dev/null || die
}

src_prepare() {
	# Remove the <3.14 restriction since Gentoo builds transitive Rust deps from source
	sed -i -e 's/requires-python = ">=3.11,<3.14"/requires-python = ">=3.11"/' pyproject.toml || die
	export HERMES_NIX_BUILD=1
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

	python_moduleinto hermes_cli/tui_dist
	python_domodule ui-tui/dist/entry.js
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
		newenvd "${FILESDIR}/hermes-agent.env" "99hermes-agent-browser"
		exeinto /usr/libexec/hermes-agent
		doexe "${FILESDIR}/hermes-agent-browser"
	fi
	if use dashboard; then
		systemd_douserunit "${FILESDIR}/hermes-dashboard.service"
	fi
}

pkg_postinst() {
	elog "Gateway (messaging platforms, cron, kanban dispatcher):"
	elog "  systemd: Hermes manages its own gateway user unit. As your user, run"
	elog "    hermes gateway install"
	elog "  which writes ~/.config/systemd/user/hermes-gateway.service, then"
	elog "    systemctl --user enable --now hermes-gateway"
	elog "  OpenRC: a system service running as the hermesagent user is provided:"
	elog "    rc-update add hermesagent default && rc-service hermesagent start"
	elog "  After upgrading Hermes, restart it: hermes gateway restart"

	if use dashboard; then
		elog ""
		elog "Web dashboard (systemd user unit, binds to 127.0.0.1:9119):"
		elog "    systemctl --user enable --now hermes-dashboard"
		elog "  To keep it running without an active login:"
		elog "    loginctl enable-linger <user>"
		elog "  After upgrading Hermes: systemctl --user restart hermes-dashboard"
		elog "  Remote access: ssh -L 9119:127.0.0.1:9119 <user>@<host>, then open"
		elog "  http://localhost:9119. It is not exposed on the network by default."
	fi

	if use browser; then
		elog ""
		elog "Browser tools: AGENT_BROWSER_EXECUTABLE_PATH is set via env.d."
		elog "Run '. /etc/profile' or start a new login shell to pick it up."
	fi
}
