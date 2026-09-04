# adaptive-overlay

A personal Gentoo overlay containing custom ebuilds and package variants.

## About

This overlay provides additional packages and versions not available in the
main Gentoo repository.

## Packages

Currently included packages:

- **app-ai/hermes-agent** - The agent that grows with you
- **app-editors/zed** - Fast, collaborative code editor
- **app-misc/ai-voice-server** - A self-hosted, highly accurate, and GPU-accelerated voice dictation pipeline
- **dev-python/fire** - Python library for automatically generating command line interfaces
- **dev-python/jiter** - Fast iterable JSON parser
- **dev-python/openai** - The official Python library for the OpenAI API
- **media-sound/amp-locker** - Audio plugin locker
- **media-sound/bitwig-studio** - Digital audio workstation
- **media-sound/carla** - Audio plugin host
- **media-sound/drum-locker** - Drum sample locker
- **media-sound/surgext** - Surge synthesizer extras
- **media-sound/yabridge** - VST bridge for Linux
- **net-vpn/forticlient** - Fortinet VPN client
- **net-vpn/openfortivpn** - Open-source Fortinet VPN client
- **x11-terms/boxxy** - Modern terminal emulator with AI assistant built with Rust and GTK 4

## Installation

### Using eselect repository (recommended)

1. Install `app-eselect/eselect-repository`:

   ```bash
   emerge --ask app-eselect/eselect-repository
   ```

2. Add the overlay:

   ```bash
   eselect repository add adaptive-overlay git https://github.com/Faraclas/adaptive-overlay.git
   ```

3. Sync the overlay:

   ```bash
   emaint sync -r adaptive-overlay
   ```

### Manual installation

1. Clone this repository:

   ```bash
   git clone https://github.com/Faraclas/adaptive-overlay.git /var/db/repos/adaptive-overlay
   ```

2. Add the overlay to `/etc/portage/repos.conf/adaptive-overlay.conf`:

```ini
   [adaptive-overlay]
   location = /var/db/repos/adaptive-overlay
   sync-type = git
   sync-uri = https://github.com/Faraclas/adaptive-overlay.git
   auto-sync = yes
```

3. Sync:

```bash
   emaint sync -r adaptive-overlay
```

## Usage

After installation, packages from this overlay can be installed using emerge:

```bash
emerge --ask media-sound/carla
```

## CI and Testing Containers

To ensure build consistency, packages in this overlay are automatically tested using GitHub Actions inside specialized Gentoo container environments. If you are developing new ebuilds, they will be mapped to a container based on their category:

- **`testenv-rust-desktop`**: Used for heavy desktop/GUI applications requiring Rust (e.g., `app-editors/zed`)
- **`testenv-python-heavy`**: Used for AI applications and their dependencies (e.g., `app-ai/*` and `dev-python/*`)
- **`testenv-audio`**: Used for digital audio workstations, hosts, and plugins (e.g., `media-sound/*`)
- **`testenv-rust`**: Used for terminal or headless applications needing a Rust toolchain (e.g., `x11-terms/boxxy` and `app-misc/ai-voice-server`)
- **`testenv`**: The lightweight base environment, used for everything else (e.g., `net-vpn/*`, `acct-user/*`, `acct-group/*`)

When a pull request is submitted, `.github/workflows/ci-build.yml` automatically maps the ebuild to the correct container and attempts to build it using `emerge`.

## Contributing

Bug reports and pull requests are welcome.

## License

Individual packages maintain their respective licenses as specified in their
ebuilds
