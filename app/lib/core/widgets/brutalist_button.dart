import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BrutalistButtonVariant { primary, secondary }

/// A button matching this app's neo-brutalist visual identity
/// (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md):
/// primary is lime-filled with a solid offset "hard shadow" and an ink
/// border; secondary is outline-only with no shadow, visually
/// lighter-weight for less prominent actions. Both use the same 56px-tall
/// touch target this app's auth buttons already established -- full-width
/// by default, or content-sized via `fullWidth: false` for side-by-side
/// pairs and compact inline placements.
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

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final backgroundColor = _isPrimary ? AppColors.primary : Colors.transparent;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink);

    final buttonCore = Container(
      padding: fullWidth ? null : const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: AppColors.ink, width: 2.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: _isPrimary
            ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)]
            : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textStyle?.color, size: 20),
            const SizedBox(width: 8),
          ],
          Text(label, style: textStyle),
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
