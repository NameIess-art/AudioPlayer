# ASMRPlayer

一个基于 Flutter 的本地 ASMR 音频播放器，支持多任务并行播放、睡眠倒计时（手动/播放触发）以及视频转音频。

## 功能概览

- 本地音频库管理：导入文件夹/单文件，保留分组结构，支持刷新与移除。
- 多会话并行播放：可同时创建多个播放任务，彼此独立控制。
- 播放列表控制：支持播放/暂停、上一首/下一首、进度拖动、音量调节、任务关闭。
- 循环策略：单曲循环、随机循环、文件夹循环、跨文件夹循环。
- 倒计时（新增）：
  `手动开始`：确认后立即开始倒计时。
  `播放后自动开始`：当任意音频开始播放时自动启动/重启倒计时。
- 倒计时结束行为：暂停当前播放中的任务，并可设置“到指定时刻自动恢复播放”。
- 视频转音频：支持将视频导出为 `mp3`、`flac`、`wav`、`aac`、`ogg`。
- 主题与缓存：支持主题切换和临时缓存清理。

## 倒计时使用说明

入口：底部导航栏 `倒计时`

1. 选择时长（分钟/小时）。
2. 选择模式：`手动开始` 或 `播放后自动开始`。
3. 点击确认：
   - 手动模式下可立即开始倒计时。
   - 触发模式下等待音频开始播放后自动开始。
4. 可选：开启“倒计时结束后自动恢复播放”，并设置恢复时间。

## 视频转音频

入口：底部导航栏 `视频转音频`

1. 选择源视频文件。
2. 选择输出目录。
3. 选择目标格式和码率（`wav`、`flac` 不使用码率选项）。
4. 点击开始转换并等待完成。

实现说明：

- 使用 `ffmpeg_kit_flutter_new_audio` 执行转码。
- 使用 `FFprobe` 获取视频时长并驱动进度显示。
- 支持转换取消，失败时输出 FFmpeg 日志用于排查。

## 环境要求

- Flutter `3.41.x`
- Dart `3.11.x`
- Android 真机或模拟器（当前主要验证 Android）

## 快速开始

```bash
flutter pub get
flutter run
```

指定设备运行：

```bash
flutter devices
flutter run -d <device-id>
```

## 构建发布

```bash
flutter build apk --release
```

产物路径：

`build/app/outputs/flutter-apk/app-release.apk`

## 项目结构

```text
lib/
  main.dart
  providers/
    audio_provider.dart
  screens/
    main_screen.dart
    library_tab.dart
    playlist_tab.dart
    timer_tab.dart
    video_converter_tab.dart
    settings_tab.dart
  theme/
    theme_provider.dart
```

## 说明

- 首次构建会下载 Android 依赖，耗时可能较长。
- 若视频转换失败，优先检查源视频可读性和输出目录写权限。
