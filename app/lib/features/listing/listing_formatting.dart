/// Pure price-display formatting. No Flutter/Supabase -- fully unit-testable.
class ListingFormatting {
  ListingFormatting._();

  static String formatPrice(num price, String transactionType) {
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
