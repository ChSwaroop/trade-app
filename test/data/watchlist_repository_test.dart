import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/storage/json_store.dart';
import 'package:tradedirect/data/models/watchlist.dart';
import 'package:tradedirect/data/repositories/watchlist_repository.dart';

void main() {
  late InMemoryJsonStore store;
  late WatchlistRepository repository;

  setUp(() {
    store = InMemoryJsonStore();
    repository = WatchlistRepository(store);
  });

  group('WatchlistRepository', () {
    test('seeds a starter watchlist on a first run', () {
      final List<Watchlist> loaded = repository.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.symbols, isNotEmpty);
    });

    test('respects an explicitly empty list rather than re-seeding', () async {
      // A user who deleted every watchlist must not find the seed resurrected
      // on the next launch.
      await repository.save(<Watchlist>[]);

      expect(repository.load(), isEmpty);
    });

    test('round-trips name, id, and symbol order', () async {
      final Watchlist original = Watchlist(
        id: 'abc',
        name: 'Banks',
        symbols: const <String>['SBIN', 'HDFCBANK', 'ICICIBANK'],
      );

      await repository.save(<Watchlist>[original]);

      // Order is user-controlled and therefore part of the data, not an
      // incidental detail of the collection.
      expect(repository.load(), <Watchlist>[original]);
      expect(
        repository.load().single.symbols,
        <String>['SBIN', 'HDFCBANK', 'ICICIBANK'],
      );
    });

    test('discards a document written under a different schema version', () {
      // Simulates an app update that changed the persisted shape.
      store.write(
        'watchlists',
        <String, Object?>{'lists': <Object?>[]},
        schemaVersion: WatchlistRepository.schemaVersion + 1,
      );

      // Unreadable state is a first run, not a crash at launch.
      expect(repository.load(), hasLength(1));
    });

    test('survives a structurally wrong document', () {
      store.write(
        'watchlists',
        <String, Object?>{'lists': 'not-a-list'},
        schemaVersion: WatchlistRepository.schemaVersion,
      );

      expect(repository.load(), hasLength(1));
    });

    test('drops entries that are not watchlists and keeps the rest', () {
      store.write(
        'watchlists',
        <String, Object?>{
          'lists': <Object?>[
            <String, Object?>{'id': 'a', 'name': 'Good', 'symbols': <String>['ITC']},
            <String, Object?>{'id': 'b'}, // missing fields
            'garbage',
          ],
        },
        schemaVersion: WatchlistRepository.schemaVersion,
      );

      final List<Watchlist> loaded = repository.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Good');
    });

    test('drops symbols that are no longer in the universe', () {
      store.write(
        'watchlists',
        <String, Object?>{
          'lists': <Object?>[
            <String, Object?>{
              'id': 'a',
              'name': 'Legacy',
              // DELISTED was tradable in an earlier build. It must vanish
              // quietly rather than throw when a row tries to resolve it.
              'symbols': <String>['ITC', 'DELISTED', 'SBIN'],
            },
          ],
        },
        schemaVersion: WatchlistRepository.schemaVersion,
      );

      expect(repository.load().single.symbols, <String>['ITC', 'SBIN']);
    });

    test('issues unique ids', () {
      expect(repository.newId(), isNot(repository.newId()));
    });
  });
}
