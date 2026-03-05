import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import '../theme/theme_provider.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Row(
            children: [
              const Icon(Icons.settings_rounded, size: 28),
              const SizedBox(width: 12),
              Text(
                '设置',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('深色模式 (Dark Mode)'),
                  subtitle: const Text('开启以获得更为沉浸的夜间体验'),
                  secondary: const Icon(Icons.dark_mode_rounded),
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme(value);
                  },
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('清理缓存'),
                  subtitle: const Text('删除临时导入的文件和数据'),
                  leading: const Icon(Icons.cleaning_services_rounded),
                  onTap: () async {
                    final cacheDir = Directory(path.join(Directory.systemTemp.path, 'music_player_imports'));
                    if (await cacheDir.exists()) {
                      await cacheDir.delete(recursive: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(const SnackBar(content: Text('缓存已清理完毕。')));
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(const SnackBar(content: Text('没有任何可以清理的缓存。')));
                      }
                    }
                  },
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Local Music Player v1.0\nHigh-Fidelity Audio Support Enabled',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
