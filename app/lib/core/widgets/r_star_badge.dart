// app/lib/core/widgets/r_star_badge.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The "R*" Rockstar-Games-style monogram badge -- an ink-black rounded
/// square containing `renly_r_star_badge.png`, a hand-tuned italic "R" with
/// an authentic bevel-cut counter plus a 5-point star tucked into its
/// bottom-right corner. Ported from Stitch's "Renly - Rockstar Style Logo
/// Refined" screen (project "Renly Property Agent Network"), downloaded as
/// SVG (that screen's `htmlCode` field carries `image/svg+xml`, not
/// markup), then rasterized to a transparent PNG with the R recolored
/// black->white (the source SVG drew it black for its own lime background;
/// this badge's own background is ink/black). Re-fetched once more under a
/// new screen ID ("Rockstar R Logo - Lowered Star") for a star-position
/// refinement (star polygon moved lower, cleaner separation from the R's
/// leg), then tuned once more directly -- not from a new Stitch fetch, just
/// computed in Python against the same source SVG's polygon -- scaling the
/// star 1.75x from its own centroid and re-centering it so one point
/// touches the R's leg, closer to real Rockstar Games proportions. All 3
/// rounds share the same SVG->recolor->crop->rasterize pipeline; only the
/// source SVG or polygon coordinates changed each time.
///
/// **The badge PNG's own canvas is centered on ink-mass centroid, not its
/// bounding box** -- the same lesson this project hit for every other logo
/// asset (the "renly" wordmark, the app icon's "R"): bbox-symmetric padding
/// is NOT the same as visually-balanced padding, since the R's thick stem
/// plus the star's added mass sit off to one side of the glyph's own
/// geometric bbox. A tight-crop-then-uniform-padding pass (every prior
/// round of this badge) measured ~18px left / ~17px up of true center on a
/// ~700px canvas. Fixed at the asset level (asymmetric padding added around
/// the tight ink crop so the centroid lands dead-center, verified to within
/// 0.15px). Even after that fix, a live-screenshot measurement (isolating
/// the badge from the adjacent "renly" text, which shares the exact same
/// `AppColors.ink` color and silently merges into one bbox if not cropped
/// out first) still showed the R's solid stroke vs. the star's thin hollow
/// outline reading unevenly PERCEIVED-heavy despite near-perfect pixel
/// centering -- fixed with the small `Transform.translate` optical nudge
/// below, itself calibrated by measuring before/after on a live screenshot
/// (an initial 3px attempt overshot into the opposite imbalance; 1px
/// landed the two margins within 1 device px of each other).
///
/// Extracted as a shared widget once a second screen (AuthSelectionScreen)
/// needed the identical badge -- copy-pasting the Container/padding/
/// Transform.translate tree into a second call site would have risked the
/// two silently drifting apart on a future edit to just one of them.
/// SplashScreen wraps this in its own `AnimatedScale` for the entrance
/// reveal; every other call site renders it static.
class RStarBadge extends StatelessWidget {
  const RStarBadge({this.size = 64, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 10 / 64),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(size * 16 / 64)),
      child: Transform.translate(
        // A small manual OPTICAL nudge -- see SplashScreen's doc comment
        // for the full measured-not-guessed reasoning behind this value.
        offset: Offset(size * 1 / 64, 0),
        child: Image.asset(
          'assets/illustrations/renly_r_star_badge.png',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => Text(
            'R',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 32 / 64,
                  height: 1,
                ),
          ),
        ),
      ),
    );
  }
}
