// app/lib/features/auth/splash_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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
/// background, the solid app-icon-style square tile (renly_logo_tile.png)
/// rather than this widget's transparent text-only wordmark. That handoff
/// no longer matters much in practice -- there is no artificial delay of
/// any kind here any more (no Future.delayed, no Timer): the moment this
/// widget's own first frame is painted, it removes the native splash AND
/// navigates to '/onboarding' in the same post-frame callback, so this
/// screen itself is never actually visible to the user. It still exists
/// (rather than folding this into main.dart directly) because
/// FlutterNativeSplash.remove() needs a real widget's first frame to hand
/// off from -- main.dart's preserve() has no frame of its own to signal
/// readiness with.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // No Future.delayed/Timer of any kind -- the post-frame callback fires
    // as soon as this widget's first frame is painted, the earliest point
    // at which removing the native splash and navigating is actually safe
    // (context.go() needs the widget in the tree, which isn't guaranteed
    // yet inside initState itself).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
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
            child: Text(
              'splash_tagline'.tr().toUpperCase(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onPrimaryContainer,
                    letterSpacing: 2,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
