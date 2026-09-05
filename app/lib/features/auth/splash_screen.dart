// app/lib/features/auth/splash_screen.dart
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

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
/// The badge glyph is the real Stitch-generated "Renly - Rockstar Style Logo
/// Refined" vector artwork, itself a direct follow-up ask, not part of the
/// original Kinetic-Reveal mockup -- a hand-tuned italic "R" with an
/// authentic bevel-cut counter plus a 5-point star tucked into its
/// bottom-right corner, replacing the earlier system-font `Text('R')` +
/// generic `PhosphorIcons.star()` approximation. Downloaded as SVG (this
/// screen's `htmlCode` field carries `image/svg+xml`, not markup), then
/// rasterized to a transparent PNG with the R recolored black->white (the
/// source SVG drew it black for its own lime background; this badge's own
/// background is ink/black) and cropped tight to its ink bbox with a small
/// breathing margin -- `renly_r_star_badge.png`. Re-fetched once more under
/// a new screen ID ("Rockstar R Logo - Lowered Star") for a star-position
/// refinement (same R path, star polygon moved lower for cleaner separation
/// from the R's leg), then tuned once more directly (not from a new Stitch
/// fetch -- computed in Python against the same source SVG's polygon): the
/// star scaled 1.75x from its own centroid and re-centered so one point
/// touches the R's right leg/foot, matching real Rockstar Games proportions
/// more closely than the Stitch-provided size. All 3 rounds share the same
/// SVG->recolor->crop->rasterize pipeline; only the source SVG or polygon
/// coordinates changed each time, never the code (the asset filename never
/// changed).
///
/// **The badge PNG's own canvas is centered on ink-mass centroid, not its
/// bounding box** -- the same lesson this project has hit repeatedly for
/// every other logo asset (the "renly" wordmark, the app icon's "R"):
/// bbox-symmetric padding is NOT the same as visually-balanced padding,
/// since the R's thick stem plus the star's added mass sit off to one side
/// of the glyph's own geometric bbox. A tight-crop-then-uniform-padding pass
/// (what every prior round of this badge did) measured ~18px left / ~17px
/// up of true center on a ~700px canvas -- visible as the whole R+star unit
/// reading "left-heavy" inside the badge box despite the Container's own
/// `EdgeInsets.all(10)` already being perfectly symmetric in code. Fixed at
/// the asset level (asymmetric padding added around the tight ink crop so
/// the centroid lands dead-center, verified to within 0.15px), not by
/// touching the Container/Image code, which was never actually the
/// problem. `Image.asset`'s `alignment: Alignment.center` was still made
/// explicit (previously implicit via `BoxFit.contain`'s own default) so the
/// centering intent reads clearly from the widget code itself. Both
/// `splash_tagline`/`splash_subtitle` l10n keys and the
/// bottom-pinned tagline text were removed in the round before
/// this one, for a plain/minimal splash with nothing below the logo.
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
                  child: Container(
                    width: 64,
                    height: 64,
                    // Symmetric on purpose: asymmetric padding here changes
                    // the INNER box's own aspect ratio away from square,
                    // which made BoxFit.contain re-scale the image (not just
                    // shift it) -- confirmed by measuring a live screenshot
                    // before/after, where a 4dp left/right padding
                    // difference overshot into an 8-device-px imbalance in
                    // the WRONG direction instead of the intended few-px
                    // nudge. The actual rightward nudge lives on the
                    // Transform.translate below instead, which shifts
                    // pixels directly with no re-scaling side effect.
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
                    child: Transform.translate(
                      // A small manual OPTICAL nudge on top of the asset's
                      // own ink-mass centering (see the doc comment above).
                      // Measuring a live screenshot confirmed the geometric
                      // centering is already correct to well under 1
                      // logical pixel -- the R's solid stroke and the
                      // star's thin outline just don't carry equal
                      // PERCEIVED visual weight at an identical pixel-area
                      // centroid, so this is a deliberate optical
                      // correction, not evidence the measurement was wrong.
                      // Same category of fix as the app icon's own
                      // real-device nudge (commit 3503409).
                      offset: const Offset(1, 0),
                      child: Image.asset(
                        'assets/illustrations/renly_r_star_badge.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stackTrace) => Text(
                          'R',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 32,
                                height: 1,
                              ),
                        ),
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
        ],
      ),
    );
  }
}
