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
	usr/share/amp-locker/*
"

src_install() {
	# Install everything to /usr/share/amp-locker for users to copy to their home directories
	insinto /usr/share/amp-locker

	# Install plugin data
	doins -r AmpLockerData

	# Install standalone binary
	doins "Amp Locker Standalone"

	# Install LV2 plugin
	if use lv2; then
		doins -r "Amp Locker.lv2"
	fi

	# Install VST3 plugin
	if use vst3; then
		doins -r "Amp Locker.vst3"
	fi

	# Install documentation
	if [ -f "How To Install.txt" ]; then
		dodoc "How To Install.txt"
	fi

	# Create installation script for users
	exeinto /usr/bin
	newexe - amp-locker-setup <<'EOF'
#!/bin/bash
# Amp Locker User Installation Script

SHARE_DIR="/usr/share/amp-locker"
USER_BIN="${HOME}/bin"
USER_LV2="${HOME}/.lv2"
USER_VST3="${HOME}/.vst3"
USER_DATA="${HOME}/Audio Assault/PluginData/Audio Assault/AmpLockerData"

echo "Installing Amp Locker to your home directory..."

# Create directories if they don't exist
mkdir -p "${USER_BIN}"
mkdir -p "${USER_DATA}"

# Copy standalone binary
if [ -f "${SHARE_DIR}/Amp Locker Standalone" ]; then
	cp "${SHARE_DIR}/Amp Locker Standalone" "${USER_BIN}/amp-locker-standalone"
	chmod +x "${USER_BIN}/amp-locker-standalone"
	echo "✓ Installed standalone to ${USER_BIN}/amp-locker-standalone"
fi

# Copy plugin data
if [ -d "${SHARE_DIR}/AmpLockerData" ]; then
	cp -r "${SHARE_DIR}/AmpLockerData"/* "${USER_DATA}/"
	echo "✓ Installed plugin data to ${USER_DATA}"
fi

# Copy LV2 plugin
if [ -d "${SHARE_DIR}/Amp Locker.lv2" ]; then
	mkdir -p "${USER_LV2}"
	cp -r "${SHARE_DIR}/Amp Locker.lv2" "${USER_LV2}/"
	echo "✓ Installed LV2 plugin to ${USER_LV2}"
fi

# Copy VST3 plugin
if [ -d "${SHARE_DIR}/Amp Locker.vst3" ]; then
	mkdir -p "${USER_VST3}"
	cp -r "${SHARE_DIR}/Amp Locker.vst3" "${USER_VST3}/"
	echo "✓ Installed VST3 plugin to ${USER_VST3}"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Make sure ${USER_BIN} is in your PATH."
echo "You can add this to your ~/.bashrc or ~/.zshrc:"
echo '  export PATH="${HOME}/bin:${PATH}"'
echo ""
echo "Ensure your DAW is configured to scan:"
echo "  - ${USER_LV2} (for LV2 plugins)"
echo "  - ${USER_VST3} (for VST3 plugins)"
EOF

	# Create uninstall script
	newexe - amp-locker-uninstall <<'EOF'
#!/bin/bash
# Amp Locker User Uninstallation Script

USER_BIN="${HOME}/bin"
USER_LV2="${HOME}/.lv2"
USER_VST3="${HOME}/.vst3"
USER_DATA="${HOME}/Audio Assault/PluginData/Audio Assault/AmpLockerData"

echo "Removing Amp Locker from your home directory..."

# Remove standalone binary
if [ -f "${USER_BIN}/amp-locker-standalone" ]; then
	rm -f "${USER_BIN}/amp-locker-standalone"
	echo "✓ Removed standalone from ${USER_BIN}"
fi

# Remove plugin data
if [ -d "${USER_DATA}" ]; then
	read -p "Remove plugin data (presets, IRs, etc.)? [y/N] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		rm -rf "${USER_DATA}"
		echo "✓ Removed plugin data"
	else
		echo "  Keeping plugin data at ${USER_DATA}"
	fi
fi

# Remove LV2 plugin
if [ -d "${USER_LV2}/Amp Locker.lv2" ]; then
	rm -rf "${USER_LV2}/Amp Locker.lv2"
	echo "✓ Removed LV2 plugin"
fi

# Remove VST3 plugin
if [ -d "${USER_VST3}/Amp Locker.vst3" ]; then
	rm -rf "${USER_VST3}/Amp Locker.vst3"
	echo "✓ Removed VST3 plugin"
fi

echo ""
echo "Uninstallation complete!"
EOF
}

pkg_postinst() {
	elog "Amp Locker has been installed to /usr/share/amp-locker"
	elog ""
	elog "To install Amp Locker to your home directory, run:"
	elog "  amp-locker-setup"
	elog ""
	elog "This will copy the files to:"
	elog "  - Standalone: ~/bin/amp-locker-standalone"
	elog "  - Plugin data: ~/Audio Assault/PluginData/Audio Assault/AmpLockerData"

	if use lv2; then
		elog "  - LV2 plugin: ~/.lv2/Amp Locker.lv2"
	fi

	if use vst3; then
		elog "  - VST3 plugin: ~/.vst3/Amp Locker.vst3"
	fi

	elog ""
	elog "Make sure ~/bin is in your PATH, and configure your DAW to scan"
	elog "the ~/.lv2 and ~/.vst3 directories for plugins."
	elog ""
	elog "To uninstall from your home directory, run: amp-locker-uninstall"
}
