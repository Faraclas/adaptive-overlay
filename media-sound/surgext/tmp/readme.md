# Purpose

This document provides an overview of Surge XT, a powerful software synthesizer used for music production.

- ✅ Ebuild created! See the installation section below.

## Latest Version

As of June 2024, the latest stable version of Surge XT is 1.3.4
link: <https://github.com/surge-synthesizer/releases-xt/releases/tag/1.3.4>

- <https://github.com/surge-synthesizer/releases-xt/releases/download/1.3.4/surge-xt-linux-x86_64-1.3.4.tar.gz>
- <https://github.com/surge-synthesizer/releases-xt/releases/download/1.3.4/surge-xt-linux-x64-1.3.4.deb>

## Gentoo Installation

An ebuild has been created for easy installation on Gentoo Linux!

### Quick Start

1. Copy the ebuild files to your local overlay:
   ```bash
   sudo mkdir -p /var/db/repos/localrepo/media-sound/surge-xt
   sudo cp surge-xt-1.3.4.ebuild /var/db/repos/localrepo/media-sound/surge-xt/
   sudo cp metadata.xml /var/db/repos/localrepo/media-sound/surge-xt/
   ```

2. Generate the manifest:
   ```bash
   cd /var/db/repos/localrepo/media-sound/surge-xt
   sudo ebuild surge-xt-1.3.4.ebuild manifest
   ```

3. Install with your preferred plugin formats:
   ```bash
   sudo USE="clap lv2 vst3" emerge -av media-sound/surge-xt
   ```

For detailed installation instructions, see **INSTALL.md**

### Files Included

- **surge-xt-1.3.4.ebuild** - The main ebuild file
- **metadata.xml** - Package metadata and USE flag descriptions
- **INSTALL.md** - Comprehensive installation guide

### Package Contents

The tarball contains a directory named `surge-xt-linux-x86_64-1.3.4` which 
includes three directories meant to be installed in /usr/{named}:
  - `bin/`: Contains the executable files.
  - `share/`: Contains shared resources like presets and documentation.
  - `lib/`: Contains necessary shared libraries.

## Package Structure (3-Level Tree)

```
surge-xt-linux-x86_64-1.3.4/
├── bin/
│   ├── Surge XT
│   ├── surge-xt-cli
│   └── Surge XT Effects
├── lib/
│   ├── clap/
│   │   ├── Surge XT.clap
│   │   └── Surge XT Effects.clap
│   ├── lv2/
│   │   ├── Surge XT.lv2/
│   │   └── Surge XT Effects.lv2/
│   └── vst3/
│       ├── Surge XT.vst3/
│       └── Surge XT Effects.vst3/
└── share/
    ├── applications/
    │   ├── Surge-XT.desktop
    │   └── Surge-XT-FX.desktop
    ├── icons/
    │   ├── hicolor/ (16x16, 32x32, 48x48, 64x64, 128x128, 256x256, 384x384, 512x512)
    │   └── scalable/
    └── surge-xt/
        ├── doc/ (changelog, copyright)
        ├── fx_presets/ (25+ effect categories)
        ├── modulator_presets/ (Envelope, Formula, LFO, MSEG, Step Seq)
        ├── patches_3rdparty/ (32+ contributor collections)
        ├── patches_factory/ (Basses, Brass, Chords, FX, Keys, Leads, etc.)
        ├── skins/ (dark-mode, Tutorials)
        ├── tuning_library/ (SCL scales, KBM mappings)
        ├── wavetables/ (Basic, Generated, Oneshot, Rhythmic, Sampled, Waldorf)
        ├── wavetables_3rdparty/ (A.Liv, Damon Armani, Emu, Layzer, etc.)
        └── WHERE TO PLACE USER DATA.txt
```
