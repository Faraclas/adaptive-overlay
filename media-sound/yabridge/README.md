# Yabridge Ebuild

This directory contains the Gentoo ebuild for yabridge, a modern and transparent
way to use Windows VST2, VST3, and CLAP audio plugins on Linux.

## Package Information

- **Version**: 5.1.1
- **Homepage**: https://github.com/robbert-vdh/yabridge
- **License**: GPL-3

## Build System

This ebuild builds yabridge from source using the Meson build system. It differs
from the binary `yabridge-bin` package by compiling everything locally.

## USE Flags

- `bitbridge` (enabled by default): Build 32-bit plugin host to support legacy
32-bit Windows plugins in 64-bit Linux hosts. Note that this requires Wine to be
built with 32-bit support and is not compatible with Wine's new WoW64 mode.

## Dependencies

### Build-time
- GCC 10 or newer
- Meson 0.56 or newer
- Wine with staging patches and winegcc
- libxcb development headers
- For bitbridge: 32-bit libxcb libraries

### Runtime
- Wine (staging recommended)
- libxcb, libXau, libXdmcp
- libmd, libbsd
- glibc

## Installation

```bash
# Add to your repos.conf if not already added
# Then:
emerge media-sound/yabridge
```

## Post-Installation

After installation, you need to set up yabridge for your Windows plugins:

1. Add your Windows plugin directories:
```bash
yabridgectl add "$HOME/.wine/drive_c/Program Files/Steinberg/VstPlugins"
yabridgectl add "$HOME/.wine/drive_c/Program Files/Common Files/VST3"
yabridgectl add "$HOME/.wine/drive_c/Program Files/Common Files/CLAP"
```

2. Sync your plugins:
```bash
yabridgectl sync
```

3. Make sure your DAW scans these directories:
   - VST2: `~/.vst/yabridge`
   - VST3: `~/.vst3/yabridge`
   - CLAP: `~/.clap/yabridge`

## Known Issues

- Wine 9.22 and later have known compatibility issues with GUI rendering (mouse cursor offset). It's recommended to use Wine 9.21 or earlier until this is resolved.
- See: https://github.com/robbert-vdh/yabridge/issues/382

## Building Notes

The ebuild uses the following Meson configuration:
- Cross-compilation using Wine's winegcc via `cross-wine.conf`
- Optional bitbridge support (enabled by default via USE flag)
- Build type and optimization flags are handled automatically by the meson eclass

Note: The original yabridge build instructions recommend unity builds for faster
compilation, but these may consume significant RAM during compilation. The ebuild
uses standard Gentoo meson eclass defaults.

## Files

- `yabridge-5.1.1.ebuild` - Main ebuild file
- `Manifest` - Checksums for source tarball
- `metadata.xml` - Package metadata and USE flag descriptions
- `README.md` - This file
- `check-dependencies.sh` - Helper script to check subproject dependency versions
- `SUBMODULES.md` - Detailed documentation about VST3 SDK submodule handling

## Maintainer Notes

### Updating to New Versions

When updating yabridge to a new version, you need to check if the subproject dependencies have changed:

1. **Check subproject versions**: Extract the new yabridge tarball and examine the `.wrap` files in `subprojects/` to see if any dependency versions or commit hashes have changed.

2. **VST3 SDK submodules**: The VST3 SDK uses git submodules that are NOT included in GitHub archive downloads. Check `subprojects/vst3.wrap` for the git revision and submodule commit hashes:
   - If the `revision` (tag) has changed, update the SRC_URI
   - If the wrap file has changed, update the git checkout commands in `src_prepare()` with the new commit hashes for:
     - `base` submodule
     - `pluginterfaces` submodule  
     - `public.sdk` submodule

3. **Other dependencies**: Check if commit hashes for asio, bitsery, clap, function2, ghc_filesystem, or tomlplusplus have changed in their respective `.wrap` files. Update SRC_URI entries and symlink paths in `src_prepare()` accordingly.

4. **Test the build**: Always test compile the ebuild after updating to ensure all dependencies are properly fetched and linked.

Example of checking for changes:
```bash
# Extract new version
tar -xzf yabridge-X.Y.Z.tar.gz
cd yabridge-X.Y.Z/subprojects

# Check VST3 SDK version and submodules
cat vst3.wrap

# Check other dependency versions
cat asio.wrap bitsery.wrap clap.wrap function2.wrap ghc_filesystem.wrap tomlplusplus.wrap
```

Alternatively, use the provided helper script:
```bash
./check-dependencies.sh yabridge-X.Y.Z.tar.gz
```

This will display all dependency versions and URLs, making it easy to spot changes.

## Maintainer

Elias Faraclas <faraclas@gmail.com>
