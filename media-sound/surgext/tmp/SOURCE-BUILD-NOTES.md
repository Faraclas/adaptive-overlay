# Source-Based Build Conversion for Surge XT

This document summarizes the conversion of the surge-xt ebuild from a binary installation to a source-based build.

## Overview

The original ebuild installed pre-compiled binaries from the upstream releases. The new ebuild builds Surge XT from source using CMake, following Gentoo's philosophy of building packages from source.

## Key Changes

### 1. Source URL

**Before:**
```
SRC_URI="https://github.com/surge-synthesizer/releases-xt/releases/download/${PV}/${PN}-linux-x86_64-${PV}.tar.gz"
```

**After:**
```
SRC_URI="https://github.com/surge-synthesizer/releases-xt/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"
```

### 2. Build System

- Added `inherit cmake xdg` to use CMake build system and XDG utilities
- Added variables for proper source directory naming (`MY_PN`, `MY_P`)
- Implemented `src_configure()` and `src_compile()` phases
- Removed `QA_PREBUILT` since we're no longer using pre-built binaries

### 3. Dependencies

#### Build Dependencies (DEPEND)

Converted from apt package names to Gentoo equivalents:

| Upstream (apt) | Gentoo Package |
|----------------|----------------|
| build-essential | dev-util/cmake + system compiler |
| git | dev-vcs/git |
| cmake | dev-util/cmake |
| libcairo-dev | x11-libs/cairo |
| libxkbcommon-x11-dev | x11-libs/libxkbcommon[X] |
| libxkbcommon-dev | x11-libs/libxkbcommon |
| libxcb-cursor-dev | x11-libs/xcb-util-cursor |
| libxcb-keysyms1-dev | x11-libs/xcb-util-keysyms |
| libxcb-util-dev | (provided by other xcb packages) |
| libxrandr-dev | x11-libs/libXrandr |
| libxinerama-dev | x11-libs/libXinerama |
| libxcursor-dev | x11-libs/libXcursor |
| libasound2-dev | media-libs/alsa-lib |
| libjack-jackd2-dev | virtual/jack (optional, standalone only) |

#### Optional JUCE Dependencies

The following dependencies are **optional** and only required to silence build warnings. They are JUCE dependencies that Surge XT itself does not use:

- `net-misc/curl` (libcurl)
- `net-libs/webkit-gtk:4` (webkit2gtk-4.0)
- `x11-libs/gtk+:3` (gtk+-x11-3.0)

These are now conditionally included only when building with the `standalone` USE flag.

### 4. USE Flags

#### New USE Flag: `standalone`

Added the `standalone` USE flag to control whether to build the standalone applications.

**Rationale:**
- JACK is only mandatory for the standalone version
- Optional JUCE dependencies (curl, webkit-gtk, gtk+) are only needed for standalone builds
- Users who only want plugins don't need these dependencies

**Updated REQUIRED_USE:**
```
REQUIRED_USE="|| ( clap lv2 vst3 standalone )"
```

At least one of the plugin formats OR the standalone version must be selected.

### 5. Build Process

#### Configure Phase
```bash
src_configure() {
    local mycmakeargs=(
        -DCMAKE_BUILD_TYPE=Release
        -DSURGE_BUILD_LV2=$(usex lv2 ON OFF)
    )
    cmake_src_configure
}
```

#### Compile Phase
```bash
src_compile() {
    cmake_src_compile surge-staged-assets
}
```

The `surge-staged-assets` target builds all Surge XT binary assets and places them in `build/surge_xt_products`.

### 6. Installation

Updated to install from CMake build directory (`${BUILD_DIR}/surge_xt_products`) instead of the binary tarball structure.

**Conditional installations:**
- Standalone executables only installed if `standalone` USE flag is set
- Desktop files only installed if `standalone` USE flag is set
- Plugins installed based on respective USE flags (clap, lv2, vst3)

### 7. Executable Naming

Changed to more Unix-friendly names:
- `Surge XT` → `surge-xt`
- `Surge XT Effects` → `surge-xt-effects`
- `surge-xt-cli` (unchanged)

## Building the Package

### Basic Build (plugins only)

```bash
sudo USE="clap lv2 vst3" emerge -av media-sound/surge-xt
```

### Build with Standalone

```bash
sudo USE="clap lv2 vst3 standalone" emerge -av media-sound/surge-xt
```

### Build Standalone Only

```bash
sudo USE="standalone" emerge -av media-sound/surge-xt
```

## Testing the Build

After installation:

### For Plugins
Check that plugin files exist:
```bash
ls /usr/lib64/clap/
ls /usr/lib64/lv2/
ls /usr/lib64/vst3/
```

### For Standalone
Run the standalone applications:
```bash
surge-xt
surge-xt-effects
surge-xt-cli --help
```

## Known Build Messages

### Harmless Warnings

You may see messages about missing dependencies during CMake configuration:

```
Could NOT find curl
Could NOT find webkit2gtk-4.0
Could NOT find gtk+-x11-3.0
```

**These are normal and harmless.** These are JUCE dependencies that Surge XT itself does not use. The build will complete successfully without them.

To silence these warnings, either:
1. Enable the `standalone` USE flag (which adds these as dependencies)
2. Manually install: `net-misc/curl net-libs/webkit-gtk:4 x11-libs/gtk+:3`

## Differences from Binary Package

### Advantages of Source Build
- Follows Gentoo philosophy
- Optimized for your specific system
- No pre-built binary QA issues
- Easier to patch if needed
- More transparent about what's being installed

### Build Time
Building from source takes longer than installing binaries. On a modern system with parallel builds, expect:
- 5-15 minutes depending on CPU and flags enabled
- More time if building all formats + standalone

## Future Improvements

Possible enhancements for future versions:

1. Add support for VST2 (requires user-provided SDK)
2. Add Python bindings support (`SURGE_BUILD_PYTHON_BINDINGS`)
3. Add LTO (Link-Time Optimization) USE flag
4. Add support for building installers (`surge-xt-distribution` target)
5. Consider adding ASIO support flag for Windows builds

## References

- Upstream README: https://github.com/surge-synthesizer/surge/blob/main/README.md
- Surge XT Homepage: https://surge-synthesizer.github.io/
- CMake Build Documentation: In upstream repository under `doc/` directory