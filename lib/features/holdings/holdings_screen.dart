import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/money/money_format.dart';
import '../../data/models/position.dart';
import 'holdings_providers.dart';
import 'widgets/holding_row.dart';

/// The portfolio: every open position with live P&L, and an aggregate above.
///
/// The screen is stateless and subscribes to nothing. Two children carry the
/// live subscriptions in isolation: [_AggregateHeader] watches
/// `holdingsAggregateProvider`, and each [HoldingRow]'s P&L column watches
/// only its own `quoteProvider`. A tick therefore repaints the header's
/// numbers and the affected row's P&L block — nothing else in the tree.
class HoldingsScreen extends ConsumerWidget {
  const HoldingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Position> positions = ref.watch(sortedHoldingsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.edge,
        title: Text(
          'Holdings',
          style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          if (positions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.edge),
              child: Center(
                child: Text(
                  '${positions.length} '
                  '${positions.length == 1 ? 'stock' : 'stocks'}',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: positions.isEmpty
          ? const _EmptyState()
          : Column(
              children: <Widget>[
                const _AggregateHeader(),
                const _SortBar(),
                Expanded(child: _HoldingsList(positions: positions)),
              ],
            ),
    );
  }
}

class _AggregateHeader extends ConsumerWidget {
  const _AggregateHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HoldingsAggregate agg = ref.watch(holdingsAggregateProvider);
    final Color pnlColor = AppColors.forSign(
      isNegative: agg.pnl.isNegative,
      isZero: agg.pnl.isZero,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.edge,
        AppSpacing.vStandard,
        AppSpacing.edge,
        AppSpacing.vStandard,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _AggregateTile(
                  label: 'INVESTED',
                  value: MoneyFormat.rupees(agg.invested),
                ),
              ),
              Expanded(
                child: _AggregateTile(
                  label: 'CURRENT VALUE',
                  value: MoneyFormat.rupees(agg.currentValue),
                  alignRight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gutter),
          Container(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            decoration: BoxDecoration(
              color: pnlColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: pnlColor.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Overall P&L', style: AppTypography.titleSm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      MoneyFormat.signedRupees(agg.pnl),
                      style: AppTypography.headlineMd.copyWith(color: pnlColor),
                    ),
                    const SizedBox(width: AppSpacing.unit * 2),
                    Text(
                      _percentLabel(agg.pnlPercent),
                      style: AppTypography.bodyNumericSm.copyWith(
                        color: pnlColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _percentLabel(Decimal? p) {
    if (p == null) return '';
    return '(${MoneyFormat.signedPercent(p)})';
  }
}

class _AggregateTile extends StatelessWidget {
  const _AggregateTile({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  final String label;
  final String value;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.vTight),
        Text(value, style: AppTypography.labelNumeric),
      ],
    );
  }
}

class _SortBar extends ConsumerWidget {
  const _SortBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HoldingsSort active = ref.watch(holdingsSortProvider);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.edge,
        vertical: AppSpacing.gutter,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final HoldingsSort sort in HoldingsSort.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.unit * 2),
              child: _SortChip(
                sort: sort,
                selected: sort == active,
                onTap: () =>
                    ref.read(holdingsSortProvider.notifier).set(sort),
              ),
            ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.sort,
    required this.selected,
    required this.onTap,
  });

  final HoldingsSort sort;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.hairline,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                sort.label,
                style: AppTypography.bodySm.copyWith(
                  color: selected ? AppColors.background : AppColors.onSurfaceVariant,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (selected && sort == HoldingsSort.pnl) ...<Widget>[
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_downward,
                  size: 14,
                  color: AppColors.background,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldingsList extends StatelessWidget {
  const _HoldingsList({required this.positions});

  final List<Position> positions;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: positions.length,
      itemBuilder: (BuildContext context, int index) {
        final Position position = positions[index];
        return HoldingRow(
          // Keyed by symbol, not index — this is what lets a row survive a
          // sort change with its own price subscription intact, the same
          // rule that keeps watchlist reorders from misbinding prices.
          key: ValueKey<String>(position.symbol),
          position: position,
          showDivider: index < positions.length - 1,
          onTap: () => AppRoutes.openTicket(context, position.symbol),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
                Icons.inventory_2_outlined,
                size: 36,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.edge + AppSpacing.unit),
            const Text('No holdings yet', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.unit * 2),
            Text(
              'Your buys will appear here with a live P&L against the current '
              'market price.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.edge * 2),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.market),
              icon: const Icon(Icons.leaderboard_outlined, size: 18),
              label: const Text('Explore market'),
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
