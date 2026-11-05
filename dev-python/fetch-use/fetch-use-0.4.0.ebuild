# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{11..15} )

inherit distutils-r1 pypi

DESCRIPTION="Python client for the Browser Use Fetch HTTP service"
HOMEPAGE="
	https://browser-use.com
	https://pypi.org/project/fetch-use/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
