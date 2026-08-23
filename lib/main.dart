import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'core/storage/json_store.dart';
import 'features/watchlists/watchlist_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only: the dense numeric rows are designed around a single
  // narrow column.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    ProviderScope(
      overrides: <Override>[
        jsonStoreProvider.overrideWithValue(await _openStore()),
      ],
      child: const TradeApp(),
    ),
  );
}

/// Opens persistent storage, falling back to memory if the platform refuses.
///
/// Local persistence is a convenience here, not a correctness requirement: an
/// app that cannot open its box should still trade, and simply forget its
/// watchlists on restart. Failing to launch would be the worse outcome.
Future<JsonStore> _openStore() async {
  try {
    await Hive.initFlutter();
    return await HiveJsonStore.open();
  } catch (error, stack) {
    debugPrint('Persistence unavailable, running in memory: $error\n$stack');
    return InMemoryJsonStore();
  }
}
