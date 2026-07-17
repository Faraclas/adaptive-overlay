# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

RUST_MIN_VER="1.85.0"
inherit cargo git-r3 systemd

DESCRIPTION="A self-hosted, highly accurate, and GPU-accelerated voice dictation pipeline"
HOMEPAGE="https://github.com/Faraclas/ai-voice-server"
EGIT_REPO_URI="https://github.com/Faraclas/ai-voice-server.git"
SRC_URI="server? ( https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin -> small.en.bin )"
LICENSE="MIT"
SLOT="0"
KEYWORDS=""
IUSE="+client +server +vulkan +nvidia rocm"
REQUIRED_USE="|| ( client server )"

# Allow cargo to download dependencies during src_compile for 9999 live ebuilds
PROPERTIES="live"
RESTRICT="network-sandbox"

DEPEND="
	server? (
		acct-group/aivoice
		acct-user/aivoice
	)
	client? (
		gui-libs/gtk4-layer-shell
		app-misc/interception-tools
		x11-misc/ydotool
		media-video/pipewire
	)
	nvidia? (
		>=dev-util/nvidia-cuda-toolkit-13.0
		x11-drivers/nvidia-drivers
	)
"
RDEPEND="${DEPEND}"



src_unpack() {
	git-r3_src_unpack

	# Fetch cargo dependencies while the network sandbox is open
	if use server; then
		cd "${S}/src/server" || die
		cargo fetch || die
	fi
	
	if use client; then
		cd "${S}/src/client" || die
		cargo fetch || die
	fi
}

src_compile() {
	if use server; then
		cd "${S}/src/server" || die

		if use nvidia; then
			einfo "Building Server (CUDA)..."
			cargo build --release --offline --features nvidia || die "Failed to build CUDA server"
			mv target/release/server target/release/ai-voice-server-cuda || die
		fi

		if use vulkan; then
			einfo "Building Server (Vulkan)..."
			cargo build --release --offline --features vulkan || die "Failed to build Vulkan server"
			mv target/release/server target/release/ai-voice-server-vulkan || die
		fi

		if use rocm; then
			einfo "Building Server (ROCm)..."
			cargo build --release --offline --features rocm || die "Failed to build ROCm server"
			mv target/release/server target/release/ai-voice-server-rocm || die
		fi

		# Always build a pure CPU fallback if no GPU backend is explicitly requested
		if ! use nvidia && ! use vulkan && ! use rocm; then
			einfo "Building Server (Pure CPU)..."
			cargo build --release --offline || die "Failed to build CPU server"
			mv target/release/server target/release/ai-voice-server-cpu || die
		fi
	fi

	if use client; then
		einfo "Building Client and Plugins..."
		cd "${S}/src/client" || die
		# This workspace builds both 'daemon' and 'interception_plugin'
		cargo build --release --offline || die "Failed to build client"
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

		# Install models and set ownership
		insinto /var/lib/ai-voice-server/models
		doins "${DISTDIR}/small.en.bin"
		fowners -R aivoice:aivoice /var/lib/ai-voice-server
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
	if use server; then
		elog "====================================================================="
		elog "To start the AI Voice Server locally, enable and start the service:"
		elog ""
		elog "  sudo systemctl enable --now ai-voice-server"
		elog ""
		elog "You can configure the server via /etc/conf.d/ai-voice-server"
		elog "====================================================================="
	fi

	if use client; then
		elog "====================================================================="
		elog "To use the AI Voice Client overlay and kernel-level dictation hotkeys,"
		elog "you must enable and start the following three services:"
		elog ""
		elog "  sudo systemctl enable --now udevmon"
		elog "  systemctl --user enable --now ydotool"
		elog "  systemctl --user enable --now ai-voice-client"
		elog ""
		elog "The AI Voice Client overlay will now start automatically on login."
		elog "====================================================================="
	fi
}
