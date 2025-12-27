# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Powerful and open-source hybrid synthesizer"
HOMEPAGE="https://surge-synthesizer.github.io/"
SRC_URI="https://github.com/surge-synthesizer/releases-xt/releases/download/${PV}/${PN}-linux-x86_64-${PV}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="clap lv2 vst3"
REQUIRED_USE="|| ( clap lv2 vst3 )"

# Runtime dependencies for the synthesizer (from .deb package)
RDEPEND="
	>=sys-libs/glibc-2.27
	x11-libs/cairo
	media-libs/fontconfig
	media-libs/freetype
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/xcb-util-cursor
	x11-libs/libxkbcommon[X]
	x11-misc/xdg-utils
	x11-misc/xclip
"

S="${WORKDIR}/${PN}-linux-x86_64-${PV}"

QA_PREBUILT="
	usr/bin/*
	usr/lib*/clap/*.clap
	usr/lib*/lv2/*.lv2/*
	usr/lib*/vst3/*.vst3/*
"

src_install() {
	# Install executables
	exeinto /usr/bin
	doexe "bin/Surge XT"
	doexe "bin/Surge XT Effects"
	doexe "bin/surge-xt-cli"

	# Install plugin formats based on USE flags
	if use clap; then
		exeinto /usr/$(get_libdir)/clap
		doexe lib/clap/"Surge XT.clap"
		doexe lib/clap/"Surge XT Effects.clap"
	fi

	if use lv2; then
		insinto /usr/$(get_libdir)/lv2
		doins -r lib/lv2/"Surge XT.lv2"
		doins -r lib/lv2/"Surge XT Effects.lv2"
		# Make the .so files executable
		fperms +x /usr/$(get_libdir)/lv2/"Surge XT.lv2"/Surge_XT.so
		fperms +x /usr/$(get_libdir)/lv2/"Surge XT Effects.lv2"/Surge_XT_Effects.so
	fi

	if use vst3; then
		insinto /usr/$(get_libdir)/vst3
		doins -r lib/vst3/"Surge XT.vst3"
		doins -r lib/vst3/"Surge XT Effects.vst3"
		# Make the .so files executable
		fperms +x /usr/$(get_libdir)/vst3/"Surge XT.vst3"/Contents/x86_64-linux/Surge_XT.so
		fperms +x /usr/$(get_libdir)/vst3/"Surge XT Effects.vst3"/Contents/x86_64-linux/Surge_XT_Effects.so
	fi

	# Install desktop files
	domenu share/applications/Surge-XT.desktop
	domenu share/applications/Surge-XT-FX.desktop

	# Install icons
	insinto /usr/share/icons
	doins -r share/icons/hicolor
	doins -r share/icons/scalable

	# Install shared data (presets, skins, wavetables, etc.)
	insinto /usr/share/surge-xt
	doins -r share/surge-xt/*

	# Install documentation
	dodoc share/surge-xt/doc/Changelog_*.md
	dodoc share/surge-xt/doc/copyright
	dodoc share/surge-xt/"WHERE TO PLACE USER DATA.txt"
}

pkg_postinst() {
	xdg_icon_cache_update

	elog "Surge XT has been installed successfully!"
	elog ""
	elog "The following components are available:"
	elog "  - Surge XT (full synthesizer)"
	elog "  - Surge XT Effects (effects-only version)"
	elog "  - surge-xt-cli (command-line interface)"
	elog ""
	elog "Plugin formats installed:"
	use clap && elog "  - CLAP: /usr/$(get_libdir)/clap/"
	use lv2 && elog "  - LV2: /usr/$(get_libdir)/lv2/"
	use vst3 && elog "  - VST3: /usr/$(get_libdir)/vst3/"
	elog ""
	elog "Factory content is located at: /usr/share/surge-xt/"
	elog ""
	elog "For information about where to place user data (custom presets,"
	elog "patches, skins, etc.), see:"
	elog "  /usr/share/doc/${PF}/WHERE TO PLACE USER DATA.txt"
}

pkg_postrm() {
	xdg_icon_cache_update
}
