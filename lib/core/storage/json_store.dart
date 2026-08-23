import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Key/value persistence for JSON documents.
///
/// Everything the app persists — watchlists, holdings, the order book — is a
/// small JSON document under a named key. Modelling storage this way rather
/// than with generated Hive adapters keeps the schema readable, keeps codegen
/// out of the build, and makes migration an ordinary function over a map.
///
/// Implementations must never throw on read. Persisted state written by an
/// older build of the app is not a crash: it is an empty document.
abstract interface class JsonStore {
  /// The document at [key], or `null` when it is absent, unreadable, or was
  /// written under a different [schemaVersion].
  Map<String, Object?>? read(String key, {required int schemaVersion});

  Future<void> write(
    String key,
    Map<String, Object?> value, {
    required int schemaVersion,
  });

  Future<void> delete(String key);
}

/// Envelope keys. The payload is nested rather than merged so a document can
/// never collide with the version field.
const String _versionField = 'schemaVersion';
const String _payloadField = 'payload';

/// Hive-backed [JsonStore]. Values are stored as JSON strings.
///
/// Storing strings rather than maps is deliberate: Hive hands back
/// `Map<dynamic, dynamic>` for nested structures, which then has to be cast at
/// every level. A JSON string round-trips through `dart:convert` into properly
/// typed maps in one step, and it is trivially inspectable on disk.
class HiveJsonStore implements JsonStore {
  const HiveJsonStore(this._box);

  static const String boxName = 'trade_app_documents';

  /// Opens the backing box. Called once during startup, before `runApp`.
  ///
  /// A corrupt box file is deleted and recreated rather than allowed to abort
  /// launch — losing local watchlists is recoverable, failing to start is not.
  static Future<HiveJsonStore> open() async {
    try {
      return HiveJsonStore(await Hive.openBox<String>(boxName));
    } catch (error, stack) {
      debugPrint('Hive box "$boxName" unreadable, recreating: $error\n$stack');
      await Hive.deleteBoxFromDisk(boxName);
      return HiveJsonStore(await Hive.openBox<String>(boxName));
    }
  }

  final Box<String> _box;

  @override
  Map<String, Object?>? read(String key, {required int schemaVersion}) {
    final String? raw = _box.get(key);
    if (raw == null) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;

      // A document from a different schema is discarded rather than guessed
      // at. Migrations, when there are any, belong here.
      if (decoded[_versionField] != schemaVersion) return null;

      final Object? payload = decoded[_payloadField];
      return payload is Map<String, Object?> ? payload : null;
    } on FormatException catch (error) {
      debugPrint('Discarding malformed document "$key": $error');
      return null;
    }
  }

  @override
  Future<void> write(
    String key,
    Map<String, Object?> value, {
    required int schemaVersion,
  }) {
    return _box.put(
      key,
      jsonEncode(<String, Object?>{
        _versionField: schemaVersion,
        _payloadField: value,
      }),
    );
  }

  @override
  Future<void> delete(String key) => _box.delete(key);
}

/// In-memory [JsonStore] for tests and for the case where Hive fails to
/// initialise at all. The app stays fully usable, it just forgets on restart.
class InMemoryJsonStore implements JsonStore {
  final Map<String, ({int version, String json})> _documents =
      <String, ({int version, String json})>{};

  @override
  Map<String, Object?>? read(String key, {required int schemaVersion}) {
    final ({int version, String json})? entry = _documents[key];
    if (entry == null || entry.version != schemaVersion) return null;
    final Object? decoded = jsonDecode(entry.json);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  @override
  Future<void> write(
    String key,
    Map<String, Object?> value, {
    required int schemaVersion,
  }) async {
    // Encoded eagerly so a test observes the same serialisation round-trip the
    // Hive implementation performs, including any non-encodable value.
    _documents[key] = (version: schemaVersion, json: jsonEncode(value));
  }

  @override
  Future<void> delete(String key) async => _documents.remove(key);
}
