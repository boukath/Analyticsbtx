// lib/core/app_theme.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚀 Global notifier to trigger instant UI rebuilds when the theme changes
final ValueNotifier<ThemeMode> appThemeNotifier = ValueNotifier(ThemeMode.dark);

class AppTheme {
  static Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (appThemeNotifier.value == ThemeMode.dark) {
      appThemeNotifier.value = ThemeMode.light;
      await prefs.setBool('is_dark_mode', false);
    } else {
      appThemeNotifier.value = ThemeMode.dark;
      await prefs.setBool('is_dark_mode', true);
    }
  }

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  // =========================================================================
  // 🎨 EYE-FRIENDLY "SOFT SKY" COLOR PALETTE
  // =========================================================================

  // Background: Deep OLED Black for Dark, Soft Sky Blue for Light (Reduces glare)
  static Color bgDeep(BuildContext context) =>
      isDark(context) ? const Color(0xFF05050A) : const Color(0xFFE6F0F9);

  // Text: Pure White for Dark, Deep Slate Blue for Light (WCAG AAA Contrast)
  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1C2A3A);

  // Secondary Text: Muted Blue-Gray for visual hierarchy without losing legibility
  static Color textSecondary(BuildContext context) =>
      isDark(context) ? Colors.white54 : const Color(0xFF596A7A);

  // =========================================================================
  // 🧊 TRANSLUCENT ACCESSIBLE GLASSMORPHISM
  // =========================================================================

  // Tint: Barely-there for Dark, Softer translucent white for Light to let the blue breathe
  static Color glassTintStart(BuildContext context) =>
      isDark(context) ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.50);

  static Color glassTintEnd(BuildContext context) =>
      isDark(context) ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.20);

  // Border: Softened edges to prevent harsh lines
  static Color glassBorder(BuildContext context) =>
      isDark(context) ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.60);

  // Shadow: Deep black for Dark, Soft Steel Blue shadow for Light to create gentle depth
  static Color glassShadow(BuildContext context) =>
      isDark(context) ? Colors.black.withOpacity(0.3) : const Color(0xFFB0C4DE).withOpacity(0.30);

  // =========================================================================
  // 🌈 DYNAMIC BACKGROUND MESH ORBS (Animated Colors)
  // =========================================================================

  // Orbs in light mode are made more pastel and transparent to prevent visual distraction
  static Color orbCyan(BuildContext context) =>
      isDark(context) ? const Color(0xFF00F0FF).withOpacity(0.20) : const Color(0xFF82CFFF).withOpacity(0.25);

  static Color orbMagenta(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF003C).withOpacity(0.15) : const Color(0xFFFF85A1).withOpacity(0.15);

  static Color orbPurple(BuildContext context) =>
      isDark(context) ? const Color(0xFF7000FF).withOpacity(0.25) : const Color(0xFF9EA1FF).withOpacity(0.20);

  // Core Accent Colors (Used for buttons, icons, and charts)
  static const Color cyan = Color(0xFF00B4D8); // Slightly deeper cyan for better light-mode contrast
  static const Color magenta = Color(0xFFFF003C);
  static const Color purple = Color(0xFF7000FF);
}