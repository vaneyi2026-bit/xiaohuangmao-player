import 'package:flutter/material.dart';

const kYellow = Color(0xFFF4C542);
const kInk = Color(0xFF1F1A10);
const kAmberDeep = Color(0xFF9A6B00); // 浅色主题里的细线、小图标、文字用（对白底约 4.7:1）

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: kYellow,
    onPrimary: kInk,
    primaryContainer: dark ? const Color(0xFF3A3018) : const Color(0xFFFFF3CC),
    onPrimaryContainer: dark ? const Color(0xFFFFE08A) : const Color(0xFF3A2C00),
    secondary: dark ? kYellow : kAmberDeep,
    onSecondary: dark ? kInk : Colors.white,
    error: const Color(0xFFD9483B),
    onError: Colors.white,
    surface: dark ? const Color(0xFF111111) : Colors.white,
    onSurface: dark ? const Color(0xFFEDEDED) : const Color(0xFF1C1C1C),
    onSurfaceVariant: dark ? const Color(0xFFB4B4B4) : const Color(0xFF5E5E5E),
    surfaceContainerLowest: dark ? const Color(0xFF0B0B0B) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF171717) : const Color(0xFFF9F9F7),
    surfaceContainer: dark ? const Color(0xFF1C1C1C) : const Color(0xFFF4F4F1),
    surfaceContainerHigh: dark ? const Color(0xFF232323) : const Color(0xFFEFEFEB),
    surfaceContainerHighest: dark ? const Color(0xFF2B2B2B) : const Color(0xFFE9E9E4),
    outline: dark ? const Color(0xFF5A5A5A) : const Color(0xFFBDBDB8),
    outlineVariant: dark ? const Color(0xFF333333) : const Color(0xFFE2E2DD),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: kYellow,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? kInk : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          )),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kYellow,
        foregroundColor: kInk,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.secondary, minimumSize: const Size(48, 44)),
    ),
    chipTheme: ChipThemeData(
      selectedColor: kYellow,
      checkmarkColor: kInk,
      secondaryLabelStyle: const TextStyle(color: kInk, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kInk : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kYellow : null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.secondary),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}

/// 播放器始终使用深色。
final playerTheme = buildTheme(Brightness.dark);
