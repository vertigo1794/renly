// app/lib/features/auth/auth_selection_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';

/// Ports stitch_renly_property_agent_network/login_register_selection_english_official_style,
/// restyled per docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md.
class AuthSelectionScreen extends StatelessWidget {
  const AuthSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'app_name'.tr(),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              Text(
                'auth_tagline'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 32),
              Image.asset(
                'assets/illustrations/auth_hero.png',
                height: 200,
                // No artwork has been dropped into assets/illustrations/ yet
                // (see this task's brief -- this is the code path only, not
                // the asset itself). Without an errorBuilder, the missing
                // asset throws inside Image's async ImageStream pipeline and
                // that exception reaches FlutterError.reportError, which
                // flutter_test treats as an unhandled exception and fails
                // the test -- even though nothing here is actually broken.
                // Degrading gracefully to empty space keeps the slot's
                // layout height stable until real art lands.
                errorBuilder: (context, error, stackTrace) => const SizedBox(height: 200),
              ),
              const SizedBox(height: 32),
              BrutalistButton(
                label: 'auth_create_account'.tr(),
                onPressed: () => context.push('/register/personal'),
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: 'auth_log_in'.tr(),
                onPressed: () => context.push('/login'),
                variant: BrutalistButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
