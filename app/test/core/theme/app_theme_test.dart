import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:renly/core/theme/app_colors.dart';
import 'package:renly/core/theme/app_theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Configure google_fonts to use offline fonts for testing
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('AppColors', () {
    test('primary matches Urby restyle token #D2FF00', () {
      expect(AppColors.primary, const Color(0xFFD2FF00));
    });

    test('primaryContainer matches Lumina Prime token #d4ff00', () {
      expect(AppColors.primaryContainer, const Color(0xFFD4FF00));
    });

    test('onPrimary is black for contrast on Vibrant Lime', () {
      expect(AppColors.onPrimary, const Color(0xFF000000));
    });

    test('background matches Urby restyle token #FFFFFF', () {
      expect(AppColors.background, const Color(0xFFFFFFFF));
    });
  });

  // NOTE: These tests use testWidgets() and call AppTheme.light fresh inside each
  // test body because AppTheme.light triggers GoogleFonts calls that schedule async
  // font-loads; these throw in bare test() zones but are tolerated in testWidgets() zones.
  // Hoisting at declaration time fails with "Binding has not yet been initialized".
  group('AppTheme.light', () {
    testWidgets('elevatedButtonTheme background stays the raw brand lime AppColors.primary', (
      WidgetTester tester,
    ) async {
      final resolvedBackground = AppTheme.light.elevatedButtonTheme.style?.backgroundColor?.resolve(
        <WidgetState>{},
      );
      expect(resolvedBackground, AppColors.primary);
    });

    testWidgets(
      'colorScheme.primary is not the bright lime brand color (must stay foreground-safe)',
      (WidgetTester tester) async {
        expect(AppTheme.light.colorScheme.primary, isNot(AppColors.primary));
        expect(AppTheme.light.colorScheme.primary, AppColors.ink);
      },
    );

    testWidgets(
      'colorScheme.onPrimary stays legible against colorScheme.primary '
      '(regression guard: both being near-black once collapsed a selected '
      'Switch\'s track/thumb contrast to ~1:1)',
      (WidgetTester tester) async {
        expect(AppTheme.light.colorScheme.onPrimary, isNot(AppTheme.light.colorScheme.primary));
      },
    );

    testWidgets('uses Material 3', (WidgetTester tester) async {
      expect(AppTheme.light.useMaterial3, isTrue);
    });

    testWidgets('headlineLarge uses Space Grotesk font family', (WidgetTester tester) async {
      expect(AppTheme.light.textTheme.headlineLarge?.fontFamily, contains('SpaceGrotesk'));
    });

    testWidgets('bodyMedium uses Space Grotesk font family', (WidgetTester tester) async {
      expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, contains('SpaceGrotesk'));
    });
  });
}
