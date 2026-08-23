import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../market/market_providers.dart';
import '../../market/stock_universe.dart';
import '../debug/feed_settings_sheet.dart';
import 'widgets/market_row.dart';

/// The market overview: live prices for the whole universe.
///
/// The screen itself is stateless and subscribes to nothing. The list of
/// instruments is fixed reference data, so it is built once; each row wires up
/// its own price subscription. A tick therefore never reaches this widget.
class LivePricesScreen extends StatelessWidget {
  const LivePricesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const List<Stock> stocks = StockUniverse.all;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.edge,
        title: Row(
          children: <Widget>[
            const Icon(Icons.account_circle_outlined, size: 24),
            const SizedBox(width: AppSpacing.gutter),
            Text(
              'TradeDirect',
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Feed settings',
            onPressed: () => FeedSettingsSheet.show(context),
          ),
          const SizedBox(width: AppSpacing.unit),
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.edge,
              AppSpacing.edge,
              AppSpacing.edge,
              AppSpacing.vStandard,
            ),
            sliver: SliverToBoxAdapter(child: _MarketHeader()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.edge,
              0,
              AppSpacing.edge,
              AppSpacing.edge,
            ),
            sliver: SliverToBoxAdapter(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(color: AppColors.hairline, width: 0.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < stocks.length; i++)
                        MarketRow(
                          key: ValueKey<String>(stocks[i].symbol),
                          stock: stocks[i],
                          showDivider: i < stocks.length - 1,
                          onTap: () {
                            // Wired to the order ticket in a later feature.
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text('Market Feed', style: AppTypography.headlineMd),
        _FeedRateLabel(),
      ],
    );
  }
}

/// Replaces the reference design's static "NIFTY 50" caption with the live
/// feed rate, which makes the tick-rate setting observable from the screen it
/// affects.
class _FeedRateLabel extends ConsumerWidget {
  const _FeedRateLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int perStock =
        ref.watch(feedConfigProvider.select((c) => c.ticksPerSecondPerStock));
    final int total = perStock * StockUniverse.all.length;
    return Text(
      'NIFTY 50 · $total ticks/s',
      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
    );
  }
}
