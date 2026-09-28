import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Centralized theme definitions for the Qari app — the "Serene Path" design
/// system. Spiritual Minimalism: warm cream/amber in light mode, contemplative
/// charcoal/amber in dark mode, glassmorphism, soft UI, generous radii.
///
/// Design rule: avoid pure black and pure white — every tone is tinted with the
/// brand's warm amber/cream so the app keeps a cohesive spiritual temperature.
class AppTheme {
  AppTheme._();

  // ─── Brand Palette (Serene Path) ─────────────────────────────────────────

  /// Warm amber-bronze — the signature accent used for primary actions,
  /// active nav and brand marks in light mode.
  static const Color amberLight = Color(0xFF9C5A1C);
  static const Color amberLightSoft = Color(0xFFB3742A);
  static const Color onAmberLight = Color(0xFFFDF6EA);

  /// Glowing amber filament — used for primary actions / active states in dark
  /// mode. Paired with a dark label so it reads like a lit ember.
  static const Color amberDark = Color(0xFFD98C3C);
  static const Color amberDarkSoft = Color(0xFFE3AE62);
  static const Color onAmberDark = Color(0xFF1C130A);

  /// High-contrast accessibility accent (amber-bronze on white/black).
  static const Color amberHighContrast = Color(0xFF7A440E);

  // ─── Light Theme (Warm Sunrise) ──────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: amberLight,
        scaffoldBackgroundColor: const Color(0xFFFDF9E9),
        colorScheme: const ColorScheme.light(
          primary: amberLight,
          onPrimary: onAmberLight,
          secondary: amberLightSoft,
          onSecondary: onAmberLight,
          surface: Color(0xFFFCF6EA),
          onSurface: Color(0xFF3B2F23),
          error: Color(0xFFB23A2E),
          onError: onAmberLight,
          outline: Color(0xFFD9C7A3),
          surfaceContainerHighest: Color(0xFFF3E7CF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFCF6EA),
          foregroundColor: Color(0xFF3B2F23),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3B2F23),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
          ),
          color: const Color(0xFFFCF6EA),
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFFCF6EA),
          selectedItemColor: amberLight,
          unselectedItemColor: Color(0xFF8A7A66),
          type: BottomNavigationBarType.fixed,
          elevation: AppConstants.bottomNavElevation,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE7D8BC),
          thickness: 1,
        ),
        textTheme: _buildTextTheme(Brightness.light),
        inputDecorationTheme: _buildInputTheme(Brightness.light),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFFFCF6EA),
          modalBackgroundColor: const Color(0xFFFCF6EA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.sheetBorderRadius),
            ),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: amberLight,
          inactiveTrackColor: amberLight.withValues(alpha: 0.2),
          thumbColor: amberLight,
          overlayColor: amberLight.withValues(alpha: 0.12),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: amberLight,
          linearTrackColor: Color(0xFFF0E2C6),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF3E7CF),
          selectedColor: amberLight.withValues(alpha: 0.18),
          labelStyle: const TextStyle(color: Color(0xFF3B2F23)),
          secondaryLabelStyle: const TextStyle(color: Color(0xFF3B2F23)),
          brightness: Brightness.light,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          foregroundColor: onAmberLight,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: amberLight,
            foregroundColor: onAmberLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: amberLight,
            foregroundColor: onAmberLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  // ─── Dark Theme (Contemplative Night) ────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: amberDark,
        scaffoldBackgroundColor: const Color(0xFF15110C),
        colorScheme: const ColorScheme.dark(
          primary: amberDark,
          onPrimary: onAmberDark,
          secondary: amberDarkSoft,
          onSecondary: onAmberDark,
          surface: Color(0xFF211A12),
          onSurface: Color(0xFFF2ECE4),
          error: Color(0xFFE57373),
          onError: onAmberDark,
          outline: Color(0xFF3D3225),
          surfaceContainerHighest: Color(0xFF2C2318),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF211A12),
          foregroundColor: Color(0xFFF2ECE4),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF2ECE4),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
          ),
          color: const Color(0xFF211A12),
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF211A12),
          selectedItemColor: amberDark,
          unselectedItemColor: Color(0xFF8E8174),
          type: BottomNavigationBarType.fixed,
          elevation: AppConstants.bottomNavElevation,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF33291C),
          thickness: 1,
        ),
        textTheme: _buildTextTheme(Brightness.dark),
        inputDecorationTheme: _buildInputTheme(Brightness.dark),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFF211A12),
          modalBackgroundColor: const Color(0xFF211A12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.sheetBorderRadius),
            ),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: amberDark,
          inactiveTrackColor: amberDark.withValues(alpha: 0.2),
          thumbColor: amberDark,
          overlayColor: amberDark.withValues(alpha: 0.12),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: amberDark,
          linearTrackColor: Color(0xFF3A2E1D),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2C2318),
          selectedColor: amberDark.withValues(alpha: 0.22),
          labelStyle: const TextStyle(color: Color(0xFFF2ECE4)),
          secondaryLabelStyle: const TextStyle(color: Color(0xFFF2ECE4)),
          brightness: Brightness.dark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          foregroundColor: onAmberDark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: amberDark,
            foregroundColor: onAmberDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: amberDark,
            foregroundColor: onAmberDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  // ─── High-Contrast Theme (accessibility) ─────────────────────────────────
  static ThemeData get highContrastTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: amberHighContrast,
        scaffoldBackgroundColor: const Color(0xFFFBF7EF),
        colorScheme: const ColorScheme.light(
          primary: amberHighContrast,
          onPrimary: Colors.white,
          secondary: Color(0xFF7A440E),
          onSecondary: Colors.white,
          surface: Color(0xFFFBF7EF),
          onSurface: Colors.black,
          error: Color(0xFFB71C1C),
          onError: Colors.white,
          outline: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFBF7EF),
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          color: Color(0xFFFBF7EF),
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFFBF7EF),
          selectedItemColor: amberHighContrast,
          unselectedItemColor: Color(0xFF5A5048),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(
          color: Colors.black,
          thickness: 2,
        ),
        textTheme: _buildHighContrastTextTheme(),
        inputDecorationTheme: _buildInputTheme(Brightness.light, highContrast: true),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Color(0xFFFBF7EF),
          modalBackgroundColor: Color(0xFFFBF7EF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.sheetBorderRadius),
            ),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: amberHighContrast,
          inactiveTrackColor: Color(0xFFCCCCCC),
          thumbColor: amberHighContrast,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: amberHighContrast,
          linearTrackColor: Color(0xFFCCCCCC),
        ),
      );

  // ─── Text Themes ────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Brightness brightness) {
    final baseColor = brightness == Brightness.light
        ? const Color(0xFF3B2F23)
        : const Color(0xFFF2ECE4);
    final muted = brightness == Brightness.light
        ? const Color(0xFF6B5C49)
        : const Color(0xFFC9BCA9);
    return TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: baseColor),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: baseColor),
      displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: baseColor),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: baseColor),
      headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: baseColor),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: baseColor),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: baseColor),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: baseColor),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: baseColor),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: baseColor),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: baseColor),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: baseColor),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: baseColor),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
    );
  }

  static TextTheme _buildHighContrastTextTheme() {
    return TextTheme(
      displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.black),
      displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.black),
      displaySmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.black),
      headlineLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
      headlineMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black),
      headlineSmall: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
      titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
      titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
      bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
      bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black),
      bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black),
      labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black),
      labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
    );
  }

  // ─── Input Decoration ───────────────────────────────────────────────────
  static InputDecorationTheme _buildInputTheme(Brightness brightness,
      {bool highContrast = false}) {
    final outlineColor = highContrast
        ? Colors.black
        : brightness == Brightness.light
            ? const Color(0xFFD9C7A3)
            : const Color(0xFF5A4B38);
    final accent = highContrast ? Colors.black : amberLight;
    return InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outlineColor, width: highContrast ? 2 : 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outlineColor, width: highContrast ? 2 : 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: highContrast ? Colors.black : amberLight,
          width: 2,
        ),
      ),
      filled: true,
      fillColor: highContrast
          ? Colors.white
          : brightness == Brightness.light
              ? const Color(0xFFF6ECDC)
              : const Color(0xFF2A2117),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // ─── Grammar Color Helpers ──────────────────────────────────────────────

  /// Gets the [GrammarColorConfig] for a given pos_group string.
  /// Falls back to 'default' if not found.
  static GrammarColorConfig getGrammarConfig(String posGroup) {
    return AppConstants.grammarColors[posGroup] ??
        AppConstants.grammarColors['default']!;
  }

  /// Gets the [Color] for a pos_group.
  static Color getGrammarColor(String posGroup) {
    return getGrammarConfig(posGroup).color;
  }

  /// Gets the [UnderlineStyle] for a pos_group.
  static UnderlineStyle getGrammarUnderline(String posGroup) {
    return getGrammarConfig(posGroup).underlineStyle;
  }

  /// Gets the tajweed [Color] for a tajweed rule key.
  static Color getTajweedColor(String rule) {
    return AppConstants.tajweedColors[rule] ??
        AppConstants.tajweedColors['normal']!;
  }

  /// Returns [color] adjusted for the surrounding theme so colored Quran text
  /// (grammar / tajweed coding) never blends into the background. On a dark
  /// theme the colors are lightened toward white; on light themes they are
  /// returned unchanged.
  static Color ensureContrast(
    Color color,
    Brightness brightness, {
    double amount = 0.45,
  }) {
    if (brightness == Brightness.dark) {
      return Color.lerp(color, Colors.white, amount) ?? color;
    }
    return color;
  }

  /// Builds a [TextDecoration] from an [UnderlineStyle].
  static TextDecoration toTextDecoration(UnderlineStyle style) {
    switch (style) {
      case UnderlineStyle.solid:
        return TextDecoration.underline;
      case UnderlineStyle.dotted:
        return TextDecoration.underline;
      case UnderlineStyle.none:
        return TextDecoration.none;
    }
  }

  /// Builds a [Paint] for custom underline rendering (dotted style).
  static Paint? buildUnderlinePaint(UnderlineStyle style, Color color) {
    if (style == UnderlineStyle.none) return null;
    return Paint()
      ..color = color
      ..strokeWidth = style == UnderlineStyle.dotted ? 1.5 : 2.0
      ..style = PaintingStyle.stroke;
  }

  // ─── Arabic Text Style ──────────────────────────────────────────────────

  /// Returns a [TextStyle] for Arabic Quran text at a given scale.
  static TextStyle arabicTextStyle({
    double fontSize = AppConstants.arabicFontDefaultSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    TextDecoration decoration = TextDecoration.none,
    Color? decorationColor,
    TextDecorationStyle decorationStyle = TextDecorationStyle.solid,
    double decorationThickness = 1.0,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: AppConstants.arabicFontFamily,
      fontSize: fontSize.clamp(
        AppConstants.arabicFontMinSize,
        AppConstants.arabicFontMaxSize,
      ),
      height: 1.8,
      color: color,
      fontWeight: fontWeight,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      letterSpacing: letterSpacing,
    );
  }

  /// Returns a [TextStyle] for Urdu text using Nastaliq font.
  static TextStyle urduTextStyle({
    double fontSize = 18,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: AppConstants.urduFontFamily,
      fontSize: fontSize,
      height: 2.0,
      color: color,
      fontWeight: fontWeight,
    );
  }
}
