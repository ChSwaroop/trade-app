import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_app/core/money/money.dart';
import 'package:trade_app/data/models/price_snapshot.dart';
import 'package:trade_app/data/models/quote.dart';
import 'package:trade_app/market/market_providers.dart';
import 'package:trade_app/market/stock_universe.dart';

/// Proves the core performance claim: a tick for one instrument rebuilds only
/// the widgets bound to that instrument, and leaves every other row untouched.
void main() {
  testWidgets('a tick rebuilds only the affected symbol', (WidgetTester tester) async {
    final _FakeSnapshots feed = _FakeSnapshots();
    final Map<String, int> buildCounts = <String, int>{};

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          snapshotProvider.overrideWith((Ref ref) => feed.stream),
        ],
        child: MaterialApp(
          home: Column(
            children: <Widget>[
              for (final Stock stock in StockUniverse.all)
                _CountingPriceText(
                  symbol: stock.symbol,
                  onBuild: (String s) =>
                      buildCounts[s] = (buildCounts[s] ?? 0) + 1,
                ),
            ],
          ),
        ),
      ),
    );

    feed.emit(<String, int>{});
    await tester.pump();
    await tester.pump();
    buildCounts.clear();

    // Move a single instrument ten times. Two pumps per emission: one to
    // deliver the stream event, one to rebuild on it.
    for (int i = 1; i <= 10; i++) {
      feed.emit(<String, int>{'RELIANCE': 298745 + i});
      await tester.pump();
      await tester.pump();
    }

    expect(buildCounts['RELIANCE'], 10, reason: 'the ticking row must update');
    for (final Stock stock in StockUniverse.all) {
      if (stock.symbol == 'RELIANCE') continue;
      expect(
        buildCounts[stock.symbol] ?? 0,
        0,
        reason: '${stock.symbol} rebuilt on a tick that did not touch it',
      );
    }
  });

  testWidgets('an unchanged republish rebuilds nothing', (WidgetTester tester) async {
    final _FakeSnapshots feed = _FakeSnapshots();
    int builds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          snapshotProvider.overrideWith((Ref ref) => feed.stream),
        ],
        child: MaterialApp(
          home: _CountingPriceText(
            symbol: 'TCS',
            onBuild: (_) => builds++,
          ),
        ),
      ),
    );

    feed.emit(<String, int>{'TCS': 412080});
    await tester.pump();
    await tester.pump();
    builds = 0;

    // Twenty snapshots in which TCS did not move — only other instruments did.
    // Quote equality must absorb every one of them.
    for (int i = 0; i < 20; i++) {
      feed.emit(<String, int>{'INFY': 167525 + i});
      await tester.pump();
      await tester.pump();
    }

    expect(builds, 0);
  });
}

/// Emits snapshots on demand, standing in for the coalescing store.
class _FakeSnapshots {
  final StreamController<PriceSnapshot> _controller =
      StreamController<PriceSnapshot>.broadcast();

  final Map<String, int> _prices = <String, int>{
    for (final Stock s in StockUniverse.all) s.symbol: s.startingPricePaise,
  };
  final Map<String, int> _sequences = <String, int>{};
  int _snapshotSequence = 0;

  Stream<PriceSnapshot> get stream => _controller.stream;

  /// Publishes a snapshot in which only [moved] changed. Symbols absent from
  /// [moved] keep their previous quote object identity-for-value, which is
  /// what lets the selector drop their rebuild.
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
}

/// A leaf bound to one symbol, reporting every rebuild.
class _CountingPriceText extends ConsumerWidget {
  const _CountingPriceText({required this.symbol, required this.onBuild});

  final String symbol;
  final ValueChanged<String> onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Quote? quote = ref.watch(quoteProvider(symbol));
    onBuild(symbol);
    return Text(
      quote?.ltp.toStorageString() ?? '--',
      textDirection: TextDirection.ltr,
    );
  }
}
