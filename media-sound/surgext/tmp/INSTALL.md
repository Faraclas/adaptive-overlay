# Installing Surge XT on Gentoo Linux

This guide explains how to install Surge XT 1.3.4 on Gentoo using the provided ebuild.

## Prerequisites

- Gentoo Linux system with portage
- Root or sudo access
- A local overlay for custom ebuilds (recommended)

## Installation Steps

### 1. Set Up a Local Overlay (if you don't have one)

If you don't already have a local overlay, create one:

```bash
sudo mkdir -p /var/db/repos/localrepo
sudo chown -R portage:portage /var/db/repos/localrepo
```

Create the overlay configuration:

```bash
sudo nano /etc/portage/repos.conf/localrepo.conf
```

Add the following content:

```ini
[localrepo]
location = /var/db/repos/localrepo
masters = gentoo
auto-sync = no
```

### 2. Create the Package Directory Structure

```bash
sudo mkdir -p /var/db/repos/localrepo/media-sound/surge-xt
```

### 3. Copy the Ebuild Files

Copy the ebuild and metadata files to your local overlay:

```bash
sudo cp surge-xt-1.3.4.ebuild /var/db/repos/localrepo/media-sound/surge-xt/
sudo cp metadata.xml /var/db/repos/localrepo/media-sound/surge-xt/
```

### 4. Set Proper Permissions

```bash
sudo chown -R portage:portage /var/db/repos/localrepo/media-sound/surge-xt
```

### 5. Generate the Manifest

```bash
cd /var/db/repos/localrepo/media-sound/surge-xt
sudo ebuild surge-xt-1.3.4.ebuild manifest
```

### 6. Install the Package

You can now install Surge XT with your desired USE flags:

#### Install with all plugin formats (recommended):
```bash
sudo emerge -av media-sound/surge-xt
```

#### Install with specific plugin formats:
```bash
# VST3 only
sudo USE="vst3 -clap -lv2" emerge -av media-sound/surge-xt

# VST3 and CLAP
sudo USE="vst3 clap -lv2" emerge -av media-sound/surge-xt

# All formats (explicit)
sudo USE="vst3 clap lv2" emerge -av media-sound/surge-xt
```

#### Set permanent USE flags (optional):
Add to `/etc/portage/package.use/surge-xt`:
```
media-sound/surge-xt clap lv2 vst3
```

Then install:
```bash
sudo emerge -av media-sound/surge-xt
```

## What Gets Installed

After installation, you'll have:

### Executables
- `/usr/bin/Surge XT` - Full synthesizer (standalone)
- `/usr/bin/Surge XT Effects` - Effects-only version (standalone)
- `/usr/bin/surge-xt-cli` - Command-line interface

### Plugins (depending on USE flags)
- **CLAP**: `/usr/lib64/clap/Surge XT.clap` and `Surge XT Effects.clap`
- **LV2**: `/usr/lib64/lv2/Surge XT.lv2/` and `Surge XT Effects.lv2/`
- **VST3**: `/usr/lib64/vst3/Surge XT.vst3/` and `Surge XT Effects.vst3/`

### Shared Resources
- `/usr/share/surge-xt/` - Factory presets, wavetables, skins, tuning library
- `/usr/share/applications/` - Desktop entries
- `/usr/share/icons/` - Application icons

### Documentation
- `/usr/share/doc/surge-xt-1.3.4/` - Changelog, copyright, user data guide

## Using Surge XT

### Standalone Applications
Launch from your application menu or terminal:
```bash
"Surge XT"              # Full synthesizer
"Surge XT Effects"      # Effects only
surge-xt-cli           # Command-line interface
```

### In Your DAW
The plugins will be automatically detected by most DAWs:
- **Reaper**, **Bitwig**, **Ardour**, **Qtractor**, etc.
- Scan for new plugins in your DAW's plugin manager

## User Data Location

For custom presets, patches, and skins, see:
```bash
cat /usr/share/doc/surge-xt-1.3.4/"WHERE TO PLACE USER DATA.txt"
```

Typically, user data goes in:
- `~/.local/share/surge-xt/` (Linux/XDG standard)

## Updating

To update to a newer version:

1. Download or create the new ebuild (e.g., `surge-xt-1.3.5.ebuild`)
2. Copy it to `/var/db/repos/localrepo/media-sound/surge-xt/`
3. Generate the manifest: `sudo ebuild surge-xt-1.3.5.ebuild manifest`
4. Update: `sudo emerge -av media-sound/surge-xt`

## Uninstalling

To remove Surge XT:
```bash
sudo emerge -av --depclean media-sound/surge-xt
```

## Troubleshooting

### Missing Dependencies
If you encounter missing dependency errors, make sure you have the required libraries:
```bash
sudo emerge -av media-libs/alsa-lib media-libs/freetype media-libs/libglvnd
```

### Plugin Not Detected in DAW
1. Verify the plugin is installed:
   ```bash
   ls /usr/lib64/vst3/
   ls /usr/lib64/clap/
   ls /usr/lib64/lv2/
   ```
2. Rescan plugins in your DAW
3. Check DAW plugin search paths in preferences

### Permission Issues
If you have permission errors, ensure proper ownership:
```bash
sudo chown -R portage:portage /var/db/repos/localrepo/media-sound/surge-xt
```

## Additional Resources

- **Official Documentation**: https://surge-synthesizer.github.io/manual-xt/
- **GitHub Repository**: https://github.com/surge-synthesizer/surge
- **Issue Tracker**: https://github.com/surge-synthesizer/surge/issues
- **Discord Community**: https://discord.gg/spGANHw

## Notes

- This is a binary package (precompiled by upstream)
- The ebuild uses `QA_PREBUILT` to skip QA checks on binary files
- All plugin formats can be installed simultaneously
- At least one plugin format (clap, lv2, or vst3) must be selected