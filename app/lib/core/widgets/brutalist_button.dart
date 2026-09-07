import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BrutalistButtonVariant { primary, secondary, dark }

/// A button matching this app's neo-brutalist visual identity
/// (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md):
/// primary is lime-filled with a solid offset "hard shadow" and an ink
/// border; secondary is outline-only with no shadow, visually
/// lighter-weight for less prominent actions; dark is ink-filled with
/// lime text -- for placing a primary-weight CTA on a lime-background
/// screen (e.g. AuthSelectionScreen), where primary's own lime fill
/// would otherwise nearly disappear into the page behind it. Both
/// primary and dark use the same 56px-tall touch target this app's auth
/// buttons already established -- full-width by default, or
/// content-sized via `fullWidth: false` for side-by-side pairs and
/// compact inline placements.
class BrutalistButton extends StatelessWidget {
  const BrutalistButton({
    required this.label,
    required this.onPressed,
    this.variant = BrutalistButtonVariant.primary,
    this.fullWidth = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalistButtonVariant variant;
  final bool fullWidth;
  final IconData? icon;

  bool get _isPrimary => variant == BrutalistButtonVariant.primary;
  bool get _isDark => variant == BrutalistButtonVariant.dark;
  bool get _hasShadow => _isPrimary || _isDark;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final backgroundColor = switch (variant) {
      BrutalistButtonVariant.primary => AppColors.primary,
      BrutalistButtonVariant.secondary => Colors.transparent,
      BrutalistButtonVariant.dark => AppColors.ink,
    };
    final textStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: _isDark ? AppColors.primaryContainer : AppColors.ink);

    final buttonCore = Container(
      // 8, not the full-width path's implicit ~20-24: an AlertDialog's
      // OverflowBar adds its own buttonPadding around each action, so two
      // fullWidth:false buttons need to be lean to land side-by-side on
      // common phone widths (verified empirically: side-by-side from
      // ~380dp with this padding; narrower phones still fall back to
      // AlertDialog's own stacked layout via actionsOverflowButtonSpacing,
      // which is a legitimate Material fallback, not a bug).
      padding: fullWidth ? null : const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: AppColors.ink, width: 2.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: _hasShadow ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)] : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textStyle?.color, size: 20),
            const SizedBox(width: 8),
          ],
          // Flexible+ellipsis is a no-op for every button that already fits
          // its available width (the overwhelming majority of call sites):
          // Flexible's own intrinsic-width contribution to the Row equals
          // its child's natural width, so IntrinsicWidth-based shrink-wrap
          // (the fullWidth:false branch below) is unaffected. It only
          // engages when the Row is laid out inside a bounded-width parent
          // narrower than the label's natural width (e.g. _ActionBar's
          // Expanded CTA slot on tight phone widths), truncating instead of
          // throwing a RenderFlex overflow.
          Flexible(child: Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          height: 56,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              // fullWidth:false must shrink-wrap regardless of the parent's
              // constraints (Column, Center, AlertDialog's OverflowBar, a
              // fixed-width SizedBox, ...). Container's own `alignment`
              // makes it expand to fill any BOUNDED parent width even when
              // its child is narrower, so a plain Container here silently
              // renders full-width outside a Row. IntrinsicWidth forces
              // sizing to the child's natural width in every case.
              child: fullWidth ? buttonCore : IntrinsicWidth(child: buttonCore),
            ),
          ),
        ),
      ),
    );
  }
}
