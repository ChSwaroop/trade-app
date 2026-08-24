import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/holdings/holdings_screen.dart';
import '../features/live_prices/live_prices_screen.dart';
import '../features/orders/order_confirmation_screen.dart';
import '../features/orders/order_ticket_screen.dart';
import '../features/watchlists/watchlist_detail_screen.dart';
import '../features/watchlists/watchlists_screen.dart';
import 'shell_scaffold.dart';

abstract final class AppRoutes {
  static const String market = '/market';
  static const String watchlists = '/watchlists';
  static const String holdings = '/holdings';

  /// Path parameter naming the watchlist on the detail route.
  static const String watchlistIdParam = 'watchlistId';

  /// Path parameter naming the instrument on the order ticket route.
  static const String symbolParam = 'symbol';

  /// Path parameter naming the placed order on the confirmation route.
  static const String orderIdParam = 'orderId';

  /// Pushes the ticket for [symbol] onto the current branch's stack, so the
  /// bottom bar stays put and back returns to whatever pushed the ticket.
  ///
  /// The ticket path is `<current-location>/ticket/<symbol>`, which nests it
  /// inside the branch's routes without any branch-aware routing table. That
  /// keeps the detail screen underneath a ticket opened from a watchlist row.
  static void openTicket(BuildContext context, String symbol) {
    final String path = GoRouterState.of(context).uri.path;
    context.push('$path/ticket/$symbol');
  }
}

/// Three branches, one per bottom-navigation destination.
///
/// Each branch owns a navigator, so pushing a watchlist detail or an order
/// ticket keeps the bottom bar in place and leaves the other tabs' state
/// untouched. The ticket + confirmation are attached under every branch so a
/// row in Market, Watchlists, or Holdings can all open them without switching
/// tabs.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.market,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (
        BuildContext context,
        GoRouterState state,
        StatefulNavigationShell navigationShell,
      ) =>
          ShellScaffold(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.market,
              builder: (BuildContext context, GoRouterState state) =>
                  const LivePricesScreen(),
              routes: _ticketRoutes(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.watchlists,
              builder: (BuildContext context, GoRouterState state) =>
                  const WatchlistsScreen(),
              routes: <RouteBase>[
                // Nested so the detail screen keeps the bottom bar and the
                // back stack belongs to the Watchlists branch. The ticket
                // route lives under detail rather than beside it so that
                // `/watchlists/ticket/...` cannot be parsed as a watchlist id.
                GoRoute(
                  path: ':${AppRoutes.watchlistIdParam}',
                  builder: (BuildContext context, GoRouterState state) =>
                      WatchlistDetailScreen(
                    watchlistId:
                        state.pathParameters[AppRoutes.watchlistIdParam]!,
                  ),
                  routes: _ticketRoutes(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.holdings,
              builder: (BuildContext context, GoRouterState state) =>
                  const HoldingsScreen(),
              routes: _ticketRoutes(),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Ticket + confirmation, mounted under each branch so navigating to one from
/// a market row, a watchlist row, or (later) a holdings row all keep the
/// current tab and its back stack.
List<RouteBase> _ticketRoutes() => <RouteBase>[
      GoRoute(
        path: 'ticket/:${AppRoutes.symbolParam}',
        builder: (BuildContext context, GoRouterState state) =>
            OrderTicketScreen(
          symbol: state.pathParameters[AppRoutes.symbolParam]!,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'confirmed/:${AppRoutes.orderIdParam}',
            builder: (BuildContext context, GoRouterState state) =>
                OrderConfirmationScreen(
              orderId: state.pathParameters[AppRoutes.orderIdParam]!,
            ),
          ),
        ],
      ),
    ];
