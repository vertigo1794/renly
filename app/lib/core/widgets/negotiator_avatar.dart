// app/lib/core/widgets/negotiator_avatar.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A circular avatar for ANOTHER negotiator (not the viewer's own profile)
/// -- their uploaded photo when set, else the initials-on-ink-circle
/// fallback this app already hand-rolled in two places
/// (`conversation_list_screen.dart` radius 22, `marketplace_screen.dart`
/// radius 15) before this widget existed. A small green dot overlays the
/// bottom-right corner ONLY when [isOnline] is true -- no dot at all when
/// false, so a viewer never has to guess whether gray means "offline" or
/// "unknown" (see the design doc's own reasoning for this choice). Has no
/// Supabase/Riverpod dependency, same principle as `SignedPhoto` --
/// [avatarUrl] is expected to already be a full public URL (the
/// avatar-photos bucket is public, unlike the private+signed-URL
/// listing/requirement photo buckets `SignedPhoto` was built for).
///
/// [size] mirrors `RStarBadge`'s own size-param convention (a single
/// scalar controlling overall diameter, with internal proportions computed
/// off it) -- default 44 matches `conversation_list_screen.dart`'s
/// pre-existing radius-22 visual, so that call site's own replacement is a
/// drop-in with zero visual change beyond the new photo/dot capability.
///
/// A `StatefulWidget`, not stateless: a broken/unreachable [avatarUrl] (a
/// deleted storage object, a transient network failure) must fall back to
/// the initials -- the same graceful-degradation SignedPhoto's own
/// `errorBuilder` provides -- rather than silently rendering a blank
/// colored disc. `CircleAvatar.backgroundImage` has no `errorBuilder`
/// param (unlike `Image.network`), so this state flip is done by hand via
/// `onBackgroundImageError`.
class NegotiatorAvatar extends StatefulWidget {
  const NegotiatorAvatar({
    required this.fullName,
    this.avatarUrl,
    this.isOnline = false,
    this.size = 44,
    super.key,
  });

  final String fullName;
  final String? avatarUrl;
  final bool isOnline;
  final double size;

  @override
  State<NegotiatorAvatar> createState() => _NegotiatorAvatarState();
}

class _NegotiatorAvatarState extends State<NegotiatorAvatar> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(covariant NegotiatorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new avatarUrl (e.g. after a re-upload) deserves a fresh attempt --
    // otherwise a negotiator who fixes their broken photo would stay stuck
    // showing initials until this widget's State is recreated from scratch.
    if (widget.avatarUrl != oldWidget.avatarUrl) {
      _imageFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showImage = widget.avatarUrl != null && !_imageFailed;
    final circle = CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: const Color(0xFF0B0F19),
      backgroundImage: showImage ? NetworkImage(widget.avatarUrl!) : null,
      onBackgroundImageError: showImage
          ? (exception, stackTrace) {
              // Swallowed, not logged: a stale/broken photo URL is an
              // expected, harmless state (e.g. deleted storage object),
              // not an error worth surfacing -- falls back to initials
              // below via setState.
              if (mounted) setState(() => _imageFailed = true);
            }
          : null,
      child: showImage
          ? null
          : Text(
              widget.fullName.isNotEmpty ? widget.fullName[0].toUpperCase() : '?',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: widget.size * 16 / 44),
            ),
    );

    if (!widget.isOnline) return circle;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: widget.size * 12 / 44,
            height: widget.size * 12 / 44,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: widget.size * 2 / 44),
            ),
          ),
        ),
      ],
    );
  }
}
