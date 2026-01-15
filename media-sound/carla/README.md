# Carla Audio Plugin Host

Carla is a fully-featured audio plugin host, with support for many audio drivers and plugin formats.

## Homepage

https://kx.studio/Applications:Carla

## USE Flags

| Flag | Default | Description |
|------|---------|-------------|
| `abi_x86_32` | No | Build the Linux 32-bit bridge (`carla-bridge-posix32`) for running 32-bit Linux plugins on a 64-bit system. Requires multilib support. |
| `alsa` | **Yes** | Enable ALSA (Advanced Linux Sound Architecture) audio driver support. |
| `gtk` | **Yes** | Enable GTK+ 3 UI support for plugins that use GTK+ interfaces. |
| `opengl` | **Yes** | Enable OpenGL support in the PyQt5 GUI. |
| `osc` | No | Enable OSC (Open Sound Control) support via liblo for remote control capabilities. |
| `pulseaudio` | **Yes** | Enable PulseAudio audio driver support. |
| `qt5` | No | Build the Qt5-based theme and enable Qt5 UI support. |
| `rdf` | No | Enable RDF (Resource Description Framework) support via rdflib for enhanced LV2 plugin metadata. |
| `sf2` | **Yes** | Enable SoundFont2 support via FluidSynth for SF2/SF3 instrument playback. |
| `sndfile` | No | Enable audio file loading support via libsndfile. |
| `wine` | No | Build Windows 64-bit bridge (`carla-bridge-win64.exe`) for running 64-bit Windows VST plugins via Wine. Requires `dev-util/mingw64-toolchain`. |
| `wine32` | No | Build Windows 32-bit bridge (`carla-bridge-win32.exe`) for running 32-bit Windows VST plugins via Wine. Requires `dev-util/mingw64-toolchain[abi_x86_32]`. |
| `X` | **Yes** | Enable X11 support for plugin UIs. |

## Plugin Bridges

Carla uses bridges to run plugins that are built for different architectures or platforms than the host system.

### Available Bridges

- **Native bridge** (`carla-bridge-native`): Always built. Runs native plugins in a separate process for stability.
- **Linux 32-bit bridge** (`carla-bridge-posix32`): Built when `abi_x86_32` USE flag is enabled. Allows running 32-bit Linux plugins on a 64-bit host.
- **Windows 32-bit bridge** (`carla-bridge-win32.exe`): Built when `wine32` USE flag is enabled. Allows running 32-bit Windows VST plugins via Wine.
- **Windows 64-bit bridge** (`carla-bridge-win64.exe`): Built when `wine` USE flag is enabled. Allows running 64-bit Windows VST plugins via Wine.

### Known Limitations

- **`abi_x86_32` and `osc` are mutually exclusive**: The 32-bit bridge requires 32-bit versions of all optional dependencies. Since `media-libs/liblo` does not have multilib (32-bit) support in Gentoo, you cannot enable both `abi_x86_32` and `osc` at the same time. If you need OSC support, you must disable the 32-bit bridge.

- **Wine bridges require `mingw64-toolchain`**: The Windows bridges are built using the `dev-util/mingw64-toolchain` package. This package does not include `libssp` (Stack Smashing Protector), so we patch Carla to build without it. For the proper solution with stack protection, see the [Gentoo MinGW wiki](https://wiki.gentoo.org/wiki/Mingw#libssp) for setting up crossdev with the `libssp` USE flag.

## Example Usage

To build Carla with default settings:

```bash
emerge media-sound/carla
```

To build with 32-bit Linux plugin bridge support (note: `osc` must be disabled):

```bash
echo "media-sound/carla abi_x86_32 -osc" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

To build with Windows 64-bit VST plugin support via Wine:

```bash
echo "media-sound/carla wine" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

To build with Windows 32-bit VST plugin support via Wine:

```bash
echo "media-sound/carla wine32" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

To build with all bridge support (32-bit Linux + both Windows bridges):

```bash
echo "media-sound/carla abi_x86_32 wine wine32 -osc" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

## Dependencies for Wine Bridges

The Wine bridges require:

- **Build time**: `dev-util/mingw64-toolchain` - Provides the MinGW cross-compilers for building Windows executables. The `wine32` flag requires `mingw64-toolchain[abi_x86_32]` for 32-bit support.
- **Run time**: `app-emulation/wine-staging` (or another Wine variant) - Required to actually run Windows plugins.

## Notes

- The `carla-control` binary is removed during installation as it is not functional in standalone builds.
- JACK support is always enabled (required dependency).
- FFmpeg support is currently disabled.
- ZynAddSubFX internal plugin support is currently disabled.