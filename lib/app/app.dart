import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../market/market_providers.dart';
import 'router.dart';
import 'theme.dart';

class TradeApp extends ConsumerStatefulWidget {
  const TradeApp({super.key});

  @override
  ConsumerState<TradeApp> createState() => _TradeAppState();
}

class _TradeAppState extends ConsumerState<TradeApp> {
  @override
  void initState() {
    super.initState();
    // Instantiate the price store eagerly so the feed is already running by
    // the time the first screen builds, rather than starting on first read.
    ref.read(priceStoreProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TradeDirect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) {
        // Cap text scaling. The design relies on a tight vertical rhythm with
        // fixed row extents; beyond 1.3x the dense numeric rows overflow.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
