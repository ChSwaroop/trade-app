import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/json_store.dart';
import '../../data/models/watchlist.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../../market/stock_universe.dart';

/// Overridden in `main` with the Hive-backed store once the box is open.
/// Defaulting to the in-memory store means tests — and a device where Hive
/// failed to initialise — get a working app that simply forgets on restart.
final Provider<JsonStore> jsonStoreProvider = Provider<JsonStore>(
  (Ref ref) => InMemoryJsonStore(),
);

final Provider<WatchlistRepository> watchlistRepositoryProvider =
    Provider<WatchlistRepository>(
  (Ref ref) => WatchlistRepository(ref.watch(jsonStoreProvider)),
);

/// Why a mutation was refused. Returning this instead of throwing keeps the
/// rules in one testable place and lets the UI decide how to present them.
enum WatchlistFailure {
  emptyName('Name cannot be empty'),
  nameTooLong('Name is too long'),
  duplicateName('A watchlist with that name already exists'),
  tooManyWatchlists('You can keep up to '
      '${WatchlistRepository.maxWatchlists} watchlists'),
  watchlistFull('A watchlist holds up to '
      '${WatchlistRepository.maxSymbolsPerWatchlist} stocks'),
  unknownSymbol('That stock is not tradable here'),
  notFound('That watchlist no longer exists');

  const WatchlistFailure(this.message);

  final String message;
}

/// The full set of watchlists, in user-defined order.
///
/// State is the single source of truth and is written through to storage after
/// every mutation. Persistence never blocks the UI: the state is updated
/// synchronously and the write is chained onto [settled], which tests await
/// instead of guessing at timing.
class WatchlistsNotifier extends Notifier<List<Watchlist>> {
  Future<void> _writes = Future<void>.value();

  /// Completes when every write issued so far has landed.
  Future<void> get settled => _writes;

  @override
  List<Watchlist> build() => ref.read(watchlistRepositoryProvider).load();

  ({WatchlistFailure? failure, String? id}) create(String rawName) {
    final String name = rawName.trim();
    final WatchlistFailure? invalid = _validateName(name);
    if (invalid != null) return (failure: invalid, id: null);
    if (state.length >= WatchlistRepository.maxWatchlists) {
      return (failure: WatchlistFailure.tooManyWatchlists, id: null);
    }

    final String id = ref.read(watchlistRepositoryProvider).newId();
    _commit(<Watchlist>[
      ...state,
      Watchlist(id: id, name: name, symbols: const <String>[]),
    ]);
    return (failure: null, id: id);
  }

  WatchlistFailure? rename(String id, String rawName) {
    final String name = rawName.trim();
    final WatchlistFailure? invalid = _validateName(name, excludingId: id);
    if (invalid != null) return invalid;
    return _update(id, (Watchlist w) => w.copyWith(name: name));
  }

  WatchlistFailure? delete(String id) {
    final List<Watchlist> next =
        state.where((Watchlist w) => w.id != id).toList();
    if (next.length == state.length) return WatchlistFailure.notFound;
    _commit(next);
    return null;
  }

  WatchlistFailure? addSymbol(String id, String symbol) {
    if (!StockUniverse.contains(symbol)) return WatchlistFailure.unknownSymbol;
    return _update(id, (Watchlist w) {
      // Adding a symbol already present is a no-op rather than a failure —
      // the picker toggles, and a double tap should not raise an error.
      if (w.contains(symbol)) return w;
      if (w.length >= WatchlistRepository.maxSymbolsPerWatchlist) return null;
      return w.copyWith(symbols: <String>[...w.symbols, symbol]);
    }, onRejected: WatchlistFailure.watchlistFull);
  }

  WatchlistFailure? removeSymbol(String id, String symbol) {
    return _update(
      id,
      (Watchlist w) => w.copyWith(
        symbols: w.symbols.where((String s) => s != symbol).toList(),
      ),
    );
  }

  /// Moves the symbol at [oldIndex] to [newIndex], where [newIndex] is the
  /// destination *after* the item has been lifted out — the convention of
  /// `ReorderableListView.onReorderItem`.
  WatchlistFailure? reorder(String id, int oldIndex, int newIndex) {
    return _update(id, (Watchlist w) {
      if (oldIndex < 0 || oldIndex >= w.length) return w;
      final List<String> symbols = <String>[...w.symbols];
      final String moved = symbols.removeAt(oldIndex);
      symbols.insert(newIndex.clamp(0, symbols.length), moved);
      return w.copyWith(symbols: symbols);
    });
  }

  /// Re-inserts [symbol] at [index]. Backs undo after a swipe-to-remove, which
  /// must restore position and not just membership.
  WatchlistFailure? insertSymbolAt(String id, String symbol, int index) {
    if (!StockUniverse.contains(symbol)) return WatchlistFailure.unknownSymbol;
    return _update(id, (Watchlist w) {
      if (w.contains(symbol)) return w;
      final List<String> symbols = <String>[...w.symbols];
      symbols.insert(index.clamp(0, symbols.length), symbol);
      return w.copyWith(symbols: symbols);
    });
  }

  WatchlistFailure? _validateName(String name, {String? excludingId}) {
    if (name.isEmpty) return WatchlistFailure.emptyName;
    if (name.length > WatchlistRepository.maxNameLength) {
      return WatchlistFailure.nameTooLong;
    }
    final bool clashes = state.any(
      (Watchlist w) =>
          w.id != excludingId &&
          w.name.toLowerCase() == name.toLowerCase(),
    );
    return clashes ? WatchlistFailure.duplicateName : null;
  }

  /// Applies [change] to one watchlist. A `null` return from [change] means
  /// the change was refused and [onRejected] is reported.
  WatchlistFailure? _update(
    String id,
    Watchlist? Function(Watchlist) change, {
    WatchlistFailure? onRejected,
  }) {
    final int index = state.indexWhere((Watchlist w) => w.id == id);
    if (index < 0) return WatchlistFailure.notFound;

    final Watchlist? updated = change(state[index]);
    if (updated == null) return onRejected ?? WatchlistFailure.notFound;
    if (updated == state[index]) return null;

    _commit(<Watchlist>[...state]..[index] = updated);
    return null;
  }

  void _commit(List<Watchlist> next) {
    state = List<Watchlist>.unmodifiable(next);
    final List<Watchlist> toSave = state;
    _writes = _writes
        .then((_) => ref.read(watchlistRepositoryProvider).save(toSave));
  }
}

final NotifierProvider<WatchlistsNotifier, List<Watchlist>> watchlistsProvider =
    NotifierProvider<WatchlistsNotifier, List<Watchlist>>(
  WatchlistsNotifier.new,
);

/// One watchlist by id, or `null` if it has been deleted.
///
/// Detail screens watch this rather than the whole collection, so editing a
/// different watchlist does not rebuild them. It also gives the detail route a
/// defined behaviour when its watchlist is deleted from under it.
final ProviderFamily<Watchlist?, String> watchlistByIdProvider =
    Provider.family<Watchlist?, String>((Ref ref, String id) {
  final List<Watchlist> all = ref.watch(watchlistsProvider);
  for (final Watchlist watchlist in all) {
    if (watchlist.id == id) return watchlist;
  }
  return null;
});

/// The symbols in one watchlist.
///
/// Separate from [watchlistByIdProvider] so that renaming a watchlist does not
/// rebuild its list of rows.
final ProviderFamily<List<String>, String> watchlistSymbolsProvider =
    Provider.family<List<String>, String>((Ref ref, String id) {
  return ref.watch(watchlistByIdProvider(id))?.symbols ?? const <String>[];
});
