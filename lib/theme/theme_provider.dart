import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    notifyListeners();
  }

  ThemeData get currentTheme {
    if (_isDarkMode) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEA5D2A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
    } else {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEA5D2A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      );
    }
  }
}
