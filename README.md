# adaptive-overlay

A personal Gentoo overlay containing custom ebuilds and package variants.

## About

This overlay provides additional packages and versions not available in the main Gentoo repository.

## Packages

Currently included packages:

- **media-sound/carla** - Audio plugin host
- **net-vpn/forticlient** - Fortinet VPN client
- **net-vpn/openfortivpn** - Open-source Fortinet VPN client

## Installation

### Using eselect repository (recommended)

1. Install `app-eselect/eselect-repository`:
   ```bash
   emerge --ask app-eselect/eselect-repository
   ```

2. Add the overlay:
   ```bash
   eselect repository add adaptive-overlay git https://github.com/YOUR_USERNAME/adaptive-overlay.git
   ```

3. Sync the overlay:
   ```bash
   emaint sync -r adaptive-overlay
   ```

### Manual installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/adaptive-overlay.git /var/db/repos/adaptive-overlay
   ```

2. Add the overlay to `/etc/portage/repos.conf/adaptive-overlay.conf`:
   ```ini
   [adaptive-overlay]
   location = /var/db/repos/adaptive-overlay
   sync-type = git
   sync-uri = https://github.com/YOUR_USERNAME/adaptive-overlay.git
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

## Contributing

Bug reports and pull requests are welcome.

## License

Individual packages maintain their respective licenses as specified in their ebuilds.