import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/data/models/quote.dart';
import 'package:tradedirect/market/market_providers.dart';
import 'package:tradedirect/market/stock_universe.dart';

import '../support/fake_snapshots.dart';

/// Proves the core performance claim: a tick for one instrument rebuilds only
/// the widgets bound to that instrument, and leaves every other row untouched.
void main() {
  testWidgets('a tick rebuilds only the affected symbol', (WidgetTester tester) async {
    final FakeSnapshots feed = FakeSnapshots();
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
    final FakeSnapshots feed = FakeSnapshots();
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
