import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../data/models/order.dart';
import '../../data/models/position.dart';
import '../../data/models/quote.dart';
import '../../market/market_providers.dart';
import '../orders/orders_providers.dart';

/// How the Holdings list is ordered.
enum HoldingsSort {
  pnl('P&L'),
  symbol('Symbol'),
  value('Value');

  const HoldingsSort(this.label);

  final String label;
}

/// Every open position, in a deterministic order (by symbol) — the sort
/// applied for display lives in a separate provider so that a sort change
/// does not rebuild the aggregate summary.
///
/// Derived from `ordersProvider` alone. Orders are persisted, so a relaunch
/// reproduces every position exactly; nothing extra needs to be stored.
final Provider<List<Position>> holdingsProvider = Provider<List<Position>>(
  (Ref ref) {
    final List<Order> orders =
        ref.watch(ordersProvider.select((Ledger l) => l.orders));
    final Map<String, Position> positions = positionsFrom(orders);
    final List<Position> list = positions.values.toList()
      ..sort((Position a, Position b) => a.symbol.compareTo(b.symbol));
    return List<Position>.unmodifiable(list);
  },
);

/// The active sort order for the Holdings screen. Not persisted — the default
/// is meaningful (P&L desc, per the PRD) and preserving a hidden preference
/// across launches would surprise more than it helps.
class HoldingsSortNotifier extends Notifier<HoldingsSort> {
  @override
  HoldingsSort build() => HoldingsSort.pnl;

  void set(HoldingsSort sort) => state = sort;
}

final NotifierProvider<HoldingsSortNotifier, HoldingsSort>
    holdingsSortProvider =
    NotifierProvider<HoldingsSortNotifier, HoldingsSort>(
  HoldingsSortNotifier.new,
);

/// Positions in display order, keyed by sort selection and the current snapshot.
///
/// Watches `snapshotProvider` because the sort-by-P&L and sort-by-value cases
/// both change with price ticks. The Provider re-runs on each snapshot, but
/// the aggregate summary and per-row leaves depend on separate providers, so
/// only this ordering slice pays the tick cost — the rows themselves don't
/// rebuild.
final Provider<List<Position>> sortedHoldingsProvider =
    Provider<List<Position>>(
  (Ref ref) {
    final List<Position> positions = ref.watch(holdingsProvider);
    final HoldingsSort sort = ref.watch(holdingsSortProvider);

    if (positions.isEmpty) return positions;

    switch (sort) {
      case HoldingsSort.symbol:
        // holdingsProvider already returns a symbol-sorted list.
        return positions;
      case HoldingsSort.pnl:
      case HoldingsSort.value:
        // Read prices from the current snapshot so the ordering stays
        // consistent within one frame with the aggregate and the rows.
        final Map<String, Quote>? quotes =
            ref.watch(snapshotProvider).value?.quotes;
        Money valueOf(Position p) =>
            quotes?[p.symbol]?.ltp.let((Money ltp) => p.currentValue(ltp)) ??
                p.totalCost;
        Money pnlOf(Position p) =>
            quotes?[p.symbol]?.ltp.let((Money ltp) => p.unrealisedPnl(ltp)) ??
                Money.zero;

        final List<Position> sorted = <Position>[...positions];
        if (sort == HoldingsSort.pnl) {
          sorted.sort((Position a, Position b) => pnlOf(b).compareTo(pnlOf(a)));
        } else {
          sorted
              .sort((Position a, Position b) => valueOf(b).compareTo(valueOf(a)));
        }
        return List<Position>.unmodifiable(sorted);
    }
  },
);

/// The one position for a symbol, or `null` when nothing is held.
///
/// Rows watch this rather than the full list so that opening one position
/// through the ticket cannot rebuild every other row.
final ProviderFamily<Position?, String> positionProvider =
    Provider.family<Position?, String>((Ref ref, String symbol) {
  for (final Position p in ref.watch(holdingsProvider)) {
    if (p.symbol == symbol) return p;
  }
  return null;
});

/// The aggregate summary shown above the list.
///
/// `invested` is exact (sum over stored totals — no rounding). `currentValue`,
/// `pnl`, `pnlPercent` are computed against a single [snapshotProvider]
/// frame, so summary == sum of visible rows at any tick by construction.
class HoldingsAggregate {
  const HoldingsAggregate({
    required this.invested,
    required this.currentValue,
    required this.pnl,
    required this.pnlPercent,
  });

  final Money invested;
  final Money currentValue;
  final Money pnl;

  /// P&L as a percentage of [invested]. `null` when there is nothing invested.
  final Decimal? pnlPercent;
}

final Provider<HoldingsAggregate> holdingsAggregateProvider =
    Provider<HoldingsAggregate>((Ref ref) {
  final List<Position> positions = ref.watch(holdingsProvider);
  final Map<String, Quote>? quotes =
      ref.watch(snapshotProvider).value?.quotes;

  Money invested = Money.zero;
  Money value = Money.zero;
  for (final Position p in positions) {
    invested = invested + p.totalCost;
    final Money? ltp = quotes?[p.symbol]?.ltp;
    // Before the first snapshot, current value falls back to cost — reporting
    // 0 would render a full portfolio as a total loss for one frame.
    value = value + (ltp == null ? p.totalCost : p.currentValue(ltp));
  }
  final Money pnl = value - invested;
  return HoldingsAggregate(
    invested: invested,
    currentValue: value,
    pnl: pnl,
    pnlPercent: pnl.ratioTo(invested),
  );
});

extension _MoneyLet<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
