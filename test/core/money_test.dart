import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradedirect/core/money/money.dart';
import 'package:tradedirect/core/money/money_format.dart';

void main() {
  group('Money construction', () {
    test('fromPaise converts to rupees exactly', () {
      expect(Money.fromPaise(298745), Money.parse('2987.45'));
      expect(Money.fromPaise(1), Money.parse('0.01'));
      expect(Money.fromPaise(0), Money.zero);
    });

    test('storage form is trailing-zero normalised, not zero-padded', () {
      // Decimal drops insignificant trailing zeros. That is fine for the
      // persistence contract — what matters is that parsing it back yields an
      // equal value — but it means storage strings must never be compared as
      // display strings.
      expect(Money.parse('0.30').toStorageString(), '0.3');
      expect(Money.parse('0.30'), Money.parse('0.3'));
      expect(MoneyFormat.rupees(Money.parse('0.3')), '₹0.30');
    });

    test('round-trips through its storage form without loss', () {
      final Money original = Money.parse('1234567.89');
      expect(Money.parse(original.toStorageString()), original);
    });
  });

  group('Money arithmetic', () {
    test('multiplication by quantity is exact', () {
      // 0.1 * 3 is 0.30000000000000004 in binary floating point.
      expect(Money.parse('0.10') * 3, Money.parse('0.30'));
      expect(0.1 * 3 == 0.3, isFalse, reason: 'the drift this type avoids');
    });

    test('repeated accumulation accrues no drift', () {
      // The failure this guards against: summing a price that has no exact
      // binary representation, a thousand times over.
      Money total = Money.zero;
      double drifting = 0;
      for (int i = 0; i < 1000; i++) {
        total = total + Money.parse('0.07');
        drifting += 0.07;
      }
      expect(total, Money.parse('70'));
      expect(drifting == 70.0, isFalse, reason: 'the drift this type avoids');
    });

    test('cost basis over many buys stays exact', () {
      // Mirrors how a holding accumulates: total cost is summed, never an
      // average, so no intermediate rounding is ever fed back in.
      const List<String> prices = <String>[
        '2987.45',
        '2991.10',
        '2985.33',
        '3001.07',
      ];
      Money totalCost = Money.zero;
      int quantity = 0;
      for (final String price in prices) {
        totalCost = totalCost + Money.parse(price) * 7;
        quantity += 7;
      }
      expect(quantity, 28);
      expect(totalCost, Money.parse('83754.65'));

      // The derived average rounds to paise for display, but the rounded value
      // is never fed back into the cost basis — which is exactly why the total
      // above is exact after four separate fills.
      expect(totalCost.divideBy(quantity), Money.parse('2991.24'));
    });

    test('subtraction produces signed results', () {
      final Money loss = Money.parse('100.00') - Money.parse('112.40');
      expect(loss.isNegative, isTrue);
      expect(loss.abs, Money.parse('12.40'));
      expect(-loss, Money.parse('12.40'));
    });
  });

  group('Money division', () {
    test('rejects a zero divisor rather than producing an infinity', () {
      expect(() => Money.parse('100.00').divideBy(0), throwsArgumentError);
    });

    test('handles a non-terminating quotient at a declared scale', () {
      // 100 / 3 does not terminate; without an explicit scale this throws.
      expect(Money.parse('100.00').divideBy(3), Money.parse('33.33'));
    });
  });

  group('Money.ratioTo', () {
    test('computes a signed percentage', () {
      final Money change = Money.parse('34.20');
      final Money base = Money.parse('2953.25');
      expect(change.ratioTo(base), Decimal.parse('1.16'));
    });

    test('is negative for a loss', () {
      final Money change = Money.parse('-12.40');
      expect(change.ratioTo(Money.parse('4133.20'))!.abs(), Decimal.parse('0.30'));
      expect(change.ratioTo(Money.parse('4133.20'))! < Decimal.zero, isTrue);
    });

    test('returns null against a zero base instead of dividing by zero', () {
      expect(Money.parse('10.00').ratioTo(Money.zero), isNull);
    });
  });

  group('Money comparison', () {
    test('orders correctly and supports equality by value', () {
      expect(Money.parse('100.00') > Money.parse('99.99'), isTrue);
      expect(Money.parse('100.00') >= Money.parse('100.00'), isTrue);
      expect(Money.parse('100.00'), Money.fromPaise(10000));
      expect(Money.parse('100.0'), Money.parse('100.00'));
    });

    test('sorts a list of amounts', () {
      final List<Money> amounts = <Money>[
        Money.parse('5.00'),
        Money.parse('-3.00'),
        Money.parse('12.50'),
      ]..sort();
      expect(
        amounts,
        <Money>[Money.parse('-3'), Money.parse('5'), Money.parse('12.5')],
      );
    });
  });

  group('MoneyFormat', () {
    test('formats rupees with Indian digit grouping', () {
      expect(MoneyFormat.rupees(Money.parse('123456.78')), '₹1,23,456.78');
      expect(MoneyFormat.rupees(Money.parse('2987.45')), '₹2,987.45');
    });

    test('always shows an explicit sign on a change', () {
      expect(MoneyFormat.signedRupees(Money.parse('34.20')), '+₹34.20');
      expect(MoneyFormat.signedRupees(Money.parse('-12.40')), '-₹12.40');
    });

    test('renders an undefined percentage as a dash', () {
      expect(MoneyFormat.percent(null), '--');
      expect(MoneyFormat.signedPercent(null), '--');
    });

    test('formats percentages to two decimals', () {
      expect(MoneyFormat.percent(Decimal.parse('1.15')), '1.15%');
      expect(MoneyFormat.signedPercent(Decimal.parse('-0.30')), '-0.30%');
    });

    test('compacts large amounts into lakhs and crores', () {
      expect(MoneyFormat.compactRupees(Money.parse('1250000')), '₹12.50L');
      expect(MoneyFormat.compactRupees(Money.parse('23400000')), '₹2.34Cr');
      expect(MoneyFormat.compactRupees(Money.parse('4500')), '₹4,500.00');
    });
  });
}
