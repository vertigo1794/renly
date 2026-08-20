/// Pure budget-range-display formatting. No Flutter/Supabase -- fully
/// unit-testable. Mirrors ListingFormatting.formatPrice's /mo-for-rent
/// convention -- a rental requirement's budget is a monthly figure too.
class RequirementFormatting {
  RequirementFormatting._();

  static String formatBudgetRange(num min, num max, String transactionType) {
    final suffix = transactionType == 'rent' ? ' /mo' : '';
    return '${_formatAmount(min)} - ${_formatAmount(max)}$suffix';
  }

  static String _formatAmount(num amount) {
    // Same NaN/Infinity guard as ListingFormatting: Postgres' `> 0` CHECK
    // does not reject 'NaN'::numeric, so one malformed row would otherwise
    // crash every client rendering the board.
    if (!amount.isFinite) return 'RM —';
    final rounded = amount.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return 'RM $buffer';
  }
}
