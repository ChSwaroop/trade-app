import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import 'money.dart';

/// Formatting for money and percentages, following the Indian numbering
/// system (`₹1,23,456.78`).
///
/// Every [NumberFormat] here is constructed once at class-load time. Number
/// formats are relatively expensive to build, and these are called from inside
/// widget `build` methods that run on every tick — allocating one per build
/// would show up in the frame budget under the 50-ticks/sec stress case.
abstract final class MoneyFormat {
  static final NumberFormat _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _plain = NumberFormat.decimalPatternDigits(
    locale: 'en_IN',
    decimalDigits: 2,
  );

  static final NumberFormat _compact = NumberFormat.decimalPatternDigits(
    locale: 'en_IN',
    decimalDigits: 2,
  );

  static final Decimal _lakh = Decimal.fromInt(100000);
  static final Decimal _crore = Decimal.fromInt(10000000);

  /// `₹2,987.45`
  static String rupees(Money amount) => _rupees.format(amount.value.toDouble());

  /// `2,987.45` — no symbol, for columns where ₹ appears in the header.
  static String plain(Money amount) => _plain.format(amount.value.toDouble());

  /// `+₹34.20` / `-₹12.40`. The sign is always explicit so gains and losses
  /// are distinguishable without relying on colour alone.
  static String signedRupees(Money amount) {
    final String sign = amount.isNegative ? '-' : '+';
    return '$sign${_rupees.format(amount.abs.value.toDouble())}';
  }

  /// `1.15%` — magnitude only, since the sign is carried by the paired amount.
  /// Renders `--` when the percentage is undefined (zero base).
  static String percent(Decimal? value) {
    if (value == null) return '--';
    return '${value.abs().toStringAsFixed(2)}%';
  }

  /// `+1.15%` / `-0.30%`, for places where the percentage stands alone.
  static String signedPercent(Decimal? value) {
    if (value == null) return '--';
    final String sign = value < Decimal.zero ? '-' : '+';
    return '$sign${value.abs().toStringAsFixed(2)}%';
  }

  /// `₹12.5L` / `₹1.24Cr` — for summary tiles where horizontal space is tight.
  /// Falls back to the full format below one lakh.
  static String compactRupees(Money amount) {
    final Decimal magnitude = amount.value.abs();
    final String sign = amount.isNegative ? '-' : '';
    if (magnitude >= _crore) {
      final String n = _compact.format((magnitude / _crore).toDouble());
      return '$sign₹${n}Cr';
    }
    if (magnitude >= _lakh) {
      final String n = _compact.format((magnitude / _lakh).toDouble());
      return '$sign₹${n}L';
    }
    return '$sign${_rupees.format(magnitude.toDouble())}';
  }
}
