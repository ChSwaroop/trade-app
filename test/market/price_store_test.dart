import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/data/models/price_snapshot.dart';
import 'package:tradedirect/data/models/quote.dart';
import 'package:tradedirect/market/feed_config.dart';
import 'package:tradedirect/market/mock_feed_engine.dart';
import 'package:tradedirect/market/price_store.dart';
import 'package:tradedirect/market/stock_universe.dart';

void main() {
  group('MockFeedEngine', () {
    test('emits at the configured aggregate rate', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(
          random: Random(1),
          config: const FeedConfig(ticksPerSecondPerStock: 2),
        );
        final List<RawTick> ticks = <RawTick>[];
        final StreamSubscription<RawTick> sub = engine.ticks.listen(ticks.add);
        engine.start();

        async.elapse(const Duration(seconds: 1));

        // 2/sec across 10 stocks = 20 ticks/sec, within timer granularity.
        expect(ticks.length, closeTo(20, 2));
        sub.cancel();
        engine.stop();
      });
    });

    test('cycles through the universe so every stock moves', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(random: Random(7));
        final Set<String> seen = <String>{};
        final StreamSubscription<RawTick> sub =
            engine.ticks.listen((RawTick t) => seen.add(t.symbol));
        engine.start();

        async.elapse(const Duration(seconds: 2));

        expect(seen, hasLength(StockUniverse.all.length));
        sub.cancel();
        engine.stop();
      });
    });

    test('keeps prices positive under extreme volatility', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(
          random: Random(3),
          config: const FeedConfig(
            ticksPerSecondPerStock: 20,
            volatilityMultiplier: 500,
          ),
        );
        final List<RawTick> ticks = <RawTick>[];
        final StreamSubscription<RawTick> sub = engine.ticks.listen(ticks.add);
        engine.start();

        async.elapse(const Duration(seconds: 5));

        expect(ticks, isNotEmpty);
        expect(ticks.every((RawTick t) => t.pricePaise >= 1), isTrue);
        sub.cancel();
        engine.stop();
      });
    });

    test('preserves prices across a reconfiguration', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(random: Random(11));
        engine.start();
        async.elapse(const Duration(seconds: 1));

        final int before = engine.currentPricePaise('RELIANCE')!;
        engine.updateConfig(const FeedConfig(ticksPerSecondPerStock: 10));

        // The stress toggle must not reset the market.
        expect(engine.currentPricePaise('RELIANCE'), before);
        engine.stop();
      });
    });

    test('resumes after being paused and unpaused', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(random: Random(5));
        final List<RawTick> ticks = <RawTick>[];
        final StreamSubscription<RawTick> sub = engine.ticks.listen(ticks.add);
        engine.start();

        engine.updateConfig(const FeedConfig(paused: true));
        async.elapse(const Duration(seconds: 1));
        expect(ticks, isEmpty);

        engine.updateConfig(const FeedConfig());
        async.elapse(const Duration(seconds: 1));
        expect(ticks, isNotEmpty);

        sub.cancel();
        engine.stop();
      });
    });
  });

  group('PriceStore coalescing', () {
    test('publishes at frame rate no matter how fast the feed runs', () {
      fakeAsync((FakeAsync async) {
        // 20/sec/stock across 10 stocks = 200 ticks/sec, four times the
        // stress threshold named in the spec.
        final MockFeedEngine engine = MockFeedEngine(
          random: Random(13),
          config: const FeedConfig(ticksPerSecondPerStock: 20),
        );
        final PriceStore store = PriceStore(engine: engine);
        final List<PriceSnapshot> published = <PriceSnapshot>[];
        final StreamSubscription<PriceSnapshot> sub =
            store.snapshots.listen(published.add);
        store.start();

        async.elapse(const Duration(seconds: 1));

        // ~200 ticks arrived; the UI must see at most ~63 publishes.
        expect(published.length, lessThanOrEqualTo(63));
        expect(published.length, greaterThan(30));
        sub.cancel();
      });
    });

    test('loses no price data while coalescing', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(
          random: Random(17),
          config: const FeedConfig(ticksPerSecondPerStock: 20),
        );
        final PriceStore store = PriceStore(engine: engine);
        PriceSnapshot? last;
        final StreamSubscription<PriceSnapshot> sub =
            store.snapshots.listen((PriceSnapshot s) => last = s);
        store.start();

        async.elapse(const Duration(seconds: 1));

        // Drain deterministically: stop the feed, then let one publish window
        // pass. Without this the comparison races — ticks that land after the
        // final publish are legitimately not in the last snapshot yet.
        engine.updateConfig(const FeedConfig(paused: true));
        async.elapse(const Duration(milliseconds: 50));

        // The published snapshot must carry the engine's newest price for
        // every symbol, not an intermediate value from mid-window.
        for (final Stock stock in StockUniverse.all) {
          expect(
            last![stock.symbol]!.ltp,
            Money.fromPaise(engine.currentPricePaise(stock.symbol)!),
            reason: 'stale price published for ${stock.symbol}',
          );
        }
        sub.cancel();
      });
    });

    test('skips publishing entirely when nothing changed', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(
          random: Random(19),
          config: const FeedConfig(paused: true),
        );
        final PriceStore store = PriceStore(engine: engine);
        final List<PriceSnapshot> published = <PriceSnapshot>[];
        final StreamSubscription<PriceSnapshot> sub =
            store.snapshots.listen(published.add);
        store.start();

        async.elapse(const Duration(seconds: 2));

        // Exactly one emission: the seed replayed to the new listener. Beyond
        // that, a paused feed must cost nothing — the publish timer fires 125
        // times over two seconds and skips every one of them because nothing
        // is dirty.
        expect(published, hasLength(1));
        expect(published.single.sequence, 0);
        sub.cancel();
      });
    });

    test('seeds every instrument before the first tick arrives', () {
      final MockFeedEngine engine = MockFeedEngine(random: Random(23));
      final PriceStore store = PriceStore(engine: engine);

      // A screen mounted before the feed emits must still render a full
      // market rather than blank rows.
      for (final Stock stock in StockUniverse.all) {
        final Quote quote = store.quoteFor(stock.symbol)!;
        expect(quote.ltp, stock.startingPrice);
        expect(quote.change.isZero, isTrue);
        expect(quote.direction, TickDirection.flat);
      }
    });

    test('exposes a synchronous price for order execution', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(random: Random(29));
        final PriceStore store = PriceStore(engine: engine);
        store.start();
        async.elapse(const Duration(seconds: 1));

        // The ticket reads this at submit time rather than trusting whatever
        // the UI last rendered.
        expect(store.priceOf('TCS'), isNotNull);
        expect(store.priceOf('TCS'), store.quoteFor('TCS')!.ltp);
        expect(store.priceOf('NOTLISTED'), isNull);
      });
    });

    test('assigns a per-symbol sequence so repeat prices still register', () {
      fakeAsync((FakeAsync async) {
        final MockFeedEngine engine = MockFeedEngine(random: Random(31));
        final PriceStore store = PriceStore(engine: engine);
        store.start();

        async.elapse(const Duration(seconds: 1));
        final int first = store.quoteFor('INFY')!.sequence;
        async.elapse(const Duration(seconds: 1));

        expect(store.quoteFor('INFY')!.sequence, greaterThan(first));
      });
    });
  });
}

