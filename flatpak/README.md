# Podcast Merlin — Flatpak Packaging Guide

This directory contains the Flatpak manifest, packaging scripts, and metadata for **Podcast Merlin** (`com.podcastmerlin.podcast_merlin_flutter`).

---

## 1. Architecture & Sandbox Permissions

Podcast Merlin runs inside the GNOME runtime sandbox (`org.gnome.Platform//50`) with the following permissions:

| Permission | Reason |
| :--- | :--- |
| `--socket=wayland` / `--socket=fallback-x11` | Native Wayland & X11 graphical display |
| `--share=ipc` | Shared memory / X11 performance |
| `--device=dri` | GPU rendering & hardware acceleration |
| `--socket=pulseaudio` | Audio playback via PulseAudio & PipeWire |
| `--share=network` | Streaming episodes, downloading feeds & Nextcloud/gPodder sync |
| `--talk-name=org.freedesktop.secrets` | Encrypted credential storage via FreeDesktop Secret Service |
| `--talk-name=org.freedesktop.Notifications` | System notifications for background download status |
| `--own-name=org.mpris.MediaPlayer2.podcast_merlin` | Desktop media playback controls & hardware media keys |
| `--filesystem=xdg-download` | Storage access for downloaded podcast episodes |

---

## 2. Quick Local Build & Install

A self-contained build script is provided at `scripts/build_flatpak.sh` which uses the host's `flatpak` tool without requiring root privileges or a separate `flatpak-builder` package:

### Build Standalone `.flatpak` Bundle
```bash
# Builds the Flutter release bundle and packages it into build/podcast_merlin.flatpak
./scripts/build_flatpak.sh
```

### Build & Automatically Install Locally
```bash
./scripts/build_flatpak.sh --install
```

### Run the Installed Flatpak
```bash
flatpak run com.podcastmerlin.podcast_merlin_flutter
```

### Advanced Options
```bash
# Skip rebuilding Flutter if build/linux/x64/release/bundle already exists
./scripts/build_flatpak.sh --skip-flutter

# Clean build directory before building
./scripts/build_flatpak.sh --clean
```

---

## 3. Building with `flatpak-builder`

If you have `flatpak-builder` installed and the GNOME Sdk (`org.gnome.Sdk//50`):

```bash
# Install the GNOME 50 SDK and Platform
flatpak install flathub org.gnome.Sdk//50 org.gnome.Platform//50

# Ensure release bundle is built first
flutter build linux --release

# Run flatpak-builder from the repository root
flatpak-builder --install --force-clean build/flatpak/build-dir flatpak/com.podcastmerlin.podcast_merlin_flutter.yaml
```

---

## 4. AppStream Metadata & Desktop Integration

- **AppStream Metainfo**: `linux/com.podcastmerlin.podcast_merlin_flutter.metainfo.xml`
  Validate locally using:
  ```bash
  appstreamcli validate --no-net linux/com.podcastmerlin.podcast_merlin_flutter.metainfo.xml
  ```
- **Desktop Entry**: `linux/com.podcastmerlin.podcast_merlin_flutter.desktop`
  Validate locally using:
  ```bash
  desktop-file-validate linux/com.podcastmerlin.podcast_merlin_flutter.desktop
  ```
- **Icons**: Scalable SVG (`logo.svg`) and high-resolution PNGs (16x16 up to 512x512) installed into standard hicolor directories.
