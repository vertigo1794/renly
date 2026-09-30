// app/lib/features/collaboration/propose_agreement_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import 'agreement_providers.dart';

/// Formats a prefill split value without a trailing ".0" (e.g. 45 not
/// 45.0), same rounding-safe intent as my_requests_screen.dart's
/// _formatSplitPercent but kept local since these are TextField prefill
/// strings, not display text.
String _formatPercent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}

class ProposeAgreementDialog extends ConsumerStatefulWidget {
  const ProposeAgreementDialog({
    super.key,
    required this.requestId,
    required this.initiatorId,
    this.initialSplitInitiator,
    this.initialSplitCounterparty,
    this.initialTerms,
    this.supersedeAgreementId,
  });

  final String requestId;
  final String initiatorId;

  /// Pre-fill values for a counter-offer -- the caller passes the
  /// SWAPPED split of the agreement being countered (see
  /// my_requests_screen.dart's "Propose New Terms" button), since the
  /// recipient countering naturally starts from "the opposite of what
  /// was offered to me." Null for a first-time proposal (empty fields).
  final double? initialSplitInitiator;
  final double? initialSplitCounterparty;
  final String? initialTerms;

  /// The pending agreement this new proposal replaces, if any -- passed
  /// straight through to AgreementRepository.createAgreement.
  final String? supersedeAgreementId;

  @override
  ConsumerState<ProposeAgreementDialog> createState() => _ProposeAgreementDialogState();
}

class _ProposeAgreementDialogState extends ConsumerState<ProposeAgreementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _initiatorController = TextEditingController(
      text: widget.initialSplitInitiator == null ? '' : _formatPercent(widget.initialSplitInitiator!));
  late final _counterpartyController = TextEditingController(
      text: widget.initialSplitCounterparty == null ? '' : _formatPercent(widget.initialSplitCounterparty!));
  late final _termsController = TextEditingController(text: widget.initialTerms ?? '');
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _initiatorController.dispose();
    _counterpartyController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  String? _percentageValidator(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed <= 0 || parsed >= 100) {
      return 'agreement_split_invalid'.tr();
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final splitInitiator = double.parse(_initiatorController.text);
    final splitCounterparty = double.parse(_counterpartyController.text);
    // Compare as integer cents, never as a raw double `==` check --
    // floating-point arithmetic can make an exact-100 sum fail an exact
    // equality comparison even when both inputs are individually valid
    // (e.g. 33.33 + 66.67 is not guaranteed to equal exactly 100.0 in
    // double precision).
    final sumInCents = (splitInitiator * 100).round() + (splitCounterparty * 100).round();
    if (sumInCents != 10000) {
      setState(() => _submitError = 'agreement_split_sum_error'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(agreementRepositoryProvider).createAgreement(
            requestId: widget.requestId,
            initiatorId: widget.initiatorId,
            splitInitiator: splitInitiator,
            splitCounterparty: splitCounterparty,
            terms: _termsController.text.trim().isEmpty ? null : _termsController.text.trim(),
            supersedeAgreementId: widget.supersedeAgreementId,
          );
      ref.invalidate(agreementForRequestProvider(widget.requestId));
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
      title: Text('agreement_propose_title'.tr()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _initiatorController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'agreement_split_initiator_label'.tr()),
              validator: _percentageValidator,
            ),
            TextFormField(
              controller: _counterpartyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'agreement_split_counterparty_label'.tr()),
              validator: _percentageValidator,
            ),
            TextFormField(
              controller: _termsController,
              decoration: InputDecoration(labelText: 'agreement_terms_label'.tr()),
              maxLines: 3,
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 8),
              Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        BrutalistButton(
          label: 'agreement_cancel'.tr(),
          variant: BrutalistButtonVariant.secondary,
          fullWidth: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        BrutalistButton(
          label: 'agreement_submit'.tr(),
          fullWidth: false,
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
