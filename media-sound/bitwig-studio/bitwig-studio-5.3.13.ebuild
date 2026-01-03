# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

DESCRIPTION="Multi-platform music-creation system for production, performance and DJing"
HOMEPAGE="https://bitwig.com"
SRC_URI="https://www.bitwig.com/dl/Bitwig%20Studio/${PV}/installer_linux/ -> ${P}.deb"
LICENSE="Bitwig"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror"

IUSE="+abi_x86_32 +ffmpeg +jack-sdk jack-client"
REQUIRED_USE="|| ( jack-sdk jack-client )"

DEPEND=""
RDEPEND="${DEPEND}
	dev-libs/expat
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	sys-libs/zlib
	ffmpeg? ( media-video/ffmpeg )
	jack-client? ( media-sound/jack2 )
	jack-sdk? ( media-video/pipewire[jack-sdk] )
	x11-libs/cairo[X]
	x11-libs/libX11[abi_x86_32?]
	x11-libs/libXau[abi_x86_32?]
	x11-libs/libXcursor
	x11-libs/libXdmcp[abi_x86_32?]
	x11-libs/libXfixes
	x11-libs/libXrender
	x11-libs/libxcb[abi_x86_32?]
	x11-libs/xcb-util-wm[abi_x86_32?]
	x11-libs/libxkbcommon[X,abi_x86_32?]
	x11-libs/pixman[abi_x86_32?]
	x11-libs/xcb-imdkit
	x11-libs/xcb-util[abi_x86_32?]
	x11-misc/xdg-utils
"

QA_PREBUILT="
	opt/bitwig-studio/BitwigStudio
	opt/bitwig-studio/bitwig-studio
	opt/bitwig-studio/bin/*
	opt/bitwig-studio/lib/*
"

S="${WORKDIR}"

src_prepare() {
	default

	# Modify desktop file to use correct categories and remove Version field
	sed -i \
		-e 's/Categories=.*/Categories=AudioVideo;Audio;AudioVideoEditing/' \
		-e '/Version=1.5/d' \
		usr/share/applications/com.bitwig.BitwigStudio.desktop || die 'sed on desktop file failed'
}

src_install() {
	# Install main application to /opt
	dodir /opt
	cp -a opt/bitwig-studio "${ED}"/opt || die "cp failed"

	# Remove bundled ffmpeg if using system version
	if use ffmpeg; then
		rm -f "${ED}"/opt/bitwig-studio/bin/ffmpeg || die
		rm -f "${ED}"/opt/bitwig-studio/bin/ffprobe || die
	fi

	# Remove 32-bit plugin host if USE flag is not set
	if ! use abi_x86_32; then
		rm "${ED}/opt/bitwig-studio/bin/BitwigPluginHost-X86-SSE41" || die
	fi

	# Create symlink to launch binary
	dosym ../../opt/bitwig-studio/bitwig-studio /usr/bin/bitwig-studio

	# Install desktop file
	domenu usr/share/applications/com.bitwig.BitwigStudio.desktop

	# Install icons
	doicon -s scalable usr/share/icons/hicolor/scalable/apps/com.bitwig.BitwigStudio.svg
	doicon -s 48 usr/share/icons/hicolor/48x48/apps/com.bitwig.BitwigStudio.png
	doicon -s 128 usr/share/icons/hicolor/128x128/apps/com.bitwig.BitwigStudio.png

	# Install MIME type icons
	doicon -s scalable -c mimetypes usr/share/icons/hicolor/scalable/mimetypes/*.svg

	# Install MIME type definitions
	insinto /usr/share/mime/packages
	doins usr/share/mime/packages/com.bitwig.BitwigStudio.xml
}

pkg_postinst() {
	xdg_icon_cache_update
	xdg_desktop_database_update
	xdg_mimeinfo_database_update

	elog "Bitwig Studio ${PV} has been installed to /opt/bitwig-studio"
	elog ""
	elog "To launch Bitwig Studio, run: bitwig-studio"
	elog ""
	elog "Audio backend:"
	if use jack-sdk; then
		elog "  - Using PipeWire with JACK SDK (default, recommended)"
	elif use jack-client; then
		elog "  - Using JACK2 (traditional JACK)"
	fi
	elog ""
	if use ffmpeg; then
		elog "Using system ffmpeg (recommended for security updates)."
	else
		elog "Using bundled ffmpeg from Bitwig."
	fi
	elog ""
	if use abi_x86_32; then
		elog "32-bit plugin bridging is enabled (default)."
	else
		elog "32-bit plugin bridging is disabled. To enable it, remove"
		elog "'-abi_x86_32' USE flag and rebuild."
	fi
	elog ""
	elog "For support and documentation, visit:"
	elog "  https://www.bitwig.com/support/"
}

pkg_postrm() {
	xdg_icon_cache_update
	xdg_desktop_database_update
	xdg_mimeinfo_database_update
}
