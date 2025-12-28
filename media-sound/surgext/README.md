# Surge XT - User Quick Start Guide

## What is Surge XT?

Surge XT is a powerful, free, and open-source hybrid synthesizer with:
- 3 oscillator sections with multiple algorithms
- Flexible modulation engine
- High-quality effects
- Extensive factory preset library
- Multiple plugin formats (CLAP, LV2, VST3)
- Optional standalone application

## Quick Install

### Recommended Installation (All Features)

```bash
sudo emerge --ask media-sound/surge-xt
```

Default USE flags will build: CLAP, LV2, VST3 plugins + standalone

### Custom Installation

#### Plugins Only (No JACK dependency)
```bash
echo "media-sound/surge-xt clap lv2 vst3 -standalone" >> /etc/portage/package.use/surge-xt
sudo emerge --ask media-sound/surge-xt
```

#### Standalone Only
```bash
echo "media-sound/surge-xt standalone -clap -lv2 -vst3" >> /etc/portage/package.use/surge-xt
sudo emerge --ask media-sound/surge-xt
```

#### Minimal Install (VST3 only, fastest)
```bash
echo "media-sound/surge-xt vst3 -clap -lv2 -standalone" >> /etc/portage/package.use/surge-xt
sudo emerge --ask media-sound/surge-xt
```

## Using Surge XT

### As a Plugin in Your DAW

1. **Install with plugin formats:**
   ```bash
   sudo USE="clap lv2 vst3" emerge media-sound/surge-xt
   ```

2. **Rescan plugins in your DAW**
   - Reaper: Options → Preferences → Plug-ins → VST → Re-scan
   - Bitwig: Settings → Locations → Plug-in Locations → Rescan
   - Ardour: Window → Plugin Manager → Refresh
   - Qtractor: View → Instruments → Refresh

3. **Look for:**
   - "Surge XT" (synthesizer)
   - "Surge XT Effects" (effects only)

### As a Standalone Application

1. **Install with standalone flag:**
   ```bash
   sudo USE="standalone" emerge media-sound/surge-xt
   ```

2. **Launch from terminal:**
   ```bash
   surge-xt              # Main synthesizer
   surge-xt-effects      # Effects version
   surge-xt-cli --help   # Command-line tool
   ```

3. **Or from application menu:**
   - Look for "Surge XT" in your audio/multimedia applications

## Where Are Things Installed?

### Plugins
```
/usr/lib64/clap/Surge XT.clap
/usr/lib64/lv2/Surge XT.lv2/
/usr/lib64/vst3/Surge XT.vst3/
```

### Factory Content
```
/usr/share/surge-xt/
├── patches_factory/     # Factory presets
├── patches_3rdparty/    # Community presets
├── wavetables/          # Wavetable files
├── fx_presets/          # Effect presets
└── skins/               # Visual themes
```

### User Data Location
```
~/.local/share/surge-xt/
```

Place your custom presets, patches, and skins here!

## First Steps

### 1. Load a Preset

1. Open Surge XT in your DAW or standalone
2. Click on the patch name at the top
3. Navigate through categories:
   - Basses
   - Leads
   - Pads
   - Keys
   - FX
   - And many more!

### 2. Basic Controls

- **Oscillators:** Left side - 3 oscillator sections
- **Filter:** Center - Flexible routing options
- **Effects:** Right side - 8 effect slots
- **Modulation:** Bottom - LFOs, envelopes, etc.
- **Global:** Top - Master volume, FX bypass, tuning

### 3. Save Your Own Presets

1. Modify a sound you like
2. Right-click on patch name
3. Select "Save Patch"
4. Choose category and name
5. Presets saved to `~/.local/share/surge-xt/`

## Common Questions

### Q: My DAW doesn't see the plugins?

**Check installation:**
```bash
ls /usr/lib64/vst3/    # Should show Surge XT.vst3
ls /usr/lib64/clap/    # Should show Surge XT.clap
ls /usr/lib64/lv2/     # Should show Surge XT.lv2
```

**Make sure:**
1. You built with plugin USE flags enabled
2. Your DAW is configured to scan those directories
3. You rescanned plugins after installation

### Q: I see warnings about curl/webkit during build?

**This is normal!** These are optional JUCE dependencies that Surge XT doesn't actually use. The build will succeed and work perfectly. You can safely ignore these warnings.

### Q: Standalone won't start?

**Check JACK:**
```bash
# Is JACK running?
ps aux | grep jack

# Start JACK if needed
qjackctl &
# or
jack_control start
```

**Or try with ALSA:**
Set audio device in Surge XT preferences.

### Q: How do I update to a newer version?

```bash
# Update overlay
sudo emaint sync -r adaptive-overlay

# Update Surge XT
sudo emerge --ask --update media-sound/surge-xt
```

## Getting Help

### Documentation
- **User Manual:** https://surge-synthesizer.github.io/manual-xt/
- **Website:** https://surge-synthesizer.github.io/

### Community
- **Discord:** https://discord.gg/spGANHw
- **GitHub:** https://github.com/surge-synthesizer/surge

### Reporting Issues

**For build/install issues:**
- Check if it's a Gentoo packaging issue (file with overlay)
- Or upstream build issue (file with Surge developers)

**For Surge XT bugs:**
- Report at: https://github.com/surge-synthesizer/surge/issues

## Tips & Tricks

### Performance

**For better performance:**
- Use Release build (default in ebuild)
- Enable CPU optimizations in /etc/portage/make.conf
- Consider using VST3 over other formats (often more efficient)

### Custom Skins

Download skins from the community:
1. Get .surge-skin files
2. Place in `~/.local/share/surge-xt/`
3. Select in Surge: Menu → Skins → [Your Skin]

### Wavetables

Add custom wavetables:
1. Get .wav files (specific format, see manual)
2. Place in `~/.local/share/surge-xt/wavetables/`
3. Refresh wavetable list in Surge

### Tuning & Scales

Surge supports microtonal tuning:
1. Load .scl files (Scala format)
2. Menu → Tuning → Load .scl file
3. Explore different musical systems!

## Keyboard Shortcuts (Standalone)

- **Ctrl+O:** Open patch browser
- **Ctrl+S:** Save patch
- **Ctrl+,:** Preferences
- **Ctrl+M:** Toggle MIDI learn
- **F1:** Help/Manual
- **Ctrl+Z:** Undo
- **Ctrl+Y:** Redo

## System Requirements

- **OS:** Gentoo Linux (amd64)
- **RAM:** 2GB minimum, 4GB+ recommended
- **CPU:** Modern multi-core processor recommended
- **Audio:** ALSA (plugins) or JACK (standalone)
- **Display:** 1280x800 minimum resolution

## Resource Usage

- **Disk Space:** ~100MB installed
- **Build Time:** 5-15 minutes (depending on CPU and USE flags)
- **CPU Usage:** Moderate (depends on preset complexity)
- **RAM Usage:** ~50-100MB per instance

## Quick Reference: USE Flags

| USE Flag | What It Does | When To Use |
|----------|--------------|-------------|
| clap | CLAP plugins | New format, good compatibility |
| lv2 | LV2 plugins | Linux native, good for Ardour |
| vst3 | VST3 plugins | Best compatibility with most DAWs |
| standalone | Standalone apps | Want to use without DAW |

## Learn More

### Tutorials
- Check the Discord #tutorials channel
- YouTube: Search "Surge XT tutorial"
- Manual: https://surge-synthesizer.github.io/manual-xt/

### Presets
- Included: 1000+ factory presets
- Community: Check Discord for user patches
- Create your own and share!

### Sound Design
- Surge excels at:
  - Complex evolving pads
  - Aggressive leads
  - Rich basses
  - Unique textures
  - Creative effects

## Enjoy!

Surge XT is a powerful and deep synthesizer. Take your time exploring its features, experiment with the modulation matrix, and don't hesitate to ask for help in the community!

**Happy music making! 🎵**