# AudioPlayer

`AudioPlayer` 是一款基于 Flutter 开发、面向 Android 的本地音频播放器，主要适用同人音声、asmr音频库场景，支持多会话播放、通知栏分组控制、封面递归发现、睡眠计时器，以及视频转音频等能力。

## 功能亮点

- 支持按文件夹或单文件导入本地音频库
- 支持多会话并行播放，每个会话可独立控制
- Android 通知栏支持分组摘要通知和子会话通知
- 支持递归发现音频库文件夹、播放列表和 `content://` 来源中的封面图
- 播放列表支持播放、暂停、上一首、下一首、拖动进度、调节音量和关闭会话
- 支持单曲循环、随机播放、文件夹循环、跨文件夹播放等播放策略
- 支持睡眠计时器，并提供手动启动和播放触发启动两种模式
- 基于 `ffmpeg_kit_flutter_new_audio` 支持视频转音频
- 支持主题切换、临时缓存清理和常用设置管理

## 当前版本

- 版本号：`1.0.4+5`
- GitHub Release：[v1.0.4](https://github.com/NameIess-art/AudioPlayer/releases/tag/v1.0.4)
- Android APK：[AudioPlayer-v1.0.4-arm64.apk](https://github.com/NameIess-art/AudioPlayer/releases/download/v1.0.4/AudioPlayer-v1.0.4-arm64.apk)

## 技术栈

- Flutter `3.41.x`
- Dart `3.11.x`
- `just_audio`
- `audio_service`，并在 `third_party/audio_service` 下维护了本地定制版本
- `provider`
- `shared_preferences`
- `ffmpeg_kit_flutter_new_audio`

## 项目结构

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

## 快速开始

```bash
flutter pub get
flutter run
```

如果要在指定设备上运行：

```bash
flutter devices
flutter run -d <device-id>
```

## 构建

调试包：

```bash
flutter build apk --debug
```

发布包：

```bash
flutter build apk --release
```

构建产物默认输出到：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 主要页面

- `音频库`：浏览已导入的本地音频分组和识别到的封面
- `播放列表`：管理当前活动播放会话及其控制项
- `计时器`：配置睡眠计时器行为
- `视频转换`：从视频中提取音频
- `设置`：管理主题、缓存、权限和相关偏好项

## 说明

- 当前项目主要在 Android 平台上进行验证和使用。
- 仓库中包含了本地覆盖的 `audio_service`，因为通知栏行为和 Android 播放链路做了定制化修改。
- 如果视频转换失败，建议优先检查源文件是否可读、存储权限是否正常，以及输出目录是否可写。
