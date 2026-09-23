# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
DISTUTILS_USE_PEP517=hatchling

inherit pypi distutils-r1

DESCRIPTION="Model Context Protocol Python SDK"
HOMEPAGE="
	https://modelcontextprotocol.io
	https://github.com/modelcontextprotocol/python-sdk
	https://pypi.org/project/mcp/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="test"

# The v2 SDK uses a split-out wire-types package and httpx2.
BDEPEND="
	dev-python/uv-dynamic-versioning[${PYTHON_USEDEP}]
"

RDEPEND="
	>=dev-python/anyio-4.10.0[${PYTHON_USEDEP}]
	>=dev-python/httpx2-2.5.0[${PYTHON_USEDEP}]
	>=dev-python/jsonschema-4.20.0[${PYTHON_USEDEP}]
	~dev-python/mcp-types-2.0.0[${PYTHON_USEDEP}]
	>=dev-python/opentelemetry-api-1.28.0[${PYTHON_USEDEP}]
	>=dev-python/pydantic-2.12.0[${PYTHON_USEDEP}]
	dev-python/cryptography[${PYTHON_USEDEP}]
	>=dev-python/pyjwt-2.10.1[${PYTHON_USEDEP}]
	>=dev-python/python-multipart-0.0.9[${PYTHON_USEDEP}]
	>=dev-python/sse-starlette-3.0.0[${PYTHON_USEDEP}]
	>=dev-python/starlette-1.3.1[${PYTHON_USEDEP}]
	>=dev-python/typing-extensions-4.13.0[${PYTHON_USEDEP}]
	>=dev-python/typing-inspection-0.4.1[${PYTHON_USEDEP}]
	>=dev-python/uvicorn-0.31.1[${PYTHON_USEDEP}]
"
