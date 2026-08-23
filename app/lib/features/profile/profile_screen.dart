// app/lib/features/profile/profile_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'profile_status_approved'.tr();
      case 'rejected':
        return 'profile_status_rejected'.tr();
      default:
        return 'profile_status_pending'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final countsAsync = ref.watch(profileCountsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('profile_title'.tr())),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
          data: (profile) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Chip(label: Text(_statusLabel(profile.verificationStatus))),
                const SizedBox(height: 12),
                Text('${'profile_ren_number_label'.tr()}: ${profile.renNumber ?? '-'}'),
                const SizedBox(height: 4),
                Text('${'profile_agency_label'.tr()}: ${profile.agencyName ?? '-'}'),
                const SizedBox(height: 20),
                countsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (counts) => Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('${counts.$1}', style: Theme.of(context).textTheme.headlineSmall),
                                Text('profile_active_listings_label'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('${counts.$2}', style: Theme.of(context).textTheme.headlineSmall),
                                Text('profile_deals_closed_label'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _EditForm(profile: profile),
                const SizedBox(height: 20),
                Text('profile_language_label'.tr(), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'en', label: Text('profile_language_en'.tr())),
                    ButtonSegment(value: 'ms', label: Text('profile_language_ms'.tr())),
                  ],
                  selected: {context.locale.languageCode},
                  onSelectionChanged: (selection) => context.setLocale(Locale(selection.first)),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: Text('profile_sign_out'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _territoryController;
  late final TextEditingController _specialisationController;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _territoryController = TextEditingController(text: widget.profile.territory ?? '');
    _specialisationController = TextEditingController(text: widget.profile.propertySpecialisation ?? '');
  }

  // After a successful save, ref.invalidate(myProfileProvider) causes
  // ProfileScreen to rebuild with a fresh Profile instance -- but since
  // _EditForm occupies the same slot with the same widget type, Flutter
  // reuses this State and initState does NOT re-run, so the controllers
  // would otherwise never resync to the newly-fetched canonical values.
  @override
  void didUpdateWidget(covariant _EditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile.territory != oldWidget.profile.territory) {
      _territoryController.text = widget.profile.territory ?? '';
    }
    if (widget.profile.propertySpecialisation != oldWidget.profile.propertySpecialisation) {
      _specialisationController.text = widget.profile.propertySpecialisation ?? '';
    }
  }

  @override
  void dispose() {
    _territoryController.dispose();
    _specialisationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            negotiatorId: negotiatorId,
            territory: _territoryController.text.trim().isEmpty ? null : _territoryController.text.trim(),
            propertySpecialisation:
                _specialisationController.text.trim().isEmpty ? null : _specialisationController.text.trim(),
          );
      ref.invalidate(myProfileProvider);
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _territoryController,
          decoration: InputDecoration(labelText: 'profile_territory_label'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _specialisationController,
          decoration: InputDecoration(labelText: 'profile_specialisation_label'.tr()),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 8),
          Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: Text('profile_save'.tr()),
        ),
      ],
    );
  }
}
