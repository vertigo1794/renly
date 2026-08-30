// app/lib/features/auth/home_placeholder_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.user(PhosphorIconsStyle.bold)),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('home_placeholder_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text('home_placeholder_body'.tr(), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                Image.asset(
                  'assets/illustrations/home_hero.png',
                  height: 160,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                ),
                const SizedBox(height: 24),
                BrutalistButton(
                  label: 'marketplace_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/marketplace'),
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'inventory_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/my-inventory'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'requirement_board_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/requirement-board'),
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'my_requirements_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/my-requirements'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'matching_my_matches_link'.tr(),
                  onPressed: () => context.push('/my-matches'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'cobroke_request_my_requests_link'.tr(),
                  onPressed: () => context.push('/my-requests'),
                  variant: BrutalistButtonVariant.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
