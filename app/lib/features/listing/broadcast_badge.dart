// app/lib/features/listing/broadcast_badge.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../matching/live_match_preview.dart';

/// Small rounded label pill shared across the Post Broadcast screens
/// (headline badges, the LIVE ticker, per-field "High Demand" tags, and
/// the commission-split section badges).
class BroadcastBadge extends StatelessWidget {
  const BroadcastBadge({super.key, required this.label, required this.color, this.textColor = Colors.black});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

/// A single editable spec field styled as a bordered "stat card" (icon on
/// top, the real value centered, a short unit label underneath) -- shared
/// by both PostListingFormBody's and PostRequirementFormBody's
/// bedrooms/bathrooms/built-up rows. Stays a real, editable TextFormField;
/// only the decoration changes from the previous plain-box style.
class SpecStatField extends StatelessWidget {
  const SpecStatField({
    super.key,
    required this.icon,
    required this.controller,
    required this.label,
    this.fieldKey,
  });

  final IconData icon;
  final TextEditingController controller;
  final String label;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(height: 4),
          TextFormField(
            key: fieldKey,
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '-',
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }
}

/// One of the 3 commission-split quick-fill presets (50/50, Full 2%,
/// Custom) shown above the raw percentage field -- tapping a preset just
/// fills the same real TextEditingController the field itself reads, same
/// interaction pattern as this app's existing location quick-fill pills.
class SplitPresetChip extends StatelessWidget {
  const SplitPresetChip({
    super.key,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          border: Border.all(color: Colors.black.withValues(alpha: selected ? 1 : 0.2)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : Colors.black,
                  ),
            ),
            Text(
              sublabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? Colors.white70 : const Color(0xFF6B7280),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square "Add Photo" grid tile with a dashed border, matching the Post
/// Broadcast mockup's upload tile (a plain circular OutlinedButton
/// before this restyle). Shared by both forms' photo grids.
class AddPhotoTile extends StatelessWidget {
  const AddPhotoTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_a_photo_outlined, size: 20),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dashPath = Path();
    const dashWidth = 6.0;
    const dashGap = 4.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        dashPath.addPath(metric.extractPath(distance, distance + dashWidth), Offset.zero);
        distance += dashWidth + dashGap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

/// Richer live-match-preview card (real topMatchScore/topMatchLabel/
/// matchCount from LiveMatchPreview, never fabricated) -- shared by both
/// forms' "Preliminary Match Radar" section. Only rendered by the caller
/// when matchCount > 0.
class MatchPreviewCard extends StatelessWidget {
  const MatchPreviewCard({super.key, required this.result, required this.radarLabelKey});

  final LiveMatchPreviewResult result;
  final String radarLabelKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(radarLabelKey.tr(), style: Theme.of(context).textTheme.labelSmall),
              if (result.topMatchScore != null)
                Text(
                  '${result.topMatchScore}% ${'preview_direct_match_suffix'.tr()}',
                  style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (result.topMatchScore != null)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                  child: Text(
                    '${result.topMatchScore}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.topMatchLabel != null)
                      Text(
                        result.topMatchLabel!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'preview_units_count'.tr(namedArgs: {'count': '${result.matchCount}'}),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
