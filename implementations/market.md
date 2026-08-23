# Feature: Market Feed (Live Prices) — COMPLETE

**PRD feature:** 2 (Live Prices Mimic)
**Status:** Done. `flutter analyze` clean, 32 tests passing, verified running in a browser.
**Date:** 2026-08-23

This document is the handoff context. Anyone picking the project up mid-stream should
read this plus [`docs/implementation-plan.md`](../docs/implementation-plan.md) and be able
to continue without re-deriving anything.

---

## 1. What was built

Feature 2 in full, plus every foundation the remaining three features depend on:

| Layer | Files | State |
|---|---|---|
| Money | `lib/core/money/money.dart`, `money_format.dart` | Done, reusable |
| Feed | `lib/market/*` | Done, reusable — the single source of prices |
| Models | `lib/data/models/quote.dart`, `price_snapshot.dart` | Done |
| Theme | `lib/app/theme.dart` | Done, reusable |
| Shell / routing | `lib/app/router.dart`, `shell_scaffold.dart`, `app.dart` | Done, two branches still placeholders |
| Market screen | `lib/features/live_prices/*` | Done |
| Flash widget | `lib/core/widgets/flash_on_change.dart` | Done, reusable |
| Debug controls | `lib/features/debug/feed_settings_sheet.dart` | Done |

**Not built yet:** Hive persistence layer, repositories, watchlists, order ticket,
holdings. The Watchlists and Holdings tabs currently render `PlaceholderScreen`.

---

## 2. The architecture decision everything else rests on

**The feed produces ticks freely; the UI consumes immutable snapshots at frame rate.**

```
MockFeedEngine  ──ticks──>  PriceStore  ──snapshots──>  quoteProvider(symbol)  ──>  leaf widgets
 integer paise               absorbs every tick          Provider.family              Text only
 1 timer, N/sec             publishes ≤ 1 per 16ms       .select semantics
```

Three properties fall out of this, and later features should not undo them:

1. **Coalescing decouples tick rate from rebuild rate.** `PriceStore` writes every tick
   into a mutable working set immediately, marks the symbol dirty, and notifies nobody.
   A 16ms timer publishes an immutable `PriceSnapshot` only if something is dirty. At 200
   ticks/sec the UI still sees ≤63 publishes/sec, and no data is lost because the working
   set always holds the newest value. If the feed is idle, zero publishes occur.
2. **One snapshot instance per frame.** When Holdings lands, its rows and its aggregate
   header must both read from the same `PriceSnapshot`. That is what makes
   "summary == sum of rows at any moment" structural rather than defensive.
3. **Widgets key off symbol, never index.** A row receives a symbol and looks up its own
   price. Reordering a watchlist therefore cannot misbind a price — there is no binding to
   break. Feature 1 gets its hardest requirement for free.

---

## 3. Money handling — read this before touching arithmetic

`Money` wraps `Decimal`, never `double`. Rules enforced in the code:

- **No general `toDouble()`.** The only escape is `toDoubleUnsafe()`, named to be greppable,
  intended for chart geometry alone.
- **Never divide with `/`.** `Decimal.operator /` returns a `Rational` and throws on
  non-terminating results. Use `divideBy(int)` or `ratioTo(Money)`, which declare scale and
  rounding in one place.
- **`toStorageString()` is the persistence form** and drops trailing zeros — `'0.30'`
  round-trips as `'0.3'`. It is exact and re-parses equal, but it is **not** a display
  string. Never assert on it as one; compare `Money` values instead.
- **A bug found and fixed during this feature:** `Rational.toDecimal(scaleOnInfinitePrecision:)`
  only applies its scale when the quotient does *not* terminate. `83754.65 / 28` terminates
  at `2991.2375` and slipped through at full precision. `divideBy` now applies an explicit
  `.round(scale: 2)` afterward. Watch for this anywhere else division is added.

### Carry-forward for Holdings (important)

Holdings must persist **`qty` + `totalCost`** and *derive* average cost. Never store the
average. Repeated buys then accumulate zero rounding error — proven by the
`cost basis over many buys stays exact` test.

On a **partial sell**, do **not** reduce `totalCost` by `avgCost × qtySold` — the rounded
average would feed drift back into the basis. Reduce proportionally instead:
`newTotalCost = totalCost × (remainingQty / originalQty)`, computed as an exact rational.

---

## 4. Component notes

### `MockFeedEngine` (`lib/market/mock_feed_engine.dart`)
- Works entirely in **integer paise**. A random walk over integers is exact by construction.
- **One timer for the whole universe.** It fires at the aggregate rate and moves one stock
  per fire, cycling through them. Raising the tick rate raises timer frequency, not timer
  count.
- **Mean-reverting** random walk: a volatility-scaled shock plus a pull back toward the open
  proportional to distance. A plain walk drifts monotonically and every stock ends the
  session absurdly far from its open.
- Prices clamp at ≥1 paise. Reconfiguration preserves prices — the stress toggle must never
  reset the market.
- `_started` is tracked separately from `_timer` because pausing cancels the timer; without
  the flag, unpausing would find a null timer and never resume. (This was a real bug.)

### `PriceStore` (`lib/market/price_store.dart`)
- `snapshots` is an `async*` generator that **yields the current snapshot to every new
  listener** before forwarding the stream. This is why a screen renders live prices on its
  first frame and why prices are current — not stale — when the user navigates back.
- `quoteFor(symbol)` / `priceOf(symbol)` are **synchronous reads**. The order ticket must
  fill from these at submit time, not from whatever the UI last rendered.
- Seeds every instrument at its opening price at construction, so nothing ever renders blank.

### `quoteProvider` (`lib/market/market_providers.dart`)
- `Provider.family<Quote?, String>` depending **only** on `snapshotProvider`. It deliberately
  does not touch `priceStoreProvider` — that lets a test drive the entire UI by overriding
  one provider without standing up a live feed and its timers.
- Rebuild suppression relies on `Quote`'s value equality. **If you add a field to `Quote`,
  add it to `==` and `hashCode`,** or every row will rebuild on every tick.
- `Quote.sequence` is in `==` on purpose: two consecutive ticks landing on the same price
  must still count as distinct prints so the flash re-fires.

### `FlashOnChange` (`lib/core/widgets/flash_on_change.dart`)
- Fires on `triggerSequence` change, 320ms fade, direction-aware colour.
- Entirely local animation state inside a `RepaintBoundary`; `AnimatedBuilder` takes a
  prebuilt `child` so only the `DecoratedBox` colour interpolates.
- Reuse this for watchlist rows and holdings rows.

### Rebuild isolation contract
Rows are plain `StatelessWidget`s that watch nothing. Only the price column is a
`ConsumerWidget`. **Keep this shape in every new list.** It is enforced by
`test/widget/rebuild_isolation_test.dart`, which asserts that ten ticks on RELIANCE cause
exactly ten rebuilds of that leaf and zero rebuilds of the other nine.

---

## 5. Design-system implementation

Tokens from `trade_app_ui/quantal/DESIGN.md` live in `lib/app/theme.dart` as `AppColors`,
`AppTypography`, `AppSpacing`. Inter is **bundled** at `assets/fonts/` (four static weights)
rather than fetched at runtime, so a clean clone runs offline with no extra setup.

Every numeric style carries `FontFeature.tabularFigures()`. Without it, digit glyphs have
different advance widths and prices jitter horizontally on each tick.

### Deliberate deviations from the reference HTML

| Design | Implementation | Why |
|---|---|---|
| Row columns both `flex-1` | Name column `Expanded`, price column shrink-wrapped | Equal flex truncated longer company names while leaving dead space beside the price |
| Sparkline in the middle column | Omitted | Already `hidden sm:flex` in the design, so absent on mobile; not a PRD requirement |
| Static "NIFTY 50" caption | "NIFTY 50 · N ticks/s", live | Makes the tick-rate setting observable on the screen it affects |
| Bottom bar with extra/wrong destinations on some screens | Three destinations only: Market, Watchlists, Holdings | Per your instruction |
| Body `#0A0A0A` vs token `surface #121317` (inconsistent in the source) | Canvas `#0A0A0A`, app bar `#121317`, cards `#1C1C1E`, hairline `#2C2C2E` | Follows what the HTML actually renders; matches the DESIGN.md elevation section |

---

## 6. Verification performed

- `flutter analyze` — clean under strict lints (`strict-casts`, `strict-inference`,
  `strict-raw-types` + 15 extra rules).
- `flutter test` — 32 passing.
- `flutter build web --debug` — compiles.
- **Ran in a browser at 375×812** and confirmed: ten rows with live prices, Indian
  formatting (`₹2,987.45`), direction-aware green/red flashes, working bottom nav, debug
  sheet opening, slider changing the rate with the header updating live, and stress mode
  driving 100 ticks/s with the UI still responsive.

Key tests and what they lock down:

| Test | Guards |
|---|---|
| `money_test.dart` → repeated accumulation / cost basis | No decimal drift; also asserts the equivalent `double` computation *does* drift |
| `price_store_test.dart` → publishes at frame rate | 200 ticks/s → ≤63 publishes/s |
| `price_store_test.dart` → loses no price data | Coalesced snapshot carries the newest price for every symbol |
| `price_store_test.dart` → skips publishing when nothing changed | Idle feed costs nothing |
| `price_store_test.dart` → resumes after pause | The `_started` bug above |
| `rebuild_isolation_test.dart` | A tick rebuilds only the affected symbol's leaf |

---

## 7. Known gaps / deliberate deferrals

- `MarketRow.onTap` is an **empty callback**. Wire it to `/ticket/:symbol` when the order
  ticket lands.
- `PlaceholderScreen` backs the Watchlists and Holdings branches; delete it once both exist.
- No persistence yet — no Hive initialisation in `main.dart`. It will need
  `await Hive.initFlutter()` and box opening **before** `runApp`.
- `FeedConfig` is not persisted; tick rate resets to the default of 2/sec/stock on restart.
  That is intentional for a debug control.
- Light theme is not implemented. The design system describes one; the PRD does not require
  it. `AppTheme` is structured to accept a `light` getter later.
- No golden tests.

---

## 8. Next feature

**Feature 1: Watchlists.** It needs, in order:

1. The Hive storage layer (`lib/core/storage/`) — schema-versioned JSON boxes, reset on
   decode failure rather than crashing at launch. This is shared with Holdings and orders,
   so build it properly here.
2. `Watchlist` model (uuid identity, ordered `List<String>` of symbols) +
   `WatchlistRepository`.
3. Screens: `/watchlists` (list, create/rename/delete) and `/watchlists/:id`
   (`ReorderableListView`, swipe-to-remove, add-stock picker sheet).
4. Reuse `MarketRow`'s structure — copy the shape, do not make rows watch providers.

Designs to follow: `trade_app_ui/watchlist_detail/`, `empty_watchlist/`,
`add_stocks_picker/`.
