import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

/// Bottom-navigation chrome wrapping the three primary destinations.
///
/// Hosted by a [StatefulShellRoute] so each tab keeps its own navigator and
/// scroll position across switches. That is also what makes returning to a
/// screen show current prices rather than stale ones: the shared price store
/// never stopped ticking, and the tab simply re-reads it on the next frame.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      label: 'Market',
      icon: Icons.leaderboard_outlined,
      selectedIcon: Icons.leaderboard,
    ),
    _Destination(
      label: 'Watchlists',
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
    ),
    _Destination(
      label: 'Holdings',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          border: Border(
            top: BorderSide(color: AppColors.hairline, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AppSpacing.navBarHeight,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      destination: _destinations[i],
                      selected: navigationShell.currentIndex == i,
                      onTap: () => _goBranch(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping the already-selected tab pops that branch back to its root, which
  /// is the conventional behaviour and the only way back out of a watchlist
  /// detail without using the app bar.
  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.accent : AppColors.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: AppTypography.labelCaps.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
