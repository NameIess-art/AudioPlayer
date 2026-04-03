# AudioPlayer

`AudioPlayer` is a Flutter-based local audio player focused on Android. It is built for personal libraries with multi-session playback, grouped playback notifications, recursive cover-art discovery, sleep timer workflows, and video-to-audio conversion.

## Highlights

- Local library management for folders and individual files
- Multi-session parallel playback with independent controls
- Android playback notifications with grouped summary and per-session child notifications
- Recursive cover-art discovery for library folders, playlists, and `content://` sources
- Playlist controls including play/pause, previous/next, seek, volume, and session close
- Loop and playback strategies including single-track loop, shuffle, folder loop, and cross-folder playback
- Sleep timer with manual start and playback-triggered start modes
- Video-to-audio conversion powered by `ffmpeg_kit_flutter_new_audio`
- Theme switching, temporary cache cleanup, and settings management

## Current Release

- Version: `1.0.3+4`
- GitHub Release: [v1.0.3](https://github.com/NameIess-art/AudioPlayer/releases/tag/v1.0.3)
- Android APK: [AudioPlayer-v1.0.3-release.apk](https://github.com/NameIess-art/AudioPlayer/releases/download/v1.0.3/AudioPlayer-v1.0.3-release.apk)

## Tech Stack

- Flutter `3.41.x`
- Dart `3.11.x`
- `just_audio`
- `audio_service` with a local patched copy under `third_party/audio_service`
- `provider`
- `shared_preferences`
- `ffmpeg_kit_flutter_new_audio`

## Project Structure

```text
lib/
  main.dart
  i18n/
  providers/
  screens/
  services/
  theme/
  widgets/

android/
  app/
    src/main/

third_party/
  audio_service/
```

## Getting Started

```bash
flutter pub get
flutter run
```

To run on a specific device:

```bash
flutter devices
flutter run -d <device-id>
```

## Build

Debug APK:

```bash
flutter build apk --debug
```

Release APK:

```bash
flutter build apk --release
```

Build output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Main Screens

- `Library`: browse imported local audio groups and discovered cover art
- `Playlist`: manage active playback sessions and per-session controls
- `Timer`: configure sleep timer behavior
- `Video Converter`: extract audio from video files
- `Settings`: theme, cache, permissions, and related preferences

## Notes

- This project is currently verified primarily on Android.
- The repository includes a local `audio_service` override because notification behavior and Android playback handling have been customized.
- If video conversion fails, first check source file readability, storage permission state, and output directory write access.
