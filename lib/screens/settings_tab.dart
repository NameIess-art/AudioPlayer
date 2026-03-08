import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/top_glass_panel.dart';
import '../widgets/top_page_header.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  Future<void> _clearTempCache(BuildContext context) async {
    final cacheDir = Directory(
      path.join(Directory.systemTemp.path, 'music_player_imports'),
    );
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('临时缓存已清理。')));
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('没有可清理的临时缓存。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final audioProvider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final format = audioProvider.converterFormat;
    final bitrate = audioProvider.converterBitrate;
    final bitrateEnabled = format != 'wav' && format != 'flac';

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 90, 16, 104),
            children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                children: [
                  SwitchListTile(
                    value: themeProvider.isDarkMode,
                    onChanged: themeProvider.toggleTheme,
                    title: const Text('深色模式'),
                    subtitle: const Text('夜间使用更低眩光的配色。'),
                    secondary: const Icon(Icons.dark_mode_rounded),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    onTap: () => _clearTempCache(context),
                    title: const Text('清理临时缓存'),
                    subtitle: const Text(
                      '删除导入过程中生成的临时文件。',
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.cleaning_services_rounded,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.transform_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '转码默认参数',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectField(
                          label: '格式',
                          value: format,
                          items: AudioProvider.converterFormats,
                          displayBuilder: (item) => item.toUpperCase(),
                          onChanged: (value) {
                            if (value != null) {
                              audioProvider.setConverterSettings(format: value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SelectField(
                          label: '码率',
                          value: bitrate,
                          items: AudioProvider.converterBitrates,
                          displayBuilder: (item) => item,
                          enabled: bitrateEnabled,
                          onChanged: (value) {
                            if (value != null) {
                              audioProvider.setConverterSettings(bitrate: value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    bitrateEnabled
                        ? 'MP3 / AAC / OGG 输出会使用该码率。'
                        : '${format.toUpperCase()} 使用格式内置编码参数，码率设置不生效。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        '关于',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本地音乐播放器 v1.0.1',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '支持并发会话与高保真音频播放。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
            ],
          ),
        ),
        const Align(
          alignment: Alignment.topCenter,
          child: TopGlassPanel(
            padding: EdgeInsets.zero,
            child: TopPageHeader(
              icon: Icons.tune_rounded,
              title: '设置',
              padding: EdgeInsets.zero,
              bottomSpacing: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.displayBuilder,
    this.enabled = true,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String Function(String) displayBuilder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          borderRadius: BorderRadius.circular(14),
          menuMaxHeight: 320,
          onChanged: enabled ? onChanged : null,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    displayBuilder(item),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
