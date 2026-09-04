// app/lib/features/auth/auth_selection_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';

/// Ports Stitch's "Login/Register Selection - English (Official Style)"
/// (project "Renly Property Agent Network") to the Urby neo-brutalist
/// system -- full-bleed lime background matching SplashScreen (this
/// screen and the splash are now visually siblings, both brand-forward
/// lime screens), the actual wordmark image as the brand mark rather
/// than rendered text, and Space Grotesk throughout rather than Stitch's
/// own Syne/Hanken Grotesk/JetBrains Mono.
///
/// The "Create account" CTA uses BrutalistButtonVariant.dark rather than
/// the usual primary: on a lime PAGE background, a lime-filled primary
/// button would nearly disappear except for its border/shadow, exactly
/// the problem Stitch's own mockup avoids by making that button solid
/// black. "Log in" stays secondary (transparent + border), which already
/// reads correctly against any background.
///
/// The legal footer text is intentionally NOT tappable, unlike Stitch's
/// (non-functional, href="#") mockup: "Privacy Policy" would need
/// '/settings/privacy' added to the router's public routes (it's
/// currently auth-gated) and there is no "Terms of Service" screen at
/// all yet -- both are real scope beyond this screen's own visual port,
/// so the copy is rendered as styled (bold) text only.
class AuthSelectionScreen extends StatelessWidget {
  const AuthSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyTextColor = AppColors.ink.withValues(alpha: 0.8);

    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/illustrations/auth_selection_bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.ink.withValues(alpha: 0.06),
                              border: Border.all(color: AppColors.ink.withValues(alpha: 0.12)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'auth_badge'.tr().toUpperCase(),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(color: AppColors.ink, letterSpacing: 1.2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Image.asset(
                            'assets/illustrations/renly_wordmark.png',
                            width: 240,
                            errorBuilder: (context, error, stackTrace) => Text(
                              'app_name'.tr(),
                              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                    color: AppColors.ink,
                                    fontSize: 48,
                                    height: 1,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'auth_tagline'.tr(),
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'auth_subtext'.tr(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: bodyTextColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      BrutalistButton(
                        label: 'auth_create_account'.tr(),
                        onPressed: () => context.push('/register/personal'),
                        variant: BrutalistButtonVariant.dark,
                      ),
                      const SizedBox(height: 12),
                      BrutalistButton(
                        label: 'auth_log_in'.tr(),
                        onPressed: () => context.push('/login'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text.rich(
                          TextSpan(
                            children: _richBody(
                              'auth_legal_footer'.tr(),
                              Theme.of(context).textTheme.labelSmall?.copyWith(color: bodyTextColor),
                              Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                            ),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Splits `text` on `**bold**` markers into spans -- same convention
/// OnboardingScreen's body copy uses for "REN Verified", reused here for
/// the legal footer's "Terms of Service"/"Privacy Policy" emphasis.
List<InlineSpan> _richBody(String text, TextStyle? baseStyle, TextStyle? boldStyle) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++) TextSpan(text: parts[i], style: i.isOdd ? boldStyle : baseStyle),
  ];
}
