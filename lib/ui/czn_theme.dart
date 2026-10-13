import 'package:flutter/material.dart';

import 'czn_raster.dart';

abstract final class CznColors {
  static const background = Color(0xFF0D141E);
  static const panel = Color(0xFF192331);
  static const border = Color(0xFF3C4A5B);
  static const red = Color(0xFFFF5B62);
  static const muted = Color(0xFFB7C3D1);
  static const text = Color(0xFFF2F0EA);
  static const green = Color(0xFF83DCC2);
  static const amber = Color(0xFFEAC187);
}

abstract final class CznTheme {
  static ThemeData get dark {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CznColors.red,
          brightness: Brightness.dark,
        ).copyWith(
          primary: CznColors.red,
          onPrimary: CznColors.background,
          secondary: CznColors.green,
          onSecondary: CznColors.background,
          surface: CznColors.panel,
          onSurface: CznColors.text,
          onSurfaceVariant: CznColors.muted,
          outline: CznColors.border,
          error: CznColors.red,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardColor: const Color(0xBE171824),
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 26,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: CznColors.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 17,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: CznColors.text,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.55,
          color: CznColors.muted,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: CznColors.muted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: CznColors.text,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: CznColors.text,
        ),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        color: Color(0xBE171824),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0x66FFE6CB)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: const Color(0xFFFFE6CB),
              side: BorderSide.none,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ).copyWith(
              backgroundBuilder: (context, states, child) => Opacity(
                opacity: states.contains(WidgetState.disabled) ? .4 : 1,
                child: CznButtonArt(child: child ?? const SizedBox.expand()),
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: CznColors.text,
              backgroundColor: Colors.transparent,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: BorderSide.none,
              shape: shape,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              backgroundBuilder: (context, states, child) => Opacity(
                opacity: states.contains(WidgetState.disabled) ? .4 : 1,
                child: CznButtonArt(child: child ?? const SizedBox.expand()),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xE6171824),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: CznColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: CznColors.border, space: 24),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CznColors.red,
        linearTrackColor: CznColors.border,
        linearMinHeight: 4,
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: CznColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CznColors.border,
        contentTextStyle: TextStyle(color: CznColors.text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
