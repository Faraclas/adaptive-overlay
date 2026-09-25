# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	adler2@2.0.1
	aead@0.6.1
	aes@0.8.4
	ahash@0.8.12
	aho-corasick@1.1.4
	allocator-api2@0.2.21
	ambient-authority@0.0.2
	android_system_properties@0.1.5
	annotate-snippets@0.9.2
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	anyhow@1.0.102
	apple-cf@0.9.3
	apple-metal@0.6.0
	apple-native-keyring-store@1.0.2
	arrayref@0.3.9
	arrayvec@0.7.6
	ashpd@0.13.11
	askama@0.14.0
	askama_derive@0.14.0
	askama_parser@0.14.0
	async-broadcast@0.7.2
	async-channel@2.5.0
	async-compat@0.2.5
	async-executor@1.14.0
	async-fs@2.2.0
	async-io@2.6.0
	async-lock@3.4.2
	async-process@2.5.0
	async-recursion@1.1.1
	async-signal@0.2.14
	async-task@4.7.1
	async-trait@0.1.89
	atomic-polyfill@1.0.3
	atomic-waker@1.1.2
	atspi-common@0.14.0
	atspi-connection@0.14.0
	atspi-proxies@0.14.0
	atspi@0.30.0
	autocfg@1.5.0
	base64@0.22.1
	basic-toml@0.1.10
	bindgen@0.69.5
	bit-set@0.8.0
	bit-vec@0.8.0
	bitflags@1.3.2
	bitflags@2.11.1
	bitvec@1.0.1
	block-buffer@0.10.4
	block-buffer@0.12.1
	block-padding@0.3.3
	block2@0.5.1
	block2@0.6.2
	blocking@1.6.2
	borrow-or-share@0.2.4
	bstr@1.13.0
	bumpalo@3.20.2
	bytecount@0.6.9
	bytemuck@1.25.0
	byteorder-lite@0.1.0
	byteorder@1.5.0
	bytes@1.11.1
	calloop@0.14.4
	camino@1.2.4
	cap-fs-ext@4.0.3
	cap-primitives@4.0.3
	cap-std@4.0.3
	cargo-platform@0.1.9
	cargo_metadata@0.19.2
	cbc@0.1.2
	cbindgen@0.29.4
	cc@1.2.62
	cexpr@0.6.0
	cfg-expr@0.15.8
	cfg-if@1.0.4
	chacha20@0.10.1
	chacha20poly1305@0.11.0
	chrono-tz@0.10.4
	chrono@0.4.45
	ciborium-io@0.2.2
	ciborium-ll@0.2.2
	ciborium@0.2.2
	cipher@0.4.4
	cipher@0.5.2
	clang-sys@1.8.1
	clap@4.6.1
	clap_builder@4.6.0
	clap_derive@4.6.1
	clap_lex@1.1.0
	clipboard-rs@0.3.5
	clipboard-win@5.4.1
	cmov@0.5.4
	cobs@0.3.0
	colorchoice@1.0.5
	concurrent-queue@2.5.0
	convert_case@0.6.0
	cookie-factory@0.3.3
	cookie@0.18.1
	cookie_store@0.22.1
	core-foundation-sys@0.8.7
	core-foundation@0.10.1
	core-graphics-types@0.2.0
	core-graphics@0.24.0
	coset@0.4.2
	cpufeatures@0.2.17
	cpufeatures@0.3.0
	crc32fast@1.5.0
	critical-section@1.2.0
	crossbeam-channel@0.5.15
	crossbeam-queue@0.3.12
	crossbeam-utils@0.8.21
	crunchy@0.2.4
	crypto-common@0.1.7
	crypto-common@0.2.2
	ctutils@0.4.2
	data-encoding@2.11.0
	deranged@0.5.8
	digest@0.10.7
	dirs-sys@0.4.1
	dirs@5.0.1
	dispatch2@0.3.1
	displaydoc@0.2.5
	document-features@0.2.12
	doom-fish-utils@0.3.2
	downcast-rs@1.2.1
	dyn-clone@1.0.20
	either@1.16.0
	email_address@0.2.9
	embed-manifest@1.5.0
	embed-resource@2.5.2
	embedded-io@0.4.0
	embedded-io@0.6.1
	endi@1.1.1
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	equivalent@1.0.2
	errno@0.3.14
	error-code@3.3.2
	evdev@0.12.2
	event-listener-strategy@0.5.4
	event-listener@5.4.1
	fancy-regex@0.18.0
	fastrand@2.4.1
	fax@0.2.7
	fdeflate@0.3.7
	filetime@0.2.29
	find-msvc-tools@0.1.9
	fixedbitset@0.5.7
	flate2@1.1.9
	fluent-uri@0.4.1
	fnv@1.0.7
	foldhash@0.1.5
	foldhash@0.2.0
	fontdue@0.9.3
	foreign-types-macros@0.2.3
	foreign-types-shared@0.1.1
	foreign-types-shared@0.3.1
	foreign-types@0.3.2
	foreign-types@0.5.0
	form_urlencoded@1.2.2
	fraction@0.15.4
	fs-err@2.11.0
	fs-set-times@0.20.3
	fs2@0.4.3
	funty@2.0.0
	futures-channel@0.3.32
	futures-core@0.3.32
	futures-executor@0.3.32
	futures-io@0.3.32
	futures-lite@2.6.1
	futures-macro@0.3.32
	futures-sink@0.3.32
	futures-task@0.3.32
	futures-util@0.3.32
	futures@0.3.32
	generic-array@0.14.7
	gethostname@1.1.0
	getrandom@0.2.17
	getrandom@0.3.4
	getrandom@0.4.2
	glob@0.3.3
	globset@0.4.19
	goblin@0.8.2
	half@2.7.1
	hash32@0.2.1
	hashbrown@0.15.5
	hashbrown@0.16.1
	hashbrown@0.17.1
	heapless@0.7.17
	heck@0.5.0
	hermit-abi@0.5.2
	hex@0.4.3
	hkdf@0.12.4
	hmac@0.12.1
	http@1.4.0
	httparse@1.10.1
	hybrid-array@0.4.14
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.65
	icu_collections@2.2.0
	icu_locale_core@2.2.0
	icu_normalizer@2.2.0
	icu_normalizer_data@2.2.0
	icu_properties@2.2.0
	icu_properties_data@2.2.0
	icu_provider@2.2.0
	id-arena@2.3.0
	idna@1.1.0
	idna_adapter@1.2.2
	image@0.25.10
	indexmap@2.14.0
	inout@0.1.4
	inout@0.2.2
	io-extras@0.19.0
	io-lifetimes@2.0.4
	io-lifetimes@3.0.1
	ipnet@2.12.0
	is_terminal_polyfill@1.70.2
	itertools@0.12.1
	itoa@1.0.18
	jobserver@0.1.35
	js-sys@0.3.98
	jsonschema-regex@0.46.10
	jsonschema@0.46.10
	keyring-core@1.0.0
	keyring@4.1.6
	lazy_static@1.5.0
	lazycell@1.3.0
	leb128fmt@0.1.0
	libc@0.2.186
	libloading@0.8.9
	libm@0.2.16
	libredox@0.1.17
	libspa-sys@0.8.0
	libspa@0.8.0
	linux-raw-sys@0.12.1
	litemap@0.8.2
	litrs@1.0.0
	lock_api@0.4.14
	log@0.4.29
	lru@0.18.1
	matchers@0.2.0
	matrixmultiply@0.3.11
	maybe-owned@0.3.4
	md-5@0.10.6
	memchr@2.8.0
	memmap2@0.9.10
	memoffset@0.6.5
	memoffset@0.9.1
	meval@0.2.0
	micromap@0.3.0
	minimal-lexical@0.2.1
	miniz_oxide@0.8.9
	mio@1.2.0
	moxcms@0.8.1
	msvc_spectre_libs@0.1.3
	native-tls@0.2.18
	ndarray@0.16.1
	nix@0.23.2
	nix@0.27.1
	nom@1.2.4
	nom@7.1.3
	nom@8.0.0
	nu-ansi-term@0.50.3
	num-bigint-dig@0.9.1
	num-bigint@0.4.8
	num-cmp@0.1.0
	num-complex@0.4.6
	num-conv@0.2.1
	num-integer@0.1.46
	num-iter@0.1.46
	num-rational@0.4.2
	num-traits@0.2.19
	num@0.4.3
	objc-sys@0.3.5
	objc2-app-kit@0.2.2
	objc2-app-kit@0.3.2
	objc2-cloud-kit@0.3.2
	objc2-core-data@0.2.2
	objc2-core-data@0.3.2
	objc2-core-foundation@0.3.2
	objc2-core-graphics@0.3.2
	objc2-core-image@0.2.2
	objc2-core-image@0.3.2
	objc2-core-location@0.3.2
	objc2-core-text@0.3.2
	objc2-core-video@0.3.2
	objc2-encode@4.1.0
	objc2-foundation@0.2.2
	objc2-foundation@0.3.2
	objc2-io-surface@0.3.2
	objc2-metal@0.2.2
	objc2-quartz-core@0.2.2
	objc2-quartz-core@0.3.2
	objc2-ui-kit@0.3.2
	objc2-user-notifications@0.3.2
	objc2@0.5.2
	objc2@0.6.4
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	oo7@0.6.0
	openssl-macros@0.1.1
	openssl-probe@0.2.1
	openssl-sys@0.9.117
	openssl@0.10.80
	option-ext@0.2.0
	ordered-stream@0.2.0
	ort-sys@2.0.0-rc.10
	ort@2.0.0-rc.10
	os_pipe@1.2.3
	outref@0.5.2
	parking@2.2.1
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	pbkdf2@0.12.2
	percent-encoding@2.3.2
	petgraph@0.8.3
	phf@0.12.1
	phf_shared@0.12.1
	pin-project-lite@0.2.17
	piper@0.2.5
	pipewire-sys@0.8.0
	pipewire@0.8.0
	pkg-config@0.3.33
	plain@0.2.3
	png@0.18.1
	polling@3.11.0
	poly1305@0.9.1
	portable-atomic-util@0.2.8
	portable-atomic@1.15.0
	postcard@1.1.3
	potential_utf@0.1.5
	powerfmt@0.2.0
	ppv-lite86@0.2.21
	prettyplease@0.2.37
	proc-macro-crate@3.5.0
	proc-macro2@1.0.106
	pxfm@0.1.29
	quick-error@2.0.1
	quick-xml@0.39.4
	quote@1.0.45
	r-efi@5.3.0
	r-efi@6.0.0
	radium@0.7.0
	rand@0.10.2
	rand@0.8.6
	rand@0.9.5
	rand_chacha@0.3.1
	rand_chacha@0.9.0
	rand_core@0.10.1
	rand_core@0.6.4
	rand_core@0.9.5
	rawpointer@0.2.1
	redox_syscall@0.5.18
	redox_users@0.4.6
	ref-cast-impl@1.0.25
	ref-cast@1.0.25
	referencing@0.46.10
	regex-automata@0.4.14
	regex-syntax@0.8.10
	regex@1.12.3
	regorus@0.10.1
	reis@0.7.0
	ring@0.17.14
	rustc-hash@1.1.0
	rustc-hash@2.1.3
	rustc_version@0.4.1
	rustix-linux-procfs@0.1.1
	rustix@1.1.4
	rustls-pki-types@1.14.1
	rustls-webpki@0.103.13
	rustls@0.23.40
	rustversion@1.0.22
	ryu@1.0.23
	schannel@0.1.29
	schemars@1.2.1
	schemars_derive@1.2.1
	scopeguard@1.2.0
	screencapturekit@8.0.1
	scroll@0.12.0
	scroll_derive@0.12.1
	secret-service@5.1.0
	security-framework-sys@2.17.0
	security-framework@3.7.0
	semver@1.0.28
	serde@1.0.228
	serde_bytes@0.11.19
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_derive_internals@0.29.1
	serde_json@1.0.149
	serde_repr@0.1.20
	serde_spanned@0.6.9
	serde_spanned@1.1.1
	serde_yaml@0.9.34+deprecated
	serde_yaml_ng@0.10.0
	sha1@0.10.6
	sha2@0.10.9
	sharded-slab@0.1.7
	shlex@1.3.0
	signal-hook-registry@1.4.8
	simd-adler32@0.3.9
	siphasher@1.0.2
	slab@0.4.12
	smallvec@1.15.1
	smallvec@2.0.0-alpha.10
	smawk@0.3.3
	socket2@0.6.3
	spin@0.10.1
	spin@0.9.9
	stable_deref_trait@1.2.1
	static_assertions@1.1.0
	strict-num@0.1.1
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.117
	synstructure@0.13.2
	system-deps@6.2.2
	tap@1.0.1
	tar@0.4.46
	target-lexicon@0.12.16
	tempfile@3.27.0
	textwrap@0.16.2
	thiserror-impl@1.0.69
	thiserror-impl@2.0.18
	thiserror@1.0.69
	thiserror@2.0.18
	thread_local@1.1.9
	tiff@0.11.3
	time-core@0.1.8
	time-macros@0.2.27
	time@0.3.47
	tiny-skia-path@0.11.4
	tiny-skia@0.11.4
	tinystr@0.8.3
	tokio-macros@2.7.0
	tokio-native-tls@0.3.1
	tokio-tungstenite@0.24.0
	tokio@1.52.1
	toml@0.8.23
	toml@0.9.12+spec-1.1.0
	toml_datetime@0.6.11
	toml_datetime@0.7.5+spec-1.1.0
	toml_datetime@1.1.1+spec-1.1.0
	toml_edit@0.22.27
	toml_edit@0.25.12+spec-1.1.0
	toml_parser@1.1.2+spec-1.1.0
	toml_write@0.1.2
	toml_writer@1.1.2+spec-1.1.0
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing-log@0.2.0
	tracing-subscriber@0.3.23
	tracing@0.1.44
	tree_magic_mini@3.2.2
	ttf-parser@0.21.1
	tungstenite@0.24.0
	typed-path@0.12.3
	typenum@1.20.0
	uds_windows@1.2.1
	unicode-general-category@1.1.0
	unicode-ident@1.0.24
	unicode-segmentation@1.13.3
	unicode-width@0.1.14
	unicode-xid@0.2.6
	uniffi@0.31.0
	uniffi_bindgen@0.31.0
	uniffi_core@0.31.0
	uniffi_internal_macros@0.31.0
	uniffi_macros@0.31.0
	uniffi_meta@0.31.0
	uniffi_pipeline@0.31.0
	uniffi_udl@0.31.0
	universal-hash@0.6.1
	unsafe-libyaml@0.2.11
	untrusted@0.9.0
	ureq-proto@0.6.0
	ureq@3.3.0
	url@2.5.8
	utf-8@0.7.6
	utf8-zero@0.8.1
	utf8_iter@1.0.4
	utf8parse@0.2.2
	uuid-simd@0.8.0
	uuid@1.23.1
	valuable@0.1.1
	vcpkg@0.2.15
	version-compare@0.2.1
	version_check@0.9.5
	vsimd@0.8.0
	vswhom-sys@0.1.3
	vswhom@0.1.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.3+wasi-0.2.9
	wasip3@0.4.0+wasi-0.3.0-rc-2026-01-06
	wasm-bindgen-macro-support@0.2.121
	wasm-bindgen-macro@0.2.121
	wasm-bindgen-shared@0.2.121
	wasm-bindgen@0.2.121
	wasm-encoder@0.244.0
	wasm-metadata@0.244.0
	wasmparser@0.244.0
	wayland-backend@0.3.15
	wayland-client@0.31.14
	wayland-protocols-wlr@0.3.12
	wayland-protocols@0.32.12
	wayland-scanner@0.31.10
	wayland-sys@0.31.11
	webpki-roots@1.0.7
	weedle2@5.0.0
	weezl@0.1.12
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-x86_64-pc-windows-gnu@0.4.0
	winapi@0.3.9
	windows-collections@0.2.0
	windows-core@0.58.0
	windows-core@0.59.0
	windows-core@0.61.2
	windows-future@0.2.1
	windows-implement@0.58.0
	windows-implement@0.59.0
	windows-implement@0.60.2
	windows-interface@0.58.0
	windows-interface@0.59.3
	windows-link@0.1.3
	windows-link@0.2.1
	windows-native-keyring-store@1.1.0
	windows-numerics@0.2.0
	windows-result@0.2.0
	windows-result@0.3.4
	windows-strings@0.1.0
	windows-strings@0.3.1
	windows-strings@0.4.2
	windows-sys@0.48.0
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.48.5
	windows-targets@0.52.6
	windows-targets@0.53.5
	windows-threading@0.1.0
	windows-win@3.0.0
	windows@0.58.0
	windows@0.59.0
	windows@0.61.3
	windows_aarch64_gnullvm@0.48.5
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_gnullvm@0.53.1
	windows_aarch64_msvc@0.48.5
	windows_aarch64_msvc@0.52.6
	windows_aarch64_msvc@0.53.1
	windows_i686_gnu@0.48.5
	windows_i686_gnu@0.52.6
	windows_i686_gnu@0.53.1
	windows_i686_gnullvm@0.52.6
	windows_i686_gnullvm@0.53.1
	windows_i686_msvc@0.48.5
	windows_i686_msvc@0.52.6
	windows_i686_msvc@0.53.1
	windows_x86_64_gnu@0.48.5
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnu@0.53.1
	windows_x86_64_gnullvm@0.48.5
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_gnullvm@0.53.1
	windows_x86_64_msvc@0.48.5
	windows_x86_64_msvc@0.52.6
	windows_x86_64_msvc@0.53.1
	winnow@0.7.15
	winnow@1.0.3
	winreg@0.52.0
	winx@0.36.4
	wit-bindgen-core@0.51.0
	wit-bindgen-rust-macro@0.51.0
	wit-bindgen-rust@0.51.0
	wit-bindgen@0.51.0
	wit-bindgen@0.57.1
	wit-component@0.244.0
	wit-parser@0.244.0
	wl-clipboard-rs@0.9.3
	writeable@0.6.3
	wyz@0.5.1
	x11@2.21.0
	x11rb-protocol@0.13.2
	x11rb@0.13.2
	xkbcommon@0.9.0
	xkeysym@0.2.1
	yansi-term@0.1.2
	yoke-derive@0.8.2
	yoke@0.8.2
	zbus-lockstep-macros@0.5.2
	zbus-lockstep@0.5.2
	zbus-secret-service-keyring-store@1.0.0
	zbus@5.16.0
	zbus_macros@5.16.0
	zbus_names@4.3.2
	zbus_xml@5.1.1
	zerocopy-derive@0.8.48
	zerocopy@0.8.48
	zerofrom-derive@0.1.7
	zerofrom@0.1.8
	zeroize@1.8.2
	zeroize_derive@1.5.0
	zerotrie@0.2.4
	zerovec-derive@0.11.3
	zerovec@0.11.6
	zip@8.6.0
	zlib-rs@0.6.6
	zmij@1.0.21
	zopfli@0.8.3
	zstd-safe@7.2.4
	zstd-sys@2.0.16+zstd.1.5.7
	zstd@0.13.3
	zune-core@0.5.1
	zune-jpeg@0.5.15
	zvariant@5.12.0
	zvariant_derive@5.12.0
	zvariant_utils@3.4.0
"

RUST_MIN_VER="1.97.1"

inherit cargo

MY_TAG="cua-driver-rs-v${PV}"

DESCRIPTION="Computer-use automation driver (MCP server) used by Hermes computer_use"
HOMEPAGE="https://github.com/trycua/cua"
SRC_URI="
	https://github.com/trycua/cua/archive/refs/tags/${MY_TAG}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/cua-${MY_TAG}/libs/cua-driver/rust"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD Boost-1.0
	CDLA-Permissive-2.0 ISC MIT MIT-0 MPL-2.0 Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="gnome +portal"

# X11/Xlib FFI (MPX drags, XTest) is always linked; portal input adds
# libei (via the pure-Rust reis crate) and libxkbcommon.
DEPEND="
	x11-libs/libX11
	x11-libs/libXext
	x11-libs/libXi
	x11-libs/libXtst
	portal? (
		dev-libs/libei
		x11-libs/libxkbcommon
	)
"
# gdbus (dev-libs/glib) is used at runtime to reach the WinRects helper;
# AT-SPI and the desktop portal are runtime services on the user's desktop.
RDEPEND="
	${DEPEND}
	app-accessibility/at-spi2-core
	dev-libs/glib
	portal? ( sys-apps/xdg-desktop-portal )
"
BDEPEND="
	virtual/pkgconfig
"

PATCHES=(
	# Treat /usr/bin/cua-driver as package-managed so `cua-driver update
	# --apply` and channel switching never replace Portage-owned files.
	"${FILESDIR}"/${PN}-0.28.3-portage-managed.patch
)

QA_FLAGS_IGNORED="usr/bin/.*"

src_compile() {
	local features=()
	use portal && features+=( cua-driver/portal-input )
	local featstr
	printf -v featstr '%s,' "${features[@]}"
	featstr=${featstr%,}
	cargo_src_compile -p cua-driver -p cursor-theme-cli \
		${featstr:+--features "${featstr}"}
}

src_test() {
	# Upstream's tests need a live X11/AT-SPI session.
	:
}

src_install() {
	dobin "$(cargo_target_dir)"/cua-driver
	# cua-driver looks up this sidecar next to its own executable.
	dobin "$(cargo_target_dir)"/cua-cursor-theme

	if use gnome; then
		# GNOME Shell helper (Wayland window geometry, capture, cursor, and
		# verified focus). cua-driver finds it over D-Bus, so a system-wide
		# install works; users still enable it per session.
		insinto /usr/share/gnome-shell/extensions/winrects@cua
		doins ../wayland-helper/winrects@cua/{metadata.json,extension.js}
	fi

	dodoc README.md CHANGELOG.md
}

# Warn when the installed GNOME Shell is not in the WinRects extension's
# declared shell-version list (GNOME refuses to load it then). No hard
# dependency: an optional extension must never block GNOME upgrades.
winrects_check_shell_version() {
	local meta="${EROOT}/usr/share/gnome-shell/extensions/winrects@cua/metadata.json"
	[[ -f ${meta} ]] || return 0
	local shell_ver
	shell_ver=$(best_version gnome-base/gnome-shell) || return 0
	[[ -n ${shell_ver} ]] || return 0
	shell_ver=${shell_ver#gnome-base/gnome-shell-}
	local major=${shell_ver%%.*}
	local supported
	supported=$(sed -n 's/.*"shell-version"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' "${meta}" | tr -d '" ')
	[[ -n ${supported} ]] || return 0
	if [[ ,${supported}, != *,${major},* ]]; then
		ewarn "WinRects supports GNOME Shell ${supported//,/, } but"
		ewarn "gnome-shell-${shell_ver} is installed. GNOME will not load the"
		ewarn "extension; computer use on GNOME Wayland will not work until a"
		ewarn "cua-driver release adds GNOME ${major}."
	else
		elog "WinRects supports GNOME Shell ${supported//,/, } (installed: ${shell_ver})."
	fi
}

pkg_postinst() {
	if use gnome; then
		winrects_check_shell_version
		elog "Enable the WinRects GNOME Shell helper (per user), then log out"
		elog "and back in:"
		elog "    gnome-extensions enable winrects@cua"
		elog "It needs user extensions allowed:"
		elog "    gsettings set org.gnome.shell disable-user-extensions false"
	fi
	elog "Computer use reads app UIs through AT-SPI; turn on GNOME accessibility:"
	elog "    gsettings set org.gnome.desktop.interface toolkit-accessibility true"
	elog "For Hermes on Wayland: hermes config set computer_use.native_wayland true"
	elog "Upstream telemetry is on by default; Hermes disables it for the"
	elog "cua-driver it starts. For direct use: cua-driver telemetry disable"
}
