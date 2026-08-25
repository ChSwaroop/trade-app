import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/storage/json_store.dart';
import 'package:tradedirect/data/models/watchlist.dart';
import 'package:tradedirect/data/repositories/watchlist_repository.dart';
import 'package:tradedirect/features/watchlists/watchlist_providers.dart';

void main() {
  late InMemoryJsonStore store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryJsonStore();
    container = ProviderContainer(
      overrides: <Override>[jsonStoreProvider.overrideWithValue(store)],
    );
  });

  tearDown(() => container.dispose());

  WatchlistsNotifier notifier() => container.read(watchlistsProvider.notifier);
  List<Watchlist> state() => container.read(watchlistsProvider);
  Watchlist first() => state().first;

  group('naming', () {
    test('rejects an empty or whitespace-only name', () {
      expect(notifier().create('   ').failure, WatchlistFailure.emptyName);
      expect(state(), hasLength(1));
    });

    test('trims surrounding whitespace', () {
      notifier().create('  Banks  ');
      expect(state().last.name, 'Banks');
    });

    test('rejects a duplicate name regardless of case', () {
      notifier().create('Banks');
      expect(notifier().create('banks').failure, WatchlistFailure.duplicateName);
    });

    test('allows a rename that keeps the same name', () {
      // The uniqueness check must exclude the watchlist being renamed, or
      // confirming an unchanged name would fail.
      expect(notifier().rename(first().id, first().name), isNull);
    });

    test('rejects a name beyond the length limit', () {
      final String tooLong = 'x' * (WatchlistRepository.maxNameLength + 1);
      expect(notifier().create(tooLong).failure, WatchlistFailure.nameTooLong);
    });

    test('caps the number of watchlists', () {
      for (int i = state().length; i < WatchlistRepository.maxWatchlists; i++) {
        expect(notifier().create('List $i').failure, isNull);
      }
      expect(
        notifier().create('One too many').failure,
        WatchlistFailure.tooManyWatchlists,
      );
    });
  });

  group('symbols', () {
    test('adds to the end and refuses unknown instruments', () {
      final String id = first().id;
      expect(notifier().addSymbol(id, 'ITC'), isNull);
      expect(first().symbols.last, 'ITC');
      expect(
        notifier().addSymbol(id, 'NOTLISTED'),
        WatchlistFailure.unknownSymbol,
      );
    });

    test('adding a symbol twice is a no-op, not an error', () {
      final String id = first().id;
      final int before = first().length;

      expect(notifier().addSymbol(id, 'ITC'), isNull);
      expect(notifier().addSymbol(id, 'ITC'), isNull);

      expect(first().length, before + 1);
    });

    test('removes a symbol and leaves the order of the rest intact', () {
      final String id = first().id;
      final List<String> before = first().symbols;

      notifier().removeSymbol(id, before[1]);

      expect(
        first().symbols,
        <String>[...before]..removeAt(1),
      );
    });

    test('reorder moves one symbol and preserves every other position', () {
      final String id = first().id;
      final List<String> before = first().symbols;

      // Move the first item to the third slot.
      notifier().reorder(id, 0, 2);

      expect(first().symbols, <String>[before[1], before[2], before[0], ...before.sublist(3)]);
      expect(first().symbols.toSet(), before.toSet());
    });

    test('reorder ignores an out-of-range index', () {
      final String id = first().id;
      final List<String> before = first().symbols;

      expect(notifier().reorder(id, 99, 0), isNull);

      expect(first().symbols, before);
    });

    test('undo restores a removed symbol to its original position', () {
      final String id = first().id;
      final List<String> before = first().symbols;
      const int index = 2;
      final String removed = before[index];

      notifier().removeSymbol(id, removed);
      notifier().insertSymbolAt(id, removed, index);

      // Restoring membership but not position would silently reshuffle the
      // list the user was looking at.
      expect(first().symbols, before);
    });
  });

  group('lifecycle', () {
    test('delete removes only the named watchlist', () {
      notifier().create('Banks');
      final String id = state().last.id;

      expect(notifier().delete(id), isNull);

      expect(state().where((Watchlist w) => w.id == id), isEmpty);
      expect(state(), hasLength(1));
    });

    test('mutating a deleted watchlist reports notFound, never throws', () {
      final String id = first().id;
      notifier().delete(id);

      expect(notifier().addSymbol(id, 'ITC'), WatchlistFailure.notFound);
      expect(notifier().rename(id, 'Gone'), WatchlistFailure.notFound);
      expect(notifier().delete(id), WatchlistFailure.notFound);
    });
  });

  group('persistence', () {
    test('every mutation is written through and survives a restart', () async {
      notifier().create('Banks');
      final String id = state().last.id;
      notifier().addSymbol(id, 'SBIN');
      notifier().addSymbol(id, 'AXISBANK');
      notifier().reorder(id, 0, 1);
      await notifier().settled;

      // A fresh container over the same store is what a relaunch looks like.
      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(watchlistsProvider), state());
      expect(
        restarted.read(watchlistsProvider).last.symbols,
        <String>['AXISBANK', 'SBIN'],
      );
    });

    test('writes land in order even when issued back to back', () async {
      final String id = first().id;
      notifier().addSymbol(id, 'ITC');
      notifier().addSymbol(id, 'LT');
      notifier().removeSymbol(id, 'ITC');
      await notifier().settled;

      final ProviderContainer restarted = ProviderContainer(
        overrides: <Override>[jsonStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restarted.dispose);

      final Watchlist persisted = restarted.read(watchlistsProvider).first;
      expect(persisted.contains('ITC'), isFalse);
      expect(persisted.contains('LT'), isTrue);
    });
  });
}
