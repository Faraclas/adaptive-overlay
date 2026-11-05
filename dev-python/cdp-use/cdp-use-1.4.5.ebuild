# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{11..15} )

inherit distutils-r1 pypi

DESCRIPTION="Type-safe client library for the Chrome DevTools Protocol"
HOMEPAGE="
	https://github.com/browser-use/cdp-use
	https://pypi.org/project/cdp-use/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# pyproject also lists httpx, which cdp_use never imports (and which
# ::gentoo deprecates); it is left out.
RDEPEND="
	dev-python/typing-extensions[${PYTHON_USEDEP}]
	dev-python/websockets[${PYTHON_USEDEP}]
"
