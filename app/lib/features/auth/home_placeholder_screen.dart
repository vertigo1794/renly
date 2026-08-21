// app/lib/features/auth/home_placeholder_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('home_placeholder_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text('home_placeholder_body'.tr(), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push('/marketplace'),
                  child: Text('marketplace_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-inventory'),
                  child: Text('inventory_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.push('/requirement-board'),
                  child: Text('requirement_board_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-requirements'),
                  child: Text('my_requirements_title_placeholder_link'.tr()),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/my-matches'),
                  child: Text('matching_my_matches_link'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
