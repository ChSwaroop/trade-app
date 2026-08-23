import 'package:uuid/uuid.dart';

import '../../core/storage/json_store.dart';
import '../models/watchlist.dart';

/// Persistence for watchlists.
///
/// The repository owns the on-disk shape; nothing above it knows that storage
/// is JSON, or Hive, or versioned. It is deliberately synchronous on read —
/// the document is a few hundred bytes and the box is already open by the time
/// the first screen builds, so making the UI await it would only introduce a
/// loading state that flashes for one frame.
class WatchlistRepository {
  const WatchlistRepository(this._store, [this._uuid = const Uuid()]);

  /// Bump when the persisted shape changes. Documents written under a
  /// different version are discarded, not migrated blindly.
  static const int schemaVersion = 1;

  static const String _key = 'watchlists';
  static const String _listsField = 'lists';

  /// The maximum a user may create. Not a technical limit — it keeps the
  /// picker and the tab bar sane, and it gives create a defined failure mode.
  static const int maxWatchlists = 10;

  /// Matches the design's row cap and keeps a detail screen scannable.
  static const int maxSymbolsPerWatchlist = 50;

  static const int maxNameLength = 24;

  final JsonStore _store;
  final Uuid _uuid;

  String newId() => _uuid.v4();

  /// Loads the persisted watchlists.
  ///
  /// An absent document means a first run, which seeds a starter watchlist so
  /// the feature is not a dead end on launch. An *empty* stored list is
  /// respected — a user who deleted everything must not have the seed
  /// resurrected on the next launch.
  List<Watchlist> load() {
    final Map<String, Object?>? document =
        _store.read(_key, schemaVersion: schemaVersion);
    if (document == null) return <Watchlist>[seedWatchlist()];

    final Object? lists = document[_listsField];
    if (lists is! List<Object?>) return <Watchlist>[seedWatchlist()];

    return lists
        .whereType<Map<String, Object?>>()
        .map(Watchlist.fromJson)
        .nonNulls
        .toList();
  }

  Future<void> save(List<Watchlist> watchlists) {
    return _store.write(
      _key,
      <String, Object?>{
        _listsField: watchlists.map((Watchlist w) => w.toJson()).toList(),
      },
      schemaVersion: schemaVersion,
    );
  }

  /// The first-run watchlist: the five most recognisable names in the
  /// universe, so the detail screen has something live to show immediately.
  Watchlist seedWatchlist() => Watchlist(
        id: _uuid.v4(),
        name: 'My Watchlist',
        symbols: const <String>[
          'RELIANCE',
          'TCS',
          'HDFCBANK',
          'INFY',
          'ICICIBANK',
        ],
      );
}
