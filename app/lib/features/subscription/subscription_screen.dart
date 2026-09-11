// app/lib/features/subscription/subscription_screen.dart
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
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
      backgroundColor: const Color(0xFFF9FAF7),
      appBar: AppBar(
        title: Text('subscription_title'.tr()),
        backgroundColor: const Color(0xFFF9FAF7),
        elevation: 0,
      ),
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
        data: (status) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_upgradeProcessing)
                _ProcessingCard(
                  timedOut: _processingTimedOut,
                  onRefresh: _refresh,
                )
              else if (status.tier == 'professional')
                _ProfessionalTierView(
                  status: status,
                  submitting: _submitting,
                  onManage: _manageSubscription,
                )
              else
                _FreeTierView(
                  submitting: _submitting,
                  onUpgrade: _upgrade,
                ),
              if (_submitError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDAD6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBA1A1A).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.warningCircle(PhosphorIconsStyle.bold), color: Theme.of(context).colorScheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark "ink" plan-status card sitting at the top of both tier states --
/// the eyebrow + tier-name pattern gives this screen its own premium
/// identity (distinct from the plain white BrutalistCard used everywhere
/// else in Profile) while the tier name text itself stays exactly what
/// subscription_screen_test.dart asserts on ('Free Plan'/'Professional
/// Plan'), just restyled rather than relocated out of the tree.
class _PlanHeroCard extends StatelessWidget {
  const _PlanHeroCard({required this.tierLabel, required this.child});

  final String tierLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: const [BoxShadow(color: AppColors.primary, offset: Offset(4, 4), blurRadius: 0)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(PhosphorIcons.crownSimple(PhosphorIconsStyle.fill), color: AppColors.ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'subscription_hero_eyebrow'.tr().toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, letterSpacing: 1.0, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tierLabel,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _FreeTierView extends StatelessWidget {
  const _FreeTierView({required this.submitting, required this.onUpgrade});

  final bool submitting;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanHeroCard(
          tierLabel: 'subscription_free_tier_label'.tr(),
          child: Text(
            'subscription_upgrade_headline'.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'subscription_upgrade_subtitle'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        const _FeatureList(),
        const SizedBox(height: 24),
        BrutalistButton(
          label: 'subscription_upgrade_button'.tr(),
          icon: PhosphorIcons.crownSimple(PhosphorIconsStyle.bold),
          onPressed: submitting ? null : onUpgrade,
        ),
        const SizedBox(height: 12),
        _TrustNote(),
      ],
    );
  }
}

class _ProfessionalTierView extends StatelessWidget {
  const _ProfessionalTierView({required this.status, required this.submitting, required this.onManage});

  final SubscriptionStatus status;
  final bool submitting;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanHeroCard(
          tierLabel: 'subscription_professional_tier_label'.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status.status == 'past_due') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFFFDAD6), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.warningCircle(PhosphorIconsStyle.bold), color: const Color(0xFFBA1A1A), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'subscription_status_past_due'.tr(),
                        style: const TextStyle(color: Color(0xFFBA1A1A), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (status.currentPeriodEnd != null)
                Row(
                  children: [
                    Icon(PhosphorIcons.calendarCheck(PhosphorIconsStyle.bold), color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${'subscription_renews_on_label'.tr()} ${status.currentPeriodEnd!.day}/${status.currentPeriodEnd!.month}/${status.currentPeriodEnd!.year}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              else
                Text('subscription_active_note'.tr(), style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('subscription_whats_included_label'.tr().toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B), letterSpacing: 0.5)),
        const SizedBox(height: 12),
        const _FeatureList(),
        const SizedBox(height: 24),
        BrutalistButton(
          label: 'subscription_manage_button'.tr(),
          icon: PhosphorIcons.gearSix(PhosphorIconsStyle.bold),
          variant: BrutalistButtonVariant.dark,
          onPressed: submitting ? null : onManage,
        ),
      ],
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  static const _keys = [
    'subscription_feature_unlimited_requests',
    'subscription_feature_priority_match',
    'subscription_feature_verified_badge',
    'subscription_feature_priority_support',
  ];

  @override
  Widget build(BuildContext context) {
    return BrutalistCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _keys.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: const Color(0xFF16A34A), size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_keys[i].tr(), style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrustNote extends StatelessWidget {
  const _TrustNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.bold), size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          'subscription_trust_note'.tr(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({required this.timedOut, required this.onRefresh});

  final bool timedOut;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return BrutalistCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('subscription_processing'.tr(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (!timedOut)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text('subscription_processing_timeout'.tr(), style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            BrutalistButton(
              label: 'subscription_refresh_button'.tr(),
              icon: PhosphorIcons.arrowClockwise(PhosphorIconsStyle.bold),
              onPressed: onRefresh,
            ),
          ],
        ],
      ),
    );
  }
}
