import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import 'auth_providers.dart';

/// Ports stitch_renly_property_agent_network/registration_professional.
/// "REN Tag Photo" is a plain image-picker upload (evidentiary record),
/// not live camera OCR scanning -- camera tag-scanning is explicitly
/// deferred per the design doc.
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
        title: Text('app_name'.tr()),
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
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reg_ren_number_field'),
                  controller: _renNumberController,
                  decoration: InputDecoration(labelText: 'field_ren_number'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_agency_name_field'),
                  controller: _agencyNameController,
                  decoration: InputDecoration(labelText: 'field_agency_name'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                Text('registration_tag_photo_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text('registration_tag_photo_hint'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _pickPhoto,
                  child: Text(_tagPhoto == null ? 'registration_choose_file'.tr() : _tagPhoto!.name),
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
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('registration_complete'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
