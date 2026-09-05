import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import 'auth_providers.dart';

/// Ports stitch_renly_property_agent_network/registration_professional.
/// "REN Tag Photo" is a plain image-picker upload (evidentiary record),
/// not live camera OCR scanning -- camera tag-scanning is explicitly
/// deferred per the design doc.
///
/// Re-fetched from Stitch's "Registration - Professional" redesign
/// (project "Renly Property Agent Network") -- same fields/submit flow as
/// before, with the same AppBar R* badge treatment Step 1 just got, a real
/// visual step-progress bar (fully filled, Step 2 of 2), per-field leading
/// icons + hint text for renNumber/agencyName, and the upload card
/// restyled into a dashed-border drop-zone (icon + title + hint + a filled
/// "Choose File" pill) matching the mockup, all on top of the existing
/// `_pickPhoto`/`_submit` logic untouched.
class RegistrationProfessionalScreen extends ConsumerStatefulWidget {
  const RegistrationProfessionalScreen({super.key, required this.negotiatorId});

  final String negotiatorId;

  @override
  ConsumerState<RegistrationProfessionalScreen> createState() => _RegistrationProfessionalScreenState();
}

class _RegistrationProfessionalScreenState extends ConsumerState<RegistrationProfessionalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _renNumberController = TextEditingController();
  final _agencyNameController = TextEditingController();
  XFile? _tagPhoto;
  bool _submitting = false;
  String? _submitError;
  String? _photoError;

  @override
  void dispose() {
    _renNumberController.dispose();
    _agencyNameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _tagPhoto = picked;
        _photoError = null;
      });
    }
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final photoValid = _tagPhoto != null;
    if (!photoValid) setState(() => _photoError = 'validation_required'.tr());
    if (!formValid || !photoValid) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final agencyId = await repository.findOrCreateAgency(_agencyNameController.text.trim());
      // XFile.readAsBytes() works on every platform including web; going
      // through dart:io's File(path) would break the web build.
      final bytes = await _tagPhoto!.readAsBytes();
      final photoUrl = await repository.uploadTagPhoto(
        negotiatorId: widget.negotiatorId,
        bytes: bytes,
      );
      await repository.completeProfessionalDetails(
        negotiatorId: widget.negotiatorId,
        renNumber: _renNumberController.text.trim(),
        agencyId: agencyId,
      );
      await repository.insertVerificationRecord(
        negotiatorId: widget.negotiatorId,
        tagPhotoUrl: photoUrl,
      );
      if (!mounted) return;
      context.go('/verification-pending');
    } catch (_) {
      // Never surface the raw exception -- see the same guard in
      // registration_personal_screen.dart for why.
      if (mounted) setState(() => _submitError = 'registration_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('registration_step2_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('registration_step2_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('registration_step2_progress'.tr(), style: Theme.of(context).textTheme.labelSmall),
                    Text('registration_professional_details_label'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.ink)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    // Step 2 of 2 -- fully filled, matching the mockup's
                    // own "width: 100%" progress bar.
                    value: 1.0,
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primaryContainer),
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reg_ren_number_field'),
                  controller: _renNumberController,
                  decoration: InputDecoration(
                    labelText: 'field_ren_number'.tr(),
                    hintText: 'field_ren_number_hint'.tr(),
                    prefixIcon: Icon(PhosphorIcons.identificationCard(PhosphorIconsStyle.bold)),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_agency_name_field'),
                  controller: _agencyNameController,
                  decoration: InputDecoration(
                    labelText: 'field_agency_name'.tr(),
                    hintText: 'field_agency_name_hint'.tr(),
                    prefixIcon: Icon(PhosphorIcons.storefront(PhosphorIconsStyle.bold)),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                Text('registration_tag_photo_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                // Dashed-border drop-zone card, matching the mockup's own
                // upload-area treatment -- icon + title + hint all now
                // live inside the card instead of the hint sitting above
                // it as a separate caption. _pickPhoto/_tagPhoto logic
                // underneath is unchanged, only the visual container.
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.ink.withValues(alpha: 0.3), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Icon(PhosphorIcons.camera(PhosphorIconsStyle.bold), color: AppColors.ink),
                        ),
                        const SizedBox(height: 12),
                        Text('registration_tag_photo_title'.tr(),
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Text(
                          'registration_tag_photo_hint'.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _pickPhoto,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
                          icon: Icon(PhosphorIcons.uploadSimple(PhosphorIconsStyle.bold), size: 18),
                          label: Text(_tagPhoto == null ? 'registration_choose_file'.tr() : _tagPhoto!.name),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_photoError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_photoError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.bold)),
                  label: Text('registration_complete'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
