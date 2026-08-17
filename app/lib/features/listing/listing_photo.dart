// app/lib/features/listing/listing_photo.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'listing_providers.dart';

/// Displays a single listing photo by fetching a short-lived signed URL
/// from the private `listing-photos` bucket. Shows a placeholder while
/// loading or on error (e.g. a photo whose upload never completed).
class ListingPhoto extends ConsumerStatefulWidget {
  const ListingPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  ConsumerState<ListingPhoto> createState() => _ListingPhotoState();
}

class _ListingPhotoState extends ConsumerState<ListingPhoto> {
  // Held in State, not created inline in build(): a FutureBuilder whose
  // future is rebuilt every frame would re-request a signed URL on every
  // rebuild (and never settle in widget tests).
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = _request();
  }

  @override
  void didUpdateWidget(ListingPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _signedUrl = _request();
    }
  }

  Future<String> _request() => ref.read(listingRepositoryProvider).createSignedUrl(widget.path);

  Widget _placeholder(BuildContext context) {
    return Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _signedUrl,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          return _placeholder(context);
        }
        return Image.network(
          snapshot.data!,
          fit: widget.fit,
          errorBuilder: (context, error, stack) => _placeholder(context),
        );
      },
    );
  }
}
