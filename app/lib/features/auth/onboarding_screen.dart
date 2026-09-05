// app/lib/features/auth/onboarding_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';

/// One onboarding slide's content. `titleKey`/`bodyKey` are easy_localization
/// keys, not raw strings, so every slide stays bilingual EN/MS like the rest
/// of the app. `badgeKey` is optional and nullable rather than required: it
/// was added when slide 1 got its Stitch-sourced badge pill ("Co-Broke
/// Network"), slide 2 got its own ("Smart Matching") when ITS refreshed
/// mockup arrived, but slide 3 hasn't had its badge copy fed in yet (this
/// project's Stitch screens arrive one at a time) -- leaving it null simply
/// hides the badge on that slide rather than inventing copy for a design
/// that hasn't been provided.
class OnboardingSlideData {
  const OnboardingSlideData({
    required this.imageAsset,
    required this.titleKey,
    required this.bodyKey,
    this.badgeKey,
  });

  final String imageAsset;
  final String titleKey;
  final String bodyKey;
  final String? badgeKey;
}

/// Ports the Stitch "Onboarding" screens (project "Renly Property Agent
/// Network") to the Urby neo-brutalist system -- the source design's
/// rounded-full pill button and Syne/Hanken Grotesk type are replaced with
/// this app's own BrutalistButton and Space Grotesk scale, same adaptation
/// already applied to the splash screen. Illustrations are downloaded
/// verbatim from Stitch (assets/illustrations/onboarding_*.png) rather than
/// hand-vectorized -- unlike the app's own simple geometric empty-state
/// icons, these are detailed line-art figures not worth re-drawing.
///
/// Slide 1 was re-fetched from Stitch under a new screen ID (the project's
/// mockups get iterated on, not just added to) with a redesigned shared
/// chrome: a top brand header (the "R" launcher-icon monogram + "renly"
/// wordmark) with Skip moved up next to it, and a badge pill above each
/// slide's title. The header renders once, outside the PageView, since
/// it's identical across every slide, not per-slide data. The progress
/// dots also picked up an active-dot-becomes-a-pill treatment instead of
/// a plain filled/unfilled circle.
///
/// Slides are added here one at a time as each is ported from Stitch; the
/// list below is the single source of truth for how many dots/pages show.
const _slides = [
  OnboardingSlideData(
    imageAsset: 'assets/illustrations/onboarding_1_collaboration.png',
    titleKey: 'onboarding_1_title',
    bodyKey: 'onboarding_1_body',
    badgeKey: 'onboarding_1_badge',
  ),
  OnboardingSlideData(
    imageAsset: 'assets/illustrations/onboarding_2_matching.png',
    titleKey: 'onboarding_2_title',
    bodyKey: 'onboarding_2_body',
    badgeKey: 'onboarding_2_badge',
  ),
  OnboardingSlideData(
    imageAsset: 'assets/illustrations/onboarding_3_verified.png',
    titleKey: 'onboarding_3_title',
    bodyKey: 'onboarding_3_body',
  ),
];

/// Splits `text` on `**bold**` markers into spans, matching Stitch's own
/// emphasis on "REN Verified" in slide 3 -- a plain Text can't carry
/// per-segment weight, and this keeps the convention available to any
/// future slide's body copy without a one-off widget for just this case.
List<InlineSpan> _richBody(String text, TextStyle? baseStyle, TextStyle? boldStyle) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++) TextSpan(text: parts[i], style: i.isOdd ? boldStyle : baseStyle),
  ];
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          'R',
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'app_name'.tr(),
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: Text('onboarding_skip'.tr().toUpperCase()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Image.asset(
                            slide.imageAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (slide.badgeKey != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  slide.badgeKey!.tr().toUpperCase(),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(color: AppColors.ink, letterSpacing: 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          slide.titleKey.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final baseStyle = Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: AppColors.ink.withValues(alpha: 0.8));
                            final boldStyle = baseStyle?.copyWith(fontWeight: FontWeight.bold, color: AppColors.ink);
                            return Text.rich(
                              TextSpan(children: _richBody(slide.bodyKey.tr(), baseStyle, boldStyle)),
                              textAlign: TextAlign.center,
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final active = index == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 32 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: active ? AppColors.primaryContainer : AppColors.ink.withValues(alpha: 0.2),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  BrutalistButton(
                    label: (_page == _slides.length - 1 ? 'onboarding_get_started' : 'onboarding_next').tr(),
                    icon: PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
