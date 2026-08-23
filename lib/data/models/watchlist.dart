import 'package:flutter/foundation.dart';

import '../../market/stock_universe.dart';

/// A named, ordered list of instruments.
///
/// Order is user-controlled and meaningful, so [symbols] is a `List` rather
/// than a `Set`; uniqueness is enforced on insertion instead.
@immutable
class Watchlist {
  Watchlist({
    required this.id,
    required this.name,
    required List<String> symbols,
  }) : symbols = List<String>.unmodifiable(symbols);

  /// Rebuilds a watchlist from persisted JSON.
  ///
  /// Returns `null` for a document that cannot be read as a watchlist. Symbols
  /// that are no longer in the universe are dropped rather than thrown on: a
  /// delisted instrument should quietly disappear from the list, not prevent
  /// the app from starting.
  static Watchlist? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    final Object? symbols = json['symbols'];
    if (id is! String || name is! String || symbols is! List<Object?>) {
      return null;
    }

    return Watchlist(
      id: id,
      name: name,
      symbols: symbols.whereType<String>().where(StockUniverse.contains).toList(),
    );
  }

  final String id;
  final String name;

  /// Unmodifiable and ordered. Widgets key off the symbol string, never the
  /// index, so reordering cannot misbind a row to another instrument's price.
  final List<String> symbols;

  int get length => symbols.length;
  bool get isEmpty => symbols.isEmpty;

  bool contains(String symbol) => symbols.contains(symbol);

  Watchlist copyWith({String? name, List<String>? symbols}) => Watchlist(
        id: id,
        name: name ?? this.name,
        symbols: symbols ?? this.symbols,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'symbols': symbols,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Watchlist &&
          other.id == id &&
          other.name == name &&
          listEquals(other.symbols, symbols);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(symbols));

  @override
  String toString() => 'Watchlist($id, $name, ${symbols.length} symbols)';
}
