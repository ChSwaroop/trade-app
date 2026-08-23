import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/live_price_column.dart';
import '../../../market/stock_universe.dart';

/// One instrument in the market list.
///
/// Deliberately a plain [StatelessWidget] that watches nothing. The left side
/// — symbol and company name — is static for the life of the row. Only
/// [LivePriceColumn] subscribes to the feed, so a tick repaints two lines of
/// text rather than rebuilding the row, the list, or the screen.
class MarketRow extends StatelessWidget {
  const MarketRow({
    required this.stock,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final Stock stock;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
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
              horizontal: AppSpacing.vListItem,
              vertical: AppSpacing.gutter,
            ),
            child: Row(
              children: <Widget>[
                // The name column flexes; the price column takes exactly the
                // width it needs. The reference design gave both columns an
                // equal flex, which truncated longer instrument names while
                // leaving dead space beside the price.
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
                LivePriceColumn(symbol: stock.symbol),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
