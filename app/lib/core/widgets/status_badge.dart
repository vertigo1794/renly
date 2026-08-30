import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small pill showing a listing's or requirement's current status --
/// see docs/superpowers/specs/2026-08-25-renly-urby-restyle-phase2a-design.md.
/// Takes the already-localized label directly rather than a raw status
/// string, so it stays domain-agnostic (works for both listing and
/// requirement status vocabularies without knowing either).
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent,
        border: Border.all(color: AppColors.ink, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
