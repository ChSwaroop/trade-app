import 'dart:async';

import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/data/models/price_snapshot.dart';
import 'package:tradedirect/data/models/quote.dart';
import 'package:tradedirect/market/stock_universe.dart';

/// Emits snapshots on demand, standing in for the coalescing store.
///
/// Overriding `snapshotProvider` with this drives the entire UI without
/// starting a feed, so widget tests stay deterministic and leave no pending
/// timers behind.
class FakeSnapshots {
  final StreamController<PriceSnapshot> _controller =
      StreamController<PriceSnapshot>.broadcast();

  final Map<String, int> _prices = <String, int>{
    for (final Stock s in StockUniverse.all) s.symbol: s.startingPricePaise,
  };
  final Map<String, int> _sequences = <String, int>{};
  int _snapshotSequence = 0;

  Stream<PriceSnapshot> get stream => _controller.stream;

  /// Publishes a snapshot in which only [moved] changed. Symbols absent from
  /// [moved] keep an equal quote, which is what lets the selector drop their
  /// rebuild.
  void emit(Map<String, int> moved) {
    moved.forEach((String symbol, int paise) {
      _prices[symbol] = paise;
      _sequences[symbol] = (_sequences[symbol] ?? 0) + 1;
    });

    _snapshotSequence++;
    _controller.add(
      PriceSnapshot(
        quotes: <String, Quote>{
          for (final Stock s in StockUniverse.all)
            s.symbol: Quote(
              symbol: s.symbol,
              ltp: Money.fromPaise(_prices[s.symbol]!),
              previousClose: s.startingPrice,
              direction: TickDirection.up,
              sequence: _sequences[s.symbol] ?? 0,
            ),
        },
        sequence: _snapshotSequence,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> dispose() => _controller.close();
}
