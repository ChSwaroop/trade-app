import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trade_app/core/money/money.dart';
import 'package:trade_app/core/money/money_format.dart';
import 'package:trade_app/core/storage/json_store.dart';
import 'package:trade_app/data/models/order.dart';
import 'package:trade_app/data/repositories/order_repository.dart';
import 'package:trade_app/features/holdings/holdings_providers.dart';
import 'package:trade_app/features/holdings/holdings_screen.dart';
import 'package:trade_app/features/holdings/widgets/holding_row.dart';
import 'package:trade_app/features/watchlists/watchlist_providers.dart';
import 'package:trade_app/market/market_providers.dart';

import '../support/fake_snapshots.dart';

/// Bench for the two properties that make Holdings correct under load:
///   1. **Summary equals the sum of visible rows at any moment.** The
///      aggregate and every row's P&L both read from the same
///      `snapshotProvider` frame, so they cannot disagree — even mid-tick.
///   2. **Sort by P&L reorders live.** A row that crosses from loss into gain
///      has to move without dropping its own price binding.
void main() {
  late FakeSnapshots feed;
  late InMemoryJsonStore store;

  Future<void> seed(List<Order> orders) async {
    await OrderRepository(store).save(orders, OrderRepository.initialBalance);
  }

  setUp(() {
    feed = FakeSnapshots();
    store = InMemoryJsonStore();
  });

  tearDown(() async {
    await feed.dispose();
  });

  Future<ProviderContainer> pumpHoldings(WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        jsonStoreProvider.overrideWithValue(store),
        snapshotProvider.overrideWith((Ref ref) => feed.stream),
      ],
    );
    addTearDown(container.dispose);

    final GoRouter router = GoRouter(
      initialLocation: '/holdings',
      routes: <RouteBase>[
        GoRoute(
          path: '/holdings',
          builder: (BuildContext context, GoRouterState state) =>
              const HoldingsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  Order buy(String sym, int qty, int paise, {int s = 0}) => Order(
        id: 'buy-$sym-$s',
        symbol: sym,
        side: OrderSide.buy,
        quantity: qty,
        fillPrice: Money.fromPaise(paise),
        timestamp: DateTime.utc(2026, 8, 24).add(Duration(seconds: s)),
      );

  testWidgets('empty state renders when no orders exist',
      (WidgetTester tester) async {
    await pumpHoldings(tester);

    expect(find.text('No holdings yet'), findsOneWidget);
    expect(find.byType(HoldingRow), findsNothing);
  });

  testWidgets('aggregate P&L equals the sum of every row at every tick',
      (WidgetTester tester) async {
    await seed(<Order>[
      buy('RELIANCE', 10, 200000, s: 0), // cost 20,000
      buy('TCS', 5, 400000, s: 1), // cost 20,000
      buy('HDFCBANK', 20, 150000, s: 2), // cost 30,000
    ]);

    final ProviderContainer container = await pumpHoldings(tester);

    // A sequence of unrelated snapshots, each moving one symbol.
    final List<Map<String, int>> ticks = <Map<String, int>>[
      <String, int>{'RELIANCE': 250000},
      <String, int>{'TCS': 380000},
      <String, int>{'HDFCBANK': 160000},
      <String, int>{'RELIANCE': 210000, 'TCS': 420000},
    ];

    for (final Map<String, int> tick in ticks) {
      feed.emit(tick);
      await tester.pump();
      await tester.pump();

      final HoldingsAggregate agg =
          container.read(holdingsAggregateProvider);
      final List<HoldingRow> rows = tester
          .widgetList<HoldingRow>(find.byType(HoldingRow))
          .toList();
      expect(rows, hasLength(3));

      // Re-derive the summary from the same snapshot the rows saw. If the
      // aggregate ever lags a frame behind, this equality breaks.
      Money summed = Money.zero;
      for (final HoldingRow row in rows) {
        final Money ltp = container
            .read(quoteProvider(row.position.symbol))!
            .ltp;
        summed = summed + row.position.unrealisedPnl(ltp);
      }
      expect(agg.pnl, summed,
          reason: 'aggregate P&L must equal the sum of visible rows');
    }
  });

  testWidgets('sort by P&L updates as prices move a row from loss to gain',
      (WidgetTester tester) async {
    await seed(<Order>[
      buy('RELIANCE', 1, 200000, s: 0),
      buy('TCS', 1, 400000, s: 1),
      buy('HDFCBANK', 1, 150000, s: 2),
    ]);

    await pumpHoldings(tester);

    // First snapshot: all at cost. Tie-broken by comparison order — we don't
    // care about the exact order, just that a swap reorders correctly next.
    feed.emit(<String, int>{
      'RELIANCE': 210000, // cost 2000 → value 2100, P&L +100
      'TCS': 380000, //     cost 4000 → value 3800, P&L −200
      'HDFCBANK': 155000, //  cost 1500 → value 1550, P&L  +50
    });
    await tester.pump();
    await tester.pump();

    List<String> renderedOrder() => tester
        .widgetList<HoldingRow>(find.byType(HoldingRow))
        .map((HoldingRow r) => r.position.symbol)
        .toList();

    // Default sort is P&L descending: RELIANCE (+1000), HDFCBANK (+500), TCS (-2000).
    expect(renderedOrder(), <String>['RELIANCE', 'HDFCBANK', 'TCS']);

    // Now TCS rockets past and RELIANCE dips into loss.
    feed.emit(<String, int>{
      'RELIANCE': 199000, //   cost 2000 → value 1990, P&L −10
      'TCS': 450000, //       cost 4000 → value 4500, P&L +500
      'HDFCBANK': 152000, //    cost 1500 → value 1520, P&L +20
    });
    await tester.pump();
    await tester.pump();

    expect(renderedOrder(), <String>['TCS', 'HDFCBANK', 'RELIANCE']);

    // Each row still shows its own current value — no misbinding across the
    // reorder. RELIANCE's current value is 1 × 1,990.00.
    final HoldingRow reliance = tester
        .widgetList<HoldingRow>(find.byType(HoldingRow))
        .firstWhere((HoldingRow r) => r.position.symbol == 'RELIANCE');
    expect(reliance.position.quantity, 1);
    expect(
      find.descendant(
        of: find.byWidget(reliance),
        matching: find.text(MoneyFormat.rupees(Money.fromPaise(199000))),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a full-close order removes the position from the list',
      (WidgetTester tester) async {
    await seed(<Order>[
      buy('ITC', 5, 43275, s: 0),
      Order(
        id: 'close',
        symbol: 'ITC',
        side: OrderSide.sell,
        quantity: 5,
        fillPrice: Money.fromPaise(45000),
        timestamp: DateTime.utc(2026, 8, 24, 0, 0, 10),
      ),
    ]);

    await pumpHoldings(tester);
    feed.emit(<String, int>{'ITC': 45000});
    await tester.pump();
    await tester.pump();

    expect(find.byType(HoldingRow), findsNothing);
    expect(find.text('No holdings yet'), findsOneWidget);
  });
}
