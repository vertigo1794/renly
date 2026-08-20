// app/lib/features/listing/listing_photo.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/signed_photo.dart';
import 'listing_providers.dart';

/// Thin wrapper binding SignedPhoto to the listing-photos bucket via
/// ListingRepository.createSignedUrl. Extracted this way (rather than
/// SignedPhoto reading listingRepositoryProvider itself) so the
/// requirement feature can reuse SignedPhoto against its own bucket
/// without depending on the listing feature's repository.
class ListingPhoto extends ConsumerWidget {
  const ListingPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SignedPhoto(
      path: path,
      fit: fit,
      signedUrlFetcher: ref.read(listingRepositoryProvider).createSignedUrl,
    );
  }
}
