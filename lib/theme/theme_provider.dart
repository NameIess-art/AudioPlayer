import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF757575),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF1F1F1F),
        onPrimary: Colors.white,
        secondary: const Color(0xFF4B4B4B),
        onSecondary: Colors.white,
        tertiary: const Color(0xFF6A6A6A),
        onTertiary: Colors.white,
        surface: const Color(0xFFF5F5F5),
        onSurface: const Color(0xFF111111),
        surfaceContainerHighest: const Color(0xFFE0E0E0),
        surfaceContainerHigh: const Color(0xFFECECEC),
        primaryContainer: const Color(0xFFD6D6D6),
        onPrimaryContainer: const Color(0xFF141414),
        secondaryContainer: const Color(0xFFDDDDDD),
        onSecondaryContainer: const Color(0xFF1D1D1D),
        outline: const Color(0xFF7A7A7A),
        outlineVariant: const Color(0xFFC6C6C6),
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF8A8A8A),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFF0F0F0),
        onPrimary: const Color(0xFF111111),
        secondary: const Color(0xFFC7C7C7),
        onSecondary: const Color(0xFF121212),
        tertiary: const Color(0xFFAEAEAE),
        onTertiary: const Color(0xFF121212),
        surface: const Color(0xFF0D0D0D),
        onSurface: const Color(0xFFF2F2F2),
        surfaceContainerHighest: const Color(0xFF262626),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        primaryContainer: const Color(0xFF333333),
        onPrimaryContainer: const Color(0xFFF2F2F2),
        secondaryContainer: const Color(0xFF2B2B2B),
        onSecondaryContainer: const Color(0xFFE5E5E5),
        outline: const Color(0xFF8C8C8C),
        outlineVariant: const Color(0xFF3A3A3A),
      );

  ThemeData _buildTheme(ColorScheme scheme) {
    final bodyText = GoogleFonts.ralewayTextTheme().copyWith(
      bodyMedium: GoogleFonts.raleway(fontSize: 16, height: 1.52),
      bodyLarge: GoogleFonts.raleway(fontSize: 17, height: 1.52),
      labelLarge: GoogleFonts.raleway(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      titleMedium: GoogleFonts.raleway(fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.lora(fontWeight: FontWeight.w700),
      headlineSmall: GoogleFonts.lora(fontWeight: FontWeight.w700),
    );

    final largeShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: bodyText.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        useIndicator: true,
        minWidth: 88,
        minExtendedWidth: 250,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 21,
        ),
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: largeShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: largeShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  ThemeData get currentTheme {
    return _buildTheme(_isDarkMode ? _darkScheme : _lightScheme);
  }
}
