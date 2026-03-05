import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_audio/statistics.dart';
import 'package:ffmpeg_kit_flutter_audio/ffprobe_kit.dart';
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
        title: const Text('视频转音频'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video File Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. 选择视频', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedVideoPath ?? '未选择视频文件',
                            style: TextStyle(
                              color: _selectedVideoPath == null ? Colors.grey : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isConverting ? null : _pickVideoFile,
                          icon: const Icon(Icons.video_file),
                          label: const Text('选择'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Output Directory Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('2. 输出位置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _outputDirectoryPath ?? '未选择输出文件夹',
                            style: TextStyle(
                              color: _outputDirectoryPath == null ? Colors.grey : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isConverting ? null : _pickOutputDirectory,
                          icon: const Icon(Icons.folder),
                          label: const Text('选择'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Output Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('3. 转换设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: '目标格式',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
                                value: _selectedFormat,
                                items: _formats.map((format) {
                                  return DropdownMenuItem(
                                    value: format,
                                    child: Text(format.toUpperCase()),
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
                            decoration: const InputDecoration(
                              labelText: '音频码率',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
                                value: _selectedBitrate,
                                items: _bitrates.map((bitrate) {
                                  return DropdownMenuItem(
                                    value: bitrate,
                                    child: Text(bitrate),
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
              ),
            ),
            const SizedBox(height: 24),

            // Conversion Progress and Status
            if (_isConverting || _progress > 0) ...[
              LinearProgressIndicator(
                value: _isConverting && _videoDurationMs == 0 ? null : _progress,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 16),
            ],
            
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isConverting ? Colors.blue : null,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            if (_isConverting)
              ElevatedButton.icon(
                onPressed: _cancelConversion,
                icon: const Icon(Icons.cancel),
                label: const Text('取消转换'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _selectedVideoPath != null && _outputDirectoryPath != null ? _startConversion : null,
                icon: const Icon(Icons.transform),
                label: const Text('开始转换'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
