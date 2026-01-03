# Bitwig Studio

## Overview

Bitwig Studio is a professional multi-platform music-creation system for production, performance, and DJing. This ebuild packages the proprietary Linux version distributed by Bitwig GmbH.

## Installation

### Emerge the Package

The ebuild will automatically download the `.deb` package from Bitwig's website:

```bash
emerge media-sound/bitwig-studio
```

Portage will fetch the file directly from Bitwig's servers. No manual download is required!

## USE Flags

- `+abi_x86_32` - Enable 32-bit plugin bridging support for loading 32-bit VST plugins in the 64-bit application (enabled by default). This requires 32-bit versions of various X11 libraries.
- `+ffmpeg` - Use system ffmpeg instead of bundled version (enabled by default, recommended for security updates and reduced disk usage)
- `+jack-sdk` - Use PipeWire with JACK SDK as the audio backend (enabled by default, recommended for modern systems)
- `jack-client` - Use JACK2 as the audio backend (traditional JACK implementation)

**Notes:** 
- At least one of `jack-sdk` or `jack-client` must be enabled.
- The `+ffmpeg` flag is enabled by default and recommended for most users.

## Notes

### System vs Bundled FFmpeg

By default (`+ffmpeg`), this ebuild removes the bundled ffmpeg binaries (~57MB) and uses the system's `media-video/ffmpeg` package instead. This is the recommended approach for:
- **Security**: Receive timely security updates from Gentoo
- **Disk space**: Avoid duplicating ffmpeg (most systems already have it)
- **Integration**: Better integration with system libraries

If you need the bundled version (e.g., for specific codec compatibility):
```bash
echo "media-sound/bitwig-studio -ffmpeg" >> /etc/portage/package.use/bitwig-studio
```

### 32-bit Plugin Support

32-bit plugin bridging is **enabled by default** via the `+abi_x86_32` USE flag. This preserves the 32-bit plugin host binary and pulls in the necessary 32-bit library dependencies.

If you don't need 32-bit plugins and want to reduce dependencies, you can disable it:
```bash
echo "media-sound/bitwig-studio -abi_x86_32" >> /etc/portage/package.use/bitwig-studio
```

### JACK vs PipeWire

The ebuild defaults to **PipeWire with JACK SDK** (`+jack-sdk`), which is the recommended modern audio backend.

If you prefer traditional JACK2 instead:
```bash
echo "media-sound/bitwig-studio -jack-sdk jack-client" >> /etc/portage/package.use/bitwig-studio
```

You can also enable both if you want flexibility, but at least one must be selected.

### License

Bitwig Studio is proprietary software (`LICENSE="Bitwig"`). The license file is included in the overlay at `licenses/Bitwig` and will be installed to:
- `/opt/bitwig-studio/EULA.txt`
- `/opt/bitwig-studio/EULA.rtf`

**Note**: Most systems with overlays have `ACCEPT_LICENSE="*"` set, so no manual license acceptance is needed. If Portage blocks the installation due to license restrictions, it will tell you to add:
```bash
echo "media-sound/bitwig-studio Bitwig" >> /etc/portage/package.license
```

## Upgrading

When upgrading to newer versions:

1. Update the ebuild filename to match the new version
2. Update the `Manifest` file with the new checksums:
   ```bash
   ebuild bitwig-studio-X.Y.Z.ebuild manifest
   ```
3. Test the installation

## Troubleshooting

### Missing 32-bit Libraries

32-bit plugin support is enabled by default. If you disabled it and want to re-enable it:

```bash
# Remove the disable flag (if you added it)
# Or explicitly enable it
echo "media-sound/bitwig-studio abi_x86_32" >> /etc/portage/package.use/bitwig

# Enable abi_x86_32 for required packages
echo "x11-libs/libX11 abi_x86_32" >> /etc/portage/package.use/bitwig
echo "x11-libs/libxcb abi_x86_32" >> /etc/portage/package.use/bitwig
# ... add other packages as needed
```

### Audio Configuration

By default, Bitwig Studio is configured to use PipeWire with JACK SDK. Make sure your user is in the `audio` group:

```bash
usermod -aG audio $USER
```

For real-time audio performance, consider configuring RT limits in `/etc/security/limits.d/audio.conf`:

```
@audio   -  rtprio     95
@audio   -  memlock    unlimited
```

## Related Packages

- `media-sound/yabridge` - Run Windows VST plugins on Linux
- `media-sound/carla` - Audio plugin host and modular rack
- `media-video/pipewire[jack-sdk]` - Modern audio server with JACK compatibility
- `media-sound/jack2` - Traditional JACK audio connection kit

## Links

- Homepage: https://www.bitwig.com/
- Support: https://www.bitwig.com/support/
- Community Forum: https://www.bitwig.com/community/
- GitHub Issues: https://github.com/bitwig/bitwig-studio/issues

## Maintainer

- Elias Faraclas <faraclas@gmail.com>