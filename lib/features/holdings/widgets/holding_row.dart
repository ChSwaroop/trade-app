import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/models/position.dart';
import '../../../data/models/quote.dart';
import '../../../market/market_providers.dart';
import '../../../market/stock_universe.dart';

/// One holdings row.
///
/// Same contract as `MarketRow` and `WatchlistRow`: a plain [StatelessWidget]
/// that watches nothing, with the live surface isolated in a single
/// [_HoldingPnlColumn] leaf. Sorting reorders the list without triggering
/// per-row rebuilds — each row survives its move with its own price
/// subscription intact.
class HoldingRow extends StatelessWidget {
  const HoldingRow({
    required this.position,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final Position position;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Stock stock = StockUniverse.bySymbol(position.symbol);

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
              horizontal: AppSpacing.edge,
              vertical: AppSpacing.gutter,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              stock.symbol,
                              style: AppTypography.titleSm,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.unit * 2),
                          Text(
                            '${position.quantity} Qty',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.vTight / 2),
                      // Only the LTP half of this line is live; the average
                      // is static for the life of the position, so the whole
                      // subtitle would still rebuild on every tick if it were
                      // in one Text. Split so the average text is const.
                      _AvgAndLtp(
                        symbol: position.symbol,
                        averageCost: position.averageCost,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.gutter),
                _HoldingPnlColumn(position: position),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The static "Avg …" text sits alongside a live LTP watcher. Splitting them
/// this way keeps the average out of the tick path — a subtitle that says
/// "Avg X · LTP Y" as one string would rebuild every tick to redraw a value
/// that never changes.
class _AvgAndLtp extends StatelessWidget {
  const _AvgAndLtp({required this.symbol, required this.averageCost});

  final String symbol;
  final Money averageCost;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppTypography.bodySm.copyWith(
      color: AppColors.onSurfaceVariant,
    );
    return Row(
      children: <Widget>[
        Text('Avg ${MoneyFormat.rupees(averageCost)} · ', style: style),
        _LtpText(symbol: symbol, style: style),
      ],
    );
  }
}

class _LtpText extends ConsumerWidget {
  const _LtpText({required this.symbol, required this.style});

  final String symbol;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Money? ltp =
        ref.watch(quoteProvider(symbol).select((Quote? q) => q?.ltp));
    return Text(
      ltp == null ? 'LTP —' : 'LTP ${MoneyFormat.rupees(ltp)}',
      style: style,
    );
  }
}

/// The live current-value + P&L block on the right of the row.
///
/// Watches `quoteProvider` and derives both figures from the same [Quote],
/// so the number in blue and the number below it can never disagree with
/// each other on a given frame.
class _HoldingPnlColumn extends ConsumerWidget {
  const _HoldingPnlColumn({required this.position});

  final Position position;

  static const double _minWidth = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Quote? quote = ref.watch(quoteProvider(position.symbol));
    if (quote == null) return const SizedBox(width: _minWidth);

    final Money value = position.currentValue(quote.ltp);
    final Money pnl = position.unrealisedPnl(quote.ltp);
    final Color pnlColor = AppColors.forSign(
      isNegative: pnl.isNegative,
      isZero: pnl.isZero,
    );

    return SizedBox(
      width: _minWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            MoneyFormat.rupees(value),
            style: AppTypography.labelNumeric,
          ),
          const SizedBox(height: AppSpacing.vTight / 2),
          Text(
            '${MoneyFormat.signedRupees(pnl)} '
            '(${MoneyFormat.signedPercent(position.unrealisedPnlPercent(quote.ltp))})',
            style: AppTypography.bodyNumericSm.copyWith(color: pnlColor),
          ),
        ],
      ),
    );
  }
}
