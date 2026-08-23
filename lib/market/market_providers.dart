import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/price_snapshot.dart';
import '../data/models/quote.dart';
import 'feed_config.dart';
import 'mock_feed_engine.dart';
import 'price_store.dart';

/// Runtime feed tuning. Writing here reconfigures the running engine without
/// resetting prices.
class FeedConfigNotifier extends Notifier<FeedConfig> {
  @override
  FeedConfig build() => const FeedConfig();

  void setTicksPerSecond(int value) {
    state = state.copyWith(
      ticksPerSecondPerStock: value.clamp(
        FeedConfig.minTicksPerSecondPerStock,
        FeedConfig.maxTicksPerSecondPerStock,
      ),
    );
    _apply();
  }

  void setVolatilityMultiplier(double value) {
    state = state.copyWith(volatilityMultiplier: value);
    _apply();
  }

  void toggleStressMode() {
    state = state.copyWith(
      ticksPerSecondPerStock: state.isStressMode
          ? FeedConfig.defaultTicksPerSecondPerStock
          : FeedConfig.stressTicksPerSecondPerStock,
    );
    _apply();
  }

  void setPaused({required bool paused}) {
    state = state.copyWith(paused: paused);
    _apply();
  }

  void _apply() => ref.read(priceStoreProvider).updateConfig(state);
}

final NotifierProvider<FeedConfigNotifier, FeedConfig> feedConfigProvider =
    NotifierProvider<FeedConfigNotifier, FeedConfig>(FeedConfigNotifier.new);

/// App-scoped singleton. Created once, started immediately, torn down with the
/// app. Every price shown anywhere in the app resolves through this instance,
/// which is what guarantees the same stock reads identically on two different
/// screens.
final Provider<PriceStore> priceStoreProvider = Provider<PriceStore>((Ref ref) {
  final MockFeedEngine engine = MockFeedEngine(config: ref.read(feedConfigProvider));
  final PriceStore store = PriceStore(engine: engine);
  ref.onDispose(store.dispose);
  store.start();
  return store;
});

/// The coalesced snapshot stream, seeded with the store's current value so a
/// screen mounted mid-session renders live prices on its first frame instead
/// of a loading state.
final StreamProvider<PriceSnapshot> snapshotProvider =
    StreamProvider<PriceSnapshot>((Ref ref) {
  final PriceStore store = ref.watch(priceStoreProvider);
  return store.snapshots;
});

/// The only price provider widgets should watch.
///
/// Selecting a single symbol out of the snapshot means a publish that did not
/// touch this stock produces an identical [Quote], and Riverpod's equality
/// check drops the rebuild. Under a 100 ticks/sec load a given row rebuilds
/// only when its own price actually moved.
/// Depends only on [snapshotProvider], not on the store itself. The store's
/// stream replays its current value to every new listener, so there is no need
/// to reach past the stream for a seed — which also means a test can drive the
/// whole UI by overriding this one provider, without standing up a live feed.
final ProviderFamily<Quote?, String> quoteProvider =
    Provider.family<Quote?, String>((Ref ref, String symbol) {
  return ref.watch(snapshotProvider).value?[symbol];
});
