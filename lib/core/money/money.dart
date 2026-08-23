import 'package:decimal/decimal.dart';

/// An exact monetary amount in Indian rupees.
///
/// Backed by [Decimal] rather than [double] so that repeated arithmetic
/// (accumulating cost basis across many buys, for example) never accumulates
/// binary floating-point drift.
///
/// Two rules keep the precision guarantee intact:
///
/// 1. There is no general `toDouble()`. The only escape hatch is
///    [toDoubleUnsafe], which is named to be greppable and is intended for
///    chart geometry alone — never for arithmetic, comparison or persistence.
/// 2. Division is never done with `/`. `Decimal.operator /` returns a
///    [Rational] and throws on non-terminating results, so all division goes
///    through [divideBy] / [ratioTo], which state the scale and rounding
///    policy in one place.
class Money implements Comparable<Money> {
  const Money._(this._value);

  /// Parses a decimal string such as `'2987.45'`. Used by the persistence
  /// layer, which always stores money as a string.
  factory Money.parse(String source) => Money._(Decimal.parse(source));

  /// Wraps an existing [Decimal].
  factory Money.fromDecimal(Decimal value) => Money._(value);

  /// Builds an amount from whole rupees.
  factory Money.fromRupees(int rupees) => Money._(Decimal.fromInt(rupees));

  /// Builds an amount from paise, avoiding any decimal literal at the call
  /// site. `Money.fromPaise(298745)` is `₹2,987.45`.
  factory Money.fromPaise(int paise) =>
      Money._((Decimal.fromInt(paise) / _hundred).toDecimal(scaleOnInfinitePrecision: 2));

  /// The scale every amount is normalised to: paise precision.
  static const int scale = 2;

  static final Decimal _hundred = Decimal.fromInt(100);

  static final Money zero = Money._(Decimal.zero);

  final Decimal _value;

  /// The underlying decimal. Exposed for formatting and for building other
  /// [Money] values — not for converting to a primitive.
  Decimal get value => _value;

  bool get isZero => _value == Decimal.zero;

  bool get isNegative => _value < Decimal.zero;

  bool get isPositive => _value > Decimal.zero;

  Money get abs => Money._(_value.abs());

  /// Rounds to paise precision using banker's-neutral half-up, the convention
  /// used for currency in Indian broking.
  Money get rounded => Money._(_value.round(scale: scale));

  Money operator +(Money other) => Money._(_value + other._value);

  Money operator -(Money other) => Money._(_value - other._value);

  Money operator -() => Money._(-_value);

  /// Multiplies by a whole quantity. Exact — no rounding required.
  Money operator *(int quantity) => Money._(_value * Decimal.fromInt(quantity));

  bool operator <(Money other) => _value < other._value;

  bool operator <=(Money other) => _value <= other._value;

  bool operator >(Money other) => _value > other._value;

  bool operator >=(Money other) => _value >= other._value;

  /// Divides by a whole quantity, rounding to paise. Used to derive an average
  /// cost from a total cost. Throws [ArgumentError] on a zero divisor rather
  /// than producing an infinity, because a zero-quantity holding should have
  /// been removed before anyone asks for its average price.
  Money divideBy(int divisor) {
    if (divisor == 0) {
      throw ArgumentError.value(divisor, 'divisor', 'Cannot divide money by zero');
    }
    // `toDecimal` only applies its scale when the quotient does not terminate,
    // so an exactly-representable result such as 2991.2375 would otherwise
    // slip through at full precision. The explicit round is what actually
    // enforces paise precision.
    return Money._(
      (_value / Decimal.fromInt(divisor))
          .toDecimal(scaleOnInfinitePrecision: scale)
          .round(scale: scale),
    );
  }

  /// This amount as a percentage of [base], rounded to two decimals.
  ///
  /// Returns `null` when [base] is zero — a percentage change from nothing is
  /// undefined, and callers render a dash rather than an infinity.
  Decimal? ratioTo(Money base) {
    if (base.isZero) return null;
    // Scale up before dividing: `Decimal / Decimal` yields a Rational, and a
    // Rational cannot then be multiplied by a Decimal.
    return ((_value * _hundred) / base._value)
        .toDecimal(scaleOnInfinitePrecision: 4)
        .round(scale: scale);
  }

  /// Escape hatch for chart geometry only. Never use for arithmetic,
  /// comparison, or anything that gets persisted or displayed as a number.
  double toDoubleUnsafe() => _value.toDouble();

  /// The canonical persistence form. Round-trips exactly through [Money.parse].
  String toStorageString() => _value.toString();

  @override
  int compareTo(Money other) => _value.compareTo(other._value);

  @override
  bool operator ==(Object other) => other is Money && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  // Prints the underlying value rather than a fixed-scale rendering, so a
  // value carrying more precision than paise is visible in a test failure
  // instead of being disguised as an equal one.
  String toString() => 'Money($_value)';
}
