# Surge XT Ebuild - Maintainer Quick Reference

## Quick Start

### Generate Manifest
```bash
cd /path/to/adaptive-overlay/media-sound/surgext
ebuild surge-xt-1.3.4.ebuild manifest
```

### Test Build
```bash
# Full build with all features
USE="clap lv2 vst3 standalone" ebuild surge-xt-1.3.4.ebuild clean compile

# Plugins only (faster test)
USE="vst3" ebuild surge-xt-1.3.4.ebuild clean compile

# Install to test system
USE="clap lv2 vst3 standalone" emerge -av media-sound/surge-xt
```

## USE Flag Combinations

### Recommended Default
```bash
USE="clap lv2 vst3 standalone"
```

### Minimal (fastest build)
```bash
USE="vst3"
```

### Plugins Only (no JACK dependency)
```bash
USE="clap lv2 vst3"
```

### Standalone Only
```bash
USE="standalone"
```

## Version Updates

### Finding New Versions
1. Check GitHub releases: https://github.com/surge-synthesizer/releases-xt/tags
2. Look for tags like `1.3.4`, `1.3.5`, etc.

### Creating New Version Ebuild
```bash
# Copy existing ebuild
cp surge-xt-1.3.4.ebuild surge-xt-1.3.5.ebuild

# Update Manifest
ebuild surge-xt-1.3.5.ebuild manifest

# Test new version
USE="vst3" ebuild surge-xt-1.3.5.ebuild clean compile install
```

### Version Bumping Checklist
- [ ] Copy ebuild to new version
- [ ] Check if CMake options changed in upstream
- [ ] Generate new Manifest
- [ ] Test build
- [ ] Test install
- [ ] Update README.md if needed

## Common Issues

### Issue: Missing curl/webkit-gtk warnings
**Status:** Normal, harmless
**Solution:** These are optional JUCE dependencies. Either:
- Ignore (build will succeed)
- Enable `standalone` USE flag
- Install manually: `emerge net-misc/curl net-libs/webkit-gtk:4`

### Issue: Build fails with LV2 errors
**Solution:** Check if `-DSURGE_BUILD_LV2=TRUE` is needed in mycmakeargs

### Issue: Can't find executables after install
**Check:**
- Was `standalone` USE flag enabled?
- Check `/usr/bin/surge-xt*`

### Issue: Plugins not detected in DAW
**Solution:**
- Verify installation: `ls /usr/lib64/{clap,lv2,vst3}/`
- Rescan plugins in DAW
- Check DAW plugin search paths

## File Locations After Install

### Executables (standalone USE flag)
```
/usr/bin/surge-xt
/usr/bin/surge-xt-effects
/usr/bin/surge-xt-cli
```

### Plugins
```
/usr/lib64/clap/Surge XT.clap
/usr/lib64/clap/Surge XT Effects.clap

/usr/lib64/lv2/Surge XT.lv2/
/usr/lib64/lv2/Surge XT Effects.lv2/

/usr/lib64/vst3/Surge XT.vst3/
/usr/lib64/vst3/Surge XT Effects.vst3/
```

### Data Files
```
/usr/share/surge-xt/          # Factory content
/usr/share/applications/      # Desktop files (if standalone)
/usr/share/icons/             # Icons
```

### User Data
```
~/.local/share/surge-xt/      # User presets, patches, etc.
```

## Dependency Updates

### When to Update Dependencies
- Major version changes
- Build failures
- Upstream README.md changes (check "Linux" section)

### How to Check Dependencies
```bash
# Check what upstream recommends
curl -s https://raw.githubusercontent.com/surge-synthesizer/surge/main/README.md | grep -A 10 "apt install"
```

Current upstream command:
```bash
sudo apt install build-essential git cmake libcairo-dev libxkbcommon-x11-dev \
    libxkbcommon-dev libxcb-cursor-dev libxcb-keysyms1-dev libxcb-util-dev \
    libxrandr-dev libxinerama-dev libxcursor-dev libasound2-dev libjack-jackd2-dev
```

### Dependency Mapping Reference
```
build-essential     → dev-util/cmake (+ system compiler)
git                 → dev-vcs/git
cmake               → dev-util/cmake
libcairo-dev        → x11-libs/cairo
libxkbcommon-*-dev  → x11-libs/libxkbcommon[X]
libxcb-*-dev        → x11-libs/xcb-util-*
libxrandr-dev       → x11-libs/libXrandr
libxinerama-dev     → x11-libs/libXinerama
libxcursor-dev      → x11-libs/libXcursor
libasound2-dev      → media-libs/alsa-lib
libjack-*-dev       → virtual/jack
libcurl*            → net-misc/curl
webkit2gtk-4.0      → net-libs/webkit-gtk:4
gtk+-x11-3.0        → x11-libs/gtk+:3
```

## Testing Checklist

Before committing changes:

### Build Testing
- [ ] Builds with `vst3` only
- [ ] Builds with `clap lv2 vst3`
- [ ] Builds with `standalone`
- [ ] Builds with all USE flags enabled
- [ ] No compilation errors
- [ ] No installation errors

### Runtime Testing
- [ ] VST3 loads in at least one DAW (if available)
- [ ] Standalone runs without crashing (if built)
- [ ] surge-xt-cli responds to `--help`
- [ ] Factory presets are accessible

### File Verification
- [ ] All expected files installed
- [ ] No leftover build artifacts in /usr
- [ ] Desktop files present (if standalone)
- [ ] Icons installed

## Upstream Resources

### Official Links
- Homepage: https://surge-synthesizer.github.io/
- GitHub: https://github.com/surge-synthesizer/surge
- Releases: https://github.com/surge-synthesizer/releases-xt
- Discord: https://discord.gg/spGANHw
- Manual: https://surge-synthesizer.github.io/manual-xt/

### Build Documentation
- Main README: https://github.com/surge-synthesizer/surge/blob/main/README.md
- Developer Guide: https://github.com/surge-synthesizer/surge/blob/main/doc/Developer%20Guide.md
- Linux Guide: https://github.com/surge-synthesizer/surge/blob/main/doc/Linux%20and%20Other%20Unix-like%20Distributions.md

### Getting Help
1. Check upstream README for build changes
2. Search GitHub issues: https://github.com/surge-synthesizer/surge/issues
3. Ask in Discord #build-systems channel
4. Check Gentoo forums/IRC for ebuild questions

## Advanced Options

### Cross-Compilation
The ebuild currently targets amd64. For cross-compilation:
- See upstream documentation for aarch64 support
- Modify KEYWORDS as needed
- Test on target architecture

### VST2 Support
VST2 requires a user-provided SDK (licensing restrictions):
1. User obtains VST2 SDK
2. Set `VST2SDK_DIR` environment variable
3. Add CMake option: `-DVST2SDK_DIR="${VST2SDK_DIR}"`

### Python Bindings
Not currently enabled. To add:
1. Add `python` USE flag
2. Inherit python-single-r1
3. Add CMake option: `-DSURGE_BUILD_PYTHON_BINDINGS=ON`

### LTO (Link-Time Optimization)
Could add for smaller binaries:
```ebuild
src_configure() {
    local mycmakeargs=(
        # ... existing options ...
        $(usex lto '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON' '')
    )
}
```

## Maintenance Schedule

### Regular Checks (Monthly)
- Check for new releases
- Review open issues affecting Linux builds
- Test build still works on current Gentoo

### Version Updates (As Released)
- Surge XT typically releases every 2-3 months
- Test new versions in overlay before marking stable
- Update dependencies if upstream requirements change

### Major Updates (Annual)
- Review all USE flags still relevant
- Check if new features need new USE flags
- Update documentation
- Consider cleanup of old versions

## Contact

For overlay-specific issues:
- Check adaptive-overlay issues/pull requests
- Contact overlay maintainer

For Surge XT build issues:
- GitHub: https://github.com/surge-synthesizer/surge/issues
- Discord: https://discord.gg/spGANHw