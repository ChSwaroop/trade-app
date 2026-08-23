import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// Which way the most recent tick moved. Drives the flash colour.
enum TickDirection { up, down, flat }

/// A price print for one instrument at one instant.
///
/// Immutable and value-equal, which is what lets a Riverpod `.select` skip a
/// rebuild when a snapshot arrives that did not change this symbol.
class Quote {
  Quote({
    required this.symbol,
    required this.ltp,
    required this.previousClose,
    required this.direction,
    required this.sequence,
  })  : change = ltp - previousClose,
        changePercent = (ltp - previousClose).ratioTo(previousClose);

  final String symbol;

  /// Last traded price.
  final Money ltp;

  /// The instrument's opening reference price. Fixed for the session, so
  /// [change] measures movement since the open rather than since the last tick.
  final Money previousClose;

  /// Absolute move since [previousClose]. Signed.
  final Money change;

  /// Percentage move since [previousClose]. Signed. Null when the reference
  /// price is zero, which cannot happen for a real instrument but is handled
  /// rather than divided by.
  final Decimal? changePercent;

  /// Direction of the last tick relative to the tick before it — not relative
  /// to the open. A stock down for the day still flashes green on an uptick.
  final TickDirection direction;

  /// Monotonic counter, incremented once per accepted tick for this symbol.
  /// Included in equality so that two consecutive ticks landing on the same
  /// price still register as a distinct print, which the flash animation
  /// needs in order to re-fire.
  final int sequence;

  bool get isUp => change.isPositive;

  bool get isDown => change.isNegative;

  @override
  bool operator ==(Object other) =>
      other is Quote &&
      other.symbol == symbol &&
      other.ltp == ltp &&
      other.previousClose == previousClose &&
      other.direction == direction &&
      other.sequence == sequence;

  @override
  int get hashCode => Object.hash(symbol, ltp, previousClose, direction, sequence);

  @override
  String toString() => 'Quote($symbol, ltp: $ltp, seq: $sequence)';
}
