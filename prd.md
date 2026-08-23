Build a trading app with the 4 features below.
Stack

Flutter (stable channel)
App must run with flutter pub get && flutter run, no extra setup
No real backend you implement a mock market-data feed
Stocks

Use these 10 stocks throughout the app:

RELIANCE, TCS, INFY, HDFCBANK, ICICIBANK, SBIN, ITC, LT, BHARTIARTL, AXISBANK

Pick any reasonable starting prices.

What we look for

Clean, readable code
Sensible architecture and folder structure
Correct realtime behavior under load
Money/decimal handling
Error and edge-case handling
Thoughtful UI for dense data
Clear commit history
Feature 1: Watchlist

Users can create and manage multiple watchlists of stocks. Stocks within a watchlist can be reordered and removed. Watchlists persist across app restarts.

Requirements

Support multiple watchlists (create, rename, delete)
Add stocks via a picker showing the 10 available stocks
Reorder stocks within a watchlist via drag
Remove stocks from a watchlist
Each row shows: symbol, last price, change, change %
Live prices update in place
Watchlists and their contents persist across app restarts
Tapping a row opens the Buy/Sell ticket pre-filled with that stock
Expected scenarios

When the app restarts, previously saved watchlists and their stocks are restored
When a stock is reordered, its live price binding stays correct (no stale ticks shown for the wrong row)
When a stock is removed, it stops receiving price updates and is gone after restart
When two watchlists contain the same stock, both show identical live prices
When a watchlist is empty, an empty state is shown
When a watchlist row is tapped, the Buy/Sell ticket opens pre-filled with that stock
Feature 2: Live Prices Mimic

A continuously updating market overview surface showing live prices for the 10 stocks. You design the mock market-data feed that powers this and the rest of the app.

Requirements

Show live prices for the 10 stocks
Each row/cell shows: symbol, LTP, change, change %, brief flash on update (green up / red down)
The mock feed emits price ticks continuously at a realistic rate
Tick rate is configurable (debug setting or constant)
The feed is the single source of price data for the entire app
The screen remains smooth (no visible jank) as ticks arrive
Expected scenarios

When prices update, only the affected cells visibly change (others are not rebuilt unnecessarily)
When the screen is scrolled, updates continue smoothly
When tick rate is increased to a stress level (e.g., 5+ ticks/sec per stock = 50+ ticks/sec overall), the UI does not freeze or drop frames noticeably
When a price moves up vs down, the flash color/direction differs
When the user navigates away and returns, prices are current (not stale from when they left)
Feature 3: Buy/Sell Ticket

A form to place a simulated market buy or sell order for a single stock. The order executes at the current LTP at the moment of submission. Validates against an in-memory wallet/margin balance. Successful orders create or update a holding.

Requirements

Pre-fill stock when opened from a watchlist or holdings row
Inputs: side (Buy/Sell), quantity
Live LTP displayed on the ticket and updates in real time
Order value = quantity × LTP at submission time
Margin/balance check before submit (Buy) and quantity-held check (Sell)
Show validation errors inline
On submit: deduct from balance (Buy) or from holdings qty (Sell), record the order, navigate to a confirmation
Persist wallet balance and order history across app restarts
Expected scenarios

When LTP changes while the form is open, the displayed price and projected order value update in real time
When the user enters an order value greater than the available balance, submit is blocked with a clear error
When a Buy order succeeds, the wallet balance decreases by qty × LTP at submit and a holding is created or its average price is updated
When a Sell order is placed for more quantity than held, submit is blocked
When the user enters fractional/negative/zero quantity, validation prevents submit
When prices use decimals, math is precise (no floating-point drift visible to the user)
Feature 4: Holdings

Portfolio view showing all currently held stocks with live P&L. Each holding row updates in real time as prices change. Aggregates total P&L at the top.

Requirements

List of holdings with: symbol, quantity, avg cost, LTP, current value, P&L (₹ and %)
Live LTP and P&L updates as ticks arrive
Sortable by P&L, by symbol, by current value (default: P&L descending)
Aggregate summary at the top: total invested, current value, total P&L (₹ and %)
Tapping a row opens the Buy/Sell ticket pre-filled for that stock
Empty state when no holdings exist
Persist holdings across app restarts
Expected scenarios

When a Buy order is placed, it appears in Holdings (or updates the existing row's qty + avg cost)
When a Sell order reduces qty to zero, the holding is removed
When prices tick, P&L numbers update without re-fetching or re-rendering the entire list
When sorted by P&L, the order updates correctly as prices move (e.g., a row crossing from loss to gain reorders)
When the aggregate summary is shown, it equals the sum of individual rows at any moment
When all 10 stocks are held, scroll and updates remain smooth during ticks