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
/// rather than this widget's transparent text-only wordmark. Two reasons
/// it isn't just "this same design, earlier": (1) the user's own request
/// for this native-splash iteration was specifically a white background
/// with the square logo, not a lime match; (2) Android 12+'s SplashScreen
/// API expects a roughly-square icon-shaped asset for anything it lays
/// out itself (image OR branding image) -- handing it a wide wordmark, or
/// worse a thin letter-spaced tagline strip, gets non-uniformly scaled to
/// fit that slot and comes out visibly squashed on real devices, so the
/// tagline (and the lime full-bleed look) can only render safely here in
/// Flutter's own layout system, once the engine is actually up.
class SplashScreen extends StatefulWidget {
  const SplashScreen({this.duration = const Duration(milliseconds: 1200), super.key});

  /// How long the splash stays up before navigating to '/onboarding'.
  /// Overridable so widget tests don't have to wait out the real delay.
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Hand off from the native splash (white bg + square logo tile, see
    // pubspec.yaml's flutter_native_splash config) the moment this widget's
    // own first frame is actually painted -- not synchronously here, since
    // main.dart's preserve() is still holding it up until then. Unlike the
    // earlier single-native-splash design, this handoff IS a visible
    // transition on purpose (white -> lime, small tile -> full wordmark);
    // it isn't trying to look seamless.
    WidgetsBinding.instance.addPostFrameCallback((_) => FlutterNativeSplash.remove());
    Future.delayed(widget.duration, () {
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
