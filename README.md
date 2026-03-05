# ASMRPlayer

基于 Flutter 的本地音频播放器，支持多音轨并行播放与独立控制，并内置视频转音频工具。

## 功能概览

- 本地音频库管理：导入文件夹、导入文件、刷新监听目录。
- 多会话并行播放：可同时播放多条音轨，互不抢占。
- 单会话独立控制：支持播放/暂停、进度拖动、音量调节、关闭任务。
- 循环策略：单曲循环、随机循环、同文件夹循环、跨文件夹循环。
- 视频转音频：支持将视频提取为 `mp3`、`flac`、`wav`、`aac`、`ogg`。
- 主题与缓存管理：支持主题切换与临时缓存清理。

## 视频转音频

入口：底部导航栏 `视频转音频`。

使用步骤：

1. 选择源视频文件。
2. 选择输出目录。
3. 选择目标格式和码率（`wav`、`flac` 不使用码率选项）。
4. 点击“开始转换”，等待进度完成。
5. 转换成功后文件保存到你选择的目录。

实现说明：

- 使用 `ffmpeg_kit_flutter_new_audio` 执行转码。
- 通过 `FFprobe` 获取视频时长并驱动进度条。
- 转换支持取消，失败会输出 FFmpeg 日志用于排查。

## 环境要求

- Flutter `3.41.x`（Dart `3.11.x`）
- Android 真机或模拟器（当前项目主要验证 Android）

## 快速开始

```bash
flutter pub get
flutter run
```

指定真机运行（示例）：

```bash
flutter devices
flutter run -d <device-id>
```

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
    video_converter_tab.dart
    settings_tab.dart
  theme/
    theme_provider.dart
```

## 说明

- 首次构建会下载 Android 依赖，耗时会较长。
- 如果转换失败，优先检查源视频是否可播放、输出目录是否可写。
