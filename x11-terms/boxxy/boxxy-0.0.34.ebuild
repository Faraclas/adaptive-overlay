# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo desktop xdg git-r3

DESCRIPTION="Modern terminal emulator with AI assistant built with Rust and GTK 4"
HOMEPAGE="https://github.com/boxxy-dev/boxxy"
EGIT_REPO_URI="https://github.com/boxxy-dev/boxxy.git"
EGIT_COMMIT="0.0.34"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# According to Cargo.toml and build failure, it requires GTK 4.21+ (features v4_22)
# and Libadwaita 1.9
RDEPEND="
	>=gui-libs/gtk-4.21:4
	>=gui-libs/libadwaita-1.9
	gui-libs/gtksourceview:5
	media-libs/gstreamer:1.0
	dev-db/sqlite:3
	dev-libs/openssl:0/3
"
DEPEND="${RDEPEND}"
BDEPEND="
	virtual/pkgconfig
	dev-util/glib-utils
"

QA_FLAGS_IGNORED="usr/bin/boxxy-terminal usr/bin/boxxy-agent"

src_unpack() {
	git-r3_src_unpack
	cargo_live_src_unpack
}

src_prepare() {
	default
}

src_configure() {
	cargo_src_configure
}

src_compile() {
	cargo_src_compile --workspace
}

src_install() {
	# Install binaries
	cargo_src_install

	# Create a symlink for the short name
	dosym boxxy-terminal /usr/bin/boxxy

	# Install desktop file
	newmenu flatpak/dev.boxxy.BoxxyTerminal.desktop dev.boxxy.BoxxyTerminal.desktop

	# Install icons
	local size
	for size in 16 24 32 48 64 128 256 512; do
		if [[ -d "resources/icons/${size}x${size}" ]]; then
			doicon -s "${size}" "resources/icons/${size}x${size}/apps/dev.boxxy.BoxxyTerminal.png"
		fi
	done
	if [[ -f "resources/icons/scalable/apps/dev.boxxy.BoxxyTerminal.svg" ]]; then
		doicon -s scalable "resources/icons/scalable/apps/dev.boxxy.BoxxyTerminal.svg"
	fi
}
