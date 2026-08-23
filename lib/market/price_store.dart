import 'dart:async';

import '../core/money/money.dart';
import '../data/models/price_snapshot.dart';
import '../data/models/quote.dart';
import 'feed_config.dart';
import 'mock_feed_engine.dart';
import 'stock_universe.dart';

/// The single source of price data for the entire app.
///
/// Ticks arrive from [MockFeedEngine] at whatever rate the feed is configured
/// for — potentially hundreds per second. They are absorbed immediately into a
/// mutable working set, but a [PriceSnapshot] is published to the UI at most
/// once per frame interval.
///
/// That decoupling is what makes the stress case tractable. At 100 ticks/sec
/// the store still publishes ~60 times/sec, and no tick is lost: the working
/// set always holds the newest price, so a coalesced publish carries the
/// latest value for every symbol that moved during the window.
class PriceStore {
  PriceStore({
    required this._engine,
    this._publishInterval = _defaultPublishInterval,
  }) {
    _seedFromUniverse();
  }

  /// ~60Hz. Publishing faster than the display refresh cannot produce a
  /// visible update, it only produces wasted rebuilds.
  static const Duration _defaultPublishInterval = Duration(milliseconds: 16);

  final MockFeedEngine _engine;
  final Duration _publishInterval;

  final Map<String, Quote> _working = <String, Quote>{};
  final Map<String, int> _sequences = <String, int>{};

  /// Symbols touched since the last publish. Empty means there is nothing to
  /// publish and the timer tick is skipped entirely.
  final Set<String> _dirty = <String>{};

  StreamSubscription<RawTick>? _tickSubscription;
  Timer? _publishTimer;
  int _snapshotSequence = 0;

  late PriceSnapshot _latest = PriceSnapshot(
    quotes: _working,
    sequence: 0,
    timestamp: DateTime.now(),
  );

  final StreamController<PriceSnapshot> _snapshots =
      StreamController<PriceSnapshot>.broadcast();

  /// Coalesced snapshot stream. Emits at most once per [_publishInterval].
  ///
  /// A new listener receives the current snapshot immediately rather than
  /// waiting for the next publish. That is what makes a screen render live
  /// prices on its first frame, and what makes prices current — not stale —
  /// when the user navigates away and comes back.
  Stream<PriceSnapshot> get snapshots async* {
    yield _latest;
    yield* _snapshots.stream;
  }

  /// The most recently published snapshot. Read synchronously by newly mounted
  /// widgets so a screen never renders empty while waiting for the first tick,
  /// which is also what makes prices current rather than stale when the user
  /// navigates back to a screen.
  PriceSnapshot get latest => _latest;

  /// Live quote for one symbol, read synchronously. This is the price an order
  /// fills at — taken from the store at submit time, not from the rendered UI.
  Quote? quoteFor(String symbol) => _working[symbol];

  /// Live price for one symbol, read synchronously.
  Money? priceOf(String symbol) => _working[symbol]?.ltp;

  bool get isRunning => _publishTimer != null;

  void start() {
    if (_tickSubscription != null) return;
    _tickSubscription = _engine.ticks.listen(_onTick);
    _publishTimer = Timer.periodic(_publishInterval, (_) => _publishIfDirty());
    _engine.start();
  }

  void updateConfig(FeedConfig config) => _engine.updateConfig(config);

  /// Seeds the working set at the opening price for every instrument so the
  /// first frame renders a full market rather than ten blank rows.
  void _seedFromUniverse() {
    for (final Stock stock in StockUniverse.all) {
      _sequences[stock.symbol] = 0;
      _working[stock.symbol] = Quote(
        symbol: stock.symbol,
        ltp: stock.startingPrice,
        previousClose: stock.startingPrice,
        direction: TickDirection.flat,
        sequence: 0,
      );
    }
  }

  /// Absorbs a tick. Deliberately cheap: one map write and one set insert.
  /// No listeners are notified here — notification is the publish timer's job.
  void _onTick(RawTick tick) {
    final Quote? previous = _working[tick.symbol];
    if (previous == null) return;

    final Money price = Money.fromPaise(tick.pricePaise);
    final int sequence = (_sequences[tick.symbol] ?? 0) + 1;
    _sequences[tick.symbol] = sequence;

    _working[tick.symbol] = Quote(
      symbol: tick.symbol,
      ltp: price,
      previousClose: previous.previousClose,
      direction: _directionOf(previous.ltp, price),
      sequence: sequence,
    );
    _dirty.add(tick.symbol);
  }

  static TickDirection _directionOf(Money previous, Money next) {
    if (next > previous) return TickDirection.up;
    if (next < previous) return TickDirection.down;
    return TickDirection.flat;
  }

  void _publishIfDirty() {
    if (_dirty.isEmpty || _snapshots.isClosed) return;
    _dirty.clear();
    _snapshotSequence++;
    _latest = PriceSnapshot(
      quotes: _working,
      sequence: _snapshotSequence,
      timestamp: DateTime.now(),
    );
    _snapshots.add(_latest);
  }

  Future<void> dispose() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    await _tickSubscription?.cancel();
    _tickSubscription = null;
    await _engine.dispose();
    await _snapshots.close();
  }
}
