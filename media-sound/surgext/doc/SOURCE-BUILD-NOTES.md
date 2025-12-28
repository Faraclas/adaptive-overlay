# Source-Based Build Notes for Surge XT

This document covers the source-based build of surge-xt, including critical fixes needed for GCC 15 compatibility.

## Overview

Surge XT is built from source using CMake. The ebuild requires patches for GCC 15 compatibility and careful handling of internal shared libraries.

## Source Configuration

### Source URL
```bash
SRC_URI="https://github.com/Faraclas/adaptive-overlay/releases/download/surgext-${PV}/${P}.tar.gz"
```

We use a custom tarball hosted on GitHub releases because:
- Upstream releases don't include git submodules needed for building
- The tarball includes all required dependencies pre-fetched
- Simplifies the build process and ensures reproducibility

### Build System
```bash
inherit cmake desktop xdg
```

- `cmake` - For CMake build system
- `desktop` - For desktop file installation (`domenu`)
- `xdg` - For icon cache and desktop database updates

## Dependencies

### Core Build Dependencies
```bash
DEPEND="
    dev-util/cmake
    x11-libs/cairo
    x11-libs/libxkbcommon[X]
    x11-libs/xcb-util-cursor
    x11-libs/xcb-util-keysyms
    x11-libs/libXrandr
    x11-libs/libXinerama
    x11-libs/libXcursor
    media-libs/alsa-lib
"
```

### Standalone-Only Dependencies
```bash
standalone? (
    virtual/jack
    net-misc/curl
    net-libs/webkit-gtk:4
    x11-libs/gtk+:3
)
```

### Build Tools
```bash
BDEPEND="
    dev-vcs/git
    dev-util/patchelf
"
```

**patchelf** is required to fix RPATHs on binaries and plugins.

## USE Flags

```bash
IUSE="+clap +lv2 +vst3 +standalone"
REQUIRED_USE="|| ( clap lv2 vst3 standalone )"
```

At least one plugin format or standalone must be enabled.

## GCC 15 Compatibility

### Required Patches

**File:** `files/surgext-1.3.4-fix-visibility.patch`

This patch fixes two critical issues with GCC 15:

1. **Filesystem library ABI issues** - Forces use of `std::filesystem` instead of bundled `ghc::filesystem`
2. **Symbol visibility** - Disables `-fvisibility=hidden` flags that prevent proper symbol resolution

The patch comments out these CMake flags:
```cmake
-fvisibility=hidden
-fvisibility-inlines-hidden
```

### CMake Configuration

```bash
src_configure() {
    local mycmakeargs=(
        -DCMAKE_BUILD_TYPE=Release
        -DSURGE_BUILD_LV2=$(usex lv2 ON OFF)
        -DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON
    )
    cmake_src_configure
}
```

**Critical flag:** `-DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON` forces the use of standard `std::filesystem`.

## Build Process

### Compile Phase
```bash
src_compile() {
    cmake_src_compile surge-staged-assets
}
```

The `surge-staged-assets` target builds everything and places files in `${BUILD_DIR}/surge_xt_products/`.

## Installation

### Internal Shared Libraries

Surge XT builds with internal shared libraries that must be installed to a private directory:

```bash
# Install to /usr/lib64/surgext/
doexe "${BUILD_DIR}/src/common/libsurge-common.so"
doexe "${BUILD_DIR}/libs/airwindows/libairwindows.so"
doexe "${BUILD_DIR}/libs/eurorack/libeurorack.so"
doexe "${BUILD_DIR}/libs/oddsound-mts/liboddsound-mts.so"
doexe "${BUILD_DIR}/libs/sqlite-3.23.3/libsqlite.so"
doexe "${BUILD_DIR}/libs/sst/sst-plugininfra/libs/strnatcmp/libstrnatcmp.so"
doexe "${BUILD_DIR}/libs/fmt/libfmt.so.9"
doexe "${BUILD_DIR}/src/lua/libsurge-lua-src.so"
```

### RPATH Configuration

All binaries, plugins, and internal libraries need RPATH set to find the private libraries:

```bash
# Fix RPATHs on internal libraries first
patchelf --force-rpath --set-rpath "/usr/lib64/surgext" "${ED}/usr/lib64/surgext/libsurge-common.so"
patchelf --force-rpath --set-rpath "/usr/lib64/surgext" "${ED}/usr/lib64/surgext/libfmt.so.9"

# Then fix binaries and plugins
patchelf --force-rpath --set-rpath "/usr/lib64/surgext" "${ED}/usr/bin/surge-xt"
# ... (for all executables and plugin .so files)
```

**Important:** Use `--force-rpath` to ensure RPATH is used instead of RUNPATH.

### Plugin Installation

**CLAP and Executables:**
```bash
exeinto /usr/lib64/clap
doexe "${BUILD_DIR}/surge_xt_products/Surge XT.clap"
```

**LV2 and VST3 (with nested .so files):**
```bash
# Install directory structure
insinto /usr/lib64/lv2
doins -r "${BUILD_DIR}/surge_xt_products/Surge XT.lv2"

# Fix permissions on embedded .so files
fperms +x "/usr/lib64/lv2/Surge XT.lv2/libSurge XT.so"
```

### Desktop Files and Icons

**Desktop files:**
```bash
domenu "${S}/scripts/installer_linux/assets/applications/Surge-XT.desktop"
```

**Icons:** (Standard sizes: 16, 32, 48, 64, 128, 256, 512)
```bash
local icon_sizes=(16 32 48 64 128 256 512)
for size in "${icon_sizes[@]}"; do
    newicon -s ${size} "${S}/scripts/installer_linux/assets/icons/hicolor/${size}x${size}/apps/surge-xt.png" surge-xt.png
done
```

**Note:** 384px is not a standard icon size in Gentoo.

## Post-Install Functions

```bash
pkg_postinst() {
    xdg_icon_cache_update
    xdg_desktop_database_update
    # ... user messages
}

pkg_postrm() {
    xdg_icon_cache_update
    xdg_desktop_database_update
}
```

Both functions are required to update desktop environment caches.

## Testing the Build

### Using ebuild Command

```bash
# Full build and stage (does NOT install to system)
PORTAGE_WORKDIR_MODE="0770" GENTOO_MIRRORS="" ebuild ./surgext-1.3.4.ebuild clean compile install

# Inspect staged files
ls -R /var/tmp/portage/media-sound/surgext-1.3.4/image/

# Test binary with LD_LIBRARY_PATH (staged files)
LD_LIBRARY_PATH=/var/tmp/portage/media-sound/surgext-1.3.4/image/usr/lib64/surgext \
    /var/tmp/portage/media-sound/surgext-1.3.4/image/usr/bin/surge-xt --help
```

### Verify RPATH

```bash
# Check RPATH is set correctly
readelf -d /var/tmp/portage/media-sound/surgext-1.3.4/image/usr/bin/surge-xt | grep RPATH

# Should show: Library rpath: [/usr/lib64/surgext]
```

### After Installation

```bash
# Verify libraries can be found
ldd /usr/bin/surge-xt

# Test standalone
surge-xt --help

# Check plugins
ls /usr/lib64/clap/
ls /usr/lib64/lv2/
ls /usr/lib64/vst3/
```

## Common Issues

### "libsurge-common.so not found" Error

**Cause:** RPATH not set correctly or library not installed.

**Solution:**
1. Verify patchelf commands ran successfully
2. Check that libraries exist in `/usr/lib64/surgext/`
3. Verify RPATH with `readelf -d <binary> | grep RPATH`

### QA Notice: Insecure RUNPATH

**Cause:** Libraries have RUNPATH pointing to build directories.

**Solution:** Ensure patchelf is run on internal libraries (`libsurge-common.so`, `libfmt.so.9`) to set proper RPATH.

### Desktop File Validation Warnings

**Expected warnings from upstream desktop files:**
- Deprecated `TerminalOptions` key
- Empty `Path` value

These are minor and don't affect functionality.

## File Locations

### Installation Paths
- Binaries: `/usr/bin/surge-xt`, `/usr/bin/surge-xt-effects`, `/usr/bin/surge-xt-cli`
- Internal libraries: `/usr/lib64/surgext/*.so`
- Plugins: `/usr/lib64/{clap,lv2,vst3}/`
- Data: `/usr/share/surge-xt/`
- Desktop files: `/usr/share/applications/`
- Icons: `/usr/share/icons/hicolor/*/apps/`

### User Data
- `~/.local/share/surge-xt/` - User presets, patches, skins

## References

- Surge XT Homepage: https://surge-synthesizer.github.io/
- GCC 15 Visibility Guide: https://gcc.gnu.org/wiki/Visibility
- Gentoo ebuild Guide: https://devmanual.gentoo.org/