# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Amp Locker guitar amplifier simulator plugin"
HOMEPAGE="https://audioassault.mx/amplocker.php"
SRC_URI="https://audioassaultdownloads.s3.amazonaws.com/AmpLocker/AmpLocker109/AmpLockerLinux.zip -> ${P}.zip"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+lv2 +vst3"
RESTRICT="bindist mirror strip"

RDEPEND="
	media-libs/alsa-lib
	media-libs/freetype
	x11-libs/libX11
	x11-libs/libXext
	x11-libs/libXinerama
"

BDEPEND="app-arch/unzip"

S="${WORKDIR}"

QA_PREBUILT="
	opt/bin/audioassault/amplocker/Amp*Locker*Standalone
	usr/lib64/lv2/Amp*Locker.lv2/*
	usr/lib64/vst3/Amp*Locker.vst3/*
"

src_install() {
	# Install to /opt/bin/audioassault/amplocker
	local install_dir="/opt/bin/audioassault/amplocker"

	# Create installation directory
	dodir "${install_dir}"

	# Install standalone binary
	exeinto "${install_dir}"
	doexe "Amp Locker Standalone"

	# Install AmpLockerData with preserved permissions
	insinto "${install_dir}"
	doins -r AmpLockerData

	# Set writable permissions for AmpLockerData (everyone can write)
	fperms -R 0777 "${install_dir}/AmpLockerData"

	# Install LV2 plugin to system location
	if use lv2; then
		insinto /usr/lib64/lv2
		doins -r "Amp Locker.lv2"
		# Make .so files executable
		find "${ED}"/usr/lib64/lv2/"Amp Locker.lv2" -type f -name "*.so" -exec chmod +x {} \; || die
	fi

	# Install VST3 plugin to system location
	if use vst3; then
		insinto /usr/lib64/vst3
		doins -r "Amp Locker.vst3"
		# Make .so files executable
		find "${ED}"/usr/lib64/vst3/"Amp Locker.vst3" -type f \( -name "*.so" -o -type f \) -exec chmod +x {} \; || die
	fi

	# Install documentation
	if [ -f "How To Install.txt" ]; then
		dodoc "How To Install.txt"
	fi

	# Install the amplocker wrapper script from files directory
	dobin "${FILESDIR}/amplocker"
}

pkg_postinst() {
	elog "Amp Locker has been installed to system directories:"
	elog ""

	if use lv2; then
		elog "  LV2 plugin: /usr/lib64/lv2/Amp Locker.lv2"
	fi

	if use vst3; then
		elog "  VST3 plugin: /usr/lib64/vst3/Amp Locker.vst3"
	fi

	elog "  Standalone & data: /opt/bin/audioassault/amplocker"
	elog ""
	elog "To install Amp Locker to your home directory, run:"
	elog "  amplocker --install"
	elog ""
	elog "This will copy files to:"
	elog "  - ~/bin/amp-locker-standalone"
	elog "  - ~/.lv2/Amp Locker.lv2"
	elog "  - ~/.vst3/Amp Locker.vst3"
	elog "  - ~/Audio Assault/PluginData/Audio Assault/AmpLockerData"
	elog ""
	elog "To launch the standalone application, run: amplocker"
	elog "To uninstall from home directory, run: amplocker --uninstall"
	elog ""
	elog "Note: System-wide plugins in /usr/lib64 should already be"
	elog "detected by most DAWs. User installation is optional."
}
