import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_audio/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:path/path.dart' as path;

class VideoConverterTab extends StatefulWidget {
  const VideoConverterTab({super.key});

  @override
  State<VideoConverterTab> createState() => _VideoConverterTabState();
}

class _VideoConverterTabState extends State<VideoConverterTab> {
  String? _selectedVideoPath;
  String? _outputDirectoryPath;
  String _selectedFormat = 'mp3';
  String _selectedBitrate = '320k';
  
  bool _isConverting = false;
  double _progress = 0.0;
  String _statusMessage = '请选择视频文件并设置转换参数';
  int _videoDurationMs = 0;

  final List<String> _formats = ['mp3', 'flac', 'wav', 'aac', 'ogg'];
  final List<String> _bitrates = ['128k', '192k', '256k', '320k'];

  Future<void> _pickVideoFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      final videoPath = result.files.single.path!;
      setState(() {
        _selectedVideoPath = videoPath;
        _statusMessage = '已选择: ${path.basename(videoPath)}';
      });
      _getVideoDuration(videoPath);
    }
  }

  Future<void> _pickOutputDirectory() async {
    String? result = await FilePicker.platform.getDirectoryPath();

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

  Future<void> _startConversion() async {
    if (_selectedVideoPath == null || _outputDirectoryPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择视频文件和输出目录')),
      );
      return;
    }

    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _statusMessage = '开始转换...';
    });

    final fileNameNoExt = path.basenameWithoutExtension(_selectedVideoPath!);
    final outputFileName = '$fileNameNoExt.$_selectedFormat';
    final outputPath = path.join(_outputDirectoryPath!, outputFileName);

    // If file already exists, we might want to automatically overwrite or rename
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    String command = '-i "$_selectedVideoPath" ';
    
    // Add format specific options
    if (_selectedFormat == 'mp3') {
      command += '-vn -ar 44100 -ac 2 -b:a $_selectedBitrate ';
    } else if (_selectedFormat == 'flac') {
      command += '-vn -c:a flac ';
    } else if (_selectedFormat == 'wav') {
      command += '-vn -c:a pcm_s16le -ar 44100 -ac 2 ';
    } else if (_selectedFormat == 'aac') {
      command += '-vn -c:a aac -b:a $_selectedBitrate ';
    } else if (_selectedFormat == 'ogg') {
      command += '-vn -c:a libvorbis -b:a $_selectedBitrate ';
    }

    command += '"$outputPath"';

    FFmpegKitConfig.enableStatisticsCallback((Statistics statistics) {
      if (_videoDurationMs > 0) {
        final timeInMilliseconds = statistics.getTime();
        setState(() {
          _progress = (timeInMilliseconds / _videoDurationMs).clamp(0.0, 1.0);
          _statusMessage = '转换中: ${(_progress * 100).toStringAsFixed(1)}%';
        });
      }
    });

    await FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _isConverting = false;
          _progress = 1.0;
          _statusMessage = '转换完成！已保存至: $outputPath';
          
          // Reset form fields after brief delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _selectedVideoPath = null;
                _progress = 0.0;
                _videoDurationMs = 0;
                _statusMessage = '请选择视频文件并设置转换参数';
              });
            }
          });
        });
      } else if (ReturnCode.isCancel(returnCode)) {
        setState(() {
          _isConverting = false;
          _statusMessage = '转换已取消';
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
      _statusMessage = '转换正在取消...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频转音频', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video File Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.video_library_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('选择视频来源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                    InkWell(
                      onTap: _isConverting ? null : _pickVideoFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedVideoPath == null
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedVideoPath ?? '轻触选择要转换的视频文件',
                                style: TextStyle(
                                  color: _selectedVideoPath == null
                                      ? Theme.of(context).colorScheme.onSurfaceVariant
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.folder_open_rounded, color: Theme.of(context).colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 32),

            // Output Directory Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.create_new_folder_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('选择保存位置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                    InkWell(
                      onTap: _isConverting ? null : _pickOutputDirectory,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _outputDirectoryPath == null
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _outputDirectoryPath ?? '轻触选择音频保存的文件夹',
                                style: TextStyle(
                                  color: _outputDirectoryPath == null
                                      ? Theme.of(context).colorScheme.onSurfaceVariant
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.folder_open_rounded, color: Theme.of(context).colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 32),

            // Output Settings
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_suggest_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('转换参数设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '目标格式',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
                                value: _selectedFormat,
                                items: _formats.map((format) {
                                  return DropdownMenuItem(
                                    value: format,
                                    child: Text(format.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  );
                                }).toList(),
                                onChanged: _isConverting
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedFormat = value;
                                          });
                                        }
                                      },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '音频码率',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
                                value: _selectedBitrate,
                                items: _bitrates.map((bitrate) {
                                  return DropdownMenuItem(
                                    value: bitrate,
                                    child: Text(bitrate, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  );
                                }).toList(),
                                onChanged: _isConverting || _selectedFormat == 'wav' || _selectedFormat == 'flac'
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedBitrate = value;
                                          });
                                        }
                                      },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
            const SizedBox(height: 48),

            // Conversion Progress and Status
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
              const SizedBox(height: 16),
            ],
            
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isConverting ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            if (_isConverting)
              FilledButton.icon(
                onPressed: _cancelConversion,
                icon: const Icon(Icons.cancel_rounded),
                label: const Text('取消转换', style: TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _selectedVideoPath != null && _outputDirectoryPath != null ? _startConversion : null,
                icon: const Icon(Icons.transform_rounded),
                label: const Text('开始转换', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
