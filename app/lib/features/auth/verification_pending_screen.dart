import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/r_star_badge.dart';
import '../../core/widgets/status_badge.dart';

/// Ports Stitch's "Verification Pending" screens (project "Renly Property
/// Agent Network") to the Urby neo-brutalist system -- this screen was a
/// bare Milestone-1 placeholder (2 plain Text widgets, no button) before
/// the first pass, never previously built out against any real mockup.
///
/// Header is the same R* badge + wordmark treatment every other auth-flow
/// screen now uses (splash/login/onboarding/registration), for chrome
/// consistency across the flow -- the source mockups show only bare
/// "Renly" text here, but this project has consistently unified that
/// chrome everywhere else rather than treating each mockup's own header as
/// authoritative. No back button, matching the mockup's own reasoning
/// (a pending screen is a dead end, standard nav is suppressed).
///
/// The illustration is `verification_hourglass.png` (see its own history:
/// re-fetched from Stitch's "Verification Pending - Animated Flowing
/// Hourglass", the mockup's own inline SVG rasterized to a real asset).
/// Every PRIOR round rendered it static and explicitly skipped the
/// mockup's CSS flip/sand-flow/glow animations as decorative -- this round
/// reverses that call on a DIRECT, explicit ask for real motion, not a
/// silent mockup detail. Built as a native Flutter animation
/// (`AnimationController` + `AnimatedBuilder`), not the `lottie` package:
/// no real hourglass Lottie JSON was available to source (this isn't
/// something safe to fetch from a guessed URL), and hand-authoring a
/// faithful Lottie JSON from scratch isn't realistic -- the user's own
/// fallback instruction ("or build a custom AnimatedBuilder") is exactly
/// what this is.
///
/// A single repeating `AnimationController` drives three effects in sync:
/// (1) the hourglass image itself rotates a full 0->360 degrees per cycle
/// through `Curves.easeInOutCubic` -- since the asset's sand fill is
/// asymmetric (bright/full top chamber, faint bottom chamber), a 180
/// rotation naturally reads as "the hourglass just flipped and is
/// refilling" without needing to redraw/re-composite the artwork itself,
/// and continuing on to 360 returns it to the start looking freshly
/// flipped again; (2) a short lime "sand" dash at the hourglass's waist
/// fades in/out in sync with the SAME cycle (strongest when upright near
/// t=0/1, fully faded at the t=0.5 flip midpoint) to suggest sand actively
/// flowing rather than a static image just spinning; (3) the outer ring's
/// glow breathes via a sine wave on the same controller, independent of
/// the rotation curve so the pulse itself stays perfectly smooth
/// regardless of how the rotation eases.
///
/// "In Progress" reuses the existing `StatusBadge` widget (already this
/// app's own pill-status convention for listing/requirement statuses)
/// rather than inventing a new pill style just for this screen.
class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RStarBadge(size: 28),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontSize: 20,
                    letterSpacing: -1.0,
                    height: 1,
                  ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value;
                    final rotation = Curves.easeInOutCubic.transform(t) * 2 * math.pi;
                    // Smooth sine-driven breathing glow -- deliberately NOT
                    // tied to the rotation curve, so the pulse itself never
                    // inherits the rotation's own ease-in/out feel.
                    final glowStrength = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
                    // Sand-at-the-waist opacity: peaks upright (t near 0/1),
                    // fades to 0 right at the t=0.5 flip midpoint.
                    final sandOpacity = (math.cos(t * 2 * math.pi) * 0.5 + 0.5).clamp(0.0, 1.0);
                    return SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.3), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryContainer.withValues(alpha: glowStrength),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surfaceVariant, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.rotate(
                                  angle: rotation,
                                  child: Image.asset(
                                    'assets/illustrations/verification_hourglass.png',
                                    height: 76,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      PhosphorIcons.hourglass(PhosphorIconsStyle.bold),
                                      size: 56,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                Opacity(
                                  opacity: sandOpacity,
                                  child: Container(
                                    width: 3,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryContainer,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.surface, width: 2),
                              ),
                              alignment: Alignment.center,
                              child: Icon(PhosphorIcons.checks(PhosphorIconsStyle.bold),
                                  size: 16, color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'verification_pending'.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'verification_pending_body'.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 16),
                StatusBadge(label: 'verification_status_in_progress'.tr().toUpperCase()),
                const SizedBox(height: 32),
                BrutalistButton(
                  label: 'verification_back_home'.tr(),
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
