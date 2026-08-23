import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/live_prices/live_prices_screen.dart';
import 'placeholder_screen.dart';
import 'shell_scaffold.dart';

abstract final class AppRoutes {
  static const String market = '/market';
  static const String watchlists = '/watchlists';
  static const String holdings = '/holdings';
}

/// Three branches, one per bottom-navigation destination.
///
/// Each branch owns a navigator, so pushing a watchlist detail or an order
/// ticket keeps the bottom bar in place and leaves the other tabs' state
/// untouched.
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
              builder: (BuildContext context, GoRouterState state) => const LivePricesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.watchlists,
              builder: (BuildContext context, GoRouterState state) => const PlaceholderScreen(
                title: 'Watchlists',
                message: 'Watchlists arrive in the next feature.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.holdings,
              builder: (BuildContext context, GoRouterState state) => const PlaceholderScreen(
                title: 'Holdings',
                message: 'Holdings arrive after the order ticket.',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
