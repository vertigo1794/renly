import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A card matching this app's neo-brutalist visual identity -- white
/// fill, an ink border, and the same hard-shadow effect BrutalistButton's
/// primary variant uses. See
/// docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md.
class BrutalistCard extends StatelessWidget {
  const BrutalistCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults to null (falls back to AppColors.surface -- every existing
  /// call site's white-fill look is unchanged) -- an optional override for
  /// call sites that need a colored variant of this same bordered/shadowed
  /// card shape (e.g. a highlighted stat card), rather than duplicating
  /// this whole decoration locally.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        border: Border.all(color: AppColors.ink, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)],
      ),
      child: child,
    );
  }
}
