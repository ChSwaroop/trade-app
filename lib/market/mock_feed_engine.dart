import 'dart:async';
import 'dart:math';

import 'feed_config.dart';
import 'stock_universe.dart';

/// A single price print emitted by the engine, in paise.
///
/// The engine works entirely in integer paise. A random walk over integers is
/// exact by construction, so the simulated price can never drift into a value
/// that is unrepresentable as currency. Conversion to [Money] happens once, in
/// the store, when a quote is built.
class RawTick {
  const RawTick({required this.symbol, required this.pricePaise});

  final String symbol;
  final int pricePaise;
}

/// Generates a continuous stream of plausible price prints for the universe.
///
/// One timer drives every instrument. It fires at the aggregate rate and moves
/// a single stock each time, cycling through the universe — so raising the
/// tick rate raises the timer frequency rather than the number of live timers.
class MockFeedEngine {
  MockFeedEngine({
    List<Stock>? stocks,
    Random? random,
    this._config = const FeedConfig(),
  })  : _stocks = stocks ?? StockUniverse.all,
        _random = random ?? Random() {
    for (final Stock stock in _stocks) {
      _pricePaise[stock.symbol] = stock.startingPricePaise;
    }
  }

  final List<Stock> _stocks;
  final Random _random;
  final Map<String, int> _pricePaise = <String, int>{};

  FeedConfig _config;
  Timer? _timer;
  int _cursor = 0;

  /// Whether [start] has been called. Tracked separately from [_timer] because
  /// pausing cancels the timer — without this flag, unpausing would find a
  /// null timer and never resume.
  bool _started = false;

  /// Emits one tick at a time. Broadcast so the store can attach and detach
  /// without tearing down the engine.
  final StreamController<RawTick> _controller = StreamController<RawTick>.broadcast();

  Stream<RawTick> get ticks => _controller.stream;

  bool get isRunning => _timer != null;

  FeedConfig get config => _config;

  /// Current price for a symbol, readable synchronously. The order ticket uses
  /// this at submit time so a fill is priced from the feed itself rather than
  /// from whatever the UI happened to have rendered.
  int? currentPricePaise(String symbol) => _pricePaise[symbol];

  void start() {
    if (_started) return;
    _started = true;
    _scheduleTimer();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Applies a new configuration, restarting the timer at the new interval if
  /// the rate changed. Prices are preserved across a reconfiguration — the
  /// stress toggle must not reset the market.
  void updateConfig(FeedConfig config) {
    final bool rateChanged =
        config.ticksPerSecondPerStock != _config.ticksPerSecondPerStock ||
            config.paused != _config.paused;
    _config = config;
    if (rateChanged && _started) {
      _timer?.cancel();
      _timer = null;
      _scheduleTimer();
    }
  }

  void _scheduleTimer() {
    if (_config.paused) return;
    _timer = Timer.periodic(_config.intervalFor(_stocks.length), (_) => _emitNext());
  }

  /// Moves one instrument and publishes the print.
  void _emitNext() {
    if (_controller.isClosed || _stocks.isEmpty) return;

    final Stock stock = _stocks[_cursor];
    _cursor = (_cursor + 1) % _stocks.length;

    final int current = _pricePaise[stock.symbol]!;
    final int next = _nextPrice(stock, current);
    _pricePaise[stock.symbol] = next;

    _controller.add(RawTick(symbol: stock.symbol, pricePaise: next));
  }

  /// A mean-reverting random walk.
  ///
  /// The step is drawn from the instrument's volatility, then nudged back
  /// toward the opening price in proportion to how far it has strayed. Without
  /// the reversion term a plain walk drifts monotonically over a long session
  /// and every stock ends up absurdly far from its open.
  int _nextPrice(Stock stock, int currentPaise) {
    final double volatility = stock.volatilityBps * _config.volatilityMultiplier;

    // Symmetric step in basis points of the current price.
    final double shockBps = (_random.nextDouble() * 2 - 1) * volatility;

    // Pull toward the open, strengthening with distance. At 5% away from the
    // open this contributes about 1bp per tick against the drift.
    final int openPaise = stock.startingPricePaise;
    final double distanceBps = (openPaise - currentPaise) / openPaise * 10000;
    final double reversionBps = distanceBps * _reversionStrength;

    final double deltaPaise = currentPaise * (shockBps + reversionBps) / 10000;

    // Round away from zero so a sub-paise move still produces a visible tick
    // rather than silently flattening the feed on low-priced instruments.
    final int delta = deltaPaise.abs() < 1
        ? (deltaPaise.isNegative ? -1 : 1)
        : deltaPaise.round();

    final int next = currentPaise + delta;

    // A price can never go non-positive. Clamping at one paise keeps the
    // percentage arithmetic well-defined in the pathological case.
    return next < 1 ? 1 : next;
  }

  static const double _reversionStrength = 0.02;

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
