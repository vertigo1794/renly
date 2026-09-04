// app/lib/features/auth/onboarding_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';

/// One onboarding slide's content. `titleKey`/`bodyKey` are easy_localization
/// keys, not raw strings, so every slide stays bilingual EN/MS like the rest
/// of the app.
class OnboardingSlideData {
  const OnboardingSlideData({
    required this.imageAsset,
    required this.titleKey,
    required this.bodyKey,
  });

  final String imageAsset;
  final String titleKey;
  final String bodyKey;
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
/// Slides are added here one at a time as each is ported from Stitch; the
/// list below is the single source of truth for how many dots/pages show.
const _slides = [
  OnboardingSlideData(
    imageAsset: 'assets/illustrations/onboarding_1_collaboration.png',
    titleKey: 'onboarding_1_title',
    bodyKey: 'onboarding_1_body',
  ),
  OnboardingSlideData(
    imageAsset: 'assets/illustrations/onboarding_2_matching.png',
    titleKey: 'onboarding_2_title',
    bodyKey: 'onboarding_2_body',
  ),
];

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
                        Text(
                          slide.titleKey.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.bodyKey.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: AppColors.ink.withValues(alpha: 0.8)),
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
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.ink.withValues(alpha: active ? 1 : 0.2),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  BrutalistButton(
                    label: 'onboarding_next'.tr(),
                    icon: PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                    onPressed: _next,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: Text('onboarding_skip'.tr().toUpperCase()),
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
