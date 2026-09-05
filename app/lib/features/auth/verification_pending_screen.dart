import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/r_star_badge.dart';
import '../../core/widgets/status_badge.dart';

/// Ports Stitch's "Verification Pending - English Style" (project "Renly
/// Property Agent Network") to the Urby neo-brutalist system -- this
/// screen was a bare Milestone-1 placeholder (2 plain Text widgets, no
/// button) before this pass, never previously built out against any real
/// mockup.
///
/// Header is the same R* badge + wordmark treatment every other auth-flow
/// screen now uses (splash/login/onboarding/registration), for chrome
/// consistency across the flow -- the source mockup shows only bare
/// "Renly" text here, but this project has consistently unified that
/// chrome everywhere else rather than treating each mockup's own header as
/// authoritative. No back button, matching the mockup's own reasoning
/// (a pending screen is a dead end, standard nav is suppressed).
///
/// The mockup's spinning outer ring and pulsing status dot are CSS
/// animations with no functional purpose (this is a static status page,
/// not something time-critical) -- rendered as a plain static ring/dot
/// instead, consistent with skipping decorative micro-interactions
/// throughout this project's Stitch ports.
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
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surfaceVariant, width: 4),
                        ),
                      ),
                      Container(
                        width: 128,
                        height: 128,
                        decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(PhosphorIcons.hourglass(PhosphorIconsStyle.bold), size: 56, color: AppColors.ink),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primaryContainer, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.bold),
                              size: 16, color: AppColors.ink),
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
