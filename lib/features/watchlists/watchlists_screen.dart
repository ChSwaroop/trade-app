import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/watchlist.dart';
import 'watchlist_providers.dart';
import 'widgets/watchlist_name_dialog.dart';

/// The watchlist index: every list the user has, with create/rename/delete.
class WatchlistsScreen extends ConsumerWidget {
  const WatchlistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Watchlist> watchlists = ref.watch(watchlistsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.edge,
        title: Text(
          'Watchlists',
          style: AppTypography.headlineMd.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New watchlist',
            onPressed: () => _create(context, ref),
          ),
          const SizedBox(width: AppSpacing.unit),
        ],
      ),
      body: watchlists.isEmpty
          ? _EmptyState(onCreate: () => _create(context, ref))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.edge),
              itemCount: watchlists.length,
              itemBuilder: (BuildContext context, int index) => _WatchlistCard(
                key: ValueKey<String>(watchlists[index].id),
                watchlist: watchlists[index],
              ),
            ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final String? name = await WatchlistNameDialog.show(
      context,
      title: 'New watchlist',
      confirmLabel: 'Create',
    );
    if (name == null || !context.mounted) return;

    final ({WatchlistFailure? failure, String? id}) result =
        ref.read(watchlistsProvider.notifier).create(name);
    if (result.failure != null) {
      _report(context, result.failure!);
      return;
    }
    // Straight into the empty list — creating one is only ever a step toward
    // filling it.
    context.go('${AppRoutes.watchlists}/${result.id}');
  }
}

void _report(BuildContext context, WatchlistFailure failure) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(failure.message)));
}

class _WatchlistCard extends ConsumerWidget {
  const _WatchlistCard({required this.watchlist, super.key});

  final Watchlist watchlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: AppColors.hairline, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          child: InkWell(
            onTap: () =>
                context.go('${AppRoutes.watchlists}/${watchlist.id}'),
            highlightColor: AppColors.surfaceHighlight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.edge,
                AppSpacing.gutter,
                AppSpacing.unit,
                AppSpacing.gutter,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          watchlist.name,
                          style: AppTypography.titleSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.vTight / 2),
                        Text(
                          _subtitle(watchlist),
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _CardMenu(watchlist: watchlist),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _subtitle(Watchlist watchlist) {
    if (watchlist.isEmpty) return 'Empty · tap to add stocks';
    final String count =
        '${watchlist.length} ${watchlist.length == 1 ? 'stock' : 'stocks'}';
    return '$count · ${watchlist.symbols.take(3).join(', ')}'
        '${watchlist.length > 3 ? '…' : ''}';
  }
}

class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.watchlist});

  final Watchlist watchlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_CardAction>(
      icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
      color: AppColors.surfaceContainer,
      tooltip: 'Watchlist options',
      onSelected: (_CardAction action) => switch (action) {
        _CardAction.rename => _rename(context, ref),
        _CardAction.delete => _delete(context, ref),
      },
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<_CardAction>>[
        PopupMenuItem<_CardAction>(
          value: _CardAction.rename,
          child: Text('Rename'),
        ),
        PopupMenuItem<_CardAction>(
          value: _CardAction.delete,
          child: Text('Delete', style: TextStyle(color: AppColors.sell)),
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
    if (failure != null) _report(context, failure);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Deleting a watchlist is not undoable from a snackbar the way removing a
    // single symbol is, so it asks first.
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: AppColors.surfaceContainer,
            title: Text('Delete "${watchlist.name}"?', style: AppTypography.titleSm),
            content: const Text(
              'The watchlist and its stocks will be removed. Your holdings '
              'are not affected.',
              style: AppTypography.bodyMd,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.sell),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;
    ref.read(watchlistsProvider.notifier).delete(watchlist.id);
  }
}

enum _CardAction { rename, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.edge * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Icon(
                Icons.list_alt,
                size: 36,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.edge + AppSpacing.unit),
            const Text('No watchlists yet', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.unit * 2),
            Text(
              'Create one to start tracking your favourite stocks and keep an '
              'eye on market movements.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.edge * 2),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Watchlist'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.buy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.edge + AppSpacing.unit * 2,
                  vertical: AppSpacing.gutter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
