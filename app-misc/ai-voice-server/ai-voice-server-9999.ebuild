# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

RUST_MIN_VER="1.85.0"
inherit cargo git-r3 systemd

DESCRIPTION="A self-hosted, highly accurate, and GPU-accelerated voice dictation pipeline"
HOMEPAGE="https://github.com/Faraclas/ai-voice-server"
EGIT_REPO_URI="https://github.com/Faraclas/ai-voice-server.git"
SRC_URI="server? ( https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin -> ${P}-small.en.bin )"
LICENSE="MIT"
SLOT="0"
KEYWORDS=""
IUSE="+client +server +vulkan +nvidia rocm"
REQUIRED_USE="|| ( client server )"

# Allow cargo to download dependencies for live ebuilds
PROPERTIES="live"

BDEPEND="
	client? ( virtual/pkgconfig )
"
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

pkg_setup() {
	if use nvidia && [[ -z "${CMAKE_CUDA_ARCHITECTURES}" ]]; then
		eerror "You have enabled the 'nvidia' USE flag."
		eerror "Because Gentoo's build sandbox blocks GPU hardware detection (NVML),"
		eerror "you MUST explicitly set your GPU's compute capability in /etc/portage/make.conf."
		eerror ""
		eerror "To find your GPU's compute capability, run the following command outside of emerge:"
		eerror "  nvidia-smi --query-gpu=compute_cap --format=csv,noheader | tr -d '.'"
		eerror ""
		eerror "For example, if the output is '86', add this line to your /etc/portage/make.conf:"
		eerror "  CMAKE_CUDA_ARCHITECTURES=\"86\""
		eerror ""
		eerror "(Note: You can specify multiple architectures separated by a semicolon, e.g., \"75;86\")"
		eerror "To compile for all possible GPUs (slow!), set it to \"all\"."
		die "CMAKE_CUDA_ARCHITECTURES is not set in make.conf"
	fi
}

src_unpack() {
	git-r3_src_unpack

	# Fetch cargo dependencies while the network sandbox is open
	if use server; then
		pushd "${S}/src/server" >/dev/null || die
		cargo fetch || die
		popd >/dev/null || die
	fi
	
	if use client; then
		pushd "${S}/src/client" >/dev/null || die
		cargo fetch || die
		popd >/dev/null || die
	fi
}

src_compile() {
	local my_target_dir=$(cargo_target_dir)
	
	if use server; then
		pushd "${S}/src/server" >/dev/null || die
		
		# Allow ggml's build script to query the GPU for the correct CUDA architecture
		addpredict /dev/nvidiactl
		addpredict /dev/nvidia-uvm
		addpredict /dev/nvidia0

		if use nvidia; then
			einfo "Building Server (CUDA) for architecture: ${CMAKE_CUDA_ARCHITECTURES}"
			export CMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}"
			cargo build --release --offline --features nvidia || die "Failed to build CUDA server"
			mv "${my_target_dir}/server" "${my_target_dir}/ai-voice-server-cuda" || die
		fi

		if use vulkan; then
			einfo "Building Server (Vulkan)..."
			cargo build --release --offline --features vulkan || die "Failed to build Vulkan server"
			mv "${my_target_dir}/server" "${my_target_dir}/ai-voice-server-vulkan" || die
		fi

		if use rocm; then
			einfo "Building Server (ROCm)..."
			cargo build --release --offline --features rocm || die "Failed to build ROCm server"
			mv "${my_target_dir}/server" "${my_target_dir}/ai-voice-server-rocm" || die
		fi
		
		if ! use nvidia && ! use vulkan && ! use rocm; then
			einfo "Building Server (Pure CPU)..."
			cargo build --release --offline || die "Failed to build CPU server"
			mv "${my_target_dir}/server" "${my_target_dir}/ai-voice-server-cpu" || die
		fi
		
		popd >/dev/null || die
	fi

	if use client; then
		einfo "Building Client and Plugins..."
		pushd "${S}/src/client" >/dev/null || die
		# This workspace builds both 'daemon' and 'interception_plugin'
		cargo build --release --offline || die "Failed to build client"
		popd >/dev/null || die
	fi
}

src_install() {
	local my_target_dir=$(cargo_target_dir)

	if use server; then
		use nvidia && dobin "${my_target_dir}/ai-voice-server-cuda"
		use vulkan && dobin "${my_target_dir}/ai-voice-server-vulkan"
		use rocm && dobin "${my_target_dir}/ai-voice-server-rocm"
		if ! use nvidia && ! use vulkan && ! use rocm; then
			dobin "${my_target_dir}/ai-voice-server-cpu"
		fi
		
		# Install the wrapper script as the primary entrypoint
		newbin "${S}/packaging/ai-voice-server.sh" ai-voice-server

		# Install systemd service and config
		systemd_dounit "${S}/packaging/systemd/ai-voice-server.service"
		newconfd "${S}/packaging/systemd/ai-voice-server.conf" ai-voice-server

		# Install models and set ownership
		insinto /var/lib/ai-voice-server/models
		newins "${DISTDIR}/${P}-small.en.bin" small.en.bin
		fowners -R aivoice:aivoice /var/lib/ai-voice-server
	fi

	if use client; then
		# Install main client (renaming from 'daemon' to 'ai-voice-client')
		newbin "${my_target_dir}/daemon" ai-voice-client

		# Install plugin
		dobin "${my_target_dir}/interception_plugin"

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
