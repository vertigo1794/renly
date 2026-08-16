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
    test('primary matches Lumina Prime token #536600', () {
      expect(AppColors.primary, const Color(0xFF536600));
    });

    test('primaryContainer matches Lumina Prime token #d4ff00', () {
      expect(AppColors.primaryContainer, const Color(0xFFD4FF00));
    });

    test('onPrimary is black for contrast on Vibrant Lime', () {
      expect(AppColors.onPrimary, const Color(0xFF000000));
    });

    test('background matches Lumina Prime token #f9faf7', () {
      expect(AppColors.background, const Color(0xFFF9FAF7));
    });
  });

  group('AppTheme.light', () {
    testWidgets('colorScheme.primary matches AppColors.primary', (WidgetTester tester) async {
      expect(AppTheme.light.colorScheme.primary, AppColors.primary);
    });

    testWidgets('uses Material 3', (WidgetTester tester) async {
      expect(AppTheme.light.useMaterial3, isTrue);
    });

    testWidgets('headlineLarge uses Syne font family', (WidgetTester tester) async {
      expect(AppTheme.light.textTheme.headlineLarge?.fontFamily, contains('Syne'));
    });

    testWidgets('bodyMedium uses Hanken Grotesk font family', (WidgetTester tester) async {
      expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, contains('Hanken'));
    });
  });
}
