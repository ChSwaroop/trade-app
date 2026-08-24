import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../data/models/order.dart';
import '../../data/repositories/order_repository.dart';
import '../../market/market_providers.dart';
import '../../market/price_store.dart';
import '../../market/stock_universe.dart';
import '../watchlists/watchlist_providers.dart' show jsonStoreProvider;

final Provider<OrderRepository> orderRepositoryProvider =
    Provider<OrderRepository>(
  (Ref ref) => OrderRepository(ref.watch(jsonStoreProvider)),
);

/// Why a submit was refused. Returning this rather than throwing keeps every
/// rule inside the notifier where it can be exercised individually, and lets
/// the ticket screen present each case however it wants.
enum OrderFailure {
  unknownSymbol('That stock is not tradable here'),
  invalidQuantity('Enter a quantity greater than zero'),
  quantityTooLarge('Quantity exceeds the maximum per order'),
  priceUnavailable('No live price yet — try again in a moment'),
  insufficientBalance('Not enough balance for this order'),
  insufficientHoldings('You do not hold enough to sell that many');

  const OrderFailure(this.message);

  final String message;
}

/// The trading ledger: every filled order and the current wallet balance.
///
/// Holdings will be derived from [orders] in the next feature, so this state
/// is the single source of truth for both. The balance moves atomically with
/// the order that caused it, in the same write, so a crash between the two
/// cannot leave the ledger inconsistent.
class Ledger {
  const Ledger({required this.orders, required this.balance});

  final List<Order> orders;
  final Money balance;

  Ledger copyWith({List<Order>? orders, Money? balance}) => Ledger(
        orders: orders ?? this.orders,
        balance: balance ?? this.balance,
      );
}

/// Result of a submit attempt. Mirrors the shape used by
/// `WatchlistsNotifier.create` so call sites present failures the same way.
typedef OrderResult = ({OrderFailure? failure, Order? order});

class OrdersNotifier extends Notifier<Ledger> {
  Future<void> _writes = Future<void>.value();

  /// Completes when every write issued so far has landed. Tests await this to
  /// observe the on-disk state without racing the chain.
  Future<void> get settled => _writes;

  @override
  Ledger build() {
    final LoadedLedger loaded = ref.read(orderRepositoryProvider).load();
    return Ledger(orders: loaded.orders, balance: loaded.balance);
  }

  /// Submits a market order. The fill price is read from [PriceStore] here,
  /// not passed in — the ticket screen's rendered price keeps ticking while
  /// the user types, and the order must fill at the price current at the
  /// moment of submission.
  OrderResult submit({
    required String symbol,
    required OrderSide side,
    required int quantity,
  }) {
    if (!StockUniverse.contains(symbol)) {
      return (failure: OrderFailure.unknownSymbol, order: null);
    }
    if (quantity <= 0) {
      return (failure: OrderFailure.invalidQuantity, order: null);
    }
    if (quantity > OrderRepository.maxQuantity) {
      return (failure: OrderFailure.quantityTooLarge, order: null);
    }

    // The synchronous read from the store, as required. Whatever the last
    // painted price was is irrelevant — the store holds the newest tick.
    final Money? price = ref.read(priceStoreProvider).priceOf(symbol);
    if (price == null) {
      return (failure: OrderFailure.priceUnavailable, order: null);
    }

    final Money value = price * quantity;
    Money nextBalance = state.balance;

    switch (side) {
      case OrderSide.buy:
        if (value > state.balance) {
          return (failure: OrderFailure.insufficientBalance, order: null);
        }
        nextBalance = state.balance - value;
      case OrderSide.sell:
        final int held = positionQty(state.orders, symbol);
        if (quantity > held) {
          return (failure: OrderFailure.insufficientHoldings, order: null);
        }
        nextBalance = state.balance + value;
    }

    final Order order = Order(
      id: ref.read(orderRepositoryProvider).newId(),
      symbol: symbol,
      side: side,
      quantity: quantity,
      fillPrice: price,
      timestamp: DateTime.now(),
    );

    _commit(state.copyWith(
      orders: <Order>[...state.orders, order],
      balance: nextBalance,
    ));

    return (failure: null, order: order);
  }

  void _commit(Ledger next) {
    state = next;
    final Ledger toSave = next;
    _writes = _writes.then(
      (_) => ref
          .read(orderRepositoryProvider)
          .save(toSave.orders, toSave.balance),
    );
  }
}

final NotifierProvider<OrdersNotifier, Ledger> ordersProvider =
    NotifierProvider<OrdersNotifier, Ledger>(OrdersNotifier.new);

/// Current wallet balance. Cheaper to watch than the full ledger for the
/// header of the ticket, which does not care about the order list.
final Provider<Money> walletBalanceProvider = Provider<Money>(
  (Ref ref) => ref.watch(ordersProvider.select((Ledger l) => l.balance)),
);

/// Net quantity held for one symbol, derived from the order history.
///
/// Holdings in Feature 4 will build on top of this — the position map is the
/// same aggregation, extended with cost basis. Keeping the derivation here
/// means the sell-side quantity check and the future Holdings screen agree by
/// construction.
final ProviderFamily<int, String> positionQtyProvider =
    Provider.family<int, String>((Ref ref, String symbol) {
  final List<Order> orders =
      ref.watch(ordersProvider.select((Ledger l) => l.orders));
  return positionQty(orders, symbol);
});

/// Signed sum of buys minus sells for [symbol] over [orders]. Pure — used by
/// both the provider above and the sell-side validation, so they can never
/// disagree.
int positionQty(List<Order> orders, String symbol) {
  int qty = 0;
  for (final Order o in orders) {
    if (o.symbol != symbol) continue;
    qty += o.isBuy ? o.quantity : -o.quantity;
  }
  return qty;
}
