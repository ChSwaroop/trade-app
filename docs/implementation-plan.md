# Trade App — Implementation Plan

Reference: [`prd.md`](../prd.md)

A Flutter trading app with four features — Watchlists, Live Prices, Buy/Sell Ticket, and
Holdings — backed by an in-memory mock market-data feed. No real backend. Must run with
`flutter pub get && flutter run`, no extra setup.

---

## 1. Tech Stack

| Area | Choice | Version |
|---|---|---|
| Framework | Flutter (stable) | 3.44.2 |
| Language | Dart | 3.12.2 |
| State management | `flutter_riverpod` | ^3.4.2 |
| Persistence | `hive_ce` + `hive_ce_flutter` (JSON maps in boxes, no codegen) | ^2.19.3 / ^2.3.4 |
| Routing | `go_router` | ^17.5.0 |
| Money | `decimal` | ^3.2.6 |
| IDs | `uuid` | ^4.6.0 |
| Formatting | `intl` | ^0.20.3 |
| Testing | `flutter_test` + `fake_async` | ^1.3.3 |
| Architecture | Feature-first + repository pattern | — |
| Market data | In-memory mock stream | — |

Deliberately excluded: `build_runner` / `hive_ce_generator` / `freezed` (keeps a fresh clone
at `pub get && run` with no codegen step), `path_provider` (transitive via
`hive_ce_flutter`), `mocktail` (repository interfaces are small enough to fake by hand).

---

## 2. Core Design Idea

Every hard requirement in the PRD — *"only affected cells rebuild"*, *"50+ ticks/sec without
dropped frames"*, *"the aggregate equals the sum of rows at any moment"*, *"no stale ticks on
the wrong row after reorder"* — falls out of a single decision:

> **The feed produces ticks freely. The UI consumes immutable snapshots at frame rate.**

```
MockFeedEngine              PriceStore                        UI
random walk per symbol  ->  absorbs every tick into a    ->   leaf widgets watch
N ticks/sec/symbol          mutable map; publishes an         quoteProvider(symbol)
(configurable)              immutable PriceSnapshot           with .select
                            once per frame (~16ms)
```

Three consequences:

1. **Coalescing decouples tick rate from rebuild rate.** 500 ticks/sec still yields at most
   ~60 publishes/sec. This is the whole answer to the stress-test scenario. Ticks are never
   dropped from the *data* — the store always holds the newest value — only the *notification*
   is throttled to the frame boundary.
2. **One immutable snapshot per frame.** Holdings rows and the aggregate summary read the
   same `PriceSnapshot` instance, so the header can never disagree with the sum of the rows
   mid-update. Consistency is structural, not defensive.
3. **Widgets key off symbol, never index.** A row knows only its symbol and looks up its own
   price. Reordering a watchlist therefore cannot misbind a price binding — there is no
   binding to break.

The feed is a single app-wide instance, making it the single source of price data for
Watchlist, Live Prices, Ticket, and Holdings alike.

---

## 3. Folder Structure

```
lib/
  main.dart                          # Hive init -> ProviderScope -> app
  app/
    app.dart                         # MaterialApp.router, theme wiring
    router.dart                      # go_router config + shell route
    theme.dart                       # colors, text styles, up/down semantics
    shell_scaffold.dart              # bottom nav (Market | Watchlists | Holdings)

  core/
    money/
      money.dart                     # Decimal-backed value type, no toDouble escape
      money_format.dart              # cached INR / percent / signed formatters
    storage/
      hive_store.dart                # box registry, open/close, schema version
      json_codec.dart                # Decimal <-> String, DateTime <-> iso8601
    result.dart                      # sealed Ok/Err for order placement
    extensions/                      # small Iterable/Decimal helpers
    widgets/
      flash_value.dart               # direction-aware flash cell
      empty_state.dart
      error_view.dart

  data/
    models/
      stock.dart                     # symbol, name, starting price
      quote.dart                     # symbol, ltp, prevClose, change, changePct
      price_snapshot.dart            # immutable Map<String, Quote> + seq
      watchlist.dart                 # id (uuid), name, ordered List<String>
      holding.dart                   # symbol, qty, totalCost -> derived avgCost
      order.dart                     # id, symbol, side, qty, fillPrice, ts
      wallet.dart                    # balance
    repositories/
      watchlist_repository.dart      # interface + Hive impl
      portfolio_repository.dart      # wallet + holdings, interface + Hive impl
      order_repository.dart          # interface + Hive impl

  market/
    stock_universe.dart              # the 10 symbols + starting prices
    feed_config.dart                 # ticksPerSecPerSymbol, volatility, stress flag
    mock_feed_engine.dart            # random-walk tick generator
    price_store.dart                 # coalescer -> Stream<PriceSnapshot>
    market_providers.dart            # snapshotProvider, quoteProvider(symbol), ltpProvider

  features/
    live_prices/
      live_prices_screen.dart
      widgets/price_tile.dart
    watchlist/
      watchlist_providers.dart
      watchlists_screen.dart         # list of watchlists, create/rename/delete
      watchlist_detail_screen.dart   # reorderable rows
      widgets/watchlist_row.dart
      widgets/stock_picker_sheet.dart
    ticket/
      ticket_providers.dart
      order_engine.dart              # pure validation + execution logic
      ticket_screen.dart
      order_confirmation_screen.dart
    holdings/
      holdings_providers.dart        # sort mode, derived rows, aggregate
      holdings_screen.dart
      widgets/holding_row.dart
      widgets/portfolio_summary.dart
    debug/
      feed_settings_sheet.dart       # tick-rate slider + stress toggle

test/
  core/money_test.dart
  market/price_store_test.dart       # fake_async, coalescing + stress
  data/repositories/*_test.dart
  features/ticket/order_engine_test.dart
  features/holdings/aggregate_test.dart
  widget/rebuild_isolation_test.dart # counts builds under N ticks
```

---

## 4. Component Specifications

### 4.1 Money (`core/money/money.dart`)

A value type wrapping `Decimal`. Rules:

- **No `double` anywhere on the data path.** Hive stores `Decimal.toString()`, parsed back with
  `Decimal.parse`. A single stray `.toDouble()` on the persistence path reintroduces exactly
  the drift the PRD tests for, so `Money` exposes no general `toDouble()`.
- **Division is explicit.** `decimal`'s `/` returns a `Rational` and throws on non-terminating
  results. All division (avg cost, P&L %) goes through a helper that converts to `Rational`
  and rounds to a declared scale, so the rounding policy is stated once rather than
  scattered.
- Scale: prices and money at 2 dp, percentages at 2 dp, both with `RoundingMode.halfUp`.
- Operators: `+`, `-`, `*` (by `int` qty), unary `-`, comparison, `isNegative`, `abs`.
- Formatting lives in `money_format.dart`, not on the type. Formatters are constructed once
  and cached — never allocated inside `build`.

### 4.2 Mock feed (`market/`)

`stock_universe.dart` holds the 10 symbols with plausible starting prices:

| Symbol | Start | Symbol | Start |
|---|---|---|---|
| RELIANCE | 2,950.00 | SBIN | 820.50 |
| TCS | 3,880.25 | ITC | 445.60 |
| INFY | 1,640.75 | LT | 3,610.90 |
| HDFCBANK | 1,705.40 | BHARTIARTL | 1,530.15 |
| ICICIBANK | 1,180.30 | AXISBANK | 1,145.80 |

`MockFeedEngine` runs a `Timer.periodic` and applies a bounded random walk per symbol
(per-symbol volatility, mean reversion toward the open, clamped so prices never go
non-positive or drift absurdly). Each stock keeps a `prevClose` fixed at its start price so
change and change % are meaningful.

`FeedConfig` exposes `ticksPerSecondPerSymbol` (default 2, range 1–10) and a stress toggle
that jumps to 50+/sec overall. Configurable from the debug sheet and via a compile-time
default constant.

`PriceStore` owns the current price map, applies incoming ticks immediately, and emits an
immutable `PriceSnapshot` on a `~16ms` scheduler only when something actually changed. It
also exposes `latestQuote(symbol)` for synchronous reads (used at order submission).

### 4.3 Riverpod graph

- `feedConfigProvider` — `Notifier<FeedConfig>`, drives engine timing.
- `priceStoreProvider` — app-scoped singleton, started at boot, disposed with the app.
- `snapshotProvider` — `StreamProvider<PriceSnapshot>`.
- `quoteProvider(symbol)` — family, `snapshotProvider.select((s) => s.quotes[symbol])`.
  This is the only thing leaf widgets watch.
- Repository providers, then `watchlistsProvider`, `holdingsProvider`, `walletProvider`,
  `ordersProvider` as async notifiers hydrated from Hive at startup.
- `holdingsRowsProvider` / `portfolioSummaryProvider` — derived from
  `holdingsProvider` × `snapshotProvider`, both from the same snapshot instance.

**Rebuild isolation contract:** rows are `const`-constructed and watch nothing. Only the
LTP / change / P&L `Text` leaves sit inside a `Consumer`. Each row gets a `RepaintBoundary`.
Lists use `ListView.builder` with a fixed `itemExtent`.

### 4.4 Flash on update

`FlashValue` compares the incoming quote against the previous one it rendered, picks
green (up) / red (down), and drives a 300 ms fade-out of the background tint. Purely local
animation state — it never rebuilds a parent, and a rapid sequence of ticks restarts rather
than queues the animation.

### 4.5 Order engine (`features/ticket/order_engine.dart`)

Pure functions, no Flutter imports, fully unit-testable:

- Validation: qty must parse as a positive integer (fractional, zero, negative and
  non-numeric all rejected with distinct messages); Buy requires
  `qty × ltp <= walletBalance`, error states the exact shortfall; Sell requires
  `qty <= heldQty`, error states the held quantity.
- Execution reads LTP synchronously from `PriceStore` **at submit time**, not from the UI's
  rendered snapshot, so the fill price is unambiguous. The confirmation screen shows the
  actual fill price.
- Buy: `balance -= qty × fill`, holding `qty += qty`, `totalCost += qty × fill`.
- Sell: `balance += qty × fill`, `totalCost -= avgCost × qty`, `qty -= qty`; holding removed
  when qty hits zero.
- **Average cost is never stored** — holdings persist `qty` and `totalCost`, and avg is
  derived. Repeated buys therefore accumulate zero rounding drift.
- Returns a sealed `Result` so the UI renders errors inline rather than throwing.

### 4.6 Persistence

Three Hive boxes holding `Map<String, dynamic>`: `watchlists`, `portfolio` (wallet +
holdings), `orders`. Every record carries a `schemaVersion`. On mismatch or a decode failure
the store logs and resets that box to defaults rather than crashing on launch. Writes are
debounced (reorder drags in particular) so a drag gesture is one write, not forty.

Seed on first run: wallet ₹10,00,000, one watchlist named "My Watchlist" containing a few
symbols, no holdings.

### 4.7 Routing

`go_router` with `StatefulShellRoute.indexedStack` so each tab keeps its scroll position
across switches — which is also what makes "navigate away and return" show current, not
stale, prices (the shared store keeps ticking; the tab just re-reads it).

```
/market                        Live Prices
/watchlists                    list of watchlists
/watchlists/:id                watchlist detail (reorderable)
/holdings                      portfolio
/ticket/:symbol?side=buy|sell  order ticket (deep-linkable, pre-filled)
/ticket/:symbol/confirmation   result
```

### 4.8 Holdings

Rows show symbol, qty, avg cost, LTP, current value, P&L in ₹ and %. Sort by P&L / symbol /
current value, default P&L descending; sort keys recompute per snapshot so a row crossing
from loss to gain reorders live. Rows carry `ValueKey(symbol)` so reordering animates rather
than rebuilding. The summary header (invested, current value, total P&L ₹ and %) is computed
from the same snapshot as the rows.

---

## 5. Build Order

Each row is one commit, in order. Foundations first so every later feature is built on
tested primitives.

| # | Commit | Contents |
|---|---|---|
| 1 | `chore: project scaffold, dependencies, strict lints` | pubspec, `analysis_options.yaml`, remove counter app, folder skeleton |
| 2 | `feat(core): Decimal-backed Money type and INR formatting` | `Money`, rounding policy, cached formatters, full unit tests |
| 3 | `feat(market): mock feed engine and frame-coalescing price store` | universe, random walk, `FeedConfig`, `PriceSnapshot`, store + providers |
| 4 | `feat(core): Hive storage layer and repositories` | box registry, schema versioning, JSON codecs, three repositories + tests |
| 5 | `feat(app): router, shell scaffold, theme` | go_router, bottom nav, up/down color semantics |
| 6 | `feat(live-prices): market overview with flash cells` | grid/list, `FlashValue`, `RepaintBoundary`, rebuild isolation |
| 7 | `feat(watchlist): multiple watchlists with reorder and persistence` | CRUD, picker sheet, `ReorderableListView`, symbol-keyed rows, empty states |
| 8 | `feat(ticket): buy/sell order ticket` | order engine, live LTP, inline validation, execution, confirmation |
| 9 | `feat(holdings): portfolio with live P&L and sorting` | rows, sorting, snapshot-consistent summary, empty state |
| 10 | `feat(debug): configurable tick rate and stress mode` | settings sheet, slider, 50+/sec toggle |
| 11 | `test: feed coalescing, order engine, repositories, rebuild isolation` | `fake_async` timing tests, build-count widget test |
| 12 | `docs: README with architecture and trade-offs` | how to run, design decisions, known limitations |

---

## 6. Testing Strategy

| Target | Test |
|---|---|
| Money | Repeated buys at odd prices accumulate no drift; rounding at boundaries; division by zero-qty guarded |
| Price store | With `fake_async`: 500 ticks/sec produces ≤ 60 snapshot emissions/sec, and the final snapshot holds the newest value for every symbol (no lost data) |
| Rebuild isolation | Widget test counts `build` calls on a row across 100 ticks and asserts the row body builds once while only leaves rebuild |
| Order engine | Table-driven: insufficient balance, oversell, qty `0` / `-1` / `1.5` / `"abc"`, exact-balance boundary, sell-to-zero removes the holding |
| Aggregate consistency | For a random portfolio and a random snapshot, summary totals equal the sum of the row values exactly |
| Repositories | Round-trip, schema-version mismatch resets cleanly, corrupt JSON does not crash |
| Reorder correctness | Reorder then tick; each row still shows its own symbol's price |

---

## 7. Edge Cases Explicitly Handled

- Same stock in two watchlists shows identical prices (single store makes this structural).
- Removing a stock stops its updates for that watchlist and it is gone after restart.
- Empty watchlist, no watchlists at all, and no holdings each show a distinct empty state.
- Deleting the last watchlist falls back cleanly rather than leaving a dangling route.
- Duplicate watchlist names are legal — identity is the uuid, not the name.
- Adding a stock already in the watchlist is a no-op with feedback, not a duplicate row.
- Price ticks while the confirm dialog is open: the order fills at the LTP read at submit,
  and the confirmation displays that exact fill price.
- Fractional, zero, negative, and non-numeric quantities are each rejected with a specific
  message.
- Corrupt or older persisted schema is detected and reset rather than crashing at launch.
- App backgrounded and resumed: the feed keeps the store current; the UI re-reads on resume
  so nothing stale is shown.

---

## 8. Performance Checklist

- Frame-boundary coalescing between feed and UI (the primary lever).
- `.select` on per-symbol providers; leaf-level `Consumer` only.
- `const` constructors on rows and static subtrees.
- `RepaintBoundary` per row; `ListView.builder` with fixed `itemExtent`.
- Formatters and `TextStyle` objects hoisted out of `build`.
- No `setState` above a row; no whole-list rebuilds on a tick.
- Verified against the stress toggle with the performance overlay and DevTools timeline.

---

## 9. Definition of Done

- `flutter pub get && flutter run` works on a clean clone with no additional setup.
- `flutter analyze` is clean under strict lints; `flutter test` passes.
- All four features work against every expected scenario listed in `prd.md`.
- Stress mode (50+ ticks/sec) runs with no visible jank while scrolling.
- Kill and relaunch the app: watchlists, order history, wallet balance, and holdings all
  restore exactly.
- README documents the architecture, the coalescing decision, the money-precision approach,
  and the known trade-offs.
