import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../data/models/order.dart';
import '../../data/models/quote.dart';
import '../../data/repositories/order_repository.dart';
import '../../market/market_providers.dart';
import '../../market/stock_universe.dart';
import 'orders_providers.dart';

/// The buy/sell ticket for one instrument.
///
/// The header LTP keeps ticking while the user chooses a quantity. The order
/// fills at the price current in the store at the moment of submission — not
/// at whatever the header last painted — so a tick landing between "tap
/// submit" and "compute fill" is captured, not lost.
class OrderTicketScreen extends ConsumerStatefulWidget {
  const OrderTicketScreen({required this.symbol, super.key});

  final String symbol;

  @override
  ConsumerState<OrderTicketScreen> createState() => _OrderTicketScreenState();
}

class _OrderTicketScreenState extends ConsumerState<OrderTicketScreen> {
  OrderSide _side = OrderSide.buy;
  int _quantity = 1;

  static const List<int> _quickChips = <int>[10, 25, 50, 100];

  bool get _knownSymbol => StockUniverse.contains(widget.symbol);

  @override
  Widget build(BuildContext context) {
    // The route is reachable only from inside the app, but a stale deep link
    // could still land here for a symbol that is not in the universe.
    if (!_knownSymbol) return _UnknownSymbolScreen(symbol: widget.symbol);

    final Stock stock = StockUniverse.bySymbol(widget.symbol);
    final Quote? quote = ref.watch(quoteProvider(widget.symbol));
    final Money balance = ref.watch(walletBalanceProvider);
    final int held = ref.watch(positionQtyProvider(widget.symbol));

    final _Validation validation = _validate(
      side: _side,
      quantity: _quantity,
      price: quote?.ltp,
      balance: balance,
      heldQty: held,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => _closeTicket(context),
        ),
        title: Text(
          stock.symbol,
          style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TicketHeader(stock: stock, quote: quote),
            const SizedBox(height: AppSpacing.vStandard),
            _SideToggle(
              side: _side,
              onChanged: (OrderSide next) => setState(() => _side = next),
            ),
            const SizedBox(height: AppSpacing.edge),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.edge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _QuantityInput(
                      quantity: _quantity,
                      hasError: validation.failure != null,
                      onChanged: (int next) => setState(() => _quantity = next),
                    ),
                    if (validation.failure != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.unit * 2),
                      _InlineError(message: _messageFor(validation, balance, held)),
                    ],
                    const SizedBox(height: AppSpacing.vStandard),
                    _QuickChips(
                      onPick: (int add) => setState(
                        () => _quantity = (_quantity + add)
                            .clamp(1, OrderRepository.maxQuantity),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.edge + AppSpacing.unit),
                    _SummaryBlock(
                      quantity: _quantity,
                      symbol: widget.symbol,
                      balance: balance,
                      side: _side,
                      heldQty: held,
                    ),
                  ],
                ),
              ),
            ),
            _SubmitFooter(
              side: _side,
              enabled: validation.failure == null,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final OrderResult result = ref.read(ordersProvider.notifier).submit(
          symbol: widget.symbol,
          side: _side,
          quantity: _quantity,
        );
    if (result.failure != null) {
      _showFailure(result.failure!);
      return;
    }
    // Confirmation replaces the ticket in the branch's stack: back should go
    // to whatever pushed the ticket, not back to the ticket.
    final String path = GoRouterState.of(context).uri.path;
    context.pushReplacement('$path/confirmed/${result.order!.id}');
  }

  void _showFailure(OrderFailure failure) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }

  void _closeTicket(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.market);
    }
  }

  String _messageFor(_Validation v, Money balance, int held) {
    switch (v.failure!) {
      case OrderFailure.invalidQuantity:
        return 'Enter a quantity of at least 1';
      case OrderFailure.quantityTooLarge:
        return 'Maximum ${OrderRepository.maxQuantity} per order';
      case OrderFailure.insufficientBalance:
        final Money short = v.shortBy ?? Money.zero;
        return 'Insufficient balance — short by ${MoneyFormat.rupees(short)}';
      case OrderFailure.insufficientHoldings:
        return 'You only hold $held ${widget.symbol}';
      case OrderFailure.priceUnavailable:
        return 'Waiting for a live price';
      case OrderFailure.unknownSymbol:
        return 'That stock is not tradable here';
    }
  }
}

/// Live-computed pre-check. Mirrors the notifier's rules so the submit button
/// can be disabled without a round-trip. The notifier remains the source of
/// truth at submit time — its price read may see a newer tick than this one.
class _Validation {
  const _Validation({this.failure, this.shortBy});

  const _Validation.ok() : this();

  final OrderFailure? failure;
  final Money? shortBy;
}

_Validation _validate({
  required OrderSide side,
  required int quantity,
  required Money? price,
  required Money balance,
  required int heldQty,
}) {
  if (quantity <= 0) {
    return const _Validation(failure: OrderFailure.invalidQuantity);
  }
  if (quantity > OrderRepository.maxQuantity) {
    return const _Validation(failure: OrderFailure.quantityTooLarge);
  }
  if (price == null) {
    return const _Validation(failure: OrderFailure.priceUnavailable);
  }
  final Money value = price * quantity;
  switch (side) {
    case OrderSide.buy:
      if (value > balance) {
        return _Validation(
          failure: OrderFailure.insufficientBalance,
          shortBy: value - balance,
        );
      }
    case OrderSide.sell:
      if (quantity > heldQty) {
        return const _Validation(failure: OrderFailure.insufficientHoldings);
      }
  }
  return const _Validation.ok();
}

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.stock, required this.quote});

  final Stock stock;
  final Quote? quote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.edge,
        AppSpacing.vStandard,
        AppSpacing.edge,
        AppSpacing.vStandard,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(stock.name, style: AppTypography.bodyMd),
                const SizedBox(height: 2),
                Text(
                  'NSE · EQ',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (quote != null) _HeaderPrice(quote: quote!),
        ],
      ),
    );
  }
}

class _HeaderPrice extends StatelessWidget {
  const _HeaderPrice({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final Color changeColor = AppColors.forSign(
      isNegative: quote.change.isNegative,
      isZero: quote.change.isZero,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(MoneyFormat.rupees(quote.ltp), style: AppTypography.labelNumeric),
        const SizedBox(height: 2),
        Text(
          '${MoneyFormat.signedRupees(quote.change)} '
          '(${MoneyFormat.percent(quote.changePercent)})',
          style: AppTypography.bodyNumericSm.copyWith(color: changeColor),
        ),
      ],
    );
  }
}

class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.side, required this.onChanged});

  final OrderSide side;
  final ValueChanged<OrderSide> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.edge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: <Widget>[
              _SidePill(
                label: 'BUY',
                colour: AppColors.buy,
                selected: side == OrderSide.buy,
                onTap: () => onChanged(OrderSide.buy),
              ),
              _SidePill(
                label: 'SELL',
                colour: AppColors.sell,
                selected: side == OrderSide.sell,
                onTap: () => onChanged(OrderSide.sell),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidePill extends StatelessWidget {
  const _SidePill({
    required this.label,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colour : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: AppTypography.titleSm.copyWith(
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityInput extends StatefulWidget {
  const _QuantityInput({
    required this.quantity,
    required this.hasError,
    required this.onChanged,
  });

  final int quantity;
  final bool hasError;
  final ValueChanged<int> onChanged;

  @override
  State<_QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<_QuantityInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.quantity}');
    _focusNode = FocusNode();
    // Select-all on focus so typing replaces the value in one tap — the point
    // of the edit-in-place UX is that a bad overshoot doesn't need backspaces.
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _QuantityInput old) {
    super.didUpdateWidget(old);
    // External changes (chips, +/- buttons) must reflect in the field, but
    // don't clobber the caret while the user is mid-edit.
    if (widget.quantity != old.quantity && !_focusNode.hasFocus) {
      final String next = '${widget.quantity}';
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      // Empty or zero on blur snaps back to 1 — never leave the field in a
      // state the validator rejects.
      final int parsed = int.tryParse(_controller.text) ?? 0;
      final int clamped = parsed < 1 ? 1 : parsed;
      if (clamped != widget.quantity) widget.onChanged(clamped);
      final String canonical = '$clamped';
      if (_controller.text != canonical) _controller.text = canonical;
    }
  }

  void _handleChanged(String raw) {
    if (raw.isEmpty) return; // Let the user clear before typing; commit on blur.
    final int parsed = int.tryParse(raw) ?? widget.quantity;
    final int clamped = parsed.clamp(1, OrderRepository.maxQuantity);
    if (clamped != parsed) {
      final String canonical = '$clamped';
      _controller.value = TextEditingValue(
        text: canonical,
        selection: TextSelection.collapsed(offset: canonical.length),
      );
    }
    if (clamped != widget.quantity) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor =
        widget.hasError ? AppColors.sell : AppColors.hairline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'QUANTITY',
          style: AppTypography.labelCaps
              .copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.unit * 2),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: widget.quantity > 1
                    ? () => widget.onChanged(widget.quantity - 1)
                    : null,
                icon: const Icon(Icons.remove),
                color: AppColors.onSurfaceVariant,
                tooltip: 'Decrease quantity',
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('ticket-quantity'),
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      '${OrderRepository.maxQuantity}'.length,
                    ),
                  ],
                  style: AppTypography.headlineMd,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: _handleChanged,
                  onSubmitted: (_) => _focusNode.unfocus(),
                ),
              ),
              IconButton(
                onPressed: widget.quantity < OrderRepository.maxQuantity
                    ? () => widget.onChanged(widget.quantity + 1)
                    : null,
                icon: const Icon(Icons.add),
                color: AppColors.onSurfaceVariant,
                tooltip: 'Increase quantity',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickChips extends StatelessWidget {
  const _QuickChips({required this.onPick});

  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < _OrderTicketScreenState._quickChips.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : AppSpacing.unit * 2,
              ),
              child: OutlinedButton(
                onPressed: () => onPick(_OrderTicketScreenState._quickChips[i]),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceVariant,
                  side: const BorderSide(color: AppColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                ),
                child: Text('+${_OrderTicketScreenState._quickChips[i]}'),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryBlock extends ConsumerWidget {
  const _SummaryBlock({
    required this.quantity,
    required this.symbol,
    required this.balance,
    required this.side,
    required this.heldQty,
  });

  final int quantity;
  final String symbol;
  final Money balance;
  final OrderSide side;
  final int heldQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching quoteProvider here means the projected value updates live as
    // the price ticks, matching the LTP shown in the header.
    final Quote? quote = ref.watch(quoteProvider(symbol));
    final Money? projected =
        quote == null ? null : quote.ltp * quantity;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.hairline, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.edge),
        child: Column(
          children: <Widget>[
            _SummaryRow(
              label: quote == null
                  ? 'Order Value'
                  : 'Order Value ($quantity × ${MoneyFormat.rupees(quote.ltp)})',
              value: projected == null
                  ? '—'
                  : MoneyFormat.rupees(projected),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.gutter),
              child: Divider(height: 0.5),
            ),
            _SummaryRow(
              label:
                  side == OrderSide.buy ? 'Available Balance' : 'Holdings',
              value: side == OrderSide.buy
                  ? MoneyFormat.rupees(balance)
                  : '$heldQty ${heldQty == 1 ? 'unit' : 'units'}',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.gutter),
        Text(value, style: AppTypography.labelNumeric),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.error_outline, size: 16, color: AppColors.sell),
        const SizedBox(width: AppSpacing.unit),
        Expanded(
          child: Text(
            message,
            style: AppTypography.bodySm.copyWith(color: AppColors.sell),
          ),
        ),
      ],
    );
  }
}

class _SubmitFooter extends StatelessWidget {
  const _SubmitFooter({
    required this.side,
    required this.enabled,
    required this.onSubmit,
  });

  final OrderSide side;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final Color colour = side == OrderSide.buy ? AppColors.buy : AppColors.sell;
    final String label =
        side == OrderSide.buy ? 'PLACE BUY ORDER' : 'PLACE SELL ORDER';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.edge),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(
          top: BorderSide(color: AppColors.hairline, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: enabled ? onSubmit : null,
          style: FilledButton.styleFrom(
            backgroundColor: colour,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surface,
            disabledForegroundColor: AppColors.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
          ),
          child: Text(
            label,
            style:
                AppTypography.titleSm.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _UnknownSymbolScreen extends StatelessWidget {
  const _UnknownSymbolScreen({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.market),
        ),
        title: const Text('Order', style: AppTypography.headlineMd),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge * 2),
          child: Text(
            '$symbol is not tradable here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

