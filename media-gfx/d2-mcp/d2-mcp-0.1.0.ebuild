# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	android_system_properties@0.1.5
	anyhow@1.0.103
	async-trait@0.1.89
	autocfg@1.5.1
	base64@0.22.1
	bitflags@2.13.0
	block-buffer@0.10.4
	bumpalo@3.20.3
	bytes@1.12.0
	cc@1.2.65
	cfg-if@1.0.4
	chrono@0.4.45
	core-foundation-sys@0.8.7
	cpufeatures@0.2.17
	crypto-common@0.1.7
	darling@0.23.0
	darling_core@0.23.0
	darling_macro@0.23.0
	digest@0.10.7
	dyn-clone@1.0.20
	errno@0.3.14
	fastrand@2.4.1
	find-msvc-tools@0.1.9
	futures@0.3.32
	futures-channel@0.3.32
	futures-core@0.3.32
	futures-executor@0.3.32
	futures-io@0.3.32
	futures-macro@0.3.32
	futures-sink@0.3.32
	futures-task@0.3.32
	futures-util@0.3.32
	generic-array@0.14.7
	getrandom@0.4.3
	iana-time-zone@0.1.65
	iana-time-zone-haiku@0.1.2
	ident_case@1.0.1
	itoa@1.0.18
	js-sys@0.3.103
	libc@0.2.186
	linux-raw-sys@0.12.1
	log@0.4.33
	memchr@2.8.2
	num-traits@0.2.19
	once_cell@1.21.4
	pastey@0.2.3
	pin-project-lite@0.2.17
	proc-macro2@1.0.106
	quote@1.0.46
	r-efi@6.0.0
	ref-cast@1.0.25
	ref-cast-impl@1.0.25
	rmcp@1.8.0
	rmcp-macros@1.8.0
	rustix@1.1.4
	rustversion@1.0.22
	schemars@1.2.1
	schemars_derive@1.2.1
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_derive_internals@0.29.1
	serde_json@1.0.150
	sha2@0.10.9
	shlex@2.0.1
	slab@0.4.12
	strsim@0.11.1
	syn@2.0.118
	tempfile@3.27.0
	thiserror@2.0.18
	thiserror-impl@2.0.18
	tokio@1.52.3
	tokio-macros@2.7.0
	tokio-stream@0.1.18
	tokio-util@0.7.18
	tracing@0.1.44
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	typenum@1.20.1
	unicode-ident@1.0.24
	version_check@0.9.5
	wait-timeout@0.2.1
	wasm-bindgen@0.2.126
	wasm-bindgen-macro@0.2.126
	wasm-bindgen-macro-support@0.2.126
	wasm-bindgen-shared@0.2.126
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.61.2
	zmij@1.0.21
"

# Conservative upstream CI baseline, not a claim of the lowest possible MSRV.
RUST_MIN_VER="1.93.1"

inherit cargo

DESCRIPTION="Stdio MCP server for D2 diagram validation, formatting, and rendering"
HOMEPAGE="https://github.com/Stranmor/d2-mcp-rs"
SRC_URI="
	https://github.com/Stranmor/d2-mcp-rs/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/d2-mcp-rs-${PV}"

LICENSE="MIT"
# Choose MIT for dual-licensed crates; include embedded code/data licenses.
LICENSE+=" Apache-2.0 BSD-2 CC0-1.0 Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND=">=media-gfx/d2-0.9.0"

DOCS=( README.md CHANGELOG.md LICENSE docs/client-configs.md docs/tools.md )

src_configure() {
	cargo_src_configure --frozen
}

src_test() {
	# The integration test silently skips without D2. Exercise it explicitly
	# after installation with verify-d2-mcp.sh instead of adding a build dep.
	cargo_src_test --lib
}

src_install() {
	cargo_src_install
	einstalldocs

	# Keep each crate's notices, including nested licenses, without collisions.
	local notice relative
	find "${ECARGO_VENDOR}" -type f \( -iname '*license*' -o \
		-iname '*copying*' -o -iname '*copyright*' -o -iname '*notice*' \) \
		-print0 > "${T}/crate-notices" || die
	while IFS= read -r -d '' notice; do
		relative="${notice#"${ECARGO_VENDOR}/"}"
		docinto "licenses/${relative%/*}"
		dodoc "${notice}"
	done < "${T}/crate-notices"

	# rmcp's crate archives omit the repository license and copied http notice.
	docinto licenses/rmcp
	dodoc "${FILESDIR}/rmcp-1.8.0-LICENSE" \
		"${FILESDIR}/rmcp-1.8.0-http-LICENSE-MIT"
	docinto licenses
	dodoc "${FILESDIR}/${P}-embedded-notices.txt"
}
