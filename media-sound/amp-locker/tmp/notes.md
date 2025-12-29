# Working Notes for building amp-locker ebuild

These notes will be used while we create the build.  Once the ebuild is complete, these notes can be removed.

## Manual Installation Steps

We will itemize the instructions for manually installing this so that we can then cretae an ebuild to automate the process.

1. Download the amp-locker source code from the official repository or website.

   - The download location is: <https://audioassaultdownloads.s3.amazonaws.com/AmpLocker/AmpLocker109/AmpLockerLinux.zip>
   - The current version of Amp Locker is v1.4.4
   - I do not know any method for digging out a .zip file progrmatically by version, the .ebuild may have to hardcode the version number in the SRC_URI

1. The contents of the .zip file are as follows:

AmpLockerLinux/
├── AmpLockerData/
│   ├── Cabs/
│   ├── IRs/
│   ├── NAMs/
│   └── Presets/ [42 amp preset folders including Berry Amp, ReAmp 2, etc.]
├── Amp Locker.lv2/
├── Amp Locker.vst3/
│   └── Contents/ [Resources, x86_64-linux]
└── __MACOSX/
    └── AmpLockerData/ [mirrors main AmpLockerData structure]

Note that we do NOT need to keep the `__MACOSX` directory.

1. The installation process involves copying the plugin files to the appropriate directories.

   - This software is meant to be installed for a user, not system-wide, and this ebuild will need to accomodate that.
   
   If any of the destination folders do not exist they will need to be created.
   - Copy `Amp Locker.lv2/` to `~/.lv2/`
   - Copy `Amp Locker.vst3/` to `~/.vst3/`
   - Copy `Amp Locker Standalone` to `~/bin`
   - Copy the AmpLockerData folder to `~/Audio Assault/PluginData/Audio Assault/AmpLockerData/`

Post installation messages to the user:

- Remind the user to ensure that their DAW is configured to scan the appropriate plugin directories (`~/.lv2/` and `~/.vst3/`).
- Inform the user that the standalone application can be found in their `~/bin` directory.
- Remind teh user to add ~/bin to their PATH if it is not already included.
