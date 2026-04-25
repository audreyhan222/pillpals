import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    // Use ThemeData.light() as the baseline. On Flutter web, ThemeData()'s default
    // textTheme can contain TextStyles with null fontSize, and scaling via
    // TextTheme.apply(fontSizeFactor) will assert.
    final base = ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A6FDB)),
    );

    return base.copyWith(
      textTheme: (() {
        final tt = base.textTheme;
        final hasAnyNullFontSize = <TextStyle?>[
          tt.displayLarge,
          tt.displayMedium,
          tt.displaySmall,
          tt.headlineLarge,
          tt.headlineMedium,
          tt.headlineSmall,
          tt.titleLarge,
          tt.titleMedium,
          tt.titleSmall,
          tt.bodyLarge,
          tt.bodyMedium,
          tt.bodySmall,
          tt.labelLarge,
          tt.labelMedium,
          tt.labelSmall,
        ].any((s) => s?.fontSize == null);

        // Avoid Flutter assertion when fontSize is null anywhere in the theme.
        final factor = hasAnyNullFontSize ? 1.0 : 1.15;

        return tt.apply(
          fontSizeFactor: factor,
          bodyColor: base.colorScheme.onSurface,
          displayColor: base.colorScheme.onSurface,
        );
      })(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

