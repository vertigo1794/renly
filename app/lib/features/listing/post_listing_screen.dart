// app/lib/features/listing/post_listing_screen.dart
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/malaysian_states.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'listing_providers.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Ports stitch_renly_property_agent_network/post_listing's "Sediakan
/// Listing" branch only -- see the design doc's "Scope split" section for
/// why the "Cari Listing" (requirement) tab isn't built here yet.
class PostListingScreen extends ConsumerStatefulWidget {
  const PostListingScreen({super.key});

  @override
  ConsumerState<PostListingScreen> createState() => _PostListingScreenState();
}

class _PostListingScreenState extends ConsumerState<PostListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Set as soon as createListing() succeeds. _submit() is three separate
  /// network calls (create -> upload photos -> attach urls); if it fails
  /// partway, the natural user response is to tap "Post Now" again, which
  /// without this would insert a SECOND listing row. Remembering the id
  /// makes the retry resume from the upload step instead.
  String? _createdListingId;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = 10 - _photos.length;
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

  /// Keyed on XFile.path rather than the list index so that removing a
  /// photo doesn't shift every later thumbnail onto the wrong bytes. Cached
  /// because a FutureBuilder re-runs its future on every rebuild otherwise,
  /// re-reading the whole image each frame.
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

    final repository = ref.read(listingRepositoryProvider);
    try {
      // Only create the row on the first attempt -- a retry after a failed
      // photo upload reuses the id created last time.
      if (_createdListingId == null) {
        final listing = await repository.createListing(
          negotiatorId: negotiatorId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
          bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.parse(_bathroomsController.text.trim()),
        );
        _createdListingId = listing.listingId;
      }
      final listingId = _createdListingId!;

      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final path = await repository.uploadListingPhoto(
          negotiatorId: negotiatorId,
          listingId: listingId,
          index: i,
          bytes: bytes,
        );
        photoUrls.add(path);
      }
      if (photoUrls.isNotEmpty) {
        await repository.updateListingPhotos(listingId: listingId, photoUrls: photoUrls);
      }

      ref.invalidate(marketplaceListingsProvider);
      ref.invalidate(myListingsProvider(negotiatorId));
      // activeListingCountProvider is deliberately not autoDispose, so it
      // caches for the whole process lifetime unless invalidated here. Without
      // this, a free-tier user who posts (or later withdraws) a listing keeps
      // seeing a stale count and a falsely disabled submit button. Invalidated
      // only after the create + photo-upload sequence has fully succeeded, so a
      // retry after a photo-upload failure isn't handed a fresh (now higher)
      // count that would disable the submit button it needs.
      ref.invalidate(activeListingCountProvider(negotiatorId));

      try {
        final createdListing = await repository.fetchListingById(listingId);
        await ref.read(matchingRepositoryProvider).computeAndStoreMatchesForListing(createdListing);
        ref.invalidate(myMatchesProvider);
        ref.invalidate(matchesForListingProvider);
        ref.invalidate(matchesForRequirementProvider);
      } catch (_) {
        // Best-effort: matching is an enhancement, not a requirement for
        // the listing itself to have been created successfully. A failure
        // here must not trap the user on a form whose real submission
        // already succeeded. Re-fetched by id (rather than reusing the
        // `listing` local from the retry-safety branch above) because that
        // variable only exists inside `if (_createdListingId == null)` --
        // a retried submit that skips re-creating the row wouldn't have it.
      }

      if (!mounted) return;
      context.go('/my-inventory');
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
        : ref.watch(activeListingCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    return Scaffold(
      appBar: AppBar(title: Text('listing_post_title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('listing_title_field'),
                  controller: _titleController,
                  decoration: InputDecoration(labelText: 'listing_field_title'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_description_field'),
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'listing_field_description'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('listing_property_type_field'),
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
                  key: const Key('listing_transaction_type_field'),
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
                  key: const Key('listing_state_field'),
                  initialValue: _state,
                  decoration: InputDecoration(labelText: 'listing_field_state'.tr()),
                  items: [
                    for (final state in malaysianStates) DropdownMenuItem(value: state, child: Text(state)),
                  ],
                  onChanged: (value) => setState(() => _state = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_area_field'),
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'listing_field_area'.tr()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('listing_price_field'),
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'listing_field_price'.tr()),
                  validator: (value) {
                    final requiredError = _requiredValidator(value);
                    if (requiredError != null) return requiredError;
                    if (double.tryParse(value!.trim()) == null) return 'validation_required'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bedroomsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'listing_field_bedrooms'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _bathroomsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'listing_field_bathrooms'.tr()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('listing_photos_label'.tr()),
                    Text('listing_photos_max'.tr()),
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
                          // XFile.readAsBytes() works on every platform
                          // including web; going through dart:io's
                          // File(path) would break the web build. Same
                          // reason as registration_professional_screen.
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
                    if (_photos.length < 10)
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
                  Text('$activeCount/3 ${'listing_active_count_label'.tr()}'),
                ],
                if (atCap) ...[
                  const SizedBox(height: 8),
                  Text(
                    'listing_cap_reached_message'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_submitting || atCap) ? null : _submit,
                  child: Text('listing_post_now'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
