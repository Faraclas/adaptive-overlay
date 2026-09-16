# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..15} )
PYPI_PN="discord.py"

inherit distutils-r1 pypi

DESCRIPTION="A Python wrapper for the Discord API"
HOMEPAGE="
	https://github.com/Rapptz/discord.py
	https://pypi.org/project/discord.py/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="voice"

RDEPEND="
	>=dev-python/aiohttp-3.7.4[${PYTHON_USEDEP}]
	$(python_gen_cond_dep '
		dev-python/audioop-lts[${PYTHON_USEDEP}]
	' 3.13 3.14 3.15)
	voice? (
		>=dev-python/pynacl-1.5.0[${PYTHON_USEDEP}]
	)
"

EPYTEST_PLUGINS=( pytest-asyncio )
distutils_enable_tests pytest
