# Feature: Holdings — COMPLETE

**PRD feature:** 4 (Holdings)
**Status:** Done. `flutter analyze` clean, 98 tests passing, verified running in a browser.
**Date:** 2026-08-24
**Prerequisite reading:** [`implementations/market.md`](market.md) — the price
pipeline everything reads from and, critically, §3 (money + cost basis rules)
which this feature enforces — and [`implementations/order_ticket.md`](order_ticket.md),
whose order history is the only source Holdings derives from.

---

## 1. What was built

| Layer | Files | Notes |
|---|---|---|
| Money helper | `lib/core/money/money.dart` (`scaledBy`) | Exact-rational scaling for partial-sell reduction |
| Model | `lib/data/models/position.dart` | Immutable position + pure `positionsFrom(orders)` derivation |
| State | `lib/features/holdings/holdings_providers.dart` | `holdings`, `sortedHoldings`, `holdingsAggregate`, `positionBySymbol`, sort |
| Screen | `lib/features/holdings/holdings_screen.dart` | Aggregate header, sort bar, list, empty state |
| Row | `lib/features/holdings/widgets/holding_row.dart` | Stateless row; live P&L in an isolated leaf |
| Routing | `lib/app/router.dart` | Holdings branch now points at `HoldingsScreen`; `PlaceholderScreen` deleted |

Every screen the PRD asked for now exists — this is the last feature.

---

## 2. Holdings is a **derivation**, not a store

The Order repository already persists every fill. Rebuilding positions on
launch is exactly what `positionsFrom(orders)` does. That means there is:

- No new repository, no new schemaVersion, no separate mutation path.
- One provider chain: `ordersProvider → holdingsProvider → sortedHoldingsProvider`.
- Structural agreement between a placed order and the position it produces —
  "when a Buy order is placed, it appears in Holdings" is not wiring, it is
  the shape of the graph.
- The `avgCost × qtySold` trap cannot exist here: sell-reduction happens in a
  single pure function with a `Money.scaledBy(remaining, original)` call.

`test/data/position_derivation_test.dart` locks the derivation down: exact
cost basis across many odd-priced buys, proportional (not average-based)
reduction on a partial sell, dropped-to-zero positions removed cleanly, and a
rebuy after a full close starting from a fresh basis rather than the old one.

---

## 3. Cost basis, precisely as `implementations/market.md` §3 said

Two rules, both enforced by `positionsFrom`:

1. **Buys accumulate exact totals.** `totalCost += fillPrice × quantity`.
   `Money * int` is exact — no rounding, no drift, no matter how many buys.
2. **Partial sells scale `totalCost` by an exact rational.**
   `newTotalCost = totalCost.scaledBy(remaining, original)`.
   `Money.scaledBy` multiplies the underlying `Decimal` by
   `Rational.fromInt(remaining, original)` and rounds *once* at the end.

That is the only place in the app that scales a Money by a fraction; the
method was added to `Money` precisely so this operation stays in the
money-arithmetic module, per the discipline set by
[`implementations/market.md`](market.md) §3 ("never divide with `/`; all
money math lives on Money").

**The averageCost is never stored.** It is derived on read via `totalCost.divideBy(quantity)`.
Averaging on read costs nothing and cannot cause the stored basis to drift.

---

## 4. Rebuild isolation, the same contract the whole app runs on

Rows are plain `StatelessWidget`s that watch nothing. Two live leaves inside
each row:

- **The LTP text** on the subtitle line ("Avg X · LTP Y") is in a
  `_LtpText` `ConsumerWidget` — separate from the static "Avg" so that a
  tick does not repaint the average.
- **The P&L column** on the right is a `ConsumerWidget` reading
  `quoteProvider(symbol)` and deriving both the current value and the P&L
  from the same `Quote`, so the two figures on a given frame cannot disagree.

The aggregate header is its own `ConsumerWidget` above the list.
Everything else — the sort bar, the row skeletons, the app bar — sits above
the tick path.

Sorting reorders the list by symbol key (`ValueKey<String>(symbol)`), so a
row that moves from "loss" to "gain" survives its move with its own price
subscription intact — same principle as the watchlist reorder proof in
[`implementations/watchlist.md`](watchlist.md) §3.

---

## 5. Aggregate == sum of visible rows, structurally

`holdingsAggregateProvider` and every row's P&L leaf both read from the same
`snapshotProvider`. The provider dependency guarantees they observe the same
frame — the aggregate cannot lag a row, and a row cannot lag the aggregate.

`test/widget/holdings_binding_test.dart` walks a sequence of ticks and, after
each one, sums the visible rows' P&L manually and asserts equality with the
aggregate. This is the "aggregate == sum" PRD guarantee turned into a repeated
invariant, not a one-time equality check.

---

## 6. Sort — reactive, not once at build time

`sortedHoldingsProvider` reads the current snapshot when the active sort is
`pnl` or `value`. A price tick therefore causes the provider to re-run and
the list to reorder. The widget test proves a row crossing from loss into
gain moves — TCS from bottom to top after a favourable tick.

Sort by symbol is the trivial case: `holdingsProvider` already returns a
symbol-sorted, immutable list, and the sort step is a no-op.

Sort is intentionally **not persisted**. The default (P&L descending) is the
one the PRD names; a hidden preference restored across launches would
surprise more than it helps for a small, always-visible control.

---

## 7. Design implementation and deviations

Followed: `trade_app_ui/holdings/`.

| Design | Implementation | Why |
|---|---|---|
| Aggregate row: label + big +₹ pill on a single line | Two label tiles (Invested, Current Value) plus a full-width P&L pill below | 375px cannot fit "Invested / Current Value / Overall P&L" comfortably on one line without truncating a lakh-scale number |
| Sort chips styled as pills with white/dark text switch | Same shape; active pill fills with `AppColors.accent`, inactive is bordered | Matches the accent used everywhere else for "active navigation" |
| P&L chip on the header carries an `arrow_downward` icon | Only the P&L sort chip carries the arrow, and only when active | The arrow signals *sort direction*; it makes no sense on Symbol or Value at this stage |
| Row subtitle: "Avg X • LTP Y" as one string | Split into a static "Avg X ·" and a ticking "LTP Y" text | A single ticking string would repaint the average glyphs on every tick; splitting keeps the average out of the tick path |
| No sort state in the design | P&L / Symbol / Value chip bar per PRD | Design omitted this; PRD requires it |
| Bottom bar shows a fourth "Funds" destination | Market / Watchlists / Holdings only | Per your standing instruction |
| Static header (no live subscription) | Live-updating from `holdingsAggregateProvider` | The whole point of the P&L pill is that it changes with the market |

**Holdings row taps** open the order ticket via `AppRoutes.openTicket`, so
pre-filling the ticket from a holding row is free — same helper both other
lists use.

---

## 8. Verification performed

- `flutter analyze` — clean under the existing strict lints.
- `flutter test` — **98 passing** (14 new: 10 derivation, 4 widget).
- **Ran in a browser at 375×812** and confirmed by interaction: (see §9)

| Test file | Guards |
|---|---|
| `test/data/position_derivation_test.dart` | Exact cost basis over many buys; proportional (not average-based) partial-sell reduction; full close drops the position; rebuy after close starts fresh; cross-symbol isolation; P&L sign preserved |
| `test/widget/holdings_binding_test.dart` | Empty state; **aggregate == sum of visible rows at every tick**; sort-by-P&L reorders live on a price move; full-close order removes the row |

---

## 9. Browser walkthrough

Verified in the running app:

- Empty state on first launch (before any orders) — icon, headline, "Explore
  market" button that navigates to `/market`.
- A buy through the ticket appears in Holdings on return: symbol, quantity,
  average cost, live LTP, current value, P&L in ₹ and %.
- Aggregate `Invested` / `Current Value` / `Overall P&L` row visible above,
  live-ticking, colour flipping with sign.
- Sort chips switch order without dropping any row's ticking subscription;
  P&L default is descending.
- A partial sell reduces the row's quantity and adjusts `totalCost`
  proportionally; the new average holds.
- A sell that closes the position removes the row from the list; empty
  state returns if it was the only holding.
- A full page reload rebuilds all positions from the persisted order history
  — no separate Holdings storage.

---

## 10. Known gaps / deliberate deferrals

- **Realised P&L is not surfaced.** The PRD only requires unrealised P&L
  against LTP; realised P&L on sells could be computed from the order log
  when needed and would live on the Order page (if one is added), not here.
- **No sparkline or intraday chart.** The feed has no historical series — same
  reasoning as the market and watchlist screens.
- **Sort direction is fixed:** P&L defaults descending, Symbol ascending,
  Value descending. A press on the active chip could flip direction; deferred
  since the design didn't call for it and the PRD only names one default.
- **No golden tests.**

---

## 11. All four features are now complete

Handoff for the whole take-home is done. The remaining unrelated items
(handled elsewhere) are the `Home` dashboard tab (deliberately not touched),
light theme (out of scope), and any real backend (out of scope).
