import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/money/money_format.dart';
import '../../data/models/order.dart';
import '../../market/stock_universe.dart';
import 'orders_providers.dart';

/// Success screen shown after a filled order. Reads the order back from the
/// ledger by id, so a refresh or deep link resolves to the same record rather
/// than depending on state passed through navigation.
class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Order? order = ref.watch(
      ordersProvider.select((Ledger l) {
        for (final Order o in l.orders) {
          if (o.id == orderId) return o;
        }
        return null;
      }),
    );

    if (order == null) return const _MissingOrder();

    final Stock stock = StockUniverse.bySymbol(order.symbol);
    final Color sideColor =
        order.isBuy ? AppColors.buy : AppColors.sell;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.edge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.edge),
              const Center(child: _SuccessBadge()),
              const SizedBox(height: AppSpacing.edge * 2),
              const Text(
                'Order Placed',
                style: AppTypography.displayLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.unit * 2),
              Text(
                'The fill has been recorded and your balance updated.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.edge * 2),
              Expanded(
                child: SingleChildScrollView(
                  child: _OrderCard(
                    order: order,
                    stock: stock,
                    sideColor: sideColor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.edge),
              FilledButton(
                onPressed: () => context.go(AppRoutes.holdings),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.buy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                ),
                child: const Text('View Holdings'),
              ),
              const SizedBox(height: AppSpacing.gutter),
              OutlinedButton(
                onPressed: () => _dismiss(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface,
                  side: const BorderSide(color: AppColors.hairline),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismiss(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.market);
    }
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.buy.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.buy.withValues(alpha: 0.3)),
      ),
      child: const Icon(Icons.check_circle, size: 44, color: AppColors.buy),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.stock,
    required this.sideColor,
  });

  final Order order;
  final Stock stock;
  final Color sideColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.hairline, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.edge + AppSpacing.unit * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SideBadge(side: order.side, colour: sideColor),
                      const SizedBox(height: AppSpacing.unit * 2),
                      Text(order.symbol, style: AppTypography.headlineMd),
                      const SizedBox(height: 2),
                      Text(
                        stock.name,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${order.quantity} '
                      '${order.quantity == 1 ? 'unit' : 'units'}',
                      style: AppTypography.titleSm,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@ ${MoneyFormat.rupees(order.fillPrice)}',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.edge),
              child: Divider(height: 0.5),
            ),
            _MetaRow(
              label: 'Total Value',
              value: MoneyFormat.rupees(order.value),
              emphasise: true,
            ),
            const SizedBox(height: AppSpacing.gutter),
            _MetaRow(label: 'Order ID', value: '#${_short(order.id)}'),
            const SizedBox(height: AppSpacing.gutter),
            _MetaRow(label: 'Timestamp', value: _formatTs(order.timestamp)),
          ],
        ),
      ),
    );
  }

  static String _short(String id) {
    // First segment of the uuid is enough to identify the order for a support
    // conversation, without dominating the row.
    final int dash = id.indexOf('-');
    return dash > 0 ? id.substring(0, dash).toUpperCase() : id.toUpperCase();
  }

  static String _formatTs(DateTime t) {
    final DateTime local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _SideBadge extends StatelessWidget {
  const _SideBadge({required this.side, required this.colour});

  final OrderSide side;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        side.name.toUpperCase(),
        style: AppTypography.labelCaps.copyWith(color: colour),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

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
        Text(
          value,
          style: emphasise
              ? AppTypography.headlineMd
              : AppTypography.labelNumeric,
        ),
      ],
    );
  }
}

class _MissingOrder extends StatelessWidget {
  const _MissingOrder();

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
            'That order is no longer available.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
