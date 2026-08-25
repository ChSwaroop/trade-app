import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/core/money/money_format.dart';
import 'package:tradedirect/core/storage/json_store.dart';
import 'package:tradedirect/data/models/watchlist.dart';
import 'package:tradedirect/data/repositories/watchlist_repository.dart';
import 'package:tradedirect/features/watchlists/watchlist_detail_screen.dart';
import 'package:tradedirect/features/watchlists/watchlist_providers.dart';
import 'package:tradedirect/features/watchlists/widgets/watchlist_row.dart';
import 'package:tradedirect/market/market_providers.dart';

import '../support/fake_snapshots.dart';

/// The requirement this feature turns on: reordering a watchlist while prices
/// are moving must never leave a row showing another instrument's price.
void main() {
  const String listId = 'test-list';
  const List<String> initial = <String>[
    'RELIANCE',
    'TCS',
    'INFY',
    'HDFCBANK',
  ];

  // Deliberately far apart so a misbinding is unmistakable rather than a
  // plausible-looking number.
  const Map<String, int> paise = <String, int>{
    'RELIANCE': 100000,
    'TCS': 200000,
    'INFY': 300000,
    'HDFCBANK': 400000,
  };

  late FakeSnapshots feed;
  late InMemoryJsonStore store;

  setUp(() async {
    feed = FakeSnapshots();
    store = InMemoryJsonStore();
    await WatchlistRepository(store).save(<Watchlist>[
      Watchlist(id: listId, name: 'Test', symbols: initial),
    ]);
  });

  tearDown(() => feed.dispose());

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        jsonStoreProvider.overrideWithValue(store),
        snapshotProvider.overrideWith((Ref ref) => feed.stream),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: WatchlistDetailScreen(watchlistId: listId),
        ),
      ),
    );

    feed.emit(paise);
    await tester.pump();
    await tester.pump();
    return container;
  }

  /// Every rendered row shows the price of the symbol it claims to be.
  void expectPricesMatchSymbols(WidgetTester tester) {
    for (final MapEntry<String, int> entry in paise.entries) {
      final Finder row = find.ancestor(
        of: find.text(MoneyFormat.rupees(Money.fromPaise(entry.value))),
        matching: find.byType(WatchlistRow),
      );
      expect(
        row,
        findsOneWidget,
        reason: 'no single row is showing ${entry.key}\'s price',
      );
      expect(
        tester.widget<WatchlistRow>(row).symbol,
        entry.key,
        reason: '${entry.key}\'s price rendered in the wrong row',
      );
    }
  }

  List<String> renderedOrder(WidgetTester tester) => tester
      .widgetList<WatchlistRow>(find.byType(WatchlistRow))
      .map((WatchlistRow row) => row.symbol)
      .toList();

  testWidgets('rows render their own prices', (WidgetTester tester) async {
    await pumpScreen(tester);

    expect(renderedOrder(tester), initial);
    expectPricesMatchSymbols(tester);
  });

  testWidgets('a reorder moves the price with the symbol',
      (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(tester);

    // Send the first row to the end.
    container.read(watchlistsProvider.notifier).reorder(listId, 0, 3);
    await tester.pump();

    expect(
      renderedOrder(tester),
      <String>['TCS', 'INFY', 'HDFCBANK', 'RELIANCE'],
    );
    expectPricesMatchSymbols(tester);
  });

  testWidgets('reordering repeatedly under a live feed never misbinds a price',
      (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(tester);
    final WatchlistsNotifier notifier =
        container.read(watchlistsProvider.notifier);

    // Interleave moves with ticks, the case where an index-keyed list would
    // hand a row the previous occupant's quote.
    for (int i = 0; i < 12; i++) {
      notifier.reorder(listId, i % 4, (i + 2) % 4);
      feed.emit(<String, int>{
        for (final MapEntry<String, int> e in paise.entries) e.key: e.value,
      });
      await tester.pump();
      await tester.pump();

      expectPricesMatchSymbols(tester);
    }

    // The set is invariant under reordering: nothing lost, nothing duplicated.
    expect(renderedOrder(tester).toSet(), initial.toSet());
  });

  testWidgets('removing a symbol drops exactly one row',
      (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(tester);

    container.read(watchlistsProvider.notifier).removeSymbol(listId, 'INFY');
    await tester.pump();

    expect(renderedOrder(tester), <String>['RELIANCE', 'TCS', 'HDFCBANK']);
    expect(find.text('INFY'), findsNothing);
  });

  testWidgets('deleting the watchlist leaves the screen recoverable',
      (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(tester);

    // The detail route can outlive its watchlist. It must not throw.
    container.read(watchlistsProvider.notifier).delete(listId);
    await tester.pump();

    expect(find.text('This watchlist no longer exists.'), findsOneWidget);
  });
}
