import 'package:flutter/material.dart';

/// 1920×1080 으로 옮긴 화면의 토큰. 1024×600 화면은 tokens.dart 의 Palette · Txt 를 쓴다
abstract final class WallpadTokens {
  static const Size designSize = Size(1920, 1080);

  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusPill = 999;

  static const double touchMin = 64;
  static const double touchNormal = 72;
  static const double touchPrimary = 80;

  static const Color surface = Color(0xDE1C2541);
  static const Color surfaceSolid = Color(0xFF232B4A);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB8FFFFFF);
  static const Color textDisabled = Color(0x73FFFFFF);
  static const Color ink = Color(0xFF1C2541);

  static const Color primary = Color(0xFF6F89FF);
  static const Color purple = Color(0xFF8067E8);
  static const Color success = Color(0xFF22A06B);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFE88A24);

  static const Color divider = Color(0x1FFFFFFF);
  static const Color border = Color(0x29FFFFFF);

  static const String fontFamily = 'Pretendard';

  static const List<String> fontFallback = [
    'Noto Sans KR',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'sans-serif',
  ];

  static const TextStyle heroGreeting = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 42,
    height: 1.14,
    fontWeight: FontWeight.w300,
    color: textPrimary,
    letterSpacing: -0.8,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 36,
    height: 1.18,
    fontWeight: FontWeight.w300,
    color: textPrimary,
    letterSpacing: -0.6,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.4,
  );

  static const TextStyle cardPrimary = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 25,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.25,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 22,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    letterSpacing: -0.15,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 22,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    letterSpacing: -0.15,
  );

  static const TextStyle secondary = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 19,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const Duration pageTransition = Duration(milliseconds: 240);
  static const Duration modalTransition = Duration(milliseconds: 200);
  static const Duration completionTransition = Duration(milliseconds: 300);
}

abstract final class WallpadTheme {
  static ThemeData light() {
    const scheme = ColorScheme.dark(
      primary: WallpadTokens.primary,
      onPrimary: Colors.white,
      secondary: WallpadTokens.purple,
      onSecondary: Colors.white,
      error: WallpadTokens.danger,
      onError: Colors.white,
      surface: WallpadTokens.surface,
      onSurface: WallpadTokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: WallpadTokens.fontFamily,
      fontFamilyFallback: WallpadTokens.fontFallback,
      dividerColor: WallpadTokens.divider,
      textTheme: const TextTheme(
        displaySmall: WallpadTokens.heroGreeting,
        headlineMedium: WallpadTokens.pageTitle,
        titleLarge: WallpadTokens.sectionTitle,
        titleMedium: WallpadTokens.cardPrimary,
        bodyLarge: WallpadTokens.body,
        bodyMedium: WallpadTokens.secondary,
        labelLarge: WallpadTokens.bodyMedium,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WallpadTokens.primary : const Color(0x3DFFFFFF)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(WallpadTokens.touchMin),
          foregroundColor: WallpadTokens.textPrimary,
          backgroundColor: WallpadTokens.surface,
          disabledForegroundColor: WallpadTokens.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WallpadTokens.radiusMd),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: WallpadTokens.ink,
          minimumSize: const Size(0, WallpadTokens.touchPrimary),
          padding: const EdgeInsets.symmetric(
            horizontal: WallpadTokens.spaceXl,
          ),
          textStyle: WallpadTokens.bodyMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WallpadTokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, WallpadTokens.touchNormal),
          padding: const EdgeInsets.symmetric(
            horizontal: WallpadTokens.spaceLg,
          ),
          foregroundColor: WallpadTokens.textPrimary,
          side: const BorderSide(color: WallpadTokens.border),
          textStyle: WallpadTokens.bodyMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WallpadTokens.radiusMd),
          ),
        ),
      ),
    );
  }
}
