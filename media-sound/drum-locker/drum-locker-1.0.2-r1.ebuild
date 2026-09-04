# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Drum Locker drum machine plugin"
HOMEPAGE="https://audioassault.mx/drumlocker.php"
SRC_URI="https://audioassaultdownloads.s3.amazonaws.com/AmpLocker/AmpLocker109/DrumLockerLinux.zip -> ${P}.zip"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+lv2 +vst3"
RESTRICT="bindist mirror strip"

RDEPEND="
	media-sound/amp-locker
"

BDEPEND="app-arch/unzip"

S="${WORKDIR}"

QA_PREBUILT="
	usr/lib64/lv2/Drum*Locker.lv2/*
	usr/lib64/vst3/Drum*Locker.vst3/*
"

src_install() {
	# Install to /opt/bin/audioassault/drumlocker
	local install_dir="/opt/bin/audioassault/drumlocker"

	# Create installation directory
	dodir "${install_dir}"

	# Install DrumLockerData with preserved permissions
	insinto "${install_dir}"
	doins -r DrumLockerData

	# Set writable permissions for DrumLockerData (everyone can write)
	fperms -R 0777 "${install_dir}/DrumLockerData"

	# Install LV2 plugin to system location
	if use lv2; then
		insinto /usr/lib64/lv2
		doins -r "Drum Locker.lv2"
		# Make .so files executable
		find "${ED}"/usr/lib64/lv2/"Drum Locker.lv2" -type f -name "*.so" -exec chmod +x {} \; || die
	fi

	# Install VST3 plugin to system location
	if use vst3; then
		insinto /usr/lib64/vst3
		doins -r "Drum Locker.vst3"
		# Make .so files executable
		find "${ED}"/usr/lib64/vst3/"Drum Locker.vst3" -type f \( -name "*.so" -o -type f \) -exec chmod +x {} \; || die
	fi

	# Install documentation if available
	if [ -f "How To Install.txt" ]; then
		dodoc "How To Install.txt"
	fi

	# Install the drumlocker wrapper script from files directory
	dobin "${FILESDIR}/drumlocker"
}

pkg_postinst() {
	elog "Drum Locker has been installed to system directories:"
	elog ""

	if use lv2; then
		elog "  LV2 plugin: /usr/lib64/lv2/Drum Locker.lv2"
	fi

	if use vst3; then
		elog "  VST3 plugin: /usr/lib64/vst3/Drum Locker.vst3"
	fi

	elog "  Plugin data: /opt/bin/audioassault/drumlocker"
	elog ""
	elog "To install Drum Locker to your home directory, run:"
	elog "  drumlocker --install"
	elog ""
	elog "This will copy files to:"
	elog "  - ~/.lv2/Drum Locker.lv2"
	elog "  - ~/.vst3/Drum Locker.vst3"
	elog "  - ~/Audio Assault/PluginData/Audio Assault/DrumLockerData"
	elog ""
	elog "To uninstall from home directory, run: drumlocker --uninstall"
	elog ""
	elog "Note: System-wide plugins in /usr/lib64 should already be"
	elog "detected by most DAWs. User installation is optional."
}
