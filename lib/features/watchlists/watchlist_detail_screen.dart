import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/watchlist.dart';
import 'watchlist_providers.dart';
import 'widgets/add_stocks_sheet.dart';
import 'widgets/watchlist_name_dialog.dart';
import 'widgets/watchlist_row.dart';

/// One watchlist: live prices, drag to reorder, swipe to remove.
class WatchlistDetailScreen extends ConsumerWidget {
  const WatchlistDetailScreen({required this.watchlistId, super.key});

  final String watchlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Watchlist? watchlist = ref.watch(watchlistByIdProvider(watchlistId));

    // The route can outlive its watchlist — deleted from the index while this
    // screen sits on the stack, or reached by a stale deep link.
    if (watchlist == null) return const _MissingWatchlist();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go(AppRoutes.watchlists),
        ),
        title: Text(
          watchlist.name,
          style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          Text(
            '${watchlist.length} '
            '${watchlist.length == 1 ? 'item' : 'items'}',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          _DetailMenu(watchlist: watchlist),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddStocksSheet.show(context, watchlistId),
        backgroundColor: AppColors.buy,
        foregroundColor: Colors.white,
        tooltip: 'Add stocks',
        child: const Icon(Icons.add),
      ),
      body: watchlist.isEmpty
          ? _EmptyWatchlist(
              onAdd: () => AddStocksSheet.show(context, watchlistId),
            )
          : Column(
              children: <Widget>[
                const _ColumnHeader(),
                Expanded(child: _SymbolList(watchlistId: watchlistId)),
              ],
            ),
    );
  }
}

/// Shows a snack bar lifted clear of the floating action button.
///
/// A floating snack bar is not laid out around the button, so the default
/// position clips it. Undo lives in these snack bars, so they cannot be allowed
/// to look broken.
void showDetailSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.edge,
          0,
          AppSpacing.edge,
          88,
        ),
      ),
    );
}

/// The reorderable body.
///
/// Watches only the symbol list, so renaming the watchlist — or any price tick
/// anywhere — cannot rebuild it.
class _SymbolList extends ConsumerWidget {
  const _SymbolList({required this.watchlistId});

  final String watchlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> symbols =
        ref.watch(watchlistSymbolsProvider(watchlistId));

    return ReorderableListView.builder(
      // The rows carry their own drag handles, matching the reference design
      // and leaving long-press free for other gestures.
      buildDefaultDragHandles: false,
      // Clears the floating action button so the last row's price is never
      // hidden behind it — a collision visible in the reference screenshot.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: symbols.length,
      onReorderItem: (int oldIndex, int newIndex) => ref
          .read(watchlistsProvider.notifier)
          .reorder(watchlistId, oldIndex, newIndex),
      proxyDecorator: _liftedRow,
      itemBuilder: (BuildContext context, int index) {
        final String symbol = symbols[index];
        return _RemovableRow(
          // Keyed by symbol, never by index: this is what lets a row survive a
          // reorder with its own price subscription intact.
          key: ValueKey<String>(symbol),
          watchlistId: watchlistId,
          symbol: symbol,
          index: index,
          showDivider: index < symbols.length - 1,
        );
      },
    );
  }

  /// The dragged row, lifted off the list. Flat by design-system rule, so it
  /// reads as raised through a lighter surface rather than a shadow.
  static Widget _liftedRow(Widget child, int index, Animation<double> _) {
    return Material(
      color: AppColors.surfaceHighlight,
      child: child,
    );
  }
}

class _RemovableRow extends ConsumerWidget {
  const _RemovableRow({
    required this.watchlistId,
    required this.symbol,
    required this.index,
    required this.showDivider,
    super.key,
  });

  final String watchlistId;
  final String symbol;
  final int index;
  final bool showDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey<String>('dismiss-$symbol'),
      direction: DismissDirection.endToStart,
      background: const _RemoveBackground(),
      onDismissed: (_) {
        final WatchlistsNotifier notifier =
            ref.read(watchlistsProvider.notifier);
        notifier.removeSymbol(watchlistId, symbol);

        // Undo restores the position, not just membership — a removal that
        // silently reshuffles the list is worse than no undo at all.
        showDetailSnackBar(
          context,
          '$symbol removed',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                notifier.insertSymbolAt(watchlistId, symbol, index),
          ),
        );
      },
      child: WatchlistRow(
        symbol: symbol,
        index: index,
        showDivider: showDivider,
        onTap: () => AppRoutes.openTicket(context, symbol),
      ),
    );
  }
}

class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.sell.withValues(alpha: 0.16),
      child: const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.edge),
          child: Icon(Icons.delete_outline, color: AppColors.sell),
        ),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppTypography.labelCaps.copyWith(
      color: AppColors.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.edge,
        vertical: AppSpacing.gutter,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('SYMBOL', style: style)),
          Text('LTP / CHG', style: style),
        ],
      ),
    );
  }
}

class _DetailMenu extends ConsumerWidget {
  const _DetailMenu({required this.watchlist});

  final Watchlist watchlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_DetailAction>(
      icon: const Icon(Icons.more_vert),
      color: AppColors.surfaceContainer,
      tooltip: 'Watchlist options',
      onSelected: (_DetailAction action) => switch (action) {
        _DetailAction.rename => _rename(context, ref),
        _DetailAction.clear => _clear(context, ref),
      },
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<_DetailAction>>[
        const PopupMenuItem<_DetailAction>(
          value: _DetailAction.rename,
          child: Text('Rename'),
        ),
        PopupMenuItem<_DetailAction>(
          value: _DetailAction.clear,
          enabled: !watchlist.isEmpty,
          child: const Text(
            'Remove all stocks',
            style: TextStyle(color: AppColors.sell),
          ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final String? name = await WatchlistNameDialog.show(
      context,
      title: 'Rename watchlist',
      confirmLabel: 'Save',
      initialValue: watchlist.name,
    );
    if (name == null || !context.mounted) return;

    final WatchlistFailure? failure =
        ref.read(watchlistsProvider.notifier).rename(watchlist.id, name);
    if (failure != null) showDetailSnackBar(context, failure.message);
  }

  void _clear(BuildContext context, WidgetRef ref) {
    final List<String> removed = watchlist.symbols;
    final WatchlistsNotifier notifier = ref.read(watchlistsProvider.notifier);
    for (final String symbol in removed) {
      notifier.removeSymbol(watchlist.id, symbol);
    }

    showDetailSnackBar(
      context,
      '${removed.length} stocks removed',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          for (int i = 0; i < removed.length; i++) {
            notifier.insertSymbolAt(watchlist.id, removed[i], i);
          }
        },
      ),
    );
  }
}

enum _DetailAction { rename, clear }

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.edge * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.playlist_add,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.edge),
            const Text('Nothing here yet', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.unit * 2),
            Text(
              'Add stocks to follow their prices live.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.edge + AppSpacing.unit),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add stocks'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingWatchlist extends StatelessWidget {
  const _MissingWatchlist();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.watchlists),
        ),
        title: const Text('Watchlist', style: AppTypography.headlineMd),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'This watchlist no longer exists.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.edge),
              FilledButton(
                onPressed: () => context.go(AppRoutes.watchlists),
                child: const Text('Back to watchlists'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
