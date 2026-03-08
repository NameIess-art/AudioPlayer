import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_audio/statistics.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../widgets/top_glass_panel.dart';
import '../widgets/top_page_header.dart';

class VideoConverterTab extends StatefulWidget {
  const VideoConverterTab({super.key});

  @override
  State<VideoConverterTab> createState() => _VideoConverterTabState();
}

class _VideoConverterTabState extends State<VideoConverterTab> {
  String? _selectedVideoPath;
  String? _outputDirectoryPath;
  bool _isConverting = false;
  double _progress = 0.0;
  String _statusMessage = '';
  int _videoDurationMs = 0;

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      final videoPath = result.files.single.path!;
      setState(() {
        _selectedVideoPath = videoPath;
        _statusMessage = '已选择：${path.basename(videoPath)}';
      });
      await _getVideoDuration(videoPath);
    }
  }

  Future<void> _pickOutputDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _outputDirectoryPath = result;
      });
    }
  }

  Future<void> _getVideoDuration(String videoPath) async {
    final mediaInformation = await FFprobeKit.getMediaInformation(videoPath);
    final information = mediaInformation.getMediaInformation();

    if (information != null) {
      final durationStr = information.getDuration();
      if (durationStr != null) {
        setState(() {
          _videoDurationMs = (double.parse(durationStr) * 1000).toInt();
        });
      }
    }
  }

  Future<void> _startConversion(AudioProvider provider) async {
    if (_selectedVideoPath == null || _outputDirectoryPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择视频文件和输出目录。')),
      );
      return;
    }

    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _statusMessage = '开始转换...';
    });

    final selectedFormat = provider.converterFormat;
    final selectedBitrate = provider.converterBitrate;
    final fileNameNoExt = path.basenameWithoutExtension(_selectedVideoPath!);
    final outputFileName = '$fileNameNoExt.$selectedFormat';
    final outputPath = path.join(_outputDirectoryPath!, outputFileName);

    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    var command = '-i "$_selectedVideoPath" ';

    if (selectedFormat == 'mp3') {
      command += '-vn -ar 44100 -ac 2 -b:a $selectedBitrate ';
    } else if (selectedFormat == 'flac') {
      command += '-vn -c:a flac ';
    } else if (selectedFormat == 'wav') {
      command += '-vn -c:a pcm_s16le -ar 44100 -ac 2 ';
    } else if (selectedFormat == 'aac') {
      command += '-vn -c:a aac -b:a $selectedBitrate ';
    } else if (selectedFormat == 'ogg') {
      command += '-vn -c:a libvorbis -b:a $selectedBitrate ';
    }

    command += '"$outputPath"';

    FFmpegKitConfig.enableStatisticsCallback((Statistics statistics) {
      if (!mounted) return;
      if (_videoDurationMs > 0) {
        final timeInMilliseconds = statistics.getTime();
        setState(() {
          _progress = (timeInMilliseconds / _videoDurationMs).clamp(0.0, 1.0);
          _statusMessage = '转换中：${(_progress * 100).toStringAsFixed(1)}%';
        });
      }
    });

    await FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      if (!mounted) return;

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _isConverting = false;
          _progress = 1.0;
          _statusMessage = '转换完成，已保存至：$outputPath';
        });
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() {
            _selectedVideoPath = null;
            _progress = 0.0;
            _videoDurationMs = 0;
            _statusMessage = '';
          });
        });
      } else if (ReturnCode.isCancel(returnCode)) {
        setState(() {
          _isConverting = false;
          _statusMessage = '转换已取消。';
        });
      } else {
        final logs = await session.getLogsAsString();
        setState(() {
          _isConverting = false;
          _statusMessage = '转换失败，请重试。';
        });
        debugPrint('FFMPEG Error: $logs');
      }
    });
  }

  void _cancelConversion() {
    FFmpegKit.cancel();
    setState(() {
      _isConverting = false;
      _statusMessage = '正在取消转换...';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();
    final selectedFormat = provider.converterFormat;
    final selectedBitrate = provider.converterBitrate;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 90, 16, 104),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PathPickerCard(
                    icon: Icons.video_library_rounded,
                    title: '视频源文件',
                    placeholder: '点击选择需要转换的视频文件',
                    value: _selectedVideoPath,
                    onTap: _isConverting ? null : _pickVideoFile,
                  ),
                  const SizedBox(height: 12),
                  _PathPickerCard(
                    icon: Icons.create_new_folder_rounded,
                    title: '输出目录',
                    placeholder: '点击选择音频保存位置',
                    value: _outputDirectoryPath,
                    onTap: _isConverting ? null : _pickOutputDirectory,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '当前参数：${selectedFormat.toUpperCase()} · ${selectedFormat == 'wav' || selectedFormat == 'flac' ? '格式自动编码' : selectedBitrate}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isConverting || _progress > 0) ...[
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                        begin: 0,
                        end: _isConverting && _videoDurationMs == 0 ? 0 : _progress,
                      ),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: _isConverting && _videoDurationMs == 0 ? null : value,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_statusMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isConverting
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_isConverting)
                    FilledButton.icon(
                      onPressed: _cancelConversion,
                      icon: const Icon(Icons.cancel_rounded),
                      label: const Text('取消转换'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          _selectedVideoPath != null && _outputDirectoryPath != null
                          ? () => _startConversion(provider)
                          : null,
                      icon: const Icon(Icons.transform_rounded),
                      label: const Text('开始转换'),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: TopGlassPanel(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TopPageHeader(
                icon: Icons.sync_rounded,
                title: '视频转音频',
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathPickerCard extends StatelessWidget {
  const _PathPickerCard({
    required this.icon,
    required this.title,
    required this.placeholder,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String placeholder;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = value != null && value!.isNotEmpty;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.4)
                        : cs.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        style: TextStyle(
                          color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.folder_open_rounded, color: cs.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
