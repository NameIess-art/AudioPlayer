import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/top_page_header.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  Future<void> _clearTempCache(BuildContext context) async {
    final i18n = context.read<AppLanguageProvider>();
    final cacheDir = Directory(
      path.join(Directory.systemTemp.path, 'music_player_imports'),
    );
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(i18n.tr('temp_cache_cleaned'))),
          );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(i18n.tr('temp_cache_none'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final audioProvider = context.watch<AudioProvider>();
    final cs = Theme.of(context).colorScheme;
    final descStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      height: 1.25,
      color: cs.onSurfaceVariant,
    );
    final format = audioProvider.converterFormat;
    final bitrate = audioProvider.converterBitrate;
    final bitrateEnabled = format != 'wav' && format != 'flac';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 132),
        children: [
          TopPageHeader(
            icon: Icons.tune_rounded,
            title: i18n.tr('settings'),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            bottomSpacing: 10,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                children: [
                  SwitchListTile(
                    value: themeProvider.isDarkMode,
                    onChanged: themeProvider.toggleTheme,
                    title: Text(i18n.tr('dark_mode')),
                    subtitle: Text(
                      i18n.tr('dark_mode_subtitle'),
                      style: descStyle,
                    ),
                    secondary: const Icon(Icons.dark_mode_rounded),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: Text(i18n.tr('language')),
                    subtitle: Text(
                      i18n.tr('language_subtitle'),
                      style: descStyle,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.language_rounded,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<AppLanguage>(
                        value: i18n.language,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: (value) {
                          if (value != null) {
                            i18n.setLanguage(value);
                          }
                        },
                        items: AppLanguage.values
                            .map(
                              (lang) => DropdownMenuItem<AppLanguage>(
                                value: lang,
                                child: Text(
                                  i18n.languageName(lang),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    onTap: () => _clearTempCache(context),
                    title: Text(i18n.tr('clear_temp_cache')),
                    subtitle: Text(
                      i18n.tr('clear_temp_cache_subtitle'),
                      style: descStyle,
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
                        i18n.tr('transcode_defaults'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectField(
                          label: i18n.tr('format'),
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
                          label: i18n.tr('bitrate'),
                          value: bitrate,
                          items: AudioProvider.converterBitrates,
                          displayBuilder: (item) => item,
                          enabled: bitrateEnabled,
                          onChanged: (value) {
                            if (value != null) {
                              audioProvider.setConverterSettings(
                                bitrate: value,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    bitrateEnabled
                        ? i18n.tr('bitrate_used')
                        : i18n.tr('bitrate_not_used', {
                            'format': format.toUpperCase(),
                          }),
                    style: descStyle,
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
                      Icon(
                        Icons.info_outline_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        i18n.tr('about'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    i18n.tr('app_version'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(i18n.tr('app_desc'), style: descStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
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
