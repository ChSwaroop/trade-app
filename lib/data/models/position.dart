import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import 'order.dart';

/// An open position in one instrument: quantity held, and the cost of holding
/// it.
///
/// **Only [quantity] and [totalCost] are stored.** The average is derived on
/// demand. This is the rule from `implementations/market.md` §3 — persisting
/// the average would round every buy and drift a little more each time; the
/// total is exact by construction.
///
/// A [Position] represents a live holding, so [quantity] is always positive.
/// A sell that reduces the quantity to zero drops the position from the
/// holdings map rather than leaving a zero-quantity ghost behind.
class Position {
  Position({
    required this.symbol,
    required this.quantity,
    required this.totalCost,
  })  : assert(quantity > 0, 'A live position has a positive quantity'),
        assert(!totalCost.isNegative, 'Cost basis cannot be negative');

  final String symbol;
  final int quantity;

  /// Sum of every buy's `qty × fill price`, reduced proportionally on partial
  /// sells. Never `avgCost × qtySold`.
  final Money totalCost;

  /// The realised average cost per share, rounded to paise. Derived from
  /// [totalCost] and [quantity] on every read — the position never stores it.
  Money get averageCost => totalCost.divideBy(quantity);

  Money currentValue(Money ltp) => ltp * quantity;

  /// Unrealised P&L against a live LTP. Signed.
  Money unrealisedPnl(Money ltp) => currentValue(ltp) - totalCost;

  /// Unrealised P&L as a percentage of the cost basis. Signed. `null` when
  /// there is no cost basis (which cannot happen for a live position, but the
  /// [Money.ratioTo] contract handles it and this mirrors that).
  Decimal? unrealisedPnlPercent(Money ltp) =>
      unrealisedPnl(ltp).ratioTo(totalCost);

  Position copyWith({int? quantity, Money? totalCost}) => Position(
        symbol: symbol,
        quantity: quantity ?? this.quantity,
        totalCost: totalCost ?? this.totalCost,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position &&
          other.symbol == symbol &&
          other.quantity == quantity &&
          other.totalCost == totalCost;

  @override
  int get hashCode => Object.hash(symbol, quantity, totalCost);

  @override
  String toString() =>
      'Position($symbol, qty: $quantity, totalCost: $totalCost)';
}

/// Folds the order history into per-symbol open positions.
///
/// The function is pure — it depends on nothing beyond [orders]. That is what
/// lets Holdings be a straight `Provider` over `ordersProvider`, keeps the
/// aggregate summary and the row list agreeing by construction, and keeps
/// this whole derivation reproducible from persisted state alone.
///
/// The rules, all from `implementations/market.md` §3:
///
/// 1. A buy adds `quantity` to the total and `quantity × fillPrice` to
///    `totalCost` — exact, no rounding, so accumulation cannot drift.
/// 2. A partial sell reduces `totalCost` **proportionally**:
///    `newTotalCost = totalCost × (remaining / original)`,
///    done as an exact rational and rounded to paise once. Never
///    `averageCost × qtySold`, which would feed the rounded average back into
///    the basis.
/// 3. A sell that brings quantity to zero (or into the red, which is defended
///    against but should never happen — the notifier blocks over-sells) drops
///    the symbol from the map. A zero-qty ghost position would then poison
///    every average by dividing by zero.
Map<String, Position> positionsFrom(List<Order> orders) {
  final Map<String, ({int qty, Money totalCost})> working =
      <String, ({int qty, Money totalCost})>{};

  for (final Order order in orders) {
    final ({int qty, Money totalCost}) prev = working[order.symbol] ??
        (qty: 0, totalCost: Money.zero);

    switch (order.side) {
      case OrderSide.buy:
        working[order.symbol] = (
          qty: prev.qty + order.quantity,
          totalCost: prev.totalCost + (order.fillPrice * order.quantity),
        );
      case OrderSide.sell:
        final int remaining = prev.qty - order.quantity;
        if (remaining <= 0) {
          // Fully closed (or over-sold, which the ticket rejects). Either way
          // the position is gone; realised P&L is out of scope for this
          // feature but the fill still lives in the order history.
          working.remove(order.symbol);
        } else {
          working[order.symbol] = (
            qty: remaining,
            totalCost: prev.totalCost.scaledBy(remaining, prev.qty),
          );
        }
    }
  }

  return <String, Position>{
    for (final MapEntry<String, ({int qty, Money totalCost})> e
        in working.entries)
      e.key: Position(
        symbol: e.key,
        quantity: e.value.qty,
        totalCost: e.value.totalCost,
      ),
  };
}
