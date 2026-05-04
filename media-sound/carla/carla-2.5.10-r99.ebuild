# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{10..14} )
MY_PN="Carla"
MY_COMMIT="97a9e0740baf6df2df942495c02532a624c44682"
MY_P="${MY_PN}-${MY_COMMIT}"

inherit python-single-r1 xdg

DESCRIPTION="Fully-featured audio plugin host, supports many audio drivers and plugin formats"
HOMEPAGE="https://kx.studio/Applications:Carla"
SRC_URI="https://github.com/falkTX/Carla/archive/${MY_COMMIT}.tar.gz -> ${PF}.tar.gz"
S="${WORKDIR}/${MY_P}"
LICENSE="GPL-2 LGPL-3"
SLOT="0"
KEYWORDS=""
IUSE="+alsa +gtk +opengl osc +pulseaudio +qt6 rdf +sf2 sndfile +X abi_x86_32 wine wine32"
REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	abi_x86_32? ( !osc )
"

DEPEND="
	${PYTHON_DEPS}
	virtual/jack
	alsa? ( media-libs/alsa-lib )
	gtk? ( x11-libs/gtk+:3 )
	osc? ( media-libs/liblo )
	pulseaudio? ( media-libs/libpulse )
	qt6? (
		$(python_gen_cond_dep 'dev-python/pyqt6[gui,opengl?,svg,widgets,${PYTHON_USEDEP}]')
		dev-qt/qtbase:6[gui,widgets]
		virtual/opengl
		x11-libs/libXcursor
		x11-libs/libXext
		x11-libs/libXrandr
	)
	rdf? ( dev-python/rdflib )
	sf2? ( media-sound/fluidsynth )
	sndfile? ( media-libs/libsndfile )
	X? ( x11-libs/libX11 )
"
RDEPEND="${DEPEND}
	wine? ( app-emulation/wine-staging )
	wine32? ( app-emulation/wine-staging[abi_x86_32(-)] )
"
BDEPEND="
	wine? (
		dev-util/mingw64-toolchain
		app-emulation/wine-staging
	)
	wine32? (
		dev-util/mingw64-toolchain[abi_x86_32]
		app-emulation/wine-staging[abi_x86_32(-)]
	)
"

PATCHES=(
	"${FILESDIR}"/carla-2.5.9-gtk.patch
)

src_prepare() {
	local wrapper

	# Add Wine bridge patch when wine or wine32 USE flag is enabled
	if use wine || use wine32; then
		PATCHES+=( "${FILESDIR}"/carla-2.5.10-no-lssp.patch )
	fi

	for wrapper in \
		data/carla \
		data/carla-control \
		data/carla-database \
		data/carla-jack-multi \
		data/carla-jack-patchbayplugin \
		data/carla-jack-single \
		data/carla-osc-gui \
		data/carla-patchbay \
		data/carla-rack \
		data/carla-settings
	do
		[ -f "${wrapper}" ] || continue
		sed -i -e "s|exec \$PYTHON|exec ${PYTHON}|" "${wrapper}" || die "sed failed for ${wrapper}"
	done

	sed -i "s;/share/appdata;/share/metainfo;g" "${S}/Makefile" || die "sed failed"
	default
}

src_compile() {
	local frontend_type=""

	if use qt6; then
		frontend_type=6
	fi

	myemakeargs=(
		LIBDIR="/usr/$(get_libdir)"
		SKIP_STRIPPING=true
		HAVE_FFMPEG=false
		HAVE_FRONTEND=$(usex qt6 true false)
		HAVE_PYQT=$(usex qt6 true false)
		FRONTEND_TYPE="${frontend_type}"
		HAVE_ZYN_DEPS=false
		HAVE_ZYN_UI_DEPS=false
		HAVE_QT4=false
		HAVE_QT5=false
		HAVE_QT5PKG=false
		HAVE_QT5BREW=false
		HAVE_QT6=$(usex qt6 true false)
		HAVE_QT6BREW=false
		HAVE_THEME=$(usex qt6 true false)
		HAVE_ALSA=$(usex alsa true false)
		HAVE_FLUIDSYNTH=$(usex sf2 true false)
		HAVE_GTK2=false
		HAVE_GTK3=$(usex gtk true false)
		HAVE_LIBLO=$(usex osc true false)
		HAVE_PULSEAUDIO=$(usex pulseaudio true false)
		HAVE_SNDFILE=$(usex sndfile true false)
		HAVE_X11=$(usex X true false)
	)

	# Print which options are enabled/disabled
	emake features PREFIX="/usr" "${myemakeargs[@]}"

	# Build main native target
	emake PREFIX="/usr" "${myemakeargs[@]}"

	# Build Linux 32-bit bridge (for running 32-bit Linux plugins on 64-bit)
	if use abi_x86_32; then
		einfo "Building Linux 32-bit bridge (posix32)..."
		emake PREFIX="/usr" "${myemakeargs[@]}" posix32
	fi

	# Build Wine 32-bit bridge (for running Windows 32-bit VST plugins)
	if use wine32; then
		einfo "Building Wine 32-bit bridge for Windows plugin support..."

		# Build the jackbridge Wine 32-bit DLL (needed for Wine plugin communication)
		emake PREFIX="/usr" "${myemakeargs[@]}" wine32

		# Build the Windows 32-bit bridge using mingw cross-compiler
		# Unset LDFLAGS - MinGW doesn't understand Gentoo hardening flags (-z relro, etc.)
		einfo "Building Windows 32-bit bridge (win32)..."
		LDFLAGS="" emake \
			PREFIX="/usr" \
			"${myemakeargs[@]}" \
			AR=i686-w64-mingw32-ar \
			CC=i686-w64-mingw32-gcc \
			CXX=i686-w64-mingw32-g++ \
			win32
	fi

	# Build Wine 64-bit bridge (for running Windows 64-bit VST plugins)
	if use wine; then
		einfo "Building Wine 64-bit bridge for Windows plugin support..."

		# Build the jackbridge Wine 64-bit DLL (needed for Wine plugin communication)
		emake PREFIX="/usr" "${myemakeargs[@]}" wine64

		# Build the Windows 64-bit bridge using mingw cross-compiler
		# Unset LDFLAGS - MinGW doesn't understand Gentoo hardening flags (-z relro, etc.)
		einfo "Building Windows 64-bit bridge (win64)..."
		LDFLAGS="" emake \
			PREFIX="/usr" \
			"${myemakeargs[@]}" \
			AR=x86_64-w64-mingw32-ar \
			CC=x86_64-w64-mingw32-gcc \
			CXX=x86_64-w64-mingw32-g++ \
			win64
	fi
}

src_install() {
	emake DESTDIR="${D}" PREFIX="/usr" LIBDIR="/usr/$(get_libdir)" "${myemakeargs[@]}" install
	find "${D}/usr" -iname "carla-control*" -delete
}
