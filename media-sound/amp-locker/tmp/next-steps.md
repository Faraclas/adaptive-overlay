# Next Steps for Testing amp-locker-1.4.4.ebuild

Follow these steps in order to test and install the amp-locker ebuild.

## 1. Create/Update the Manifest

```bash
cd /home/elias/code/gentoo/adaptive-overlay/media-sound/amp-locker
PORTAGE_WORKDIR_MODE="0770" GENTOO_MIRRORS="" ebuild ./amp-locker-1.4.4.ebuild manifest
```

This downloads the source file and creates checksums.

## 2. Test Unpack Phase

```bash
PORTAGE_WORKDIR_MODE="0770" GENTOO_MIRRORS="" ebuild ./amp-locker-1.4.4.ebuild clean unpack
```

This extracts the zip file to verify it unpacks correctly.

## 3. Test Compile Phase

```bash
PORTAGE_WORKDIR_MODE="0770" GENTOO_MIRRORS="" ebuild ./amp-locker-1.4.4.ebuild compile
```

Note: This may be a no-op since amp-locker is a binary package, but run it to verify.

## 4. Test Install Phase

```bash
PORTAGE_WORKDIR_MODE="0770" GENTOO_MIRRORS="" ebuild ./amp-locker-1.4.4.ebuild install
```

This stages files to `/var/tmp/portage/media-sound/amp-locker-1.4.4/image/` - **does NOT touch your live system**.

## 5. Inspect the Staged Files

```bash
# List all files
find /var/tmp/portage/media-sound/amp-locker-1.4.4/image/ -type f

# Browse directory structure
ls -R /var/tmp/portage/media-sound/amp-locker-1.4.4/image/
```

Check that:
- Files are staged to `/usr/share/amp-locker/`
- Setup script is in `/usr/bin/amp-locker-setup`
- Uninstall script is in `/usr/bin/amp-locker-uninstall`
- AmpLockerData directory is present
- LV2 and VST3 plugins are present (if USE flags enabled)

## 6. Clean Up Test Files

```bash
PORTAGE_WORKDIR_MODE="0770" ebuild ./amp-locker-1.4.4.ebuild clean
```

This removes the temporary build directory.

## 7. Install to Live System (if all looks good)

```bash
emerge amp-locker
```

Or with specific USE flags:

```bash
# Install with only LV2 (no VST3)
USE="-vst3" emerge amp-locker

# Install everything (default)
emerge amp-locker
```

## 8. Run User Setup

After the system installation, each user needs to run:

```bash
amp-locker-setup
```

This will copy the files to the user's home directory:
- `~/bin/amp-locker-standalone`
- `~/.lv2/Amp Locker.lv2/`
- `~/.vst3/Amp Locker.vst3/`
- `~/Audio Assault/PluginData/Audio Assault/AmpLockerData/`

## 9. Test the Installation

```bash
# Launch standalone
amp-locker-standalone

# Check that data directory was created
ls -la ~/Audio\ Assault/PluginData/Audio\ Assault/AmpLockerData/

# Verify plugin paths
ls -la ~/.lv2/Amp\ Locker.lv2/
ls -la ~/.vst3/Amp\ Locker.vst3/

# Check ~/bin is in PATH
echo $PATH | grep -o "${HOME}/bin"
```

## 10. Uninstalling from Home Directory

To remove Amp Locker from your home directory (while keeping the system files):

```bash
amp-locker-uninstall
```

This will prompt you whether to remove user data (presets, IRs, etc.).