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
/// The illustration was re-fetched from Stitch under a new screen ID
/// ("Verification Pending - Animated Flowing Hourglass") for a much more
/// elaborate hand-crafted hourglass -- gradient lime sand, glass specular
/// highlights, dark cap plates with a lime accent stripe -- replacing the
/// first pass's generic `PhosphorIcons.hourglass()`. That distinctiveness
/// was worth downloading as a real asset rather than approximating with a
/// stock icon a second time: extracted the mockup's own inline `<svg>`,
/// dropped the bottom-chamber sand fill's opacity to a faint 0.15 (the
/// full-opacity resting frame implied an already-half-emptied hourglass,
/// which read oddly for a JUST-submitted verification), and rasterized to
/// `verification_hourglass.png`. The mockup's flip-rotation + sand-drain/
/// fill animations (a ~4.2s infinite CSS cycle) are skipped as decorative,
/// same call made for the spinning ring/pulsing dot in the first pass --
/// this is a static status page, not something time-critical.
///
/// "In Progress" reuses the existing `StatusBadge` widget (already this
/// app's own pill-status convention for listing/requirement statuses)
/// rather than inventing a new pill style just for this screen.
class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

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
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Faint ambient ring, matching the mockup's own
                      // outer aura ring (its glow/spin are the skipped
                      // decorative animation this doc comment covers).
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.3), width: 2),
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
                        child: Image.asset(
                          'assets/illustrations/verification_hourglass.png',
                          height: 76,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(PhosphorIcons.hourglass(PhosphorIconsStyle.bold), size: 56, color: AppColors.ink),
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
                          child: Icon(PhosphorIcons.checks(PhosphorIconsStyle.bold), size: 16, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
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
