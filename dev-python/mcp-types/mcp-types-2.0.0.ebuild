# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=standalone
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1

DESCRIPTION="Model Context Protocol wire types"
HOMEPAGE="
	https://modelcontextprotocol.io
	https://github.com/modelcontextprotocol/python-sdk
	https://pypi.org/project/mcp-types/
"
SRC_URI="https://files.pythonhosted.org/packages/f5/4c/c78d78c3d52b0ac594ad7cc8ef5972adfe070e3597a8a4c6ce0cd39196ea/mcp_types-${PV}-py3-none-any.whl"
S="${WORKDIR}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror strip test"

# The source distribution uses VCS-derived dynamic versioning; install the
# pure-Python wheel published for this exact version instead.
RDEPEND="
	>=dev-python/pydantic-2.12.0[${PYTHON_USEDEP}]
	>=dev-python/typing-extensions-4.13.0[${PYTHON_USEDEP}]
"

src_unpack() {
	:
}

src_compile() {
	:
}

python_install() {
	distutils_wheel_install "${ED}" "${DISTDIR}/mcp_types-${PV}-py3-none-any.whl"
}
