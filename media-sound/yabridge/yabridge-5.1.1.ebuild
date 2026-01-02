# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	anstream-0.3.2
	anstyle-1.0.1
	anstyle-parse-0.2.1
	anstyle-query-1.0.0
	anstyle-wincon-1.0.2
	anyhow-1.0.72
	autocfg-1.1.0
	bitflags-1.3.2
	bitflags-2.4.0
	cc-1.0.82
	cfg-if-1.0.0
	clap-4.3.21
	clap_builder-4.3.21
	clap_derive-4.3.12
	clap_lex-0.5.0
	clipboard-win-4.5.0
	colorchoice-1.0.0
	colored-2.0.4
	crossbeam-channel-0.5.8
	crossbeam-deque-0.8.3
	crossbeam-epoch-0.9.15
	crossbeam-utils-0.8.16
	dirs-next-2.0.0
	dirs-sys-next-0.1.2
	either-1.9.0
	endian-type-0.1.2
	errno-0.3.2
	errno-dragonfly-0.1.2
	error-code-2.3.1
	fd-lock-3.0.13
	getrandom-0.2.10
	goblin-0.6.1
	heck-0.4.1
	hermit-abi-0.3.2
	io-lifetimes-1.0.11
	is_executable-1.0.1
	is-terminal-0.4.9
	itoa-0.4.8
	lazy_static-1.4.0
	libc-0.2.147
	libloading-0.7.4
	linux-raw-sys-0.3.8
	linux-raw-sys-0.4.5
	log-0.4.20
	memchr-2.5.0
	memoffset-0.6.5
	memoffset-0.9.0
	nibble_vec-0.1.0
	nix-0.23.2
	num_cpus-1.16.0
	once_cell-1.18.0
	plain-0.2.3
	proc-macro2-1.0.66
	promptly-0.3.1
	quote-1.0.32
	radix_trie-0.2.1
	rayon-1.7.0
	rayon-core-1.11.0
	redox_syscall-0.2.16
	redox_users-0.4.3
	rustix-0.37.23
	rustix-0.38.8
	rustyline-9.1.2
	ryu-0.2.8
	same-file-1.0.6
	scopeguard-1.2.0
	scroll-0.11.0
	scroll_derive-0.11.1
	serde-1.0.183
	serde_derive-1.0.183
	serde_jsonrc-0.1.0
	smallvec-1.11.0
	smawk-0.3.1
	str-buf-1.0.6
	strsim-0.10.0
	syn-2.0.28
	terminal_size-0.2.6
	textwrap-0.16.0
	thiserror-1.0.44
	thiserror-impl-1.0.44
	toml-0.5.11
	unicode-ident-1.0.11
	unicode-linebreak-0.1.5
	unicode-segmentation-1.10.1
	unicode-width-0.1.10
	utf8parse-0.2.1
	walkdir-2.3.3
	wasi-0.11.0+wasi-snapshot-preview1
	which-4.4.0
	winapi-0.3.9
	winapi-i686-pc-windows-gnu-0.4.0
	winapi-util-0.1.5
	winapi-x86_64-pc-windows-gnu-0.4.0
	windows_aarch64_gnullvm-0.48.0
	windows_aarch64_msvc-0.48.0
	windows_i686_gnu-0.48.0
	windows_i686_msvc-0.48.0
	windows-sys-0.48.0
	windows-targets-0.48.1
	windows_x86_64_gnu-0.48.0
	windows_x86_64_gnullvm-0.48.0
	windows_x86_64_msvc-0.48.0
	xdg-2.5.2
"

inherit meson cargo

DESCRIPTION="A modern and transparent way to use Windows VST2, VST3 and CLAP plugins on Linux"
HOMEPAGE="https://github.com/robbert-vdh/yabridge"
SRC_URI="
	https://github.com/robbert-vdh/yabridge/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/chriskohlhoff/asio/archive/7609450f71434bdc9fbd9491a9505b423c2a8496.tar.gz -> asio-1.28.2.tar.gz
	https://github.com/fraillt/bitsery/archive/d1a47e06e2104b195a19c73b61f1d5c1dceaa228.tar.gz -> bitsery-5.2.3.tar.gz
	https://github.com/free-audio/clap/archive/094bb76c85366a13cc6c49292226d8608d6ae50c.tar.gz -> clap-1.1.9.tar.gz
	https://github.com/Naios/function2/archive/9e303865d14f1204f09379e37bbeb30c4375139a.tar.gz -> function2-4.2.3.tar.gz
	https://github.com/gulrak/filesystem/archive/8a2edd6d92ed820521d42c94d179462bf06b5ed3.tar.gz -> ghc_filesystem-1.5.14.tar.gz
	https://github.com/marzer/tomlplusplus/archive/30172438cee64926dc41fdd9c11fb3ba5b2ba9de.tar.gz -> tomlplusplus-3.4.0.tar.gz
	https://github.com/robbert-vdh/vst3sdk/archive/refs/tags/v3.7.7_build_19-patched.tar.gz -> vst3sdk-3.7.7_build_19-patched.tar.gz
	https://github.com/nicokoch/reflink/archive/e8d93b465f5d9ad340cd052b64bbc77b8ee107e2.tar.gz -> reflink-e8d93b465f5d9ad340cd052b64bbc77b8ee107e2.tar.gz
	$(cargo_crate_uris)
"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+bitbridge"

DEPEND="
	>=sys-devel/gcc-10
	x11-libs/libxcb
	virtual/wine[staging]
	bitbridge? (
		x11-libs/libxcb[abi_x86_32]
	)
"

RDEPEND="
	${DEPEND}
	app-crypt/libmd
	dev-libs/libbsd
	sys-libs/glibc
	x11-libs/libXau
	x11-libs/libxcb
	x11-libs/libXdmcp
	virtual/wine
"

BDEPEND="
	>=dev-build/meson-0.56
	dev-vcs/git
	virtual/rust
"

QA_PREBUILT="/usr/*"
QA_TEXTRELS="usr/bin/yabridge-host-32.exe.so"

src_prepare() {
	default

	# Populate subprojects directory with pre-downloaded sources
	# This is necessary because Gentoo disables network access during builds
	# The asio tarball extracts to asio-<hash>/asio/ but the meson.build expects
	# to find asio/include, so we link to the parent directory
	ln -s "${WORKDIR}/asio-7609450f71434bdc9fbd9491a9505b423c2a8496" \
		"${S}/subprojects/asio" || die
	ln -s "${WORKDIR}/bitsery-d1a47e06e2104b195a19c73b61f1d5c1dceaa228" \
		"${S}/subprojects/bitsery" || die
	ln -s "${WORKDIR}/clap-094bb76c85366a13cc6c49292226d8608d6ae50c" \
		"${S}/subprojects/clap" || die
	ln -s "${WORKDIR}/function2-9e303865d14f1204f09379e37bbeb30c4375139a" \
		"${S}/subprojects/function2" || die
	ln -s "${WORKDIR}/filesystem-8a2edd6d92ed820521d42c94d179462bf06b5ed3" \
		"${S}/subprojects/ghc_filesystem" || die
	ln -s "${WORKDIR}/tomlplusplus-30172438cee64926dc41fdd9c11fb3ba5b2ba9de" \
		"${S}/subprojects/tomlplusplus" || die

	# VST3 SDK requires git submodules which aren't included in GitHub archives
	# We need to manually clone them during prepare phase
	#
	# MAINTAINER NOTE: When updating yabridge, check subprojects/vst3.wrap in the
	# new version's source to see if these commit hashes have changed. The wrap file
	# specifies which commits to use for each submodule. Update the git clone
	# commands below if the hashes in the wrap file are different.
	#
	# Current version (v3.7.7_build_19-patched) uses:
	#   base:           ea2bac9a109cce69ced21833fa6ff873dd6e368a
	#   pluginterfaces: bc5ff0f87aaa3cd28c114810f4f03c384421ad2c
	#   public.sdk:     bbb0538535b171e805c8a8b612c2cd8a5f95738b
	einfo "Cloning VST3 SDK submodules (this requires network access)..."
	cd "${WORKDIR}/vst3sdk-3.7.7_build_19-patched" || die

	# Remove empty directories that come from the tarball
	rm -rf base pluginterfaces public.sdk || die

	# Clone submodules to specific commits
	# We can't use --depth 1 because we need to fetch specific commit hashes
	git clone https://github.com/steinbergmedia/vst3_base.git base || die
	git clone https://github.com/steinbergmedia/vst3_pluginterfaces.git pluginterfaces || die
	git clone https://github.com/steinbergmedia/vst3_public_sdk.git public.sdk || die
	(cd base && git checkout ea2bac9a109cce69ced21833fa6ff873dd6e368a && rm -rf .git) || die
	(cd pluginterfaces && git checkout bc5ff0f87aaa3cd28c114810f4f03c384421ad2c && rm -rf .git) || die
	(cd public.sdk && git checkout bbb0538535b171e805c8a8b612c2cd8a5f95738b && rm -rf .git) || die
	cd "${S}" || die

	ln -s "${WORKDIR}/vst3sdk-3.7.7_build_19-patched" \
		"${S}/subprojects/vst3" || die

	# Copy meson.build files from packagefiles to subprojects
	# This is needed because --wrap-mode nodownload doesn't process .wrap files
	# which normally handle the patch_directory directive
	cp "${S}/subprojects/packagefiles/asio/meson.build" \
		"${S}/subprojects/asio/" || die
	cp "${S}/subprojects/packagefiles/bitsery/meson.build" \
		"${S}/subprojects/bitsery/" || die
	cp "${S}/subprojects/packagefiles/clap/meson.build" \
		"${S}/subprojects/clap/" || die
	cp "${S}/subprojects/packagefiles/function2/meson.build" \
		"${S}/subprojects/function2/" || die
	cp "${S}/subprojects/packagefiles/ghc_filesystem/meson.build" \
		"${S}/subprojects/ghc_filesystem/" || die

	# Patch yabridgectl's Cargo.toml to use local path for reflink instead of git
	# The cargo eclass doesn't handle git dependencies well in offline mode
	cd "${S}/tools/yabridgectl" || die
	sed -i \
		-e 's|reflink = { git = "https://github.com/nicokoch/reflink", rev = "e8d93b465f5d9ad340cd052b64bbc77b8ee107e2" }|reflink = { path = "'"${WORKDIR}"'/reflink-e8d93b465f5d9ad340cd052b64bbc77b8ee107e2" }|' \
		Cargo.toml || die "Failed to patch Cargo.toml for reflink dependency"
	cd "${S}" || die
}

src_configure() {
	local emesonargs=(
		--cross-file="${S}/cross-wine.conf"
		$(meson_use bitbridge)
	)

	meson_src_configure
}

src_compile() {
	meson_src_compile

	# Build yabridgectl manually using cargo
	# We can't use cargo_src_compile because yabridgectl is in a subdirectory
	cd "${S}/tools/yabridgectl" || die
	cargo build --release --all-features || die "cargo build failed"
}

src_install() {
	# Install Wine plugin host binaries
	exeinto /usr/bin
	doexe "${BUILD_DIR}/yabridge-host.exe"
	if use bitbridge; then
		doexe "${BUILD_DIR}/yabridge-host-32.exe"
	fi

	# Install .exe.so files (Wine shared libraries)
	doexe "${BUILD_DIR}/yabridge-host.exe.so"
	if use bitbridge; then
		doexe "${BUILD_DIR}/yabridge-host-32.exe.so"
	fi

	# Install plugin libraries
	dolib.so "${BUILD_DIR}/libyabridge-vst2.so"
	dolib.so "${BUILD_DIR}/libyabridge-vst3.so"
	dolib.so "${BUILD_DIR}/libyabridge-clap.so"
	dolib.so "${BUILD_DIR}/libyabridge-chainloader-vst2.so"
	dolib.so "${BUILD_DIR}/libyabridge-chainloader-vst3.so"
	dolib.so "${BUILD_DIR}/libyabridge-chainloader-clap.so"

	# Install yabridgectl binary (built with cargo)
	dobin "${S}/tools/yabridgectl/target/release/yabridgectl"

	# Install documentation
	dodoc README.md CHANGELOG.md
}

pkg_postinst() {
	#      12345678901234567890123456789012345678901234567890123456789012345678901234567890
	einfo "wine 9.22 and later have known compatibility issues, such as the mouse cursor"
	einfo "being offset. You probably want to stick with wine 9.21 or below until a fix is"
	einfo "available."
	einfo ""
	einfo "See: https://github.com/robbert-vdh/yabridge/issues/382"
	einfo ""
	einfo "To set up yabridge for your Windows plugins:"
	einfo ""
	einfo "  1. Add your plugin directories using:"
	einfo "     yabridgectl add \"\$HOME/.wine/drive_c/Program Files/Steinberg/VstPlugins\""
	einfo "     yabridgectl add \"\$HOME/.wine/drive_c/Program Files/Common Files/VST3\""
	einfo "     yabridgectl add \"\$HOME/.wine/drive_c/Program Files/Common Files/CLAP\""
	einfo ""
	einfo "  2. Run 'yabridgectl sync' to set up yabridge for all your plugins"
	einfo ""
	einfo "Plugins will be available in:"
	einfo "  VST2: ~/.vst/yabridge"
	einfo "  VST3: ~/.vst3/yabridge"
	einfo "  CLAP: ~/.clap/yabridge"
}
