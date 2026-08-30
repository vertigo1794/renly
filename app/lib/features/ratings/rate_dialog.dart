// app/lib/features/ratings/rate_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import 'models/rating.dart';
import 'rating_providers.dart';

class RateDialog extends ConsumerStatefulWidget {
  const RateDialog({
    super.key,
    required this.agreementId,
    required this.raterId,
    required this.ratedId,
    this.existingRating,
  });

  final String agreementId;
  final String raterId;
  final String ratedId;
  final Rating? existingRating;

  @override
  ConsumerState<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<RateDialog> {
  late int _stars;
  late final TextEditingController _reviewController;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _stars = widget.existingRating?.stars ?? 5;
    _reviewController = TextEditingController(text: widget.existingRating?.reviewText ?? '');
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final reviewText = _reviewController.text.trim().isEmpty ? null : _reviewController.text.trim();
      final existing = widget.existingRating;
      if (existing == null) {
        await ref.read(ratingRepositoryProvider).createRating(
              agreementId: widget.agreementId,
              raterId: widget.raterId,
              ratedId: widget.ratedId,
              stars: _stars,
              reviewText: reviewText,
            );
      } else {
        await ref.read(ratingRepositoryProvider).updateRating(
              ratingId: existing.ratingId,
              stars: _stars,
              reviewText: reviewText,
            );
      }
      ref.invalidate(myRatingForAgreementProvider(widget.agreementId));
      ref.invalidate(ratingsForNegotiatorProvider(widget.ratedId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'listing_error_generic'.tr();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // On narrow phones (~360dp and below) the two BrutalistButtons can
      // still slightly exceed the actions row's available width and fall
      // back to AlertDialog's stacked layout -- this spacing keeps their
      // 2.5px ink borders from touching in that fallback case.
      actionsOverflowButtonSpacing: 8,
      title: Text('rating_dialog_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 5 stars at the 48x48 minimum touch target (240dp total) can
          // exceed a narrow phone's dialog content width (e.g. 360dp and
          // below, once AlertDialog's own inset/content padding is
          // subtracted) -- SingleChildScrollView preserves the full touch
          // target everywhere instead of shrinking it back below 48dp to
          // force a fit, at the cost of a scroll gesture on the narrowest
          // screens only.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return _BrutalistStar(
                  starValue: starValue,
                  selected: starValue <= _stars,
                  onTap: _submitting ? null : () => setState(() => _stars = starValue),
                );
              }),
            ),
          ),
          TextField(
            controller: _reviewController,
            decoration: InputDecoration(labelText: 'rating_review_label'.tr()),
            maxLines: 3,
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        BrutalistButton(
          label: 'rating_cancel'.tr(),
          variant: BrutalistButtonVariant.secondary,
          fullWidth: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        BrutalistButton(
          label: 'rating_submit'.tr(),
          fullWidth: false,
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _BrutalistStar extends StatelessWidget {
  const _BrutalistStar({required this.starValue, required this.selected, required this.onTap});

  final int starValue;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${'rating_star_label'.tr()} $starValue',
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        // Padding(8) around a 32px icon gives a 48x48 tap target, meeting
        // the Material/WCAG minimum touch-target size -- the plain
        // IconButton this replaced guaranteed that via
        // kMinInteractiveDimension; a bare GestureDetector does not.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            PhosphorIcons.star(selected ? PhosphorIconsStyle.bold : PhosphorIconsStyle.regular),
            color: AppColors.ink,
            size: 32,
          ),
        ),
      ),
    );
  }
}
