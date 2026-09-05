// app/lib/features/auth/splash_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// Ports the Stitch "Splash Screen - Updated Logo" design (project
/// "Renly Property Agent Network") to the Urby neo-brutalist system --
/// lime background, bold wordmark, small caps tagline pinned near the
/// bottom -- using this app's own Space Grotesk type scale rather than
/// Stitch's Lumina-Prime-era Syne/JetBrains Mono, which this project
/// replaced outright (see app_theme.dart).
///
/// The wordmark itself is the actual Stitch-generated logo asset (its own
/// lime fill already matches AppColors.primaryContainer exactly, so it
/// blends into the Scaffold behind it) rather than rendered text -- unlike
/// every other onboarding/auth screen title, this one IS the brand mark.
///
/// The native splash (pubspec.yaml's flutter_native_splash config) is a
/// DELIBERATELY different screen, not a seamless twin of this one: white
/// background, the solid lime tile carrying Stitch's uppercase-R monogram
/// (renly_r_logo_tile.png, also the app's launcher icon) rather than this
/// widget's transparent text-only wordmark. main.dart
/// removes that native splash a fixed 600ms after runApp() -- this widget
/// is what's underneath it by then, and it stays up on its own for a
/// further 1.8s before navigating to '/onboarding'. These are two
/// separately-tuned durations for two visually distinct screens, not one
/// combined handoff -- FlutterNativeSplash.remove() lives entirely in
/// main.dart now, not here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) context.go('/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/illustrations/renly_wordmark.png',
              width: 220,
              errorBuilder: (context, error, stackTrace) => Text(
                'app_name'.tr(),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppColors.ink,
                      fontSize: 48,
                      height: 1,
                    ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Column(
              children: [
                Text(
                  'splash_tagline'.tr().toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onPrimaryContainer,
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'splash_subtitle'.tr().toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.onPrimaryContainer.withValues(alpha: 0.6),
                        letterSpacing: 1,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
