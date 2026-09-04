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
/// rather than this widget's transparent text-only wordmark. It stays up
/// for a fixed 2s (held via main.dart's FlutterNativeSplash.preserve())
/// before this widget removes it and navigates straight on to
/// '/onboarding' -- this screen's own UI still exists (rather than
/// folding the remove()+navigate call into main.dart directly) because
/// FlutterNativeSplash.remove() needs a real widget's first frame to hand
/// off from, not because its own Scaffold is meant to be seen; at this
/// duration there's rarely a visible gap between the native splash
/// disappearing and '/onboarding' appearing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // The post-frame callback (rather than calling this directly in
    // initState) is what makes the delayed remove()+navigate below safe to
    // schedule -- it guarantees this widget's first frame has actually
    // painted, i.e. the earliest point context.go() is guaranteed to have
    // a mounted widget to act on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        FlutterNativeSplash.remove();
        if (mounted) context.go('/onboarding');
      });
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
