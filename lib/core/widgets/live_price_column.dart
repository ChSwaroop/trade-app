import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/quote.dart';
import '../../market/market_providers.dart';
import 'flash_on_change.dart';
import '../money/money_format.dart';

/// Last traded price and change for one instrument, flashing on each tick.
///
/// This is the app's only price subscriber. Every list — market, watchlist,
/// holdings — is built from plain widgets that watch nothing, with one of
/// these at the leaf. A tick therefore repaints two lines of text instead of
/// rebuilding a row, a list, or a screen, and the isolation is enforced by
/// `test/widget/rebuild_isolation_test.dart`.
class LivePriceColumn extends ConsumerWidget {
  const LivePriceColumn({required this.symbol, super.key});

  final String symbol;

  /// Reserved width for the placeholder, so a row's layout does not shift when
  /// the first quote arrives.
  static const double _minWidth = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Quote? quote = ref.watch(quoteProvider(symbol));
    if (quote == null) {
      return const SizedBox(width: _minWidth);
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
