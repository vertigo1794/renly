// app/lib/features/listing/post_listing_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/malaysian_states.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../matching/live_match_preview.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/models/requirement.dart';
import '../requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;
import 'broadcast_badge.dart';
import 'listing_drafts_provider.dart';
import 'listing_providers.dart';
import 'models/listing.dart';
import 'models/listing_draft.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Ports stitch_renly_property_agent_network/post_listing's "Sediakan
/// Listing" branch, now in 3 modes (My Inventory Premium Restyle):
/// plain create (both params null), edit (editListingId set -- loads and
/// pre-fills from the real Listing, submits via updateListingDetails),
/// and draft-resume (initialDraft set -- pre-fills from a local,
/// never-submitted draft). editListingId and initialDraft are mutually
/// exclusive in practice; passing both is not a supported combination.
class PostListingFormBody extends ConsumerStatefulWidget {
  const PostListingFormBody({super.key, this.editListingId, this.initialDraft});

  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostListingFormBody> createState() => _PostListingFormBodyState();
}

class _PostListingFormBodyState extends ConsumerState<PostListingFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _sqftController = TextEditingController();
  final _commissionSplitController = TextEditingController();

  /// Which commission-split preset is currently highlighted -- '5050',
  /// 'full', or 'custom' (which reveals the raw percentage field below
  /// the presets), or null when nothing has been picked yet. Tracked
  /// separately from _commissionSplitController.text because tapping
  /// Custom clears the field to prompt fresh input, and a cleared field's
  /// text alone can't distinguish "no preset chosen" from "Custom chosen,
  /// not yet typed".
  String? _splitPreset;

  static String? _presetForSplitValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed == '50') return '5050';
    if (trimmed == '100') return 'full';
    return 'custom';
  }

  Timer? _previewDebounce;
  List<Requirement>? _previewCandidates;
  LiveMatchPreviewResult _previewResult = const LiveMatchPreviewResult(matchCount: 0);
  String _propertyType = 'apartment';
  String _transactionType = 'sale';
  String _state = malaysianStates.first;
  bool _titleVerified = false;
  bool _exclusiveMandate = false;
  final List<XFile> _photos = [];
  bool _submitting = false;
  String? _submitError;

  /// Set as soon as createListing() succeeds. _submit() is three separate
  /// network calls (create -> upload photos -> attach urls); if it fails
  /// partway, the natural user response is to tap "Post Now" again, which
  /// without this would insert a SECOND listing row. Remembering the id
  /// makes the retry resume from the upload step instead. Also set
  /// immediately in edit mode (from widget.editListingId) so _submit's
  /// branch logic has one single "do we have an id" check.
  String? _createdListingId;

  bool get _isEditMode => widget.editListingId != null;

  /// One-shot guard: the loaded Listing (edit mode) arrives asynchronously
  /// via listingDetailProvider, but the form's controllers must only be
  /// populated ONCE, not on every rebuild while that provider re-emits.
  bool _prefilledFromListing = false;

  @override
  void initState() {
    super.initState();
    _createdListingId = widget.editListingId;
    final draft = widget.initialDraft;
    if (draft != null) {
      _titleController.text = draft.title;
      _descriptionController.text = draft.description;
      _propertyType = draft.propertyType;
      _transactionType = draft.transactionType;
      _state = draft.state;
      _areaController.text = draft.area;
      _priceController.text = draft.price ?? '';
      _bedroomsController.text = draft.bedrooms ?? '';
      _bathroomsController.text = draft.bathrooms ?? '';
      _sqftController.text = draft.sqft ?? '';
      _commissionSplitController.text = draft.commissionSplitPercent ?? '';
      _splitPreset = _presetForSplitValue(_commissionSplitController.text);
      _titleVerified = draft.titleVerified;
      _exclusiveMandate = draft.exclusiveMandate;
    }
    _loadPreviewCandidates();
    for (final controller in [_areaController, _priceController, _bedroomsController, _bathroomsController, _sqftController]) {
      controller.addListener(_onPreviewFieldChanged);
    }
  }

  /// Best-effort, same reasoning as _submit()'s matching-computation catch
  /// block: the live match preview is an enhancement layered on top of the
  /// form, never a requirement for posting/editing a listing to work. A
  /// failure here (offline, backend hiccup, or -- in widget tests --
  /// Supabase never having been initialized at all) must not crash
  /// initState/the whole form; _previewCandidates simply stays null and
  /// _recomputePreview's own null-check keeps the preview card hidden.
  Future<void> _loadPreviewCandidates() async {
    try {
      final requirements = await ref.read(requirementRepositoryProvider).fetchBoardRequirements();
      if (!mounted) return;
      setState(() {
        _previewCandidates = requirements;
        _recomputePreview();
      });
    } catch (e) {
      // Intentionally swallowed -- see doc comment above. debugPrint keeps
      // a real failure visible in test/debug output (matches
      // chat_screen.dart's _markConversationRead precedent) without
      // surfacing anything to the user.
      debugPrint('_loadPreviewCandidates failed: $e');
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    for (final controller in [_areaController, _priceController, _bedroomsController, _bathroomsController, _sqftController]) {
      controller.removeListener(_onPreviewFieldChanged);
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _sqftController.dispose();
    _commissionSplitController.dispose();
    super.dispose();
  }

  void _prefillFromListing(Listing listing) {
    if (_prefilledFromListing) return;
    _prefilledFromListing = true;
    _titleController.text = listing.title;
    _descriptionController.text = listing.description;
    _propertyType = listing.propertyType;
    _transactionType = listing.transactionType;
    _state = listing.state;
    _areaController.text = listing.area;
    _priceController.text = listing.price.toString();
    _bedroomsController.text = listing.bedrooms?.toString() ?? '';
    _bathroomsController.text = listing.bathrooms?.toString() ?? '';
    _sqftController.text = listing.builtUpSqft?.toString() ?? '';
    _commissionSplitController.text = listing.commissionSplitPercent?.toString() ?? '';
    _splitPreset = _presetForSplitValue(_commissionSplitController.text);
    _titleVerified = listing.titleVerified;
    _exclusiveMandate = listing.exclusiveMandate;
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

  double? get _commissionSplitValue {
    final text = _commissionSplitController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  int? get _sqftValue {
    final text = _sqftController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _saveAsDraft() async {
    if (_titleController.text.trim().isEmpty) return;
    final draft = ListingDraft(
      draftId: widget.initialDraft?.draftId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      savedAt: DateTime.now(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      propertyType: _propertyType,
      transactionType: _transactionType,
      state: _state,
      area: _areaController.text.trim(),
      price: _priceController.text.trim().isEmpty ? null : _priceController.text.trim(),
      bedrooms: _bedroomsController.text.trim().isEmpty ? null : _bedroomsController.text.trim(),
      bathrooms: _bathroomsController.text.trim().isEmpty ? null : _bathroomsController.text.trim(),
      sqft: _sqftController.text.trim().isEmpty ? null : _sqftController.text.trim(),
      commissionSplitPercent:
          _commissionSplitController.text.trim().isEmpty ? null : _commissionSplitController.text.trim(),
      titleVerified: _titleVerified,
      exclusiveMandate: _exclusiveMandate,
    );
    // Resuming an existing draft and saving again replaces it (same
    // draftId) rather than creating a duplicate entry.
    if (widget.initialDraft != null) {
      await ref.read(listingDraftsProvider.notifier).remove(widget.initialDraft!.draftId);
    }
    await ref.read(listingDraftsProvider.notifier).add(draft);
    if (!mounted) return;
    context.go('/my-inventory');
  }

  void _onPreviewFieldChanged() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(_recomputePreview);
    });
  }

  void _recomputePreview() {
    final candidates = _previewCandidates;
    if (candidates == null) return;
    final price = double.tryParse(_priceController.text.trim());
    if (price == null) {
      _previewResult = const LiveMatchPreviewResult(matchCount: 0);
      return;
    }
    final draftListing = Listing(
      listingId: 'preview',
      negotiatorId: ref.read(currentNegotiatorIdProvider) ?? 'preview',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      propertyType: _propertyType,
      transactionType: _transactionType,
      state: _state,
      area: _areaController.text.trim(),
      price: price,
      bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.tryParse(_bedroomsController.text.trim()),
      bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.tryParse(_bathroomsController.text.trim()),
      builtUpSqft: _sqftValue,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime.now(),
    );
    _previewResult = LiveMatchPreview.forListing(draftListing, candidates);
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
      if (_isEditMode) {
        await repository.updateListingDetails(
          listingId: widget.editListingId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          propertyType: _propertyType,
          transactionType: _transactionType,
          state: _state,
          area: _areaController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          bedrooms: _bedroomsController.text.trim().isEmpty ? null : int.parse(_bedroomsController.text.trim()),
          bathrooms: _bathroomsController.text.trim().isEmpty ? null : int.parse(_bathroomsController.text.trim()),
          builtUpSqft: _sqftValue,
          commissionSplitPercent: _commissionSplitValue,
          titleVerified: _titleVerified,
          exclusiveMandate: _exclusiveMandate,
        );
        ref.invalidate(listingDetailProvider(widget.editListingId!));
        ref.invalidate(marketplaceListingsProvider);
        ref.invalidate(myListingsProvider(negotiatorId));
        if (!mounted) return;
        context.go('/my-inventory');
        return;
      }

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
          builtUpSqft: _sqftValue,
          commissionSplitPercent: _commissionSplitValue,
          titleVerified: _titleVerified,
          exclusiveMandate: _exclusiveMandate,
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

      // A draft that was just successfully posted is no longer a draft.
      if (widget.initialDraft != null) {
        await ref.read(listingDraftsProvider.notifier).remove(widget.initialDraft!.draftId);
      }

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
    final atCap = !_isEditMode && tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    if (_isEditMode) {
      final listingAsync = ref.watch(listingDetailProvider(widget.editListingId!));
      listingAsync.whenData(_prefillFromListing);
      if (listingAsync.isLoading && !_prefilledFromListing) {
        return const Center(child: CircularProgressIndicator());
      }
    }

    return SafeArea(
      top: false,
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
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: BroadcastBadge(
                      label: 'broadcast_high_demand_badge'.tr(),
                      color: const Color(0xFFBBF7D0),
                      textColor: const Color(0xFF166534),
                    ),
                  ),
                ),
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
                  onChanged: (value) => setState(() {
                    _propertyType = value!;
                    _recomputePreview();
                  }),
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
                  onChanged: (value) => setState(() {
                    _transactionType = value!;
                    _recomputePreview();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('listing_state_field'),
                  initialValue: _state,
                  decoration: InputDecoration(labelText: 'listing_field_state'.tr()),
                  items: [
                    for (final state in malaysianStates) DropdownMenuItem(value: state, child: Text(state)),
                  ],
                  onChanged: (value) => setState(() {
                    _state = value!;
                    _recomputePreview();
                  }),
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
                Text('listing_key_specs_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SpecStatField(
                        icon: PhosphorIcons.bed(PhosphorIconsStyle.bold),
                        controller: _bedroomsController,
                        label: 'inventory_stat_beds'.tr(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SpecStatField(
                        icon: PhosphorIcons.bathtub(PhosphorIconsStyle.bold),
                        controller: _bathroomsController,
                        label: 'inventory_stat_baths'.tr(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SpecStatField(
                        fieldKey: const Key('listing_sqft_field'),
                        icon: PhosphorIcons.ruler(PhosphorIconsStyle.bold),
                        controller: _sqftController,
                        label: 'inventory_stat_sqft'.tr(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('listing_field_commission_split'.tr(), style: Theme.of(context).textTheme.labelSmall),
                    BroadcastBadge(
                      label: 'listing_split_fast_matching_badge'.tr(),
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SplitPresetChip(
                        label: 'split_preset_5050'.tr(),
                        sublabel: 'listing_split_5050_sub'.tr(),
                        selected: _splitPreset == '5050',
                        onTap: () => setState(() {
                          _splitPreset = '5050';
                          _commissionSplitController.text = '50';
                          _recomputePreview();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SplitPresetChip(
                        label: 'split_preset_full'.tr(),
                        sublabel: 'listing_split_full_sub'.tr(),
                        selected: _splitPreset == 'full',
                        onTap: () => setState(() {
                          _splitPreset = 'full';
                          _commissionSplitController.text = '100';
                          _recomputePreview();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SplitPresetChip(
                        label: 'split_preset_custom'.tr(),
                        sublabel: 'listing_split_custom_sub'.tr(),
                        selected: _splitPreset == 'custom',
                        onTap: () => setState(() {
                          _splitPreset = 'custom';
                          _commissionSplitController.clear();
                          _recomputePreview();
                        }),
                      ),
                    ),
                  ],
                ),
                if (_splitPreset == 'custom') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('listing_commission_split_field'),
                    controller: _commissionSplitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = double.tryParse(value.trim());
                      if (parsed == null || parsed <= 0 || parsed > 100) return 'validation_required'.tr();
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const Key('listing_title_verified_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_title_verified'.tr()),
                  subtitle: Text('listing_title_verified_caption'.tr()),
                  value: _titleVerified,
                  onChanged: (value) => setState(() => _titleVerified = value),
                ),
                SwitchListTile(
                  key: const Key('listing_exclusive_mandate_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('listing_field_exclusive_mandate'.tr()),
                  subtitle: Text('listing_exclusive_mandate_caption'.tr()),
                  value: _exclusiveMandate,
                  onChanged: (value) => setState(() => _exclusiveMandate = value),
                ),
                const SizedBox(height: 12),
                // Photo editing has no wired-up submit path in edit mode --
                // updateListingDetails() deliberately never touches
                // photo_urls (see its own doc comment; that's
                // updateListingPhotos's job, which the edit flow doesn't
                // call). Hiding the whole section here, rather than just
                // disabling it, avoids implying a capability edit mode
                // doesn't actually have.
                if (!_isEditMode) ...[
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
                      if (_photos.length < 10) AddPhotoTile(label: 'listing_add_photo'.tr(), onTap: _pickPhotos),
                    ],
                  ),
                ],
                if (!_isEditMode && tierAsync.valueOrNull?.tier == 'free') ...[
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
                if (_previewResult.matchCount > 0) ...[
                  const SizedBox(height: 16),
                  MatchPreviewCard(result: _previewResult, radarLabelKey: 'listing_preview_radar_label'),
                ],
                const SizedBox(height: 24),
                BrutalistButton(
                  label: _isEditMode ? 'listing_save_changes'.tr() : 'listing_post_now'.tr(),
                  icon: _isEditMode ? null : PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
                if (!_isEditMode) ...[
                  const SizedBox(height: 12),
                  BrutalistButton(
                    label: 'listing_save_as_draft'.tr(),
                    variant: BrutalistButtonVariant.secondary,
                    onPressed: _submitting ? null : _saveAsDraft,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}
