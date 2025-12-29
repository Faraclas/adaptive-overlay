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

S="${WORKDIR}/AmpLockerLinux"

QA_PREBUILT="
	opt/amp-locker/Amp-Locker-Standalone
	opt/amp-locker/lv2/Amp-Locker.lv2/*
	opt/amp-locker/vst3/Amp-Locker.vst3/*
"

src_install() {
	# Install plugin data directory
	insinto /opt/amp-locker/data
	doins -r AmpLockerData/.

	# Set writable permissions for plugin data (user presets, IRs, etc.)
	fperms -R 0777 /opt/amp-locker/data

	# Standalone is always installed
	exeinto /opt/amp-locker
	newexe "Amp Locker Standalone" Amp-Locker-Standalone

	# Create wrapper script
	dodir /usr/bin
	cat > "${ED}"/usr/bin/amp-locker-standalone <<-EOF || die
		#!/bin/sh
		export AMPLOCKER_DATA_PATH="\${HOME}/Audio Assault/PluginData/Audio Assault/AmpLockerData"
		if [ ! -d "\${AMPLOCKER_DATA_PATH}" ]; then
			mkdir -p "\${AMPLOCKER_DATA_PATH}"
			cp -r /opt/amp-locker/data/* "\${AMPLOCKER_DATA_PATH}/"
		fi
		exec /opt/amp-locker/Amp-Locker-Standalone "\$@"
	EOF
	fperms +x /usr/bin/amp-locker-standalone

	if use lv2; then
		insinto /opt/amp-locker/lv2
		doins -r "Amp Locker.lv2"
		find "${ED}"/opt/amp-locker/lv2 -type f -name "*.so" -exec chmod +x {} \; || die
	fi

	if use vst3; then
		insinto /opt/amp-locker/vst3
		doins -r "Amp Locker.vst3"
		find "${ED}"/opt/amp-locker/vst3 -type f -name "*.so" -exec chmod +x {} \; || die
	fi

	# Install documentation
	if [ -f "How To Install.txt" ]; then
		dodoc "How To Install.txt"
	fi
}

pkg_postinst() {
	elog "Amp Locker has been installed to /opt/amp-locker"
	elog ""
	elog "The standalone application can be launched with: amp-locker-standalone"
	elog ""

	if use lv2; then
		elog "LV2 plugin installed to: /opt/amp-locker/lv2/Amp Locker.lv2"
		elog "You may need to add /opt/amp-locker/lv2 to your LV2_PATH:"
		elog "  export LV2_PATH=\"\${LV2_PATH}:/opt/amp-locker/lv2\""
		elog ""
	fi

	if use vst3; then
		elog "VST3 plugin installed to: /opt/amp-locker/vst3/Amp Locker.vst3"
		elog "You may need to add /opt/amp-locker/vst3 to your VST3_PATH:"
		elog "  export VST3_PATH=\"\${VST3_PATH}:/opt/amp-locker/vst3\""
		elog ""
	fi

	elog "Plugin data (presets, IRs, cabs) will be automatically copied to:"
	elog "  ~/Audio Assault/PluginData/Audio Assault/AmpLockerData"
	elog "on first run of the standalone application."
	elog ""
	elog "For DAW use, ensure your DAW is configured to scan the plugin directories."
}
