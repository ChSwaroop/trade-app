import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../market/feed_config.dart';
import '../../market/market_providers.dart';
import '../../market/stock_universe.dart';

/// Runtime controls for the mock feed.
///
/// Exists to make the load characteristics of the app demonstrable: the tick
/// rate can be pushed to the stress level and back while watching the frame
/// timings, without a restart and without resetting prices.
class FeedSettingsSheet extends ConsumerWidget {
  const FeedSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (_) => const FeedSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FeedConfig config = ref.watch(feedConfigProvider);
    final FeedConfigNotifier notifier = ref.read(feedConfigProvider.notifier);
    final int stockCount = StockUniverse.all.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.edge,
          0,
          AppSpacing.edge,
          AppSpacing.edge,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('FEED SETTINGS', style: AppTypography.labelCaps),
            const SizedBox(height: AppSpacing.vStandard),
            _Row(
              label: 'Ticks per second, per stock',
              value: '${config.ticksPerSecondPerStock}',
            ),
            Slider(
              value: config.ticksPerSecondPerStock.toDouble(),
              min: FeedConfig.minTicksPerSecondPerStock.toDouble(),
              max: FeedConfig.maxTicksPerSecondPerStock.toDouble(),
              divisions: FeedConfig.maxTicksPerSecondPerStock -
                  FeedConfig.minTicksPerSecondPerStock,
              label: '${config.ticksPerSecondPerStock}/s',
              onChanged: (double value) =>
                  notifier.setTicksPerSecond(value.round()),
            ),
            _Row(
              label: 'Total feed rate',
              value: '${config.totalTicksPerSecond(stockCount)} ticks/s',
            ),
            const SizedBox(height: AppSpacing.vTight),
            Text(
              'The UI publishes at most 60 snapshots/s regardless of feed rate. '
              'Raising this raises the load on the coalescer, not the frame rate.',
              style: AppTypography.bodySm.copyWith(color: AppColors.muted),
            ),
            const Divider(height: AppSpacing.edge * 2),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stress mode', style: AppTypography.bodyMd),
              subtitle: Text(
                '${FeedConfig.stressTicksPerSecondPerStock * stockCount} ticks/s '
                'across the universe',
                style: AppTypography.bodySm.copyWith(color: AppColors.muted),
              ),
              value: config.isStressMode,
              onChanged: (_) => notifier.toggleStressMode(),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause feed', style: AppTypography.bodyMd),
              subtitle: Text(
                'Freezes prices without resetting them',
                style: AppTypography.bodySm.copyWith(color: AppColors.muted),
              ),
              value: config.paused,
              onChanged: (bool value) => notifier.setPaused(paused: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.vTight),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: AppTypography.bodyMd),
          Text(value, style: AppTypography.labelNumeric),
        ],
      ),
    );
  }
}
