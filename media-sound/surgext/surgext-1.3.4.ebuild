# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake desktop xdg

PATCHES=(
	"${FILESDIR}/${P}-fix-visibility.patch"
)

MY_PN="surge"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Powerful and open-source hybrid synthesizer"
HOMEPAGE="https://surge-synthesizer.github.io/"
SRC_URI="https://github.com/Faraclas/adaptive-overlay/releases/download/surgext-${PV}/${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+clap +lv2 +vst3 +standalone"
REQUIRED_USE="|| ( clap lv2 vst3 standalone )"

# Build dependencies
DEPEND="
	dev-util/cmake
	x11-libs/cairo
	x11-libs/libxkbcommon[X]
	x11-libs/libxcb
	x11-libs/xcb-util-cursor
	x11-libs/xcb-util-keysyms
	x11-libs/libXrandr
	x11-libs/libXinerama
	x11-libs/libXcursor
	media-libs/alsa-lib
	standalone? (
		virtual/jack
		net-misc/curl
		net-libs/webkit-gtk:4
		x11-libs/gtk+:3
	)
"

# Runtime dependencies
RDEPEND="
	${DEPEND}
	media-libs/fontconfig
	media-libs/freetype
	x11-libs/libX11
	x11-misc/xdg-utils
	x11-misc/xclip
"

BDEPEND="
	dev-vcs/git
"

S="${WORKDIR}/surge-${PV}"

src_configure() {
	local mycmakeargs=(
		-DCMAKE_BUILD_TYPE=Release
		-DSURGE_BUILD_LV2=$(usex lv2 ON OFF)
		-DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON
	)

	cmake_src_configure
}

src_compile() {
	cmake_src_compile surge-staged-assets
}

src_install() {
	# Install standalone executables if built
	if use standalone; then
		exeinto /usr/bin
		newexe "${BUILD_DIR}/surge_xt_products/Surge XT" "surge-xt"
		newexe "${BUILD_DIR}/surge_xt_products/Surge XT Effects" "surge-xt-effects"
		doexe "${BUILD_DIR}/surge_xt_products/surge-xt-cli"
	fi

	# Install plugin formats based on USE flags
	if use clap; then
		insinto /usr/$(get_libdir)/clap
		doins "${BUILD_DIR}/surge_xt_products/Surge XT.clap"
		doins "${BUILD_DIR}/surge_xt_products/Surge XT Effects.clap"
	fi

	if use lv2; then
		insinto /usr/$(get_libdir)/lv2
		doins -r "${BUILD_DIR}/surge_xt_products/Surge XT.lv2"
		doins -r "${BUILD_DIR}/surge_xt_products/Surge XT Effects.lv2"
	fi

	if use vst3; then
		insinto /usr/$(get_libdir)/vst3
		doins -r "${BUILD_DIR}/surge_xt_products/Surge XT.vst3"
		doins -r "${BUILD_DIR}/surge_xt_products/Surge XT Effects.vst3"
	fi

	# Install desktop files for standalone
	if use standalone; then
		domenu "${S}/scripts/installer_linux/assets/applications/Surge-XT.desktop"
		domenu "${S}/scripts/installer_linux/assets/applications/Surge-XT-FX.desktop"
	fi

	# Install icons
	local icon_sizes=(16 32 48 64 128 256 384 512)
	for size in "${icon_sizes[@]}"; do
		newicon -s ${size} "${S}/scripts/installer_linux/assets/icons/hicolor/${size}x${size}/apps/surge-xt.png" surge-xt.png
	done

	# Install shared data (presets, skins, wavetables, etc.)
	insinto /usr/share/surge-xt
	doins -r "${S}/resources/data"/*

	# Install documentation
	dodoc README.md
	dodoc AUTHORS
	if [[ -f "${S}/doc/Changelog.md" ]]; then
		dodoc "${S}/doc/Changelog.md"
	fi
}

pkg_postinst() {
	xdg_icon_cache_update

	elog "Surge XT has been installed successfully!"
	elog ""
	if use standalone; then
		elog "The following standalone components are available:"
		elog "  - surge-xt (full synthesizer)"
		elog "  - surge-xt-effects (effects-only version)"
		elog "  - surge-xt-cli (command-line interface)"
		elog ""
	fi
	elog "Plugin formats installed:"
	use clap && elog "  - CLAP: /usr/$(get_libdir)/clap/"
	use lv2 && elog "  - LV2: /usr/$(get_libdir)/lv2/"
	use vst3 && elog "  - VST3: /usr/$(get_libdir)/vst3/"
	elog ""
	elog "Factory content is located at: /usr/share/surge-xt/"
	elog ""
	elog "User data (custom presets, patches, skins, etc.) should be placed in:"
	elog "  ~/.local/share/surge-xt/"
}

pkg_postrm() {
	xdg_icon_cache_update
}
