# Feature: Watchlists — COMPLETE

**PRD feature:** 1 (Watchlist Management)
**Status:** Done. `flutter analyze` clean, 61 tests passing, verified running in a browser.
**Date:** 2026-08-23
**Prerequisite reading:** [`implementations/market.md`](market.md) — this feature builds
directly on its price pipeline and does not restate it.

---

## 1. What was built

| Layer | Files | Notes |
|---|---|---|
| Storage | `lib/core/storage/json_store.dart` | **Shared foundation** — Holdings and orders use this next |
| Model | `lib/data/models/watchlist.dart` | uuid identity, ordered symbols |
| Repository | `lib/data/repositories/watchlist_repository.dart` | Owns the on-disk shape and the limits |
| State | `lib/features/watchlists/watchlist_providers.dart` | All mutation rules, write-through persistence |
| Screens | `watchlists_screen.dart`, `watchlist_detail_screen.dart` | Index + detail |
| Widgets | `widgets/watchlist_row.dart`, `add_stocks_sheet.dart`, `watchlist_name_dialog.dart` | |
| Shared | `lib/core/widgets/live_price_column.dart` | **Extracted** from `MarketRow` so both lists use one price leaf |
| Startup | `lib/main.dart` | Hive initialised before `runApp` |

`PlaceholderScreen` now backs only the Holdings tab.

---

## 2. Storage — build on this, do not reinvent it

`JsonStore` is a key/value store of small JSON documents. Two implementations:
`HiveJsonStore` (a `Box<String>` of JSON) and `InMemoryJsonStore` (tests, and the
fallback when Hive will not initialise).

Three decisions worth keeping:

1. **Values are JSON strings, not maps.** Hive returns `Map<dynamic, dynamic>` for
   nested structures, which forces a cast at every level under `strict-casts`. A JSON
   string decodes into properly typed maps in one step.
2. **Every document is version-stamped.** `read` takes the caller's `schemaVersion` and
   returns `null` when the stored version differs. A shape change is therefore a
   one-line bump, not a migration written under pressure. Migrations, when they exist,
   belong inside the store.
3. **Reads never throw.** Malformed JSON, a wrong version, a corrupt box file — all
   resolve to "no document", which the repository treats as a first run. **Losing local
   watchlists is recoverable; failing to launch is not.** `main` extends the same rule
   to Hive itself: if `initFlutter` throws, the app runs on `InMemoryJsonStore` and
   simply forgets on restart.

Adding a new persisted document = pick a key, define a `schemaVersion`, write a
repository. Nothing else needs to change.

---

## 3. The requirement this feature turns on

> *"Reordering must never misbind a row to another instrument's price."*

This is structural, not defended. Rows are keyed by **symbol**, never by index, and each
row looks up its own price through `quoteProvider(symbol)`. There is no index-to-price
binding for a move to invalidate.

`test/widget/watchlist_binding_test.dart` proves it: twelve reorders interleaved with
price ticks, asserting after **every** step that the widget displaying a given price is
the row that claims that symbol. Prices in the fixture are set far apart so a misbinding
would be unmistakable rather than a plausible-looking number.

The row shape is inherited from `MarketRow`: a plain `StatelessWidget` that watches
nothing, with `LivePriceColumn` as the only subscriber. **Keep this shape in Holdings.**

---

## 4. State and rules

`WatchlistsNotifier` holds the full collection and is the only writer. Every rule lives
there, so the UI contains no validation:

| Rule | Behaviour |
|---|---|
| Empty / whitespace-only name | Refused |
| Duplicate name (case-insensitive) | Refused — the check excludes the list being renamed, or confirming an unchanged name would fail |
| Name > 24 chars | Refused |
| More than 10 watchlists | Refused |
| More than 50 symbols in one list | Refused |
| Unknown symbol | Refused |
| **Adding a symbol already present** | **No-op, not an error** — the picker toggles, so a double tap must not raise |
| Mutating a deleted watchlist | Returns `notFound`, never throws |

Mutations return a `WatchlistFailure?` rather than throwing. Returning failures keeps
the rules in one testable place and lets each call site decide how to present them —
currently a snackbar.

### Persistence timing

State updates synchronously; the write is **chained** onto a future:

```dart
_writes = _writes.then((_) => repository.save(toSave));
```

Chaining rather than firing in parallel means back-to-back edits land on disk in the
order they were made. `notifier.settled` exposes that chain so tests await it instead of
guessing at timing — `test/features/watchlist_notifier_test.dart` uses it to simulate a
relaunch by building a second `ProviderContainer` over the same store.

### Provider granularity

- `watchlistByIdProvider(id)` — one list; editing a *different* list rebuilds nothing here.
- `watchlistSymbolsProvider(id)` — symbols only; **renaming does not rebuild the rows.**
- The picker's rows watch `.select((w) => w.contains(symbol))`, so adding one stock
  rebuilds one row out of ten.

---

## 5. Seeding and the empty state

An **absent** document is a first run and seeds one starter watchlist (five recognisable
symbols), so the feature is not a dead end on launch. An **explicitly empty** list is
respected — a user who deleted everything must not find the seed resurrected on the next
launch. Both cases are tested.

---

## 6. Design implementation and deviations

Followed: `watchlist_detail`, `empty_watchlist`, `add_stocks_picker`.

| Design | Implementation | Why |
|---|---|---|
| Drag handle revealed on hover (`opacity-0 group-hover:opacity-100`, `hidden md:block`) | Always visible | Hover does not exist on touch. As drawn, reordering would be undiscoverable on the phone the app targets |
| FAB overlapping the last row's price (visible in `screen.png`) | 88px bottom padding on the list | The reference screenshot has the FAB sitting on top of INFY's price |
| TREND sparkline column | Omitted | The feed has no historical series, and the column is dead weight at 375px. Same call as the market screen |
| Row subtitle `NSE · EQ` | Company name | Identical on every row, so it carries no information; the company name disambiguates |
| No design for the watchlists **index** | Card list, `more_vert` → Rename / Delete | Only the empty state was provided |
| Sheet bottom edge stopping above the tab bar | `useRootNavigator: true` | A modal that leaves the tab bar exposed reads as a layout bug |
| Material default snack bar | Themed dark | The default inverts the surface — a white slab over live prices |
| Bottom bars in the design showing other destinations | Market / Watchlists / Holdings only | Per your instruction |

Deleting a watchlist asks for confirmation; removing a single symbol does not, because
that one has undo. **Undo restores position, not just membership** — a removal that
silently reshuffles the list is worse than no undo at all.

---

## 7. Verification performed

- `flutter analyze` — clean under strict lints.
- `flutter test` — **61 passing** (29 new).
- **Ran in a browser at 375×812** and confirmed by interaction: the index renders and
  navigates; the detail list shows live ticking prices; **dragging TCS down two rows
  moved its price with it**; swipe-to-remove fired the undo snackbar and undo restored
  INFY to its original index; the picker toggled SBIN with the app bar's item count
  updating live behind the sheet; and **after a full page reload the added symbol and
  the reordered sequence were both still there**, with the deep-linked detail route
  restored from its id.

| Test file | Guards |
|---|---|
| `test/widget/watchlist_binding_test.dart` | Reorder under load never misbinds a price; a deleted watchlist leaves the screen recoverable |
| `test/features/watchlist_notifier_test.dart` | Every rule in §4; write-through survives a simulated relaunch; ordered writes |
| `test/data/watchlist_repository_test.dart` | Seed on first run, empty respected, schema-version mismatch resets, malformed documents survived, delisted symbols dropped |

---

## 8. Known gaps

- `WatchlistRow.onTap` is an **empty callback**, like `MarketRow.onTap`. Both wire to
  `/ticket/:symbol` when the order ticket lands.
- No search on the watchlists **index** — with a cap of 10 it is not yet worth it.
- Watchlists cannot be reordered relative to each other, only their contents.
- No golden tests.

---

## 9. Next feature

**Feature 3: Buy/Sell ticket**, then **Feature 4: Holdings**.

1. Order model + `OrderRepository` on the existing `JsonStore` (new key, own
   `schemaVersion`). Ids from `Uuid`.
2. `/ticket/:symbol` route, pushed from both `MarketRow.onTap` and `WatchlistRow.onTap`.
3. **Fill from `PriceStore.priceOf(symbol)` at submit time** — a synchronous read, not
   whatever the UI last rendered. See `implementations/market.md` §4.
4. Validation: quantity > 0, integral, sufficient holdings on a sell. Designs:
   `order_ticket_buy`, `order_ticket_invalid`, `order_confirmation`.

**Holdings must honour the cost-basis rule in `implementations/market.md` §3:** persist
`qty` + `totalCost` and derive the average; on a partial sell reduce `totalCost`
proportionally as an exact rational, never by `avgCost × qtySold`.
