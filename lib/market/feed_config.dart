/// Tuning for the mock market-data feed.
///
/// Exposed through a debug sheet so the stress scenario (50+ ticks/sec across
/// the universe) can be exercised at runtime without a rebuild.
class FeedConfig {
  const FeedConfig({
    this.ticksPerSecondPerStock = defaultTicksPerSecondPerStock,
    this.volatilityMultiplier = 1.0,
    this.paused = false,
  });

  /// A realistic resting rate: roughly two prints per second per instrument,
  /// or ~20 ticks/sec across the ten stocks.
  static const int defaultTicksPerSecondPerStock = 2;

  static const int minTicksPerSecondPerStock = 1;
  static const int maxTicksPerSecondPerStock = 20;

  /// The rate the stress toggle jumps to: 10/sec/stock = 100 ticks/sec overall,
  /// double the threshold named in the spec.
  static const int stressTicksPerSecondPerStock = 10;

  final int ticksPerSecondPerStock;

  /// Scales the random walk's step size. Useful for making price movement
  /// visible in a demo without also raising the tick rate.
  final double volatilityMultiplier;

  final bool paused;

  /// Total ticks per second across the whole universe, for display.
  int totalTicksPerSecond(int stockCount) => ticksPerSecondPerStock * stockCount;

  bool get isStressMode => ticksPerSecondPerStock >= stressTicksPerSecondPerStock;

  /// The engine timer interval. One timer drives the whole universe: it fires
  /// at the aggregate rate and moves a slice of stocks each time, which keeps
  /// the number of active timers at one regardless of the tick rate.
  Duration intervalFor(int stockCount) {
    final int perSecond = totalTicksPerSecond(stockCount);
    if (perSecond <= 0) return const Duration(seconds: 1);
    final int micros = (Duration.microsecondsPerSecond / perSecond).floor();
    return Duration(microseconds: micros.clamp(1000, Duration.microsecondsPerSecond));
  }

  FeedConfig copyWith({
    int? ticksPerSecondPerStock,
    double? volatilityMultiplier,
    bool? paused,
  }) {
    return FeedConfig(
      ticksPerSecondPerStock: ticksPerSecondPerStock ?? this.ticksPerSecondPerStock,
      volatilityMultiplier: volatilityMultiplier ?? this.volatilityMultiplier,
      paused: paused ?? this.paused,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FeedConfig &&
      other.ticksPerSecondPerStock == ticksPerSecondPerStock &&
      other.volatilityMultiplier == volatilityMultiplier &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(ticksPerSecondPerStock, volatilityMultiplier, paused);
}
