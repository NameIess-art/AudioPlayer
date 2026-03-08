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
        seedColor: const Color(0xFF0F7896),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF0E6A86),
        onPrimary: Colors.white,
        secondary: const Color(0xFF0D9488),
        onSecondary: Colors.white,
        tertiary: const Color(0xFF15803D),
        onTertiary: Colors.white,
        surface: const Color(0xFFF3F9FB),
        onSurface: const Color(0xFF0F172A),
        surfaceContainerHighest: const Color(0xFFDDEBF0),
        surfaceContainerHigh: const Color(0xFFE7F2F6),
        primaryContainer: const Color(0xFFCEE9F2),
        onPrimaryContainer: const Color(0xFF08303C),
        secondaryContainer: const Color(0xFFCDEDE8),
        onSecondaryContainer: const Color(0xFF0B3833),
        outline: const Color(0xFF738A97),
        outlineVariant: const Color(0xFFBDD0DA),
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF22B3C8),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF76D4E4),
        onPrimary: const Color(0xFF072E37),
        secondary: const Color(0xFF63D4C8),
        onSecondary: const Color(0xFF052D29),
        tertiary: const Color(0xFF60D798),
        onTertiary: const Color(0xFF062D1B),
        surface: const Color(0xFF091218),
        onSurface: const Color(0xFFE4F0F4),
        surfaceContainerHighest: const Color(0xFF203541),
        surfaceContainerHigh: const Color(0xFF162833),
        primaryContainer: const Color(0xFF154A5B),
        onPrimaryContainer: const Color(0xFFC0EAF2),
        secondaryContainer: const Color(0xFF134942),
        onSecondaryContainer: const Color(0xFFBEEDE7),
        outline: const Color(0xFF7F95A1),
        outlineVariant: const Color(0xFF33505C),
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
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
        ),
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
