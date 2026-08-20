// app/lib/core/widgets/signed_photo.dart
import 'package:flutter/material.dart';

/// Displays a single photo by fetching a short-lived signed URL through the
/// given [signedUrlFetcher]. Shows a placeholder while loading or on error
/// (e.g. a photo whose upload never completed). Bucket-agnostic: callers
/// pass in whichever repository method knows which private bucket to sign
/// against (ListingRepository.createSignedUrl, RequirementRepository's
/// equivalent, etc.) -- this widget itself has no Supabase/Riverpod
/// dependency.
class SignedPhoto extends StatefulWidget {
  const SignedPhoto({super.key, required this.path, required this.signedUrlFetcher, this.fit = BoxFit.cover});

  final String path;
  final Future<String> Function(String path) signedUrlFetcher;
  final BoxFit fit;

  @override
  State<SignedPhoto> createState() => _SignedPhotoState();
}

class _SignedPhotoState extends State<SignedPhoto> {
  // Held in State, not created inline in build(): a FutureBuilder whose
  // future is rebuilt every frame would re-request a signed URL on every
  // rebuild (and never settle in widget tests).
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = widget.signedUrlFetcher(widget.path);
  }

  @override
  void didUpdateWidget(SignedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _signedUrl = widget.signedUrlFetcher(widget.path);
    }
  }

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
