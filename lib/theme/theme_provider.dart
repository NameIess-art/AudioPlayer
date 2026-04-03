import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_preferences.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    _isDarkMode = await AppPreferences.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme(bool value) async {
    _isDarkMode = value;
    await AppPreferences.setBool('isDarkMode', value);
    notifyListeners();
  }

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C7B8B),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF1B222E),
        onPrimary: Colors.white,
        secondary: const Color(0xFF4A5568),
        onSecondary: Colors.white,
        tertiary: const Color(0xFF5A6B7C),
        onTertiary: Colors.white,
        surface: const Color(0xFFF7F9FB),
        onSurface: const Color(0xFF131821),
        surfaceContainerHighest: const Color(0xFFE2E8F0),
        surfaceContainerHigh: const Color(0xFFEDF2F7),
        primaryContainer: const Color(0xFFD3DEF2),
        onPrimaryContainer: const Color(0xFF161F2C),
        secondaryContainer: const Color(0xFFE2E8F0),
        onSecondaryContainer: const Color(0xFF1A212E),
        outline: const Color(0xFF7A899E),
        outlineVariant: const Color(0xFFCBD5E1),
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF90A4AE),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFF1F5F9),
        onPrimary: const Color(0xFF0F172A),
        secondary: const Color(0xFFCBD5E1),
        onSecondary: const Color(0xFF131C2D),
        tertiary: const Color(0xFFB0BEC5),
        onTertiary: const Color(0xFF111827),
        surface: const Color(0xFF080D14),
        onSurface: const Color(0xFFF5F7FA),
        surfaceContainerHighest: const Color(0xFF1E293B),
        surfaceContainerHigh: const Color(0xFF131B28),
        primaryContainer: const Color(0xFF2E3E53),
        onPrimaryContainer: const Color(0xFFF1F5F9),
        secondaryContainer: const Color(0xFF263345),
        onSecondaryContainer: const Color(0xFFE2E8F0),
        outline: const Color(0xFF64748B),
        outlineVariant: const Color(0xFF334155),
      );

  ThemeData _buildTheme(ColorScheme scheme) {
    final bodyText = GoogleFonts.ralewayTextTheme().copyWith(
      bodyMedium: GoogleFonts.raleway(fontSize: 14, height: 1.5),
      bodyLarge: GoogleFonts.raleway(fontSize: 15, height: 1.5),
      labelLarge: GoogleFonts.raleway(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.raleway(fontSize: 10, fontWeight: FontWeight.w600),
      labelSmall: GoogleFonts.raleway(fontSize: 9.5, fontWeight: FontWeight.w600),
      bodySmall: GoogleFonts.raleway(fontSize: 10, fontWeight: FontWeight.w500),
      titleMedium: GoogleFonts.raleway(fontWeight: FontWeight.w800, fontSize: 14, height: 1.25),
      titleLarge: GoogleFonts.lora(fontWeight: FontWeight.w800, fontSize: 18),
      headlineSmall: GoogleFonts.lora(fontWeight: FontWeight.w900, fontSize: 20),
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkRipple.splashFactory,
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
          visualDensity: VisualDensity.standard,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.55),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        minLeadingWidth: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
