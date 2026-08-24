import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trade_app/core/money/money.dart';
import 'package:trade_app/core/storage/json_store.dart';
import 'package:trade_app/data/models/order.dart';
import 'package:trade_app/data/repositories/order_repository.dart';
import 'package:trade_app/features/orders/orders_providers.dart';
import 'package:trade_app/features/watchlists/watchlist_providers.dart';
import 'package:trade_app/market/feed_config.dart';
import 'package:trade_app/market/market_providers.dart';
import 'package:trade_app/market/mock_feed_engine.dart';
import 'package:trade_app/market/price_store.dart';

/// A [PriceStore] whose engine never starts, and whose [priceOf] can be
/// pinned per symbol. Extending rather than mocking keeps the seeded working
/// set from the universe available as the fallback.
class _TestPriceStore extends PriceStore {
  _TestPriceStore() : super(engine: MockFeedEngine(config: const FeedConfig()));

  final Map<String, Money?> overrides = <String, Money?>{};

  @override
  Money? priceOf(String symbol) {
    if (overrides.containsKey(symbol)) return overrides[symbol];
    return super.priceOf(symbol);
  }
}

void main() {
  late InMemoryJsonStore store;
  late _TestPriceStore priceStore;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryJsonStore();
    priceStore = _TestPriceStore();
    container = ProviderContainer(
      overrides: <Override>[
        jsonStoreProvider.overrideWithValue(store),
        priceStoreProvider.overrideWithValue(priceStore),
      ],
    );
  });

  tearDown(() => container.dispose());

  OrdersNotifier notifier() => container.read(ordersProvider.notifier);
  Ledger ledger() => container.read(ordersProvider);

  group('validation', () {
    test('a first run starts with the seed balance and no orders', () {
      expect(ledger().orders, isEmpty);
      expect(ledger().balance, OrderRepository.initialBalance);
    });

    test('refuses a quantity of zero or less', () {
      final OrderResult result = notifier().submit(
        symbol: 'RELIANCE',
        side: OrderSide.buy,
        quantity: 0,
      );

      expect(result.failure, OrderFailure.invalidQuantity);
      expect(result.order, isNull);
      expect(ledger().orders, isEmpty);
      expect(ledger().balance, OrderRepository.initialBalance);
    });

    test('refuses a quantity above the per-order cap', () {
      final OrderResult result = notifier().submit(
        symbol: 'ITC',
        side: OrderSide.buy,
        quantity: OrderRepository.maxQuantity + 1,
      );

      expect(result.failure, OrderFailure.quantityTooLarge);
    });

    test('refuses a symbol outside the universe', () {
      final OrderResult result = notifier().submit(
        symbol: 'DELISTED',
        side: OrderSide.buy,
        quantity: 1,
      );

      expect(result.failure, OrderFailure.unknownSymbol);
    });

    test('refuses a submit when the feed has no price yet', () {
      priceStore.overrides['RELIANCE'] = null;

      final OrderResult result = notifier().submit(
        symbol: 'RELIANCE',
        side: OrderSide.buy,
        quantity: 1,
      );

      // Must not crash — the feed can be behind on first launch.
      expect(result.failure, OrderFailure.priceUnavailable);
    });

    test('refuses a buy that exceeds available balance', () {
      // Peg the price so that qty × price cleanly exceeds the initial balance.
      priceStore.overrides['RELIANCE'] = Money.fromRupees(1000);

      final OrderResult result = notifier().submit(
        symbol: 'RELIANCE',
        side: OrderSide.buy,
        quantity: OrderRepository.initialBalance.value.toBigInt().toInt() ~/
                1000 +
            1,
      );

      expect(result.failure, OrderFailure.insufficientBalance);
      expect(ledger().balance, OrderRepository.initialBalance);
    });

    test('refuses a sell for more than the current holding', () {
      final OrderResult result = notifier().submit(
        symbol: 'RELIANCE',
        side: OrderSide.sell,
        quantity: 1,
      );

      expect(result.failure, OrderFailure.insufficientHoldings);
    });
  });

  group('fills', () {
    test('a buy debits the wallet by exactly quantity × fill price', () {
      priceStore.overrides['ITC'] = Money.fromPaise(43275);

      final OrderResult result = notifier().submit(
        symbol: 'ITC',
        side: OrderSide.buy,
        quantity: 10,
      );

      expect(result.failure, isNull);
      expect(result.order!.fillPrice, Money.fromPaise(43275));
      expect(result.order!.value, Money.fromPaise(432750));
      expect(
        ledger().balance,
        OrderRepository.initialBalance - Money.fromPaise(432750),
      );
    });

    test('a sell after a buy leaves the net position matching the difference',
        () {
      priceStore.overrides['SBIN'] = Money.fromPaise(76530);

      notifier().submit(
        symbol: 'SBIN',
        side: OrderSide.buy,
        quantity: 20,
      );
      priceStore.overrides['SBIN'] = Money.fromPaise(78000);
      final OrderResult sold = notifier().submit(
        symbol: 'SBIN',
        side: OrderSide.sell,
        quantity: 8,
      );

      expect(sold.failure, isNull);
      // Sell price is the new tick, not the buy price.
      expect(sold.order!.fillPrice, Money.fromPaise(78000));
      expect(container.read(positionQtyProvider('SBIN')), 12);
    });

    test('the fill uses the price current at submit, not any earlier read', () {
      priceStore.overrides['LT'] = Money.fromPaise(350000);
      // A quick pre-check the ticket might do before the user hits submit.
      expect(priceStore.priceOf('LT'), Money.fromPaise(350000));

      // Ticks arrive between the pre-check and the submit.
      priceStore.overrides['LT'] = Money.fromPaise(356790);

      final OrderResult result = notifier().submit(
        symbol: 'LT',
        side: OrderSide.buy,
        quantity: 1,
      );

      expect(result.order!.fillPrice, Money.fromPaise(356790));
    });
  });

  group('persistence', () {
    test('writes land in order and survive a simulated relaunch', () async {
      priceStore.overrides['ITC'] = Money.fromPaise(43275);
      priceStore.overrides['INFY'] = Money.fromPaise(167525);

      notifier().submit(
        symbol: 'ITC',
        side: OrderSide.buy,
        quantity: 4,
      );
      notifier().submit(
        symbol: 'INFY',
        side: OrderSide.buy,
        quantity: 2,
      );
      await notifier().settled;

      // A fresh container over the same store is what a relaunch looks like.
      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[
          jsonStoreProvider.overrideWithValue(store),
          priceStoreProvider.overrideWithValue(_TestPriceStore()),
        ],
      );
      addTearDown(restarted.dispose);

      final Ledger persisted = restarted.read(ordersProvider);
      expect(persisted.orders, hasLength(2));
      expect(persisted.orders.map((Order o) => o.symbol), <String>[
        'ITC',
        'INFY',
      ]);
      expect(persisted.balance, ledger().balance);
    });

    test('back-to-back writes are chained rather than racing', () async {
      priceStore.overrides['ITC'] = Money.fromPaise(43275);

      notifier().submit(symbol: 'ITC', side: OrderSide.buy, quantity: 1);
      notifier().submit(symbol: 'ITC', side: OrderSide.buy, quantity: 1);
      notifier().submit(symbol: 'ITC', side: OrderSide.buy, quantity: 1);
      await notifier().settled;

      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[
          jsonStoreProvider.overrideWithValue(store),
          priceStoreProvider.overrideWithValue(_TestPriceStore()),
        ],
      );
      addTearDown(restarted.dispose);

      // The last write wins, and it carries every order — so nothing dropped.
      expect(restarted.read(ordersProvider).orders, hasLength(3));
    });

    test('each fill has a unique id', () {
      priceStore.overrides['ITC'] = Money.fromPaise(43275);

      notifier().submit(symbol: 'ITC', side: OrderSide.buy, quantity: 1);
      notifier().submit(symbol: 'ITC', side: OrderSide.buy, quantity: 1);

      final List<Order> orders = ledger().orders;
      expect(orders, hasLength(2));
      expect(orders[0].id, isNot(orders[1].id));
    });
  });
}
