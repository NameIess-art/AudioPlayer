import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/audio_provider.dart';
import 'screens/main_screen.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Note: just_audio_background is NOT initialized here because it patches 
  // AudioPlayer globally and limits playback to a single stream at a time,
  // which conflicts with our concurrent multi-session architecture.
  // Background audio is still supported via the FOREGROUND_SERVICE permission.

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AudioProvider()),
      ],
      child: const MusicPlayerApp(),
    ),
  );
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: '本地音乐播放器',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.currentTheme,
          home: const MainScreen(),
        );
      },
    );
  }
}
