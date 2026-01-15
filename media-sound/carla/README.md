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
| `X` | **Yes** | Enable X11 support for plugin UIs. |

## Plugin Bridges

Carla uses bridges to run plugins that are built for different architectures or platforms than the host system.

### Available Bridges

- **Native bridge** (`carla-bridge-native`): Always built. Runs native plugins in a separate process for stability.
- **Linux 32-bit bridge** (`carla-bridge-posix32`): Built when `abi_x86_32` USE flag is enabled. Allows running 32-bit Linux plugins on a 64-bit host.

### Known Limitations

- **`abi_x86_32` and `osc` are mutually exclusive**: The 32-bit bridge requires 32-bit versions of all optional dependencies. Since `media-libs/liblo` does not have multilib (32-bit) support in Gentoo, you cannot enable both `abi_x86_32` and `osc` at the same time. If you need OSC support, you must disable the 32-bit bridge.

### Planned Bridge Support

Future versions of this ebuild may include:

- **Windows 32-bit bridge** (`carla-bridge-win32.exe`): For running 32-bit Windows VST plugins via Wine.
- **Windows 64-bit bridge** (`carla-bridge-win64.exe`): For running 64-bit Windows VST plugins via Wine.

## Example Usage

To build Carla with 32-bit plugin bridge support:

```bash
echo "media-sound/carla abi_x86_32" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

To build with common audio production features (without 32-bit bridge):

```bash
echo "media-sound/carla alsa gtk osc qt5 sf2 sndfile X" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

To build with 32-bit bridge support (note: `osc` must be disabled):

```bash
echo "media-sound/carla alsa gtk qt5 sf2 sndfile X abi_x86_32 -osc" >> /etc/portage/package.use/carla
emerge media-sound/carla
```

## Notes

- The `carla-control` binary is removed during installation as it is not functional in standalone builds.
- JACK support is always enabled (required dependency).
- FFmpeg support is currently disabled.
- ZynAddSubFX internal plugin support is currently disabled.