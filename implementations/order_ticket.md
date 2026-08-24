# Feature: Buy/Sell Order Ticket — COMPLETE

**PRD feature:** 3 (Buy/Sell Ticket)
**Status:** Done. `flutter analyze` clean, 84 tests passing, verified running in a browser.
**Date:** 2026-08-24
**Prerequisite reading:** [`implementations/market.md`](market.md) — the price
pipeline this feature reads at submit time — and
[`implementations/watchlist.md`](watchlist.md) — the persistence, notifier, and
row-tap conventions this feature reuses verbatim.

---

## 1. What was built

| Layer | Files | Notes |
|---|---|---|
| Model | `lib/data/models/order.dart` | Immutable, uuid identity, JSON round-trip |
| Repository | `lib/data/repositories/order_repository.dart` | Orders **and** wallet balance in one document |
| State | `lib/features/orders/orders_providers.dart` | Every rule + write-through; also exposes `positionQty` for Holdings to build on |
| Screens | `lib/features/orders/order_ticket_screen.dart`, `order_confirmation_screen.dart` | |
| Routing | `lib/app/router.dart` | `ticket/:symbol` + `confirmed/:orderId` mounted under **every** branch |
| Row taps | `market_row.dart` and `watchlist_row.dart` now push `/…/ticket/:symbol` via `AppRoutes.openTicket` |

`PlaceholderScreen` still backs Holdings — that is Feature 4.

---

## 2. Storage — a second document on the same `JsonStore`

The trading ledger is one document under key `trading` with `schemaVersion: 1`,
holding **both** the order history and the wallet balance:

```json
{ "orders": [ ...Order.toJson() ], "balance": "472578.58" }
```

Two things are worth stating explicitly:

1. **Orders and balance move together.** Every fill both appends an order and
   moves the balance — persisting them in the same write is what makes a crash
   between the two impossible. A separate `WalletRepository` would have been
   two writes and one race.
2. **A garbled balance falls back to the seed, not to zero.** Zero would
   silently block every subsequent buy. Losing history is recoverable; making
   the app permanently un-buyable is not — same principle
   [`implementations/watchlist.md`](watchlist.md) §2 applies to `JsonStore`.

Adding another persisted document remains a one-line schemaVersion bump plus a
new repository, per the pattern established for watchlists.

---

## 3. The requirement this feature turns on

> *"When LTP changes while the form is open, the displayed price and projected
> order value update in real time — but the order fills at the LTP at the
> moment of submission."*

`OrdersNotifier.submit` never accepts a price argument. It calls
`ref.read(priceStoreProvider).priceOf(symbol)` **inside** `submit` — the
synchronous read documented in [`implementations/market.md`](market.md) §4.
Whatever the header last painted is irrelevant to what fills.

`test/widget/order_ticket_test.dart` locks this down. It uses two independent
surfaces: `FakeSnapshots` drives what the UI paints, a `_TestPriceStore`
whose `priceOf` can be pinned drives what the notifier reads. The headline
test pumps a snapshot at price P1, pins the store to P2 **without** pumping a
new snapshot, taps submit, and asserts the fill == P2. This is the analogue of
`test/widget/watchlist_binding_test.dart`.

The real app made the same case visible in the browser: `26 × ₹1,057.28` was
rendered in the summary; submit landed on `26 × ₹1,054.67`, because the store
had ticked between paint and tap. The confirmation shows the executed price.

---

## 4. Rules

All validation lives in `OrdersNotifier.submit` and returns an `OrderFailure`
enum — nothing throws. The ticket UI pre-checks the same predicates to disable
the submit button, but the notifier remains the source of truth because its
price read may see a newer tick than the UI's.

| Rule | Failure |
|---|---|
| Unknown symbol | `unknownSymbol` |
| Quantity ≤ 0 or non-integer | `invalidQuantity` (`int` type enforces integrality) |
| Quantity > per-order cap (100 000) | `quantityTooLarge` |
| Feed has no price for the symbol yet | `priceUnavailable` — must not crash |
| Buy: value > balance | `insufficientBalance` |
| Sell: quantity > current net position | `insufficientHoldings` |

**Wallet seed:** ₹5,00,000 — comfortably above the priciest starting price ×
any sensible quantity, so a fresh install can actually place an order.

**Positions are derived from the order history**, not persisted separately.
`positionQty(orders, symbol)` sums buys and subtracts sells over the order
list, and `positionQtyProvider.family(String)` is the same function watched
reactively. Holdings in Feature 4 will build on top — same aggregation,
extended with cost basis (see §7).

### Persistence timing

Same shape as `WatchlistsNotifier`: state updates synchronously, the write is
**chained** onto `_writes = _writes.then(...)`, and `notifier.settled` is
exposed for tests. Back-to-back submits therefore land on disk in the order
they were made.

---

## 5. Routing — nested under every branch, no shell switch

`/ticket/:symbol` and `/ticket/:symbol/confirmed/:orderId` are mounted under
each of the three shell branches (Market, Watchlists → detail, Holdings). A
single `AppRoutes.openTicket(context, symbol)` does the right thing without a
branch-aware routing table:

```dart
static void openTicket(BuildContext context, String symbol) {
  final String path = GoRouterState.of(context).uri.path;
  context.push('$path/ticket/$symbol');
}
```

- From `/market` → `/market/ticket/RELIANCE`.
- From `/watchlists/{id}` → `/watchlists/{id}/ticket/RELIANCE`, so the
  detail screen stays under the ticket in the branch's back stack.
- From `/holdings` (Feature 4) → `/holdings/ticket/RELIANCE`.

The ticket route is **not** mounted at the `/watchlists` level so that
`ticket` cannot be parsed as a `:watchlistId`. Confirmation is pushed with
`context.pushReplacement` from a path relative to the current location, so
"Done" pops back to whatever originally opened the ticket, not to the ticket.

---

## 6. Design implementation and deviations

Followed: `order_ticket_buy`, `order_ticket_invalid`, `order_confirmation`.

| Design | Implementation | Why |
|---|---|---|
| Two selects: **Order Type** (Market/Limit) and **Product** (Delivery/Intraday) | Both omitted | The PRD only supports a market order; the design's Limit and Intraday inputs are all disabled in the "invalid" mockup as well. Leaving them in the UI would be theatre. |
| Header shows a static change badge ("+1.2%") | Live-ticking change and change % coloured for direction | The rest of the app treats the header LTP as live; treating it as a still is inconsistent |
| Invalid-state footer shows "MARGIN REQ." and the SELL button reads "BUY" while disabled | Footer is the primary action button; label matches the side; disabled state greys out and drops the shadow | The design's mockup contradicts itself (BUY tab active + BUY button disabled + "Insufficient balance" error) — reading the intent rather than the pixel |
| Post-fill screen has a hardcoded `24 Oct, 11:32 AM` timestamp and `#TRD-992103` order id | Actual timestamp (local) and the first uuid segment | Same reason a static change badge doesn't fit |
| Confirmation card includes "Order Type: Market / Delivery" | Omitted | Feeds off the two omitted selects; carries no information |
| Header shows "NSE • EQ" in the invalid mockup, company name in the valid mockup | Company name **and** "NSE · EQ" | Both are useful on a form the user might spend a few seconds staring at |
| Bottom bars in some designs include other destinations | Market / Watchlists / Holdings only | Per your instruction |

**Row taps** in both `MarketRow` and `WatchlistRow` now push the ticket
through `AppRoutes.openTicket`, so the placeholder `onTap` callbacks noted in
[`implementations/watchlist.md`](watchlist.md) §8 are resolved.

---

## 7. Carry-forward for Holdings (Feature 4)

- `positionQty(orders, symbol)` in `orders_providers.dart` already computes
  the signed net position. Holdings will reuse it and extend to a full
  position map keyed by symbol.
- **Cost basis rule from [`implementations/market.md`](market.md) §3 still
  applies unchanged.** Persist `totalCost` alongside `qty`; derive the
  average; on a partial sell reduce `totalCost` proportionally as an exact
  rational. `Money.divideBy` and the `Rational → Decimal` guard cover that
  arithmetic today.
- Because orders are the single source of truth, Holdings can be *derived*
  reactively from `ordersProvider` (a Riverpod computed provider) rather than
  a separately-mutated store. That is what makes "when a Buy appears in
  Holdings" free — no wiring to remember to invoke.
- The confirmation screen already navigates to `/holdings` on "View
  Holdings", so its landing page is the next thing to build.

---

## 8. Verification performed

- `flutter analyze` — clean under the existing strict lints.
- `flutter test` — **84 passing** (23 new: 6 repository, 13 notifier, 4 widget).
- **Ran in a browser at 375×812** and confirmed by interaction:
  - Tapped a `MarketRow` for ICICIBANK → ticket opened, bottom bar preserved,
    live LTP + change ticking in the header.
  - `+25` chip drove quantity to 26, order value block updated live to
    `26 × ₹1,057.28 = ₹27,489.28`.
  - Submitted → confirmation shows fill at `₹1,054.67` — a *different* price
    from the last-rendered `₹1,057.28`, exactly the behaviour the headline
    test asserts. Total value on the card is 26 × the fill price, not the
    rendered price.
  - Balance on the next ticket open was `₹4,72,578.58` (= 5,00,000 − 27,421.42).
  - Tapped an `ICICIBANK` row inside `My Watchlist` → ticket opened with
    the **Watchlists** tab still selected; SELL toggle turned the accent red;
    entering `101` surfaced "You only hold 26 ICICIBANK" inline and disabled
    the submit button.
  - **Full page reload**: balance and holdings both intact — SELL with
    quantity 1 was re-enabled with "Holdings: 26 units" showing.

| Test file | Guards |
|---|---|
| `test/data/order_repository_test.dart` | Seed on first run; round-trip; schema-mismatch reset; malformed order dropped; garbled balance reset (not silently zeroed); ids unique |
| `test/features/orders_notifier_test.dart` | Every rule in §4; fills use the store price at submit, not any earlier read; buy debits and sell credits are exact; write-through survives a simulated relaunch; ordered writes |
| `test/widget/order_ticket_test.dart` | **Headline test: submitting while the price ticks fills at the price current at submit, not the price first rendered**; live projected value; balance / holdings errors disable submit inline |

---

## 9. Known gaps / deliberate deferrals

- **Wallet balance is fungible cash**, not a margin construct — there is no
  intraday/delivery distinction, no leverage, no charges. The PRD asks for a
  "wallet/margin balance" and this is the simpler side of that.
- **No "you're about to spend ₹X, confirm?" step** on submit. The design does
  not include one, and the fill-at-submit rule means any confirmation dialog
  would either freeze the price (contradicting the requirement) or race it
  (contradicting itself).
- The confirmation screen's "View Holdings" button lands on the current
  Holdings placeholder. When Feature 4 replaces it, this link starts working
  without any change here.
- No golden tests.
- No sorting or filtering of the order history — there is no "Orders" screen
  yet. When one lands, it should watch `ordersProvider` and reuse the same
  `MoneyFormat.rupees` conventions.

---

## 10. Next feature

**Feature 4: Holdings.** It should:

1. Add a `Position` derivation over `ordersProvider` that computes `qty` and
   `totalCost` per symbol, treating a partial sell as
   `newTotalCost = totalCost × (remainingQty / originalQty)` — never
   `avgCost × qtySold` (see §7).
2. Persist the *derived* Positions **or** keep them purely derived — the
   ledger already survives a restart, so a derived-only Positions layer is
   the simpler design. Pick that unless a real reason emerges.
3. Reuse `LivePriceColumn` for the per-row LTP and add a per-row P&L leaf
   that reads only `quoteProvider(symbol)` + the position — same rebuild
   isolation contract as everywhere else in the app.
4. Wire `HoldingsRow.onTap` to `AppRoutes.openTicket(context, symbol)` to
   pre-fill the ticket for that instrument.
5. Design references: `trade_app_ui/holdings/`.
