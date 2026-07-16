# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo git-r3 systemd

DESCRIPTION="A self-hosted, highly accurate, and GPU-accelerated voice dictation pipeline"
HOMEPAGE="https://github.com/Faraclas/ai-voice-server"
EGIT_REPO_URI="https://github.com/Faraclas/ai-voice-server.git"

LICENSE="MIT"
SLOT="0"
KEYWORDS=""
IUSE="+client +server +vulkan +nvidia rocm"
REQUIRED_USE="|| ( client server )"

# Allow cargo to download dependencies during src_compile for 9999 live ebuilds
PROPERTIES="live"

DEPEND="
	client? (
		gui-libs/gtk4-layer-shell
		app-misc/interception-tools
		x11-misc/ydotool
		media-video/pipewire
	)
	nvidia? (
		>=dev-util/nvidia-cuda-toolkit-12.0
		x11-drivers/nvidia-drivers
	)
"
RDEPEND="${DEPEND}"

src_unpack() {
	git-r3_src_unpack
}

src_compile() {
	if use server; then
		if use nvidia; then
			einfo "Building Server (CUDA)..."
			cd "${S}/src/server" || die
			cargo build --release --features nvidia || die "Failed to build CUDA server"
			mv target/release/server target/release/ai-voice-server-cuda || die
		fi

		if use vulkan; then
			einfo "Building Server (Vulkan)..."
			cd "${S}/src/server" || die
			cargo build --release --features vulkan || die "Failed to build Vulkan server"
			mv target/release/server target/release/ai-voice-server-vulkan || die
		fi

		if use rocm; then
			einfo "Building Server (ROCm)..."
			cd "${S}/src/server" || die
			cargo build --release --features rocm || die "Failed to build ROCm server"
			mv target/release/server target/release/ai-voice-server-rocm || die
		fi

		# Always build a pure CPU fallback if no GPU backend is explicitly requested
		if ! use nvidia && ! use vulkan && ! use rocm; then
			einfo "Building Server (Pure CPU)..."
			cd "${S}/src/server" || die
			cargo build --release || die "Failed to build CPU server"
			mv target/release/server target/release/ai-voice-server-cpu || die
		fi
	fi

	if use client; then
		einfo "Building Client and Plugins..."
		cd "${S}/src/client" || die
		# This workspace builds both 'daemon' and 'interception_plugin'
		cargo build --release || die "Failed to build client"
	fi
}

src_install() {
	if use server; then
		use nvidia && dobin "${S}/src/server/target/release/ai-voice-server-cuda"
		use vulkan && dobin "${S}/src/server/target/release/ai-voice-server-vulkan"
		use rocm && dobin "${S}/src/server/target/release/ai-voice-server-rocm"
		if ! use nvidia && ! use vulkan && ! use rocm; then
			dobin "${S}/src/server/target/release/ai-voice-server-cpu"
		fi
		# Install the wrapper script as the primary entrypoint
		exeinto /usr/bin
		newexe "${S}/packaging/ai-voice-server.sh" ai-voice-server

		# Install systemd service and config
		systemd_dounit "${S}/packaging/systemd/ai-voice-server.service"
		newconfd "${S}/packaging/systemd/ai-voice-server.conf" ai-voice-server
	fi

	if use client; then
		# Install main client (renaming from 'daemon' to 'ai-voice-client')
		newbin "${S}/src/client/target/release/daemon" ai-voice-client

		# Install plugin
		dobin "${S}/src/client/target/release/interception_plugin"

		# Install systemd user service
		systemd_douserunit "${S}/packaging/systemd/ai-voice-client.service"

		# Install udevmon config
		insinto /etc/interception/udevmon.d
		doins "${S}/packaging/systemd/udevmon.yaml"
	fi
}

pkg_postinst() {
	if use client; then
		elog "====================================================================="
		elog "To use the kernel-level dictation hotkey and auto-typing, you must"
		elog "enable and start the required root daemons on your system:"
		elog ""
		elog "  sudo systemctl enable --now udevmon ydotoold"
		elog ""
		elog "The AI Voice Client overlay will start automatically on login via"
		elog "the installed systemd user service (ai-voice-client.service)."
		elog "====================================================================="
	fi
}
