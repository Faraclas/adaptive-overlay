# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..14} )

inherit distutils-r1

DESCRIPTION="Self-creating AI agent with constitution and persistent identity"
HOMEPAGE="
	https://ouroboros-agent.ai/
	https://github.com/razzant/ouroboros
"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/razzant/ouroboros.git"
else
	SRC_URI="https://github.com/razzant/ouroboros/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
fi

LICENSE="MIT"
SLOT="0"
# Upstream hermetic test suite expects a live Git repository checkout and runs
# inside the ouroboros-home container (scripts/ouroboros-home.sh test).
RESTRICT="test"

RDEPEND="
	app-benchmarks/hyperfine
	app-misc/jq
	app-shells/fzf
	dev-libs/nspr
	dev-libs/nss
	dev-python/uv
	dev-util/ast-grep
	dev-util/difftastic
	dev-util/github-cli
	dev-vcs/git
	media-libs/alsa-lib
	net-libs/nodejs
	sys-apps/eza
	sys-apps/fd
	sys-apps/ripgrep
	sys-apps/ripgrep-all
	dev-python/croniter[${PYTHON_USEDEP}]
	dev-python/ddgs[${PYTHON_USEDEP}]
	dev-python/dulwich[${PYTHON_USEDEP}]
	>=dev-python/httptools-0.8.0[${PYTHON_USEDEP}]
	dev-python/httpx2[${PYTHON_USEDEP}]
	>=dev-python/jsonschema-4.0[${PYTHON_USEDEP}]
	>=dev-python/mcp-1.29[${PYTHON_USEDEP}]
	>=dev-python/openai-1.66.0[${PYTHON_USEDEP}]
	>=dev-python/pillow-10.0[${PYTHON_USEDEP}]
	dev-python/pip[${PYTHON_USEDEP}]
	>=dev-python/pypdf-7.0[${PYTHON_USEDEP}]
	>=dev-python/pytest-7.0[${PYTHON_USEDEP}]
	>=dev-python/pytest-timeout-2.1[${PYTHON_USEDEP}]
	>=dev-python/pytest-xdist-3.5[${PYTHON_USEDEP}]
	>=dev-python/python-dotenv-0.13[${PYTHON_USEDEP}]
	dev-python/python-multipart[${PYTHON_USEDEP}]
	>=dev-python/pyyaml-6.0[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	dev-python/socksio[${PYTHON_USEDEP}]
	dev-python/starlette[${PYTHON_USEDEP}]
	>=dev-python/tree-sitter-0.23.2[${PYTHON_USEDEP}]
	>=dev-python/tree-sitter-language-pack-0.9.1[${PYTHON_USEDEP}]
	>=dev-python/typing-extensions-4.5.0[${PYTHON_USEDEP}]
	dev-python/tzdata[${PYTHON_USEDEP}]
	>=dev-python/uvicorn-0.30[${PYTHON_USEDEP}]
	>=dev-python/uvloop-0.15.1[${PYTHON_USEDEP}]
	>=dev-python/watchfiles-0.20[${PYTHON_USEDEP}]
	dev-python/websockets[${PYTHON_USEDEP}]
"
DEPEND="${RDEPEND}"

src_prepare() {
	# 1. Strip unused lazy-only gigachat and huggingface_hub dependencies.
	# 2. Relax mcp and tree-sitter upper bounds for adaptive-overlay/::gentoo.
	sed -i \
		-e '/"gigachat>=/d' \
		-e '/"huggingface_hub",/d' \
		-e 's/"mcp>=1.10,<2.0"/"mcp>=1.10"/' \
		-e 's/"tree-sitter>=0.23.2,<0.25"/"tree-sitter>=0.23.2"/' \
		pyproject.toml || die

	distutils-r1_src_prepare
}

src_install() {
	distutils-r1_src_install

	# Install a clean baseline seed copy so containers/ouroboros-home can
	# bootstrap the mutable brain repository on first start.
	insinto /usr/share/ouroboros/seed
	doins -r \
		BIBLE.md \
		README.md \
		VERSION \
		pyproject.toml \
		uv.lock \
		launcher.py \
		server.py \
		devtools \
		docs \
		ouroboros \
		prompts \
		scripts \
		skills \
		supervisor \
		tests \
		web
}

pkg_postinst() {
	elog " "
	elog "===== Ouroboros Habitat Notice ====="
	elog "  Ouroboros is a self-modifying autonomous agent that edits its own"
	elog "  source tree and commits to Git. Run it inside the persistent"
	elog "  ouroboros-home Podman container (scripts/ouroboros-home.sh) with"
	elog "  OUROBOROS_REPO_DIR mounted at /home/agent/ouroboros rather than"
	elog "  directly on the host workstation."
}
