import '../core/money/money.dart';

/// A tradable instrument. Static reference data — never ticks.
class Stock {
  const Stock({
    required this.symbol,
    required this.name,
    required this.startingPricePaise,
    required this.volatilityBps,
  });

  /// NSE trading symbol, e.g. `RELIANCE`. Used as the identity key everywhere
  /// in the app — rows, providers and persisted records all key off this.
  final String symbol;

  /// Display name, e.g. `Reliance Industries Ltd.`
  final String name;

  /// Opening price in paise. Doubles as the previous close, so change and
  /// change % are meaningful from the first tick.
  final int startingPricePaise;

  /// Per-tick volatility in basis points. Large-cap banks move less per tick
  /// than mid-caps, which makes the feed look plausible rather than uniform.
  final int volatilityBps;

  Money get startingPrice => Money.fromPaise(startingPricePaise);
}

/// The ten instruments the app trades, per the product spec.
abstract final class StockUniverse {
  static const List<Stock> all = <Stock>[
    Stock(
      symbol: 'RELIANCE',
      name: 'Reliance Industries Ltd.',
      startingPricePaise: 298745,
      volatilityBps: 12,
    ),
    Stock(
      symbol: 'TCS',
      name: 'Tata Consultancy Services',
      startingPricePaise: 412080,
      volatilityBps: 9,
    ),
    Stock(
      symbol: 'INFY',
      name: 'Infosys Limited',
      startingPricePaise: 167525,
      volatilityBps: 11,
    ),
    Stock(
      symbol: 'HDFCBANK',
      name: 'HDFC Bank Ltd.',
      startingPricePaise: 143210,
      volatilityBps: 8,
    ),
    Stock(
      symbol: 'ICICIBANK',
      name: 'ICICI Bank Ltd.',
      startingPricePaise: 105690,
      volatilityBps: 8,
    ),
    Stock(
      symbol: 'SBIN',
      name: 'State Bank of India',
      startingPricePaise: 76530,
      volatilityBps: 14,
    ),
    Stock(
      symbol: 'ITC',
      name: 'ITC Ltd.',
      startingPricePaise: 43275,
      volatilityBps: 10,
    ),
    Stock(
      symbol: 'LT',
      name: 'Larsen & Toubro Ltd.',
      startingPricePaise: 356790,
      volatilityBps: 13,
    ),
    Stock(
      symbol: 'BHARTIARTL',
      name: 'Bharti Airtel Ltd.',
      startingPricePaise: 124550,
      volatilityBps: 11,
    ),
    Stock(
      symbol: 'AXISBANK',
      name: 'Axis Bank Ltd.',
      startingPricePaise: 112045,
      volatilityBps: 12,
    ),
  ];

  static final Map<String, Stock> _bySymbol = <String, Stock>{
    for (final Stock stock in all) stock.symbol: stock,
  };

  static final List<String> symbols =
      List<String>.unmodifiable(all.map((Stock s) => s.symbol));

  /// Looks up reference data. Throws on an unknown symbol — a symbol that is
  /// not in the universe means corrupt persisted state, and failing loudly
  /// here is better than rendering a blank row.
  static Stock bySymbol(String symbol) {
    final Stock? stock = _bySymbol[symbol];
    if (stock == null) {
      throw ArgumentError.value(symbol, 'symbol', 'Not in the stock universe');
    }
    return stock;
  }

  static bool contains(String symbol) => _bySymbol.containsKey(symbol);
}
