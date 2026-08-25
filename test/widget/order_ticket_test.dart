import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/core/money/money_format.dart';
import 'package:tradedirect/core/storage/json_store.dart';
import 'package:tradedirect/data/models/order.dart';
import 'package:tradedirect/features/orders/order_ticket_screen.dart';
import 'package:tradedirect/features/orders/orders_providers.dart';
import 'package:tradedirect/features/watchlists/watchlist_providers.dart';
import 'package:tradedirect/market/feed_config.dart';
import 'package:tradedirect/market/market_providers.dart';
import 'package:tradedirect/market/mock_feed_engine.dart';
import 'package:tradedirect/market/price_store.dart';

import '../support/fake_snapshots.dart';

/// Bench for the headline behaviour of this feature: an order fills at the
/// price current in the store when submit is tapped, not at the price the
/// header last painted.
///
/// Two independent surfaces stand in for the live pipeline:
///   * `FakeSnapshots` drives what the UI re-renders.
///   * A `_TestPriceStore` whose `priceOf` can be pinned drives what the
///     notifier reads at submit time.
/// A tick that lands in the store but not yet on screen is exactly the case
/// the requirement is about.
class _TestPriceStore extends PriceStore {
  _TestPriceStore() : super(engine: MockFeedEngine(config: const FeedConfig()));

  final Map<String, Money> pinned = <String, Money>{};

  @override
  Money? priceOf(String symbol) => pinned[symbol] ?? super.priceOf(symbol);
}

void main() {
  const String symbol = 'RELIANCE';

  late FakeSnapshots feed;
  late InMemoryJsonStore store;
  late _TestPriceStore priceStore;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    feed = FakeSnapshots();
    store = InMemoryJsonStore();
    priceStore = _TestPriceStore();
    container = ProviderContainer(
      overrides: <Override>[
        jsonStoreProvider.overrideWithValue(store),
        priceStoreProvider.overrideWithValue(priceStore),
        snapshotProvider.overrideWith((Ref ref) => feed.stream),
      ],
    );
    router = GoRouter(
      initialLocation: '/ticket/$symbol',
      routes: <RouteBase>[
        GoRoute(
          path: '/ticket/:symbol',
          builder: (BuildContext context, GoRouterState state) =>
              OrderTicketScreen(
            symbol: state.pathParameters['symbol']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'confirmed/:orderId',
              builder: (BuildContext context, GoRouterState state) =>
                  const Scaffold(body: Text('CONFIRMED_STUB')),
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    await feed.dispose();
    container.dispose();
  });

  Future<void> pumpTicket(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // Two pumps: one for the router to settle its initial navigation, one
    // for the snapshot stream to deliver its seeded frame.
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    final Finder button = find.text('PLACE BUY ORDER');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'submitting while the price is ticking fills at the price current at '
    'submit, not the price first rendered',
    (WidgetTester tester) async {
      // Painted price: 2,900.00. Store price: 2,900.00.
      final Money rendered = Money.fromPaise(290000);
      priceStore.pinned[symbol] = rendered;
      await pumpTicket(tester);
      feed.emit(<String, int>{symbol: 290000});
      await tester.pump();
      await tester.pump();

      // Confirm the header actually shows the rendered price.
      expect(find.text(MoneyFormat.rupees(rendered)), findsWidgets);

      // A tick lands in the store but is *not* pumped to the UI. This is the
      // scenario the requirement is about: the UI is one tick behind the feed.
      final Money atSubmit = Money.fromPaise(291234);
      priceStore.pinned[symbol] = atSubmit;

      await tapSubmit(tester);

      final List<Order> orders = container.read(ordersProvider).orders;
      expect(orders, hasLength(1));
      expect(
        orders.single.fillPrice,
        atSubmit,
        reason: 'fill must reflect the store at submit, not the rendered LTP',
      );
      // The confirmation shows the executed price the notifier captured.
      expect(find.text('CONFIRMED_STUB'), findsOneWidget);
    },
  );

  testWidgets(
    'the projected order value updates live as ticks arrive',
    (WidgetTester tester) async {
      priceStore.pinned[symbol] = Money.fromPaise(100000);
      await pumpTicket(tester);
      feed.emit(<String, int>{symbol: 100000});
      await tester.pump();
      await tester.pump();

      // Default quantity is 1, so projected value == LTP.
      expect(find.text(MoneyFormat.rupees(Money.fromPaise(100000))),
          findsWidgets);

      feed.emit(<String, int>{symbol: 105000});
      await tester.pump();

      // 105,000 paise = ₹1,050 shown in both header and summary.
      expect(find.text(MoneyFormat.rupees(Money.fromPaise(105000))),
          findsWidgets);
    },
  );

  testWidgets(
    'insufficient balance disables submit and surfaces an inline error',
    (WidgetTester tester) async {
      // Price × qty will exceed the seed balance easily.
      priceStore.pinned[symbol] = Money.fromRupees(1000000);
      await pumpTicket(tester);
      feed.emit(<String, int>{symbol: 100000000});
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Insufficient balance'), findsOneWidget);

      final Finder button = find.text('PLACE BUY ORDER');
      expect(
        tester.widget<FilledButton>(find.ancestor(
          of: button,
          matching: find.byType(FilledButton),
        )).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'a sell for more than the current holding is blocked before submit',
    (WidgetTester tester) async {
      priceStore.pinned[symbol] = Money.fromPaise(200000);
      await pumpTicket(tester);
      feed.emit(<String, int>{symbol: 200000});
      await tester.pump();
      await tester.pump();

      // Switch to sell without ever buying: the holdings check must trip.
      await tester.tap(find.text('SELL'));
      await tester.pump();

      expect(find.textContaining('only hold 0 RELIANCE'), findsOneWidget);
    },
  );
}
