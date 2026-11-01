# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..15} )

inherit distutils-r1 pypi

DESCRIPTION="Comprehensive collection of 160+ tree-sitter language parsers"
HOMEPAGE="
	https://github.com/Goldziher/tree-sitter-language-pack
	https://pypi.org/project/tree-sitter-language-pack/
"

LICENSE="Apache-2.0 MIT"
SLOT="0"
KEYWORDS="~amd64"
# Upstream test suite requires gitpython and network-fetched vendor fixtures.
RESTRICT="test"

RDEPEND="
	>=dev-python/tree-sitter-0.23.2[${PYTHON_USEDEP}]
	>=dev-python/typing-extensions-4.15.0[${PYTHON_USEDEP}]
"
BDEPEND="
	>=dev-python/cython-3.0.12[${PYTHON_USEDEP}]
"

src_prepare() {
	# Relax exact tree-sitter pin for ::gentoo's dev-python/tree-sitter and
	# drop the 3 external language subpackages from unconditional metadata.
	sed -i \
		-e 's/"tree-sitter==0.23.2",/"tree-sitter>=0.23.2",/' \
		-e '/"tree-sitter-c-sharp==/d' \
		-e '/"tree-sitter-embedded-template==/d' \
		-e '/"tree-sitter-yaml==/d' \
		pyproject.toml || die

	sed -i \
		-e '/^import tree_sitter_c_sharp$/d' \
		-e '/^import tree_sitter_embedded_template$/d' \
		-e '/^import tree_sitter_yaml$/d' \
		-e 's/tree_sitter_yaml\.language()/import_module("tree_sitter_yaml").language()/' \
		-e 's/tree_sitter_c_sharp\.language()/import_module("tree_sitter_c_sharp").language()/' \
		-e 's/tree_sitter_embedded_template\.language()/import_module("tree_sitter_embedded_template").language()/' \
		tree_sitter_language_pack/__init__.py || die

	distutils-r1_src_prepare
}
