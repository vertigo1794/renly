// app/lib/features/auth/splash_screen.dart
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// Ports the Stitch "Splash Screen - Kinetic R to Renly Animation" design
/// (project "Renly Property Agent Network") to the Urby neo-brutalist
/// system -- lime background, bold wordmark, small caps tagline pinned near
/// the bottom -- using this app's own Space Grotesk type scale rather than
/// Stitch's Lumina-Prime-era Syne/Hanken Grotesk, which this project
/// replaced outright (see app_theme.dart).
///
/// This redesign replaces the prior static Image.asset wordmark with a real
/// two-stage entrance animation, ported from Stitch's CSS transition
/// classes: an "R" monogram badge appears first (already on-screen, ink
/// background / lime glyph), then after a ~700ms dramatic pause the "renly"
/// wordmark unmasks outward from behind it. A raster image can't animate a
/// width-reveal cleanly, so the wordmark is rendered as real text
/// (Space Grotesk, matching this app's own type system) instead of the
/// image asset used before -- consistent with every other screen's title
/// text, unlike the pre-animation splash's stated exception for this one.
/// Skipped from the source design as web-only, not meaningful on a mobile
/// splash: the tap-to-replay handler (`onclick="replayAnimation()"`) and the
/// two blurred ambient background glows (Stitch's own `-15%`-offset radial
/// blobs), since the flat lime background already matches the rest of the
/// app's brand screens.
///
/// The native splash (pubspec.yaml's flutter_native_splash config) is a
/// DELIBERATELY different screen, not a seamless twin of this one: white
/// background, the solid lime tile carrying Stitch's uppercase-R monogram
/// (renly_r_logo_tile.png, also the app's launcher icon) rather than this
/// widget's animated text-only wordmark. main.dart
/// removes that native splash a fixed 600ms after runApp() -- this widget
/// is what's underneath it by then, and it stays up on its own for a
/// further 2s (700ms pause + ~1050ms reveal animation, plus a small buffer)
/// before navigating to '/onboarding'. These are two separately-tuned
/// durations for two visually distinct screens, not one combined handoff --
/// FlutterNativeSplash.remove() lives entirely in main.dart now, not here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    // Matches Stitch's own runIntroAnimation(): a ~700ms dramatic pause
    // before the badge settles and the wordmark unmasks.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _revealed = true);
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) context.go('/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Stitch's own --anim-ease: cubic-bezier(0.16, 1, 0.3, 1).
    const kineticCurve = Cubic(0.16, 1, 0.3, 1);
    final wordmarkStyle = Theme.of(
      context,
    ).textTheme.headlineLarge?.copyWith(color: AppColors.ink, fontSize: 48, height: 1);
    // Measured, not guessed: the reveal-container's target width must match
    // the actual rendered "renly" text exactly, or the animation either
    // clips the word or leaves dead space that throws off Center()'s
    // visual centering of the badge+wordmark unit as a whole.
    final wordmarkPainter = TextPainter(
      text: TextSpan(text: 'app_name'.tr(), style: wordmarkStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final wordmarkWidth = wordmarkPainter.width;
    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _revealed ? 1.0 : 1.6,
                  duration: const Duration(milliseconds: 1050),
                  curve: kineticCurve,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: Text(
                      'R',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: AppColors.primaryContainer,
                            fontWeight: FontWeight.w900,
                            fontSize: 32,
                            height: 1,
                          ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _revealed ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 950),
                    curve: kineticCurve,
                    width: _revealed ? wordmarkWidth + 14 : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    padding: const EdgeInsets.only(left: 14),
                    child: OverflowBox(
                      maxWidth: wordmarkWidth,
                      alignment: Alignment.centerLeft,
                      child: Text('app_name'.tr(), style: wordmarkStyle),
                    ),
                  ),
                ),
              ],
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
