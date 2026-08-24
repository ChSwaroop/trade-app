import '../../core/money/money.dart';
import '../../market/stock_universe.dart';

/// Whether an order buys or sells the instrument.
enum OrderSide {
  buy,
  sell;

  static OrderSide? fromJson(Object? raw) => switch (raw) {
        'buy' => OrderSide.buy,
        'sell' => OrderSide.sell,
        _ => null,
      };

  String toJson() => name;
}

/// A completed market order: what filled, at what price, when.
///
/// Orders are immutable — the app never edits or cancels a placed order, it
/// just records the next one. That is what lets Holdings be a straight
/// derivation over the order list rather than a separately-mutated store, and
/// why partial sells cannot desync the cost basis.
class Order {
  const Order({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.fillPrice,
    required this.timestamp,
  });

  /// Rebuilds an order from persisted JSON.
  ///
  /// Returns `null` on any missing, mistyped, or nonsensical field. Same
  /// contract as `Watchlist.fromJson` — a bad document rescues to "no order",
  /// never crashes the load.
  static Order? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? symbol = json['symbol'];
    final Object? side = json['side'];
    final Object? qty = json['quantity'];
    final Object? price = json['fillPrice'];
    final Object? ts = json['timestamp'];

    if (id is! String || id.isEmpty) return null;
    if (symbol is! String || !StockUniverse.contains(symbol)) return null;
    final OrderSide? parsedSide = OrderSide.fromJson(side);
    if (parsedSide == null) return null;
    if (qty is! int || qty <= 0) return null;
    if (price is! String) return null;
    if (ts is! String) return null;

    final Money parsedPrice;
    try {
      parsedPrice = Money.parse(price);
    } on FormatException {
      return null;
    }
    if (!parsedPrice.isPositive) return null;

    final DateTime? parsedTs = DateTime.tryParse(ts);
    if (parsedTs == null) return null;

    return Order(
      id: id,
      symbol: symbol,
      side: parsedSide,
      quantity: qty,
      fillPrice: parsedPrice,
      timestamp: parsedTs,
    );
  }

  final String id;
  final String symbol;
  final OrderSide side;
  final int quantity;

  /// Price at which the order actually filled, taken from `PriceStore` at the
  /// moment of submission — not from whatever the UI last painted.
  final Money fillPrice;

  final DateTime timestamp;

  /// Exact — quantity is an int, so no rounding is required.
  Money get value => fillPrice * quantity;

  bool get isBuy => side == OrderSide.buy;
  bool get isSell => side == OrderSide.sell;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'symbol': symbol,
        'side': side.toJson(),
        'quantity': quantity,
        'fillPrice': fillPrice.toStorageString(),
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Order &&
          other.id == id &&
          other.symbol == symbol &&
          other.side == side &&
          other.quantity == quantity &&
          other.fillPrice == fillPrice &&
          other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(id, symbol, side, quantity, fillPrice, timestamp);

  @override
  String toString() =>
      'Order($id, $side $quantity $symbol @ $fillPrice, $timestamp)';
}
