import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/money/money_format.dart';
import '../../../core/widgets/flash_on_change.dart';
import '../../../data/models/quote.dart';
import '../../../market/market_providers.dart';
import '../../../market/stock_universe.dart';

/// One instrument in the market list.
///
/// Deliberately a plain [StatelessWidget] that watches nothing. The left side
/// — symbol and company name — is static for the life of the row. Only
/// [_LivePriceColumn] subscribes to the feed, so a tick repaints two lines of
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                _LivePriceColumn(symbol: stock.symbol),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The only part of a market row that is subscribed to the feed.
class _LivePriceColumn extends ConsumerWidget {
  const _LivePriceColumn({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Quote? quote = ref.watch(quoteProvider(symbol));
    if (quote == null) {
      return const SizedBox(width: 96);
    }

    final Color changeColor = AppColors.forSign(
      isNegative: quote.change.isNegative,
      isZero: quote.change.isZero,
    );

    return FlashOnChange(
      triggerSequence: quote.sequence,
      direction: quote.direction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            MoneyFormat.rupees(quote.ltp),
            style: AppTypography.labelNumeric,
          ),
          const SizedBox(height: AppSpacing.vTight / 2),
          Text(
            '${MoneyFormat.signedRupees(quote.change)} '
            '(${MoneyFormat.percent(quote.changePercent)})',
            style: AppTypography.bodyNumericSm.copyWith(color: changeColor),
          ),
        ],
      ),
    );
  }
}
