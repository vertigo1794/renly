/// A read-only view of one negotiator's subscription state. `tier` is the
/// only field that gates anything (Sub-milestone B reads this, not
/// `status`/`currentPeriodEnd`) -- the other two are display-only,
/// written verbatim from Stripe's own vocabulary by the stripe-webhook
/// Edge Function, never interpreted client-side.
class SubscriptionStatus {
  final String tier;
  final String? status;
  final DateTime? currentPeriodEnd;

  const SubscriptionStatus({required this.tier, this.status, this.currentPeriodEnd});

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final rawPeriodEnd = json['current_period_end'] as String?;
    return SubscriptionStatus(
      tier: json['subscription_tier'] as String,
      status: json['subscription_status'] as String?,
      currentPeriodEnd: rawPeriodEnd == null ? null : DateTime.parse(rawPeriodEnd),
    );
  }
}
