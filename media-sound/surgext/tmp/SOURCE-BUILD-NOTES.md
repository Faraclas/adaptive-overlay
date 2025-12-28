# Source-Based Build Conversion for Surge XT

This document summarizes the conversion of the surge-xt ebuild from a binary installation to a source-based build.

## Overview

The original ebuild installed pre-compiled binaries from the upstream releases. The new ebuild builds Surge XT from source using CMake, following Gentoo's philosophy of building packages from source.

**Important:** This package requires patches for GCC 15 compatibility. See the "GCC 15 Compatibility" section below for details.

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
        -DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON
    )
    cmake_src_configure
}

**Note:** The `-DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON` flag is required to use the platform's standard `std::filesystem` instead of the bundled `ghc::filesystem` library, which has compatibility issues with GCC 15.
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

## GCC 15 Compatibility

### Issues Encountered

Surge XT 1.3.4 required patches to build successfully with GCC 15 due to stricter enforcement of symbol visibility rules.

#### 1. Filesystem Library Issues

**Problem:** The bundled `ghc::filesystem` library had ABI compatibility issues with GCC 15, causing undefined reference errors:
```
undefined reference to `ghc::filesystem::path::u8string[abi:cxx11]() const'
undefined reference to `ghc::filesystem::path::c_str() const'
```

**Root Cause:** GCC 15's stricter handling of C++11 ABI tags and symbol mangling exposed incompatibilities in the `ghc::filesystem` implementation.

**Solution:** Force the use of the platform's native `std::filesystem` (fully supported in C++17) by adding:
```cmake
-DSST_PLUGININFRA_FILESYSTEM_FORCE_PLATFORM=ON
```

This tells the build system to use `std::filesystem` instead of the third-party `ghc::filesystem` implementation.

#### 2. Symbol Visibility Issues

**Problem:** Multiple undefined reference errors during linking for symbols that clearly existed in the compiled libraries:
```
undefined reference to `plaits::Voice::Init(stmlib::BufferAllocator*)'
undefined reference to `plaits::Voice::Render(...)'
undefined reference to `src_process'
undefined reference to `strnatcasecmp(char const*, char const*)'
undefined reference to `MTS_SetNoteTuning'
undefined reference to `AirWinBaseClass::pluginRegistry()'
```

**Root Cause Analysis:**
1. The build system applies `-fvisibility=hidden` globally to all compilation units
2. GCC 15 enforces symbol visibility more strictly than previous versions
3. Symbols in shared libraries (`.so` files) were being compiled as local (`t`) instead of global (`T`)
4. Investigation with `nm` showed symbols existed but were hidden:
   ```bash
   $ nm /path/to/libeurorack.so | grep "plaits.*Voice.*Render"
   000000000000cea0 t _ZN6plaits5Voice6RenderE...  # 't' = local, not 'T' = global
   ```

**Why This Affects GCC 15 Specifically:**
- GCC 15 has stricter enforcement of visibility rules across compilation units
- Previous GCC versions were more lenient with static libraries and symbol visibility
- Clang has historically been stricter, so this code might also fail with Clang

**Solution:** Created patch `surgext-1.3.4-fix-visibility.patch` that disables the global visibility hidden flags:

```diff
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -80,9 +80,9 @@
     $<$<NOT:$<OR:$<BOOL:${WIN32}>,$<BOOL:${SURGE_SKIP_WERROR}>>>:-Werror>
 
     # PE/COFF doesn't support visibility
-    $<$<NOT:$<BOOL:${WIN32}>>:-fvisibility=hidden>
+    #$<$<NOT:$<BOOL:${WIN32}>>:-fvisibility=hidden>
     # Inlines visibility is only relevant with C++
-    $<$<AND:$<NOT:$<BOOL:${WIN32}>>,$<COMPILE_LANGUAGE:CXX>>:-fvisibility-inlines-hidden>
+    #$<$<AND:$<NOT:$<BOOL:${WIN32}>>,$<COMPILE_LANGUAGE:CXX>>:-fvisibility-inlines-hidden>
```

**Why This Works:**
- Removes the global `-fvisibility=hidden` flag that was hiding all symbols by default
- Allows symbols in shared libraries to be exported with default visibility
- Enables proper symbol resolution during linking

**Trade-offs:**
- Slightly larger binary size (more symbols exported)
- Potentially more symbol collisions (though unlikely in practice)
- Better compatibility with stricter compilers

### Patches Required

The following patch file is required and included in the ebuild:

**File:** `files/surgext-1.3.4-fix-visibility.patch`
- Disables global `-fvisibility=hidden` and `-fvisibility-inlines-hidden` flags
- Applied automatically during the prepare phase via the `PATCHES` array

### Testing GCC 15 Compatibility

To verify the build works correctly:

1. **Check symbol visibility:**
   ```bash
   nm -D /usr/lib64/libeurorack.so | grep " T " | head
   ```
   Should show exported (global) symbols.

2. **Verify linking:**
   ```bash
   ldd /usr/bin/surge-xt
   ```
   All libraries should be found without errors.

3. **Test runtime:**
   ```bash
   surge-xt --help  # Should not crash
   ```

### Clang Compatibility

The visibility fix should also work with Clang, as Clang has historically been even stricter about symbol visibility. To test with Clang:

```bash
CC=clang CXX=clang++ emerge -1 surgext
```

### Future Considerations

**Upstream Fix Recommended:**
These issues should be reported upstream to the Surge XT developers:
1. Update `ghc::filesystem` to a newer version or migrate to `std::filesystem` by default
2. Review and properly annotate symbols that need to be exported with visibility attributes
3. Consider using `-fvisibility=default` as the baseline with explicit hiding of internal symbols

**For Packagers:**
- Monitor upstream releases for native GCC 15 compatibility fixes
- These patches may not be needed for Surge XT 1.4.0 and later versions
- Test with both GCC and Clang to ensure broad compatibility

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

## Troubleshooting

### Build Fails with Undefined References

If you see undefined reference errors during linking:

1. **Verify patches are applied:**
   ```bash
   ebuild surgext-1.3.4.ebuild clean prepare
   grep -n "fvisibility=hidden" /var/tmp/portage/media-sound/surgext-1.3.4/work/surge-1.3.4/CMakeLists.txt
   ```
   The visibility flags should be commented out (lines starting with `#`).

2. **Check GCC version:**
   ```bash
   gcc --version
   ```
   GCC 15 requires the visibility patch.

3. **Clean rebuild:**
   ```bash
   ebuild surgext-1.3.4.ebuild clean compile
   ```

### Filesystem-Related Errors

If you see errors about `ghc::filesystem`:

1. Ensure the CMake flag is set in `src_configure()`:
   ```bash
   grep "FORCE_PLATFORM" /usr/portage/media-sound/surgext/surgext-1.3.4.ebuild
   ```

2. Verify it's being passed to CMake:
   ```bash
   grep "FORCE_PLATFORM" /var/tmp/portage/media-sound/surgext-1.3.4/work/surge-1.3.4_build/CMakeCache.txt
   ```

## Future Improvements

Possible enhancements for future versions:

1. **Remove patches when upstream fixes are available** - Monitor Surge XT 1.4.0+ for native GCC 15 support
2. Add support for VST2 (requires user-provided SDK)
3. Add Python bindings support (`SURGE_BUILD_PYTHON_BINDINGS`)
4. Add LTO (Link-Time Optimization) USE flag
5. Add support for building installers (`surge-xt-distribution` target)
6. Consider adding ASIO support flag for Windows builds
7. Test and document Clang compatibility

## References

- Upstream README: https://github.com/surge-synthesizer/surge/blob/main/README.md
- Surge XT Homepage: https://surge-synthesizer.github.io/
- CMake Build Documentation: In upstream repository under `doc/` directory
- GCC 15 Changes: https://gcc.gnu.org/gcc-15/changes.html
- GCC 15 Porting Guide: https://gcc.gnu.org/gcc-15/porting_to.html
- Symbol Visibility Guide: https://gcc.gnu.org/wiki/Visibility