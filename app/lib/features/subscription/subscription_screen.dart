// app/lib/features/subscription/subscription_screen.dart
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/subscription_status.dart';
import 'subscription_providers.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _submitting = false;
  String? _submitError;
  bool _upgradeProcessing = false;
  bool _processingTimedOut = false;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _upgrade() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final clientSecret = await ref.read(subscriptionRepositoryProvider).createSubscription();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'renly',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      setState(() {
        _upgradeProcessing = true;
        _processingTimedOut = false;
      });
      // The Realtime stream can emit 'professional' BEFORE this line --
      // stripe-webhook fires the instant the payment confirms, which can
      // beat presentPaymentSheet() resolving. ref.listen's callback in
      // build() already ran for that emission (while _upgradeProcessing
      // was still false, so it did nothing) and will NOT run again for
      // the same value, so switching into the processing state now would
      // strand the screen on "Processing..." for the full 15 seconds
      // despite the upgrade already being complete. Read the current
      // value once here and short-circuit out instead of waiting for an
      // emission that has already been and gone.
      if (ref.read(subscriptionStatusProvider).valueOrNull?.tier == 'professional') {
        setState(() {
          _upgradeProcessing = false;
          _processingTimedOut = false;
        });
        return;
      }
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted) setState(() => _processingTimedOut = true);
      });
    } on StripeException catch (e) {
      // Dismissing the native PaymentSheet is a StripeException with
      // FailureCode.Canceled -- a deliberate user action, not a failure.
      // Showing red error text for it is worse than cosmetic here: by
      // this point create-subscription has already left a real,
      // billable-later Stripe Subscription on the server, and a user who
      // reads "error" as "that failed, try again" is precisely the user
      // who used to manufacture duplicate subscriptions. Return silently
      // -- no error, no state change; the finally block still clears
      // _submitting.
      if (e.error.code == FailureCode.Canceled) {
        return;
      }
      if (mounted) setState(() => _submitError = e.error.localizedMessage ?? 'listing_error_generic'.tr());
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _manageSubscription() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final url = await ref.read(subscriptionRepositoryProvider).createPortalSession();
      // launchUrl RETURNS false (it does not throw) when no installed app
      // can handle the URL -- e.g. no browser on the device. Unchecked,
      // that made this button a completely silent no-op: the spinner
      // stops, nothing happens, and the user has no idea the billing
      // portal never opened.
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        setState(() => _submitError = 'listing_error_generic'.tr());
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _refresh() {
    _timeoutTimer?.cancel();
    setState(() {
      _upgradeProcessing = false;
      _processingTimedOut = false;
    });
    ref.invalidate(subscriptionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen (not a direct field mutation during build) is the
    // correct Riverpod way to react to a provider change with a side
    // effect (setState) -- mutating _upgradeProcessing directly inside
    // build() would only happen to work here because a rebuild was
    // already in progress, and would silently stop working if this
    // screen's build ever became conditionally skipped for any reason.
    ref.listen<AsyncValue<SubscriptionStatus>>(subscriptionStatusProvider, (previous, next) {
      if (_upgradeProcessing && next.valueOrNull?.tier == 'professional') {
        _timeoutTimer?.cancel();
        setState(() {
          _upgradeProcessing = false;
          _processingTimedOut = false;
        });
      }
    });

    final statusAsync = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text('subscription_title'.tr())),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('listing_error_generic'.tr()),
              TextButton(
                onPressed: () => ref.invalidate(subscriptionStatusProvider),
                child: Text('agreement_retry'.tr()),
              ),
            ],
          ),
        ),
        data: (status) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_upgradeProcessing) ...[
                Text('subscription_processing'.tr()),
                const SizedBox(height: 12),
                if (!_processingTimedOut)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Text('subscription_processing_timeout'.tr()),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _refresh, child: Text('subscription_refresh_button'.tr())),
                ],
              ] else if (status.tier == 'professional') ...[
                Text('subscription_professional_tier_label'.tr(), style: Theme.of(context).textTheme.titleLarge),
                if (status.status == 'past_due') ...[
                  const SizedBox(height: 8),
                  Text('subscription_status_past_due'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (status.currentPeriodEnd != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${'subscription_renews_on_label'.tr()}: ${status.currentPeriodEnd!.day}/${status.currentPeriodEnd!.month}/${status.currentPeriodEnd!.year}',
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _manageSubscription,
                  child: Text('subscription_manage_button'.tr()),
                ),
              ] else ...[
                Text('subscription_free_tier_label'.tr(), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _upgrade,
                  child: Text('subscription_upgrade_button'.tr()),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
