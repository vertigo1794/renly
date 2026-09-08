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
class NegotiatorAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final circle = CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF0B0F19),
      backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
      // A broken/unreachable avatarUrl must not crash every one of this
      // widget's 9+ call sites -- same graceful-degradation intent as
      // SignedPhoto's own errorBuilder, just via CircleAvatar's own error
      // callback since backgroundImage (unlike Image.network) has no
      // errorBuilder param. Swallowed, not logged: a stale/broken photo URL
      // is an expected, harmless state (e.g. deleted storage object), not
      // an error worth surfacing.
      onBackgroundImageError: avatarUrl == null ? null : (exception, stackTrace) {},
      child: avatarUrl != null
          ? null
          : Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: size * 16 / 44),
            ),
    );

    if (!isOnline) return circle;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 12 / 44,
            height: size * 12 / 44,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: size * 2 / 44),
            ),
          ),
        ),
      ],
    );
  }
}
