import 'quote.dart';

/// An immutable view of the whole market at one frame boundary.
///
/// The consistency guarantee of the app rests on this type: holdings rows and
/// the portfolio summary header both read from a single snapshot instance, so
/// the aggregate can never disagree with the sum of the rows mid-update.
class PriceSnapshot {
  PriceSnapshot({
    required Map<String, Quote> quotes,
    required this.sequence,
    required this.timestamp,
  }) : quotes = Map<String, Quote>.unmodifiable(quotes);

  PriceSnapshot.empty()
      : quotes = const <String, Quote>{},
        sequence = 0,
        timestamp = null;

  final Map<String, Quote> quotes;

  /// Increments once per publish. Lets consumers detect a stale read and gives
  /// tests a deterministic handle on how many publishes occurred.
  final int sequence;

  /// When this snapshot was published. Null only for the initial empty value.
  final DateTime? timestamp;

  bool get isEmpty => quotes.isEmpty;

  Quote? operator [](String symbol) => quotes[symbol];

  @override
  String toString() => 'PriceSnapshot(seq: $sequence, symbols: ${quotes.length})';
}
