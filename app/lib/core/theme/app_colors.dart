import 'package:flutter/material.dart';

/// Color tokens ported from stitch_renly_property_agent_network/lumina_prime/DESIGN.md.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFD2FF00);
  // DESIGN.md frontmatter says on-primary #ffffff, but the prose "Color
  // Roles" section says #000000 (text/icons on Lime buttons). White-on-lime
  // fails contrast; using black per the prose section.
  static const Color onPrimary = Color(0xFF000000);
  static const Color primaryContainer = Color(0xFFD4FF00);
  static const Color onPrimaryContainer = Color(0xFF5F7400);

  static const Color secondary = Color(0xFF5F5E5E);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFE5E2E1);
  static const Color onSecondaryContainer = Color(0xFF656464);

  static const Color tertiary = Color(0xFF732EE4);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFF4EAFF);
  static const Color onTertiaryContainer = Color(0xFF8140F2);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  static const Color background = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF191C1B);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF191C1B);
  static const Color surfaceVariant = Color(0xFFE2E3E0);
  static const Color outline = Color(0xFF757A60);

  // Urby-inspired neo-brutalist tokens (2026-08-25-renly-urby-restyle-design.md).
  static const Color ink = Color(0xFF0A0A0A);
  static const Color accent = Color(0xFF7C3AED);
}
