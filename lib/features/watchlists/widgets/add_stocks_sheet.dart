import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/models/watchlist.dart';
import '../../../market/stock_universe.dart';
import '../watchlist_providers.dart';

/// Bottom sheet for adding and removing instruments in one place.
///
/// Toggling in place rather than closing on each pick is the difference
/// between adding five stocks in five taps and doing it in ten.
class AddStocksSheet extends StatefulWidget {
  const AddStocksSheet({required this.watchlistId, super.key});

  static Future<void> show(BuildContext context, String watchlistId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Above the shell's navigator, so the sheet and its scrim cover the
      // bottom bar instead of stopping short of it.
      useRootNavigator: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (BuildContext context) =>
          AddStocksSheet(watchlistId: watchlistId),
    );
  }

  final String watchlistId;

  @override
  State<AddStocksSheet> createState() => _AddStocksSheetState();
}

class _AddStocksSheetState extends State<AddStocksSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Stock> get _matches {
    final String query = _query.trim().toUpperCase();
    if (query.isEmpty) return StockUniverse.all;
    return StockUniverse.all
        .where(
          (Stock s) =>
              s.symbol.contains(query) || s.name.toUpperCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<Stock> matches = _matches;

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the
      // results the user is typing to find.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: <Widget>[
            const _SheetHeader(),
            _SearchField(
              controller: _controller,
              onChanged: (String value) => setState(() => _query = value),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const _NoMatches()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.edge),
                      itemCount: matches.length,
                      itemExtent: AppSpacing.listRowExtent,
                      itemBuilder: (BuildContext context, int index) =>
                          _PickerRow(
                        key: ValueKey<String>(matches[index].symbol),
                        stock: matches[index],
                        watchlistId: widget.watchlistId,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.edge,
        AppSpacing.gutter,
        AppSpacing.unit,
        AppSpacing.gutter,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.edge),
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('Add Stocks', style: AppTypography.titleSm),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                color: AppColors.onSurfaceVariant,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
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
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        style: AppTypography.bodyMd,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceHighlight,
          hintText: 'Search stocks (e.g. RELIANCE)',
          hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.muted),
          prefixIcon: const Icon(Icons.search, color: AppColors.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// One instrument in the picker.
///
/// Watches only its own membership: adding RELIANCE rebuilds the RELIANCE row
/// and nothing else in a ten-row sheet.
class _PickerRow extends ConsumerWidget {
  const _PickerRow({required this.stock, required this.watchlistId, super.key});

  final Stock stock;
  final String watchlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isAdded = ref.watch(
      watchlistByIdProvider(watchlistId).select(
        (Watchlist? w) => w?.contains(stock.symbol) ?? false,
      ),
    );

    void toggle() {
      final WatchlistsNotifier notifier =
          ref.read(watchlistsProvider.notifier);
      final WatchlistFailure? failure = isAdded
          ? notifier.removeSymbol(watchlistId, stock.symbol)
          : notifier.addSymbol(watchlistId, stock.symbol);

      if (failure != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }

    return InkWell(
      onTap: toggle,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.hairline, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.edge),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      stock.symbol,
                      style: AppTypography.titleSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              _ToggleIcon(isAdded: isAdded, symbol: stock.symbol),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.isAdded, required this.symbol});

  final bool isAdded;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    if (isAdded) {
      return Semantics(
        label: 'Remove $symbol',
        child: const Icon(Icons.check_circle, color: AppColors.buy),
      );
    }
    return Semantics(
      label: 'Add $symbol',
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.buy.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.add, size: 18, color: AppColors.buy),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.edge * 2),
        child: Text(
          'No stocks match that search.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
