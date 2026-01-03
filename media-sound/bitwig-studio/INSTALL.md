# Installation Guide for Bitwig Studio 5.3.13

## Prerequisites

Before installing Bitwig Studio, ensure your system is properly configured:

1. **Add the overlay to your system** (if not already done):
   ```bash
   # Using eselect repository
   eselect repository add adaptive-overlay git https://github.com/Faraclas/adaptive-overlay.git
   
   # Or manually
   mkdir -p /var/db/repos/adaptive-overlay
   cd /var/db/repos/adaptive-overlay
   git clone https://github.com/Faraclas/adaptive-overlay.git .
   ```

2. **Sync the overlay**:
   ```bash
   emerge --sync adaptive-overlay
   ```

## Step 1: Configure USE Flags (Optional)

The ebuild has sensible defaults:
- **32-bit plugin support is enabled** (`+abi_x86_32`)
- **System ffmpeg is used** (`+ffmpeg`)
- **PipeWire with JACK SDK is enabled** (`+jack-sdk`)

### If you want to disable 32-bit plugin support:

```bash
echo "media-sound/bitwig-studio -abi_x86_32" >> /etc/portage/package.use/bitwig-studio
```

### If you want to use bundled ffmpeg instead of system ffmpeg:

```bash
echo "media-sound/bitwig-studio -ffmpeg" >> /etc/portage/package.use/bitwig-studio
```

This keeps Bitwig's bundled ffmpeg (~57MB) instead of using the system version.
Only recommended if you have specific compatibility needs.

### If you prefer traditional JACK2 instead of PipeWire:

```bash
echo "media-sound/bitwig-studio -jack-sdk jack-client" >> /etc/portage/package.use/bitwig-studio
```

### If you keep the defaults (32-bit support enabled):

You'll need to enable `abi_x86_32` for required X11 dependencies:

```bash
# Enable abi_x86_32 for dependencies (only needed if keeping +abi_x86_32)
echo "x11-libs/libX11 abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/libXau abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/libXdmcp abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/libxcb abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/libxcb-wm abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/libxkbcommon abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/pixman abi_x86_32" >> /etc/portage/package.use/bitwig-studio
echo "x11-libs/xcb-util abi_x86_32" >> /etc/portage/package.use/bitwig-studio
```

## Step 2: Install Audio Backend (if needed)

Bitwig Studio requires JACK audio support. The ebuild defaults to PipeWire with JACK SDK (`+jack-sdk`).

### Default: PipeWire with JACK SDK (Recommended)
```bash
# Ensure PipeWire has jack-sdk USE flag enabled
echo "media-video/pipewire jack-sdk" >> /etc/portage/package.use/pipewire
emerge media-video/pipewire
```

### Alternative: Using JACK2 (Traditional)
If you set `jack-client` USE flag instead:
```bash
emerge media-sound/jack2
```

## Step 3: Install Bitwig Studio

Now you can install the package. Portage will automatically download the `.deb` file from Bitwig's website:

```bash
emerge media-sound/bitwig-studio
```

This will:
- Install Bitwig Studio to `/opt/bitwig-studio`
- Create a launcher script at `/usr/bin/bitwig-studio`
- Install desktop files and MIME types
- Use system ffmpeg instead of bundled version (unless disabled with `-ffmpeg`)

## Step 4: Configure Real-time Audio (Recommended)

For optimal audio performance, configure real-time priorities:

1. **Add your user to the audio group**:
   ```bash
   sudo usermod -aG audio $USER
   ```

2. **Configure RT limits** (create `/etc/security/limits.d/audio.conf`):
   ```
   @audio   -  rtprio     95
   @audio   -  memlock    unlimited
   ```

3. **Log out and back in** for changes to take effect

## Step 5: Launch Bitwig Studio

You can now launch Bitwig Studio:

```bash
bitwig-studio
```

Or from your application menu: **Sound & Video → Bitwig Studio**

## Post-Installation

### First Launch

On first launch, Bitwig Studio will:
1. Ask you to agree to the EULA
2. Request your license information (if you have a purchased license)
3. Create user data directories in `~/.BitwigStudio/`

### Plugin Directories

Bitwig Studio will scan these directories for plugins:
- VST2: `~/.vst/`
- VST3: `~/.vst3/` and `/usr/lib64/vst3/`
- CLAP: `~/.clap/` and `/usr/lib64/clap/`

### Windows Plugin Support

To run Windows VST plugins on Linux, install yabridge:
```bash
emerge media-sound/yabridge
```

See the yabridge documentation for setup instructions.

## Troubleshooting

### "Missing library" errors
If you get library errors, ensure all dependencies are installed:
```bash
emerge -av media-sound/bitwig-studio
```

### Audio device issues
- Make sure JACK or PipeWire is running
- Check that your user is in the `audio` group
- Verify RT limits are configured properly

### 32-bit plugin problems
32-bit plugin support is enabled by default. If you disabled it and want it back:
1. Remove `-abi_x86_32` from your package.use file (or add `abi_x86_32`)
2. Rebuild with all 32-bit dependencies:
   ```bash
   emerge -av media-sound/bitwig-studio
   ```

### Permission denied errors
Bitwig needs access to audio devices:
```bash
# Check audio group membership
groups | grep audio

# Add if missing
sudo usermod -aG audio $USER
```

### Audio backend issues
By default, the ebuild uses PipeWire with JACK SDK. If you have issues:
- Ensure PipeWire is running: `systemctl --user status pipewire`
- Check JACK compatibility: `pw-jack bitwig-studio`
- If using JACK2 instead, ensure jackd is running

## Updating

To update to a newer version:

1. Sync the overlay to get the new ebuild
2. Update to the new ebuild version:
   ```bash
   emerge -u media-sound/bitwig-studio
   ```

Portage will automatically download the new version from Bitwig's servers.

## Uninstalling

To remove Bitwig Studio:

```bash
emerge -C media-sound/bitwig-studio
```

Note: This will not remove your user data in `~/.BitwigStudio/`

## Support

- Official Support: https://www.bitwig.com/support/
- Community Forum: https://www.bitwig.com/community/
- Overlay Issues: https://github.com/Faraclas/adaptive-overlay/issues
