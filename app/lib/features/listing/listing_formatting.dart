/// Pure price-display formatting. No Flutter/Supabase -- fully unit-testable.
class ListingFormatting {
  ListingFormatting._();

  static String formatPrice(num price, String transactionType) {
    // num.round() throws on NaN/Infinity, and Postgres' `price > 0` CHECK
    // does NOT reject 'NaN'::numeric (Postgres orders NaN above every other
    // numeric), so one malformed row would otherwise crash every client
    // rendering the marketplace list.
    if (!price.isFinite) return 'RM —';
    final rounded = price.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    final suffix = transactionType == 'rent' ? ' /mo' : '';
    return 'RM $buffer$suffix';
  }
}
