// app/lib/features/auth/splash_screen.dart
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';

/// Ports the Stitch "Splash Screen - Kinetic R to Renly Animation" design
/// (project "Renly Property Agent Network") to the Urby neo-brutalist
/// system -- flat lime background, bold wordmark, no tagline text -- using
/// this app's own Space Grotesk type scale rather than Stitch's
/// Lumina-Prime-era Syne/Hanken Grotesk, which this project replaced
/// outright (see app_theme.dart).
///
/// This redesign replaces the prior static Image.asset wordmark with a real
/// two-stage entrance animation, ported from Stitch's CSS transition
/// classes: an "R" monogram badge appears first (already on-screen, ink
/// background), then after a ~700ms dramatic pause the "renly" wordmark
/// unmasks outward from behind it. A raster image can't animate a
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
/// The badge is `RStarBadge` (`core/widgets/r_star_badge.dart`) -- see its
/// own doc comment for the full provenance of `renly_r_star_badge.png`
/// (Stitch's "Renly - Rockstar Style Logo Refined"/"Rockstar R Logo -
/// Lowered Star" screens, the SVG->recolor->crop->rasterize pipeline, and
/// the ink-mass-centroid + optical-nudge centering history). Extracted out
/// of this file once AuthSelectionScreen needed the identical badge too.
/// Both `splash_tagline`/`splash_subtitle` l10n keys and the bottom-pinned
/// tagline text were removed in an earlier round, for a plain/minimal
/// splash with nothing below the logo.
///
/// The native splash (pubspec.yaml's flutter_native_splash config) is a
/// DELIBERATELY different screen, not a seamless twin of this one: white
/// background, the solid lime tile carrying Stitch's uppercase-R monogram
/// (renly_r_logo_tile.png, also the app's launcher icon) rather than this
/// widget's animated text-only wordmark. main.dart
/// removes that native splash a fixed 600ms after runApp() -- this widget
/// is what's underneath it by then, and it stays up on its own for a
/// further 3.5s (700ms pause + ~1050ms reveal animation, plus a generous
/// dwell before navigating) before navigating to '/onboarding'. These are
/// two separately-tuned durations for two visually distinct screens, not
/// one combined handoff -- FlutterNativeSplash.remove() lives entirely in
/// main.dart now, not here.
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
    Future.delayed(const Duration(milliseconds: 3500), () {
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
                  child: const RStarBadge(),
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
        ],
      ),
    );
  }
}
