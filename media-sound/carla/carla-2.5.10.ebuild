# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{10..14} )
MY_PN="Carla"
MY_P="${MY_PN}-${PV}"

inherit python-single-r1 xdg

DESCRIPTION="Fully-featured audio plugin host, supports many audio drivers and plugin formats"
HOMEPAGE="https://kx.studio/Applications:Carla"
SRC_URI="https://github.com/falkTX/Carla/archive/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_P}"
LICENSE="GPL-2 LGPL-3"
SLOT="0"
KEYWORDS="amd64 x86"
IUSE="+alsa +gtk +opengl osc +pulseaudio qt5 rdf +sf2 sndfile +X abi_x86_32 wine wine32"
REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	abi_x86_32? ( !osc )
"

DEPEND="
	${PYTHON_DEPS}
	$(python_gen_cond_dep 'dev-python/pyqt5[gui,opengl?,svg,widgets,${PYTHON_USEDEP}]')
	virtual/jack
	alsa? ( media-libs/alsa-lib )
	gtk? ( x11-libs/gtk+:3 )
	osc? ( media-libs/liblo )
	pulseaudio? ( media-libs/libpulse )
	qt5? (
		dev-qt/qtcore:5
		dev-qt/qtgui:5
		dev-qt/qtwidgets:5
	)
	rdf? ( dev-python/rdflib )
	sf2? ( media-sound/fluidsynth )
	sndfile? ( media-libs/libsndfile )
	X? ( x11-libs/libX11 )
"
RDEPEND="${DEPEND}
	wine? ( app-emulation/wine-staging )
	wine32? ( app-emulation/wine-staging )
"
BDEPEND="
	wine? ( dev-util/mingw64-toolchain )
	wine32? ( dev-util/mingw64-toolchain[abi_x86_32] )
"

PATCHES=(
	"${FILESDIR}"/carla-2.5.9-gtk.patch
)

src_prepare() {
	# Add Wine bridge patch when wine or wine32 USE flag is enabled
	if use wine || use wine32; then
		PATCHES+=( "${FILESDIR}"/carla-2.5.10-no-lssp.patch )
	fi

	sed -i -e "s|exec \$PYTHON|exec ${PYTHON}|" \
		data/carla \
		data/carla-control \
		data/carla-database \
		data/carla-jack-multi \
		data/carla-jack-single \
		data/carla-patchbay \
		data/carla-rack \
		data/carla-settings || die "sed failed"
	sed -i "s;/share/appdata;/share/metainfo;g" "${S}/Makefile" || die "sed failed"
	default
}

src_compile() {
	local myemakeargs=(
		LIBDIR="/usr/$(get_libdir)"
		SKIP_STRIPPING=true
		HAVE_FFMPEG=false
		HAVE_ZYN_DEPS=false
		HAVE_ZYN_UI_DEPS=false
		HAVE_QT4=false
		HAVE_QT5=$(usex qt5 true false)
		HAVE_THEME=$(usex qt5 true false)
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
		emake posix32
	fi

	# Build Wine 32-bit bridge (for running Windows 32-bit VST plugins)
	if use wine32; then
		einfo "Building Wine 32-bit bridge for Windows plugin support..."

		# Build the jackbridge Wine 32-bit DLL (needed for Wine plugin communication)
		emake wine32

		# Build the Windows 32-bit bridge using mingw cross-compiler
		# Unset LDFLAGS - MinGW doesn't understand Gentoo hardening flags (-z relro, etc.)
		einfo "Building Windows 32-bit bridge (win32)..."
		LDFLAGS="" emake \
			AR=i686-w64-mingw32-ar \
			CC=i686-w64-mingw32-gcc \
			CXX=i686-w64-mingw32-g++ \
			win32
	fi

	# Build Wine 64-bit bridge (for running Windows 64-bit VST plugins)
	if use wine; then
		einfo "Building Wine 64-bit bridge for Windows plugin support..."

		# Build the jackbridge Wine 64-bit DLL (needed for Wine plugin communication)
		emake wine64

		# Build the Windows 64-bit bridge using mingw cross-compiler
		# Unset LDFLAGS - MinGW doesn't understand Gentoo hardening flags (-z relro, etc.)
		einfo "Building Windows 64-bit bridge (win64)..."
		LDFLAGS="" emake \
			AR=x86_64-w64-mingw32-ar \
			CC=x86_64-w64-mingw32-gcc \
			CXX=x86_64-w64-mingw32-g++ \
			win64
	fi
}

src_install() {
	emake DESTDIR="${D}" PREFIX="/usr" LIBDIR="/usr/$(get_libdir)" install
	find "${D}/usr" -iname "carla-control*" -delete
}
