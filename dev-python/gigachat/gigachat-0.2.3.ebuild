# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 pypi

DESCRIPTION="GigaChat Python library for the GigaChat API"
HOMEPAGE="
	https://github.com/ai-forever/gigachat
	https://pypi.org/project/gigachat/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	>=dev-python/httpx-0.24[${PYTHON_USEDEP}]
	>=dev-python/pydantic-2.0[${PYTHON_USEDEP}]
	>=dev-python/pydantic-settings-2.0[${PYTHON_USEDEP}]
"

# Upstream tests require dev-only vcrpy/pytest-recording/pytest-httpx.
RESTRICT="test"
