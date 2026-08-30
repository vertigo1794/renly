import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BrutalistButtonVariant { primary, secondary }

/// A button matching this app's neo-brutalist visual identity
/// (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md):
/// primary is lime-filled with a solid offset "hard shadow" and an ink
/// border; secondary is outline-only with no shadow, visually
/// lighter-weight for less prominent actions. Both use the same 56px-tall
/// full-width touch target this app's auth buttons already established.
class BrutalistButton extends StatelessWidget {
  const BrutalistButton({
    required this.label,
    required this.onPressed,
    this.variant = BrutalistButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalistButtonVariant variant;

  bool get _isPrimary => variant == BrutalistButtonVariant.primary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final backgroundColor = _isPrimary ? AppColors.primary : Colors.transparent;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink);

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border.all(color: AppColors.ink, width: 2.5),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isPrimary
                    ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(label, style: textStyle),
            ),
          ),
        ),
      ),
    );
  }
}
