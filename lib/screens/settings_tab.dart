import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/app_feedback.dart';
import '../widgets/mobile_overlay_inset.dart';
import '../widgets/top_page_header.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static const MethodChannel _powerChannel = MethodChannel(
    'music_player/power',
  );

  Future<void> _clearTempCache(BuildContext context) async {
    final i18n = context.read<AppLanguageProvider>();
    final cacheDir = Directory(
      path.join(Directory.systemTemp.path, 'music_player_imports'),
    );
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      if (context.mounted) {
        showAppSnackBar(
          context,
          i18n.tr('temp_cache_cleaned'),
          tone: AppFeedbackTone.success,
          icon: Icons.cleaning_services_rounded,
        );
      }
      return;
    }

    if (context.mounted) {
      showAppSnackBar(
        context,
        i18n.tr('temp_cache_none'),
        tone: AppFeedbackTone.info,
        icon: Icons.info_outline_rounded,
      );
    }
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _powerChannel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openBatteryOptimizationSettings(BuildContext context) async {
    if (!Platform.isAndroid) return;
    try {
      await _powerChannel.invokeMethod<bool>('openBatteryOptimizationSettings');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final audioProvider = context.watch<AudioProvider>();
    final bottomInset = MobileOverlayInset.of(context);
    final cs = Theme.of(context).colorScheme;
    final descStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      height: 1.25,
      color: cs.onSurfaceVariant,
    );

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
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
                  SwitchListTile(
                    value: audioProvider.multiThreadPlaybackEnabled,
                    onChanged: audioProvider.setMultiThreadPlaybackEnabled,
                    title: Text(i18n.tr('multi_thread_playback')),
                    subtitle: Text(
                      i18n.tr('multi_thread_playback_subtitle'),
                      style: descStyle,
                    ),
                    secondary: const Icon(Icons.multitrack_audio_rounded),
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
                    onTap: () => _openBatteryOptimizationSettings(context),
                    title: Text(i18n.tr('background_keep_alive')),
                    subtitle: FutureBuilder<bool>(
                      future: _isIgnoringBatteryOptimizations(),
                      builder: (context, snapshot) {
                        final ignoring = snapshot.data == true;
                        final status = ignoring
                            ? i18n.tr('background_keep_alive_ready')
                            : i18n.tr('background_keep_alive_subtitle');
                        return Text(status, style: descStyle);
                      },
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.battery_saver_rounded,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
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
