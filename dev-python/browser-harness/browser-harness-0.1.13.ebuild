# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..15} )

inherit distutils-r1 pypi

DESCRIPTION="Thin CDP harness that lets an agent drive a real browser"
HOMEPAGE="
	https://github.com/browser-use/browser-harness
	https://pypi.org/project/browser-harness/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/cdp-use[${PYTHON_USEDEP}]
	dev-python/fetch-use[${PYTHON_USEDEP}]
	dev-python/pillow[${PYTHON_USEDEP}]
	dev-python/websockets[${PYTHON_USEDEP}]
"

src_prepare() {
	# The MCP server is a top-level "mcp_server" module in site-packages and
	# needs the optional mcp extra; Hermes drives the harness directly.
	sed -i \
		-e '/^py-modules = \["mcp_server"\]$/d' \
		-e '/^browser-harness-mcp = /d' \
		pyproject.toml || die
	rm src/mcp_server.py src/browser_harness/mcp_cli.py || die
	distutils-r1_src_prepare
}
