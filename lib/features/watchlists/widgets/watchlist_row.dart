import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/live_price_column.dart';
import '../../../market/stock_universe.dart';

/// One instrument inside a watchlist.
///
/// Same contract as `MarketRow`: a plain [StatelessWidget] that watches
/// nothing, with the live price isolated in a single leaf. The row is
/// identified by symbol, never by index, which is what makes reordering safe —
/// there is no index-to-price binding that a move could invalidate.
class WatchlistRow extends StatelessWidget {
  const WatchlistRow({
    required this.symbol,
    required this.index,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String symbol;

  /// Position in the list, needed only to start a drag.
  final int index;

  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Stock stock = StockUniverse.bySymbol(symbol);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: showDivider
              ? const Border(
                  bottom: BorderSide(color: AppColors.hairline, width: 0.5),
                )
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          highlightColor: AppColors.surfaceHighlight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.edge,
              vertical: AppSpacing.gutter,
            ),
            child: Row(
              children: <Widget>[
                // The reference design reveals the drag handle on hover, which
                // does not exist on touch. On a phone it has to be permanently
                // visible or reordering is undiscoverable.
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.gutter),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        stock.symbol,
                        style: AppTypography.titleSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.vTight / 2),
                      Text(
                        stock.name,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.gutter),
                LivePriceColumn(symbol: symbol),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
