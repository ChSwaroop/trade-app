import 'package:uuid/uuid.dart';

import '../../core/money/money.dart';
import '../../core/storage/json_store.dart';
import '../models/order.dart';

/// The trading ledger loaded from disk.
///
/// Orders and wallet balance live in one document because they change together
/// — every fill both records an order and moves the balance — so one atomic
/// write per submit keeps them consistent.
class LoadedLedger {
  const LoadedLedger({required this.orders, required this.balance});

  final List<Order> orders;
  final Money balance;
}

/// Persistence for the order history and the wallet balance.
///
/// Same repository shape as `WatchlistRepository`: owns the on-disk form, hands
/// back typed values, and never throws on read. A malformed document is
/// treated as a first run — losing local history is recoverable, failing to
/// launch is not.
class OrderRepository {
  const OrderRepository(this._store, [this._uuid = const Uuid()]);

  /// Bump when the persisted shape changes. Documents written under a
  /// different version are discarded rather than migrated silently.
  static const int schemaVersion = 1;

  static const String _key = 'trading';
  static const String _ordersField = 'orders';
  static const String _balanceField = 'balance';

  /// Seed wallet balance for a first run. Comfortably above the priciest
  /// starting price × any sensible quantity, so a user can actually place an
  /// order without first funding an account.
  static final Money initialBalance = Money.fromRupees(500000);

  /// Maximum quantity a single order may specify. Not a real-world lot limit —
  /// it just gives validation a defined ceiling and stops the +chips from
  /// running away.
  static const int maxQuantity = 100000;

  final JsonStore _store;
  final Uuid _uuid;

  String newId() => _uuid.v4();

  LoadedLedger load() {
    final Map<String, Object?>? document =
        _store.read(_key, schemaVersion: schemaVersion);
    if (document == null) {
      return LoadedLedger(orders: const <Order>[], balance: initialBalance);
    }

    final Object? rawOrders = document[_ordersField];
    final List<Order> orders = rawOrders is List<Object?>
        ? rawOrders
            .whereType<Map<String, Object?>>()
            .map(Order.fromJson)
            .nonNulls
            .toList()
        : const <Order>[];

    final Object? rawBalance = document[_balanceField];
    Money balance = initialBalance;
    if (rawBalance is String) {
      try {
        balance = Money.parse(rawBalance);
      } on FormatException {
        // Fall through to the seed; a corrupt balance is safer to reset than
        // to trust as zero (which would block every buy).
      }
    }

    return LoadedLedger(orders: orders, balance: balance);
  }

  Future<void> save(List<Order> orders, Money balance) {
    return _store.write(
      _key,
      <String, Object?>{
        _ordersField: orders.map((Order o) => o.toJson()).toList(),
        _balanceField: balance.toStorageString(),
      },
      schemaVersion: schemaVersion,
    );
  }
}
