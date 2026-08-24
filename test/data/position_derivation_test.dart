import 'package:flutter_test/flutter_test.dart';
import 'package:trade_app/core/money/money.dart';
import 'package:trade_app/data/models/order.dart';
import 'package:trade_app/data/models/position.dart';

void main() {
  Order buy(String sym, int qty, int paise, {int seconds = 0}) => Order(
        id: 'buy-$sym-$qty-$paise-$seconds',
        symbol: sym,
        side: OrderSide.buy,
        quantity: qty,
        fillPrice: Money.fromPaise(paise),
        timestamp: DateTime.utc(2026, 8, 24).add(Duration(seconds: seconds)),
      );

  Order sell(String sym, int qty, int paise, {int seconds = 0}) => Order(
        id: 'sell-$sym-$qty-$paise-$seconds',
        symbol: sym,
        side: OrderSide.sell,
        quantity: qty,
        fillPrice: Money.fromPaise(paise),
        timestamp: DateTime.utc(2026, 8, 24).add(Duration(seconds: seconds)),
      );

  group('positionsFrom', () {
    test('an empty order history yields no positions', () {
      expect(positionsFrom(const <Order>[]), isEmpty);
    });

    test('a single buy stores exact quantity and totalCost', () {
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('ITC', 10, 43275),
      ]);

      expect(positions.keys, <String>['ITC']);
      final Position itc = positions['ITC']!;
      expect(itc.quantity, 10);
      // 10 × 432.75 = 4,327.50 exactly.
      expect(itc.totalCost, Money.fromPaise(432750));
      expect(itc.averageCost, Money.fromPaise(43275));
    });

    test('cost basis stays exact across many buys at odd prices', () {
      // A sequence deliberately chosen so 28 units at three prices produce a
      // total whose average involves a repeating decimal (2,344.0357...);
      // the average-based approach would drift with each accumulation. The
      // total-cost approach cannot: it is a pure integer sum.
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('LT', 7, 234567, seconds: 0),
        buy('LT', 11, 235012, seconds: 1),
        buy('LT', 10, 234198, seconds: 2),
      ]);

      final Position lt = positions['LT']!;
      expect(lt.quantity, 28);
      // 7×2345.67 + 11×2350.12 + 10×2341.98
      // = 16,419.69 + 25,851.32 + 23,419.80 = 65,690.81
      expect(lt.totalCost, Money.fromPaise(6569081));
      // Average rounds — the total does not.
      expect(lt.averageCost, Money.fromPaise(234610));
    });

    test('a partial sell reduces totalCost proportionally, not by avg×qty', () {
      // Buy 3 @ 100.03, buy 4 @ 200.05, then sell 2. Average is 157.15;
      // avg×2 = 314.30 would leave totalCost 400.29 - 314.30 = 85.99. The
      // proportional rule keeps totalCost exact: 400.29 × 5/7 rounded.
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('X', 3, 10003, seconds: 0),
        buy('X', 4, 20005, seconds: 1),
        sell('X', 2, 25000, seconds: 2),
      ]);

      final Position x = positions['X']!;
      expect(x.quantity, 5);
      // totalCost before sell = 3×100.03 + 4×200.05 = 300.09 + 800.20 = 1,100.29
      // × 5/7 = 785.9214... → 785.92 rounded to paise.
      expect(x.totalCost, Money.parse('785.92'));
    });

    test('selling to zero drops the position', () {
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('SBIN', 5, 76530, seconds: 0),
        sell('SBIN', 5, 78000, seconds: 1),
      ]);

      expect(positions.containsKey('SBIN'), isFalse);
    });

    test('rebuying after a full close starts fresh, not from prior basis', () {
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('ITC', 10, 43275, seconds: 0),
        sell('ITC', 10, 45000, seconds: 1),
        buy('ITC', 4, 44000, seconds: 2),
      ]);

      final Position itc = positions['ITC']!;
      expect(itc.quantity, 4);
      expect(itc.totalCost, Money.fromPaise(176000));
    });

    test('positions for different symbols do not cross-contaminate', () {
      final Map<String, Position> positions = positionsFrom(<Order>[
        buy('RELIANCE', 2, 300000, seconds: 0),
        buy('TCS', 3, 410000, seconds: 1),
        sell('RELIANCE', 1, 305000, seconds: 2),
      ]);

      expect(positions['RELIANCE']!.quantity, 1);
      expect(positions['TCS']!.quantity, 3);
      expect(positions['TCS']!.totalCost, Money.fromPaise(1230000));
    });
  });

  group('Position getters', () {
    final Position position = Position(
      symbol: 'ITC',
      quantity: 10,
      totalCost: Money.fromPaise(432750),
    );

    test('currentValue is qty × ltp — exact, no rounding', () {
      expect(position.currentValue(Money.fromPaise(45000)),
          Money.fromPaise(450000));
    });

    test('unrealised P&L is currentValue − totalCost', () {
      expect(position.unrealisedPnl(Money.fromPaise(45000)),
          Money.fromPaise(17250));
    });

    test('unrealised loss carries a negative sign, not an absolute value', () {
      final Money pnl = position.unrealisedPnl(Money.fromPaise(40000));
      expect(pnl.isNegative, isTrue);
      expect(pnl, Money.fromPaise(-32750));
    });
  });
}
