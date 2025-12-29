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
tree /var/tmp/portage/media-sound/amp-locker-1.4.4/image/
# or
ls -R /var/tmp/portage/media-sound/amp-locker-1.4.4/image/
```

Check that:
- LV2 plugin is in `usr/lib64/lv2/Amp Locker.lv2/`
- VST3 plugin is in `usr/lib64/vst3/Amp Locker.vst3/`
- Standalone binary is in `opt/bin/audioassault/amplocker/Amp Locker Standalone`
- AmpLockerData folder is in `opt/bin/audioassault/amplocker/AmpLockerData/`
- The `amplocker` script is in `usr/bin/amplocker`
- AmpLockerData has proper permissions (0777)

```bash
# Check AmpLockerData permissions
stat /var/tmp/portage/media-sound/amp-locker-1.4.4/image/opt/bin/audioassault/amplocker/AmpLockerData/
```

## 6. Clean Up Test Files

```bash
PORTAGE_WORKDIR_MODE="0770" ebuild ./amp-locker-1.4.4.ebuild clean
```

This removes the temporary build directory.

## 7. Install to Live System (if all looks good)

```bash
# Install with default USE flags (lv2 and vst3 enabled)
sudo emerge amp-locker

# Or install with only LV2 (no VST3)
sudo USE="-vst3" emerge amp-locker

# Or install with only VST3 (no LV2)
sudo USE="-lv2" emerge amp-locker
```

## 8. Verify System Installation

```bash
# Check that files were installed
ls -la /usr/lib64/lv2/Amp\ Locker.lv2/
ls -la /usr/lib64/vst3/Amp\ Locker.vst3/
ls -la /opt/bin/audioassault/amplocker/
stat /opt/bin/audioassault/amplocker/AmpLockerData/

# Check that amplocker script is available
which amplocker
amplocker --help
```

## 9. Install to User Home Directory

Each user who wants to use Amp Locker should run:

```bash
amplocker --install
```

This will copy files to:
- `~/bin/amp-locker-standalone`
- `~/.lv2/Amp Locker.lv2/`
- `~/.vst3/Amp Locker.vst3/`
- `~/Audio Assault/PluginData/Audio Assault/AmpLockerData/`

## 10. Test the Installation

```bash
# Launch standalone (no parameters)
amplocker

# Or launch standalone from ~/bin
~/bin/amp-locker-standalone

# Check that data directory was created
ls -la ~/Audio\ Assault/PluginData/Audio\ Assault/AmpLockerData/

# Verify user plugin paths
ls -la ~/.lv2/Amp\ Locker.lv2/
ls -la ~/.vst3/Amp\ Locker.vst3/

# Check ~/bin is in PATH
echo $PATH | grep "${HOME}/bin"
```

## 11. Test in a DAW

- Open your DAW (Reaper, Ardour, Bitwig, etc.)
- Scan for plugins
- Both system-wide plugins (`/usr/lib64/lv2` and `/usr/lib64/vst3`) and user-local plugins (`~/.lv2` and `~/.vst3`) should be detected
- Load the Amp Locker plugin to verify it works

## 12. Uninstalling from Home Directory

To remove Amp Locker from your home directory (while keeping the system files):

```bash
amplocker --uninstall
```

This will:
- Remove the standalone from `~/bin`
- Remove LV2 and VST3 plugins from `~/.lv2` and `~/.vst3`
- Ask whether to remove plugin data (presets, IRs, etc.)

## 13. Complete System Uninstall

To completely remove Amp Locker from the system:

```bash
# First uninstall from home directory
amplocker --uninstall

# Then uninstall system package
sudo emerge --unmerge amp-locker
```

## Notes

- The system installation to `/usr/lib64/lv2` and `/usr/lib64/vst3` means most DAWs will find the plugins automatically without user installation
- User installation with `amplocker --install` is optional but recommended for:
  - Having a local copy you can modify
  - Having the standalone in `~/bin`
  - Having plugin data in your home directory
- The AmpLockerData folder at `/opt/bin/audioassault/amplocker/AmpLockerData/` has 0777 permissions to allow user modifications