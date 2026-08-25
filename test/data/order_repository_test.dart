import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/core/storage/json_store.dart';
import 'package:tradedirect/data/models/order.dart';
import 'package:tradedirect/data/repositories/order_repository.dart';

void main() {
  late InMemoryJsonStore store;
  late OrderRepository repository;

  setUp(() {
    store = InMemoryJsonStore();
    repository = OrderRepository(store);
  });

  group('OrderRepository', () {
    test('a first run seeds the wallet balance and empty history', () {
      final LoadedLedger loaded = repository.load();

      expect(loaded.orders, isEmpty);
      expect(loaded.balance, OrderRepository.initialBalance);
    });

    test('round-trips orders and balance exactly', () async {
      final DateTime now = DateTime.utc(2026, 8, 24, 10, 32);
      final Order buy = Order(
        id: 'order-1',
        symbol: 'RELIANCE',
        side: OrderSide.buy,
        quantity: 5,
        fillPrice: Money.fromPaise(298745),
        timestamp: now,
      );
      final Order sell = Order(
        id: 'order-2',
        symbol: 'RELIANCE',
        side: OrderSide.sell,
        quantity: 2,
        fillPrice: Money.fromPaise(299999),
        timestamp: now.add(const Duration(minutes: 1)),
      );

      await repository.save(<Order>[buy, sell], Money.fromRupees(493765));

      final LoadedLedger loaded = repository.load();
      expect(loaded.orders, <Order>[buy, sell]);
      expect(loaded.balance, Money.fromRupees(493765));
    });

    test('a schema-version mismatch resets to the seed balance', () {
      // Simulates an app update that changed the persisted shape.
      store.write(
        'trading',
        <String, Object?>{'orders': <Object?>[], 'balance': '1.00'},
        schemaVersion: OrderRepository.schemaVersion + 1,
      );

      final LoadedLedger loaded = repository.load();
      expect(loaded.orders, isEmpty);
      expect(loaded.balance, OrderRepository.initialBalance);
    });

    test('a malformed order in the document does not sink the load', () {
      store.write(
        'trading',
        <String, Object?>{
          'orders': <Object?>[
            <String, Object?>{
              'id': 'ok',
              'symbol': 'ITC',
              'side': 'buy',
              'quantity': 1,
              'fillPrice': '432.75',
              'timestamp': '2026-08-24T10:00:00.000Z',
            },
            <String, Object?>{'id': 'broken'}, // missing fields
            <String, Object?>{
              'id': 'unknown-symbol',
              'symbol': 'DELISTED',
              'side': 'buy',
              'quantity': 1,
              'fillPrice': '10.00',
              'timestamp': '2026-08-24T10:00:00.000Z',
            },
            'garbage',
          ],
          'balance': OrderRepository.initialBalance.toStorageString(),
        },
        schemaVersion: OrderRepository.schemaVersion,
      );

      final LoadedLedger loaded = repository.load();
      expect(loaded.orders, hasLength(1));
      expect(loaded.orders.single.id, 'ok');
    });

    test('a garbled balance is reset rather than trusted as zero', () {
      // A "0" balance would silently block every subsequent buy.
      store.write(
        'trading',
        <String, Object?>{'orders': <Object?>[], 'balance': 'not-a-number'},
        schemaVersion: OrderRepository.schemaVersion,
      );

      expect(repository.load().balance, OrderRepository.initialBalance);
    });

    test('issues unique ids', () {
      expect(repository.newId(), isNot(repository.newId()));
    });
  });
}
