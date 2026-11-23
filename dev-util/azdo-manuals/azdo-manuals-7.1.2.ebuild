# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

RUST_MIN_VER="1.91.0"

CRATES="
	adler2@2.0.1
	aho-corasick@1.1.5
	android_system_properties@0.1.6
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	autocfg@1.5.1
	base64@0.23.1
	bitflags@2.13.2
	block-buffer@0.12.1
	bumpalo@3.20.4
	bytes@1.12.2
	cc@1.11.3
	cfg-if@1.0.5
	chrono@0.4.45
	clap@4.6.9
	clap_builder@4.6.7
	clap_derive@4.6.9
	clap_lex@1.1.2
	colorchoice@1.0.5
	combine@4.6.9
	const-oid@0.10.3
	core-foundation-sys@0.8.7
	core-foundation@0.10.1
	cpufeatures@0.3.1
	crc32fast@1.5.5
	crypto-common@0.2.2
	digest@0.11.3
	equivalent@1.0.3
	errno@0.3.15
	fastrand@2.5.0
	find-msvc-tools@0.1.15
	flate2@1.1.11
	foldhash@0.2.0
	futures-core@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	getrandom@0.2.17
	getrandom@0.4.3
	hashbrown@0.17.1
	heck@0.5.0
	http@1.5.0
	httparse@1.10.1
	hybrid-array@0.4.15
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.65
	indexmap@2.14.2
	is_terminal_polyfill@1.70.2
	itoa@1.0.19
	jni-macros@0.22.4
	jni-sys-macros@0.4.1
	jni-sys@0.4.1
	jni@0.22.4
	js-sys@0.3.107
	libc@0.2.191
	linux-raw-sys@0.12.1
	log@0.4.35
	memchr@2.8.3
	miniz_oxide@0.9.1
	num-traits@0.2.19
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	openssl-probe@0.2.2
	percent-encoding@2.3.2
	pin-project-lite@0.2.18
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@6.0.0
	regex-automata@0.4.19
	regex-syntax@0.8.12
	regex@1.13.2
	ring@0.17.14
	rustc_version@0.4.1
	rustix@1.1.6
	rustls-native-certs@0.8.5
	rustls-pki-types@1.16.0
	rustls-platform-verifier-android@0.2.0
	rustls-platform-verifier@0.7.1
	rustls-webpki@0.103.17
	rustls@0.23.46
	rustversion@1.0.23
	same-file@1.0.6
	schannel@0.1.30
	security-framework-sys@2.17.0
	security-framework@3.7.0
	semver@1.0.28
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.154
	sha1@0.11.0
	shlex@2.0.1
	simd-adler32@0.3.10
	simd_cesu8@1.2.0
	simdutf8@0.1.5
	slab@0.4.12
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.119
	syn@3.0.10
	tempfile@3.27.0
	thiserror-impl@2.0.21
	thiserror@2.0.21
	typenum@1.20.1
	unicode-ident@1.0.27
	untrusted@0.9.0
	ureq-proto@0.7.1
	ureq@3.5.2
	utf8-zero@0.8.1
	utf8parse@0.2.2
	walkdir@2.5.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasm-bindgen-macro-support@0.2.130
	wasm-bindgen-macro@0.2.130
	wasm-bindgen-shared@0.2.130
	wasm-bindgen@0.2.130
	webpki-root-certs@1.0.12
	webpki-roots@1.0.12
	winapi-util@0.1.11
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	zeroize@1.9.2
	zlib-rs@0.6.8
	zmij@1.0.23
"

inherit cargo

DESCRIPTION="Generate utcp HTTP manuals for the Azure DevOps REST API"
HOMEPAGE="https://github.com/Faraclas/agent-misc"

MY_TAG="azdo-manuals-v${PV}"
SRC_URI="
	https://github.com/Faraclas/agent-misc/archive/refs/tags/${MY_TAG}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/agent-misc-${MY_TAG}/azdo-manuals"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+="
	0BSD Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD CDLA-Permissive-2.0
	ISC MIT Unicode-3.0 Unlicense ZLIB
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND="
	app-misc/ca-certificates
	>=dev-util/utcp-0.2.0
"
BDEPEND="
	test? ( >=dev-util/utcp-0.2.0 )
"

QA_FLAGS_IGNORED="usr/bin/azdo-manuals"

src_test() {
	# The utcp load test registers the generated manuals in a throwaway utcp
	# (temporary folders, --direct, no network). REQUIRE_UTCP=1 makes it fail
	# instead of skipping when utcp is missing.
	local -x UTCP_BIN="${BROOT}/usr/bin/utcp" REQUIRE_UTCP=1
	cargo_src_test
}

src_install() {
	dobin "$(cargo_target_dir)/azdo-manuals"
	dodoc README.md docs/operating.md docs/azdo-manuals-spec.md NOTICE ../LICENSE
}

pkg_postinst() {
	elog "Generate and stage the manuals for your Azure DevOps organization (per user, needs network):"
	elog "    azdo-manuals generate --org <org> --stage"
	elog "It prints the PAT permissions and the next steps: give utcp the PAT as AZURE_DEVOPS_EXT_PAT,"
	elog "check with utcp doctor, review with utcp diff, test with azdo-manuals read-test, then utcp promote."
	elog "After upgrading azdo-manuals, run generate --stage again, then utcp diff and utcp promote."
	elog "Docs: /usr/share/doc/${PF}/operating.md* and README.md*"
}
