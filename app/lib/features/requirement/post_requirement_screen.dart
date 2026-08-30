// app/lib/features/requirement/post_requirement_screen.dart
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import '../../core/widgets/brutalist_button.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'requirement_providers.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Separate screen from PostListingScreen -- see the design doc for why the
/// mockup's tab toggle isn't retrofitted into the shared, already-tested
/// listing form.
class PostRequirementScreen extends ConsumerStatefulWidget {
  const PostRequirementScreen({super.key});

  @override
  ConsumerState<PostRequirementScreen> createState() => _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  static const _maxPhotos = 3;

  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();
  final _bedroomsController = TextEditingController();
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Same retry-safety as PostListingScreen: set once createRequirement()
  /// succeeds, so a retry after a failed photo upload resumes from the
  /// upload step instead of inserting a second row.
  String? _createdRequirementId;

  @override
  void dispose() {
    _areaController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    _bedroomsController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, limit: remaining);
    if (picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(remaining));
    });
  }

  void _removePhoto(int index) {
    final removed = _photos[index];
    setState(() => _photos.removeAt(index));
    _photoBytesCache.remove(removed.path);
  }

  /// Keyed on XFile.path rather than the list index -- same reasoning as
  /// PostListingScreen's cache: removing a photo shouldn't shift every
  /// later thumbnail onto the wrong cached bytes.
  final Map<String, Future<Uint8List>> _photoBytesCache = {};

  Future<Uint8List> _photoBytes(int index) {
    final photo = _photos[index];
    return _photoBytesCache.putIfAbsent(photo.path, photo.readAsBytes);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(requirementRepositoryProvider);
    try {
      if (_createdRequirementId == null) {
        final requirement = await repository.createRequirement(
          negotiatorId: negotiatorId,
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          budgetMin: double.parse(_budgetMinController.text.trim()),
          budgetMax: double.parse(_budgetMaxController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
        );
        _createdRequirementId = requirement.requirementId;
      }
      final requirementId = _createdRequirementId!;

      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path = await repository.uploadRequirementPhoto(
          negotiatorId: negotiatorId,
          requirementId: requirementId,
          index: i,
          bytes: bytes,
        );
        photoUrls.add(path);
      }
      if (photoUrls.isNotEmpty) {
        await repository.updateRequirementPhotos(requirementId: requirementId, photoUrls: photoUrls);
      }

      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(negotiatorId));
      // Same reasoning as PostListingScreen: the count provider is not
      // autoDispose, so it stays cached until invalidated, and invalidating it
      // only after the upload sequence succeeds keeps a retrying user from
      // being locked out by a freshly incremented count.
      ref.invalidate(activeRequirementCountProvider(negotiatorId));

      try {
        final createdRequirement = await repository.fetchRequirementById(requirementId);
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForRequirement(createdRequirement);
        ref.invalidate(myMatchesProvider);
        ref.invalidate(matchesForListingProvider);
        ref.invalidate(matchesForRequirementProvider);
      } catch (_) {
        // Best-effort, same reasoning as PostListingScreen.
      }

      if (!mounted) return;
      context.go('/my-requirements');
    } catch (e) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final tierAsync = ref.watch(subscriptionStatusProvider);
    final countAsync = negotiatorId == null
        ? const AsyncValue<int>.data(0)
        : ref.watch(activeRequirementCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    return Scaffold(
      appBar: AppBar(title: Text('requirement_post_title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('requirement_property_type_field'),
                  initialValue: _propertyType,
                  decoration: InputDecoration(labelText: 'listing_field_property_type'.tr()),
                  items: [
                    DropdownMenuItem(value: 'apartment', child: Text('listing_property_type_apartment'.tr())),
                    DropdownMenuItem(value: 'house', child: Text('listing_property_type_house'.tr())),
                    DropdownMenuItem(value: 'commercial', child: Text('listing_property_type_commercial'.tr())),
                    DropdownMenuItem(value: 'land', child: Text('listing_property_type_land'.tr())),
                  ],
                  onChanged: (value) => setState(() => _propertyType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('requirement_transaction_type_field'),
                  initialValue: _transactionType,
                  decoration: InputDecoration(labelText: 'listing_field_transaction_type'.tr()),
                  items: [
                    DropdownMenuItem(value: 'sale', child: Text('listing_transaction_type_sale'.tr())),
                    DropdownMenuItem(value: 'rent', child: Text('listing_transaction_type_rent'.tr())),
                  ],
                  onChanged: (value) => setState(() => _transactionType = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('requirement_state_field'),
                  initialValue: _state,
                  decoration: InputDecoration(labelText: 'listing_field_state'.tr()),
                  items: [
                    for (final state in malaysianStates) DropdownMenuItem(value: state, child: Text(state)),
                  ],
                  onChanged: (value) => setState(() => _state = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('requirement_area_field'),
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('requirement_budget_min_field'),
                  controller: _budgetMinController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'requirement_field_budget_min'.tr()),
                  validator: (value) {
                    final requiredError = _requiredValidator(value);
                    if (requiredError != null) return requiredError;
                    if (double.tryParse(value!.trim()) == null) return 'validation_required'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('requirement_budget_max_field'),
                  controller: _budgetMaxController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'requirement_field_budget_max'.tr()),
                  validator: (value) {
                    final requiredError = _requiredValidator(value);
                    if (requiredError != null) return requiredError;
                    final max = double.tryParse(value!.trim());
                    if (max == null) return 'validation_required'.tr();
                    final min = double.tryParse(_budgetMinController.text.trim());
                    if (min != null && max < min) return 'requirement_budget_max_below_min'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bedroomsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_bedrooms'.tr()),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('listing_photos_label'.tr()),
                    Text('requirement_photos_max'.tr()),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    ...List.generate(_photos.length, (index) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FutureBuilder<Uint8List>(
                                future: _photoBytes(index),
                                builder: (context, snapshot) {
                                  final bytes = snapshot.data;
                                  if (bytes == null) {
                                    return Container(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    );
                                  }
                                  return Image.memory(bytes, fit: BoxFit.cover);
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removePhoto(index),
                              child: const CircleAvatar(
                                radius: 12,
                                child: Icon(Icons.close, size: 16),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    if (_photos.length < _maxPhotos)
                      OutlinedButton(
                        onPressed: _pickPhotos,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo),
                            Text('listing_add_photo'.tr(), style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ],
                ),
                if (tierAsync.valueOrNull?.tier == 'free') ...[
                  const SizedBox(height: 12),
                  Text('$activeCount/3 ${'requirement_active_count_label'.tr()}'),
                ],
                if (atCap) ...[
                  const SizedBox(height: 8),
                  Text(
                    'requirement_cap_reached_message'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: 'requirement_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
